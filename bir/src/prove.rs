// In this module, we generate a proof of the TLS request and generate a proof of the TLS response.

use std::env;

use http_body_util::Empty;
use hyper::{body::Bytes, Request, StatusCode};
use hyper_util::rt::TokioIo;
use spansy::Spanned;
use tlsn_examples::ExampleType;
use tokio_util::compat::{FuturesAsyncReadCompatExt, TokioAsyncReadCompatExt};

use notary_client::{Accepted, NotarizationRequest, NotaryClient};
use tls_server_fixture::SERVER_DOMAIN;
use tlsn_common::config::ProtocolConfig;
use tlsn_core::{request::RequestConfig, transcript::TranscriptCommitConfig};
use tlsn_formats::http::{DefaultHttpCommitter, HttpCommit, HttpTranscript};
use tlsn_prover::{Prover, ProverConfig};
use tlsn_server_fixture::DEFAULT_FIXTURE_PORT;
use tracing::debug;

use clap::Parser;

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Args {
    #[clap(default_value_t, value_enum)]
    example_type: ExampleType,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    let (uri, extra_headers) = match args.example_type {
        ExampleType::Json => ("/formats/json", vec![]),
        ExampleType::Html => ("/formats/html", vec![]),
        ExampleType::Authenticated => ("/protected", vec![("Authorization", "random_auth_token")]),
    };

    notarize(uri, extra_headers, &args.example_type).await
}

async fn notarize(
    uri: &str,
    extra_headers: Vec<(&str, &str)>,
    example_type: &ExampleType,
) -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    let notary_host: String = env::var("NOTARY_HOST").unwrap_or("127.0.0.1".into());
    let notary_port: u16 = env::var("NOTARY_PORT").unwrap_or("7047".into()).parse()?;
    let server_host: String = env::var("SERVER_HOST").unwrap_or("127.0.0.1".into());
    let server_port: u16 = env::var("SERVER_PORT")
        .unwrap_or(DEFAULT_FIXTURE_PORT)
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
    let prover = Prover::new(prover_config).setup(notary_connection.compat()).await?;

    let client_socket = tokio::net::TcpStream::connect((server_host, server_port)).await?;

    // Bind the prover
    let (mpc_tls_connection, prover_fut) = prover.connect(client_socket.compat()).await?;

    let mpc_tls_connection = TokioIo::new(mpc_tls_connection.compat());

    let prover_task = tokio::spawn(prover_fut);

    let (mut request_sender, connection) = hyper::client::conn::http1::handshake(mpc_tls_connection).await?;
}
