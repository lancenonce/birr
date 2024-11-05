use clap::Parser;
use tlsn_examples::ExampleType;


pub mod prove;

// #[tokio::main]
// async fn main() -> Result<(), Box<dyn Error>> {
//     // let url = "https://api.nbe.gov.et/api/get-selected-exchange-rates";

//     // let client = Client::new();

//     // let res = client.get(url).send().await?;

//     // if res.status().is_success() {
//     //     let body = res.text().await?;
        
//     //     println!("{}", body);
//     // } else {
//     //     eprintln!("Failed to fetch exchange rates: {}", res.status());
//     // }

//     Ok(())
// }

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Args {
    #[clap(default_value_t, value_enum)]
    example_type: ExampleType,
}

#[tokio::main]
pub async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    let url = "https://api.nbe.gov.et/api/get-selected-exchange-rates";

    let (_, extra_headers) = match args.example_type {
        ExampleType::Json => ("/formats/json", vec![]),
        ExampleType::Html => ("/formats/html", vec![]),
        ExampleType::Authenticated => ("/protected", vec![("Authorization", "random_auth_token")]),
    };

    prove::notarize(url, extra_headers, &args.example_type).await
}