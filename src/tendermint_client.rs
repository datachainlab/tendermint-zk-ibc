use ethers::types::H256;
use log::*;
use tendermint::{block::Header, Hash};

#[derive(Debug, serde::Deserialize)]
pub struct HeaderResponse {
    pub result: WrappedHeader,
}

#[derive(Debug, serde::Deserialize)]
pub struct WrappedHeader {
    pub header: Header,
}

pub(crate) async fn fetch_trusted_block_hash(url: &str, height: u64) -> H256 {
    let res = request_from_rpc(url, &format!("header?height={}", height + 1), 10).await;
    let v: HeaderResponse = serde_json::from_str(&res).expect("Failed to parse JSON");
    match v.result.header.last_block_id.unwrap().hash {
        Hash::Sha256(hash) => H256::from_slice(&hash),
        Hash::None => panic!("Failed to fetch block hash from Tendermint RPC"),
    }
}

// Request data from the Tendermint RPC with quadratic backoff & multiple RPC's.
pub(crate) async fn request_from_rpc(url: &str, route: &str, retries: usize) -> String {
    let url = format!("{}/{}", url, route);
    info!("Querying url {:?}", url.clone());
    let mut res = reqwest::get(url.clone()).await;
    let mut num_retries = 0;
    while res.is_err() && num_retries < retries {
        info!("Querying url {:?}", url.clone());
        res = reqwest::get(url.clone()).await;
        // Quadratic backoff for requests.
        tokio::time::sleep(std::time::Duration::from_secs(2u64.pow(num_retries as u32))).await;
        num_retries += 1;
    }

    if res.is_ok() {
        return res.unwrap().text().await.unwrap();
    }

    panic!("Failed to fetch data from Tendermint RPC");
}
