// In this module, we generate a proof of the TLS request and generate a proof of the TLS response.

use std::env;

use http_body_util::Empty;
use hyper::{body::Bytes, Request, StatusCode};
use hyper_util::rt::TokioIo;
use tlsn_formats::spansy::Spanned;
use tlsn_examples::ExampleType;
use tokio_util::compat::{FuturesAsyncReadCompatExt, TokioAsyncReadCompatExt};

use notary_client::{Accepted, NotarizationRequest, NotaryClient};
use tlsn_common::config::ProtocolConfig;
use tlsn_core::{request::RequestConfig, transcript::TranscriptCommitConfig};
use tlsn_formats::http::{DefaultHttpCommitter, HttpCommit, HttpTranscript};
use tlsn_prover::{Prover, ProverConfig};
use tlsn_server_fixture::DEFAULT_FIXTURE_PORT;
use tracing::debug;


const SERVER_DOMAIN: &str = "api.nbe.gov.et";

pub async fn notarize(
    uri: &str,
    extra_headers: Vec<(&str, &str)>,
    example_type: &ExampleType,
) -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    let notary_host: String = env::var("NOTARY_HOST").unwrap_or("127.0.0.1".into());
    let notary_port: u16 = env::var("NOTARY_PORT").unwrap_or("7047".into()).parse()?;
    let server_host: String = env::var("SERVER_HOST").unwrap_or("127.0.0.1".into());
    let server_port: u16 = env::var("SERVER_PORT")
        .unwrap_or(DEFAULT_FIXTURE_PORT.to_string())
        .parse()?;

    // First, we build a client to connect to the notary server
    let notary_client = NotaryClient::builder()
        .host(notary_host)
        .port(notary_port)
        .build()
        .unwrap();

    let notarization_request = NotarizationRequest::builder()
        .max_sent_data(tlsn_examples::MAX_SENT_DATA)
        .max_recv_data(tlsn_examples::MAX_RECV_DATA)
        .build()
        .unwrap();

    let Accepted {
        io: notary_connection,
        id: _session_id,
        ..
    } = notary_client
        .request_notarization(notarization_request)
        .await
        .expect("Could not connect to the notary. Is it running?");

    // Now, we configure the prover
    let prover_config = ProverConfig::builder()
        .server_name(SERVER_DOMAIN)
        .protocol_config(
            ProtocolConfig::builder()
                .max_sent_data(tlsn_examples::MAX_SENT_DATA)
                .max_recv_data(tlsn_examples::MAX_RECV_DATA)
                .build()
                .unwrap(),
        )
        .crypto_provider(tlsn_examples::get_crypto_provider_with_server_fixture())
        .build()?;

    // Next, we create the prover and perform setup
    let prover = Prover::new(prover_config)
        .setup(notary_connection.compat())
        .await?;

    let client_socket = tokio::net::TcpStream::connect((server_host, server_port)).await?;

    // Bind the prover
    let (mpc_tls_connection, prover_fut) = prover.connect(client_socket.compat()).await?;

    let mpc_tls_connection = TokioIo::new(mpc_tls_connection.compat());

    let prover_task = tokio::spawn(prover_fut);

    let (mut request_sender, connection) =
        hyper::client::conn::http1::handshake(mpc_tls_connection).await?;

    tokio::spawn(connection);

    // Now, we call build the api request
    let request_builder = Request::builder().uri(uri).method("GET").header("Host", SERVER_DOMAIN).header("Accept", "*/*").header("Accept-Encoding", "identity").header("Connection", "close");

    let mut request_builder = request_builder; 
    for (key, value) in extra_headers {
        request_builder = request_builder.header(key, value);
    }
    let request = request_builder.body(Empty::<Bytes>::new())?;

    println!("Starting an MPC TLS connection with the server");

    let response = request_sender.send_request(request).await?;

    println!("Got a response from the server: {}", response.status());

    assert!(response.status() == StatusCode::OK);

    let prover = prover_task.await??;

    let mut prover = prover.start_notarize();

    let transcript = HttpTranscript::parse(prover.transcript())?;

    let body_content = &transcript.responses[0].body.as_ref().unwrap().content;

    let body = String::from_utf8_lossy(body_content.span().as_bytes());

    match body_content {
        tlsn_formats::http::BodyContent::Json(_json) => {
            let parsed = serde_json::from_str::<serde_json::Value>(&body)?;
            debug!("{}", serde_json::to_string_pretty(&parsed)?);
        }
        tlsn_formats::http::BodyContent::Unknown(_span) => {
            debug!("{}", &body);
        }
        _ => {}
    }

    let mut builder = TranscriptCommitConfig::builder(prover.transcript());

    DefaultHttpCommitter::default().commit_transcript(&mut builder, &transcript)?;

    prover.transcript_commit(builder.build()?);

    let request_config = RequestConfig::default();

    let (attestation, secrets) = prover.finalize(&request_config).await?;

    println!("Notarization Complete!");

    let attestation_path = tlsn_examples::get_file_path(example_type, "attestation");
    let secrets_path = tlsn_examples::get_file_path(example_type, "secreats");

    tokio::fs::write(&attestation_path, bincode::serialize(&attestation)?).await?;

    tokio::fs::write(&secrets_path, bincode::serialize(&secrets)?).await?;

    println!("Successfully Notarized");
    println!(
        "The attestation has been written to `{attestation_path}` and the \
        corresponding secrets to `{secrets_path}`."
    );

    Ok(())
}
