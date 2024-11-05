use reqwest::Client;
use std::error::Error;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let url = "https://api.nbe.gov.et/api/get-selected-exchange-rates";

    let client = Client::new();

    let res = client.get(url).send().await?;

    if res.status().is_success() {
        let body = res.text().await?;
        
        println!("{}", body);
    } else {
        eprintln!("Failed to fetch exchange rates: {}", res.status());
    }

    Ok(())
}