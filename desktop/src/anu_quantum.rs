//! ANU Quantum RNG — real vacuum fluctuation entropy

use crate::SharedState;

pub async fn run_entropy_stream(state: SharedState) {
    loop {
        if let Ok(entropy) = fetch_anu_entropy().await {
            let mut s = state.write().await;
            s.entropy.bytes_received += entropy.len() as u64;
            s.entropy.sample = entropy.iter().take(16).copied().collect();
        }
        tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
    }
}

async fn fetch_anu_entropy() -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let url = "https://qrng.anu.edu.au/API/jsonI.php?length=1024&type=uint8";
    let response = reqwest::get(url).await?;
    let json: serde_json::Value = response.json().await?;
    let data: Vec<u8> = json["data"]
        .as_array()
        .unwrap_or(&vec![])
        .iter()
        .filter_map(|v| v.as_u64().map(|u| u as u8))
        .collect();
    Ok(data)
}
