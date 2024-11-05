// In this module, we generate a proof of the TLS request and generate a proof of the TLS response.

use clap::Parser;
use notary_client::{Accepted, NotarizationRequest, NotaryClient};
use std::env;
use tlsn_examples::ExampleType;
use tlsn_server_fixture::DEFAULT_FIXTURE_PORT;

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
}
