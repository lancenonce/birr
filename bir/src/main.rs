pub mod prove;

#[tokio::main]
pub async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let url = "http://api.nbe.gov.et/api/get-selected-exchange-rates";

    prove::notarize(url).await
}