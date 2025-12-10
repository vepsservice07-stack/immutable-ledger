use anyhow::Result;
use tracing::{info, Level};
use tracing_subscriber;

mod ledger;
mod server;
mod sealing;
mod crypto;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .init();

    info!("Starting ImmutableLedger Service");

    // Get etcd endpoints from environment or use default
    let etcd_endpoints = std::env::var("ETCD_ENDPOINTS")
        .unwrap_or_else(|_| "https://etcd-client.immutable-ledger.svc.cluster.local:2379".to_string());
    
    let etcd_endpoints: Vec<String> = etcd_endpoints
        .split(',')
        .map(|s| s.trim().to_string())
        .collect();

    info!("Connecting to etcd at: {:?}", etcd_endpoints);

    // TLS certificates for etcd connection
    let ca_cert_path = std::env::var("ETCD_CA_CERT")
        .unwrap_or_else(|_| "/etc/etcd-certs/ca.crt".to_string());
    let client_cert_path = std::env::var("ETCD_CLIENT_CERT")
        .unwrap_or_else(|_| "/etc/etcd-certs/tls.crt".to_string());
    let client_key_path = std::env::var("ETCD_CLIENT_KEY")
        .unwrap_or_else(|_| "/etc/etcd-certs/tls.key".to_string());

    // Initialize the Ledger
    let ledger = ledger::Ledger::new(
        etcd_endpoints,
        ca_cert_path,
        client_cert_path,
        client_key_path,
    ).await?;

    info!("Ledger initialized successfully");

    // Start gRPC server
    let addr = "0.0.0.0:50051".parse()?;
    info!("Starting gRPC server on {}", addr);

    server::start_server(addr, ledger).await?;

    Ok(())
}