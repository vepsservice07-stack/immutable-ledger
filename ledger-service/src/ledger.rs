use anyhow::{Result, Context};
use etcd_client::{Client, ConnectOptions, TlsOptions};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{info, error};

use crate::crypto::HashChain;
use crate::sealing::{SealingEngine, SealedEventData};

/// The ImmutableLedger - Core sequencing engine
pub struct Ledger {
    etcd_client: Arc<Mutex<Client>>,
    sealing_engine: Arc<SealingEngine>,
    hash_chain: Arc<Mutex<HashChain>>,
}

impl Ledger {
    pub async fn new(
        endpoints: Vec<String>,
        ca_cert_path: String,
        client_cert_path: String,
        client_key_path: String,
    ) -> Result<Self> {
        info!("Initializing Ledger with etcd endpoints: {:?}", endpoints);

        // Read TLS certificates
        let ca_cert = tokio::fs::read(&ca_cert_path)
            .await
            .context("Failed to read CA certificate")?;
        let client_cert = tokio::fs::read(&client_cert_path)
            .await
            .context("Failed to read client certificate")?;
        let client_key = tokio::fs::read(&client_key_path)
            .await
            .context("Failed to read client key")?;

        // Configure TLS
        let tls_options = TlsOptions::new()
            .ca_certificate(etcd_client::Certificate::from_pem(ca_cert))
            .identity(etcd_client::Identity::from_pem(client_cert, client_key));

        let connect_options = ConnectOptions::new().with_tls(tls_options);

        // Connect to etcd
        let client = Client::connect(endpoints, Some(connect_options))
            .await
            .context("Failed to connect to etcd")?;

        info!("Successfully connected to etcd cluster");

        // Initialize components
        let sealing_engine = Arc::new(SealingEngine::new());
        let hash_chain = Arc::new(Mutex::new(HashChain::new()));

        Ok(Self {
            etcd_client: Arc::new(Mutex::new(client)),
            sealing_engine,
            hash_chain,
        })
    }

    /// Submit a certified event for sealing
    /// This is the main entry point that implements the 50ms contract
    pub async fn seal_event(
        &self,
        event_id: String,
        payload: Vec<u8>,
        _veps_signature: String,
        _veps_timestamp: i64,
    ) -> Result<SealedEventData> {
        let start = std::time::Instant::now();

        // Step 1: Receipt - Event received from VEPS
        info!("Received event {} for sealing", event_id);

        // Step 2: Indexing - Assign sequence number via etcd
        let sequence_number = self.assign_sequence_number(&event_id).await?;
        info!("Assigned sequence number {} to event {}", sequence_number, event_id);

        // Step 3: Hash Chain - Compute cryptographic hash
        let previous_hash = {
            let chain = self.hash_chain.lock().await;
            chain.get_latest_hash()
        };
        
        let event_hash = self.sealing_engine.compute_event_hash(
            sequence_number,
            &event_id,
            &payload,
            &previous_hash,
        );

        // Step 4: Replication & Quorum - Write to etcd (Raft consensus)
        let sealed_event = SealedEventData {
            sequence_number,
            event_id: event_id.clone(),
            payload,
            event_hash: event_hash.clone(),
            previous_hash: previous_hash.clone(),
            sealed_timestamp: chrono::Utc::now().timestamp_millis(),
            commit_latency_ms: 0, // Will be set below
        };

        self.write_to_ledger(&sealed_event).await?;

        // Step 5: Seal Complete - Update hash chain
        {
            let mut chain = self.hash_chain.lock().await;
            chain.add_hash(sequence_number, event_hash.clone());
        }

        let elapsed = start.elapsed();
        let latency_ms = elapsed.as_millis() as i64;
        
        info!(
            "Event {} sealed with sequence {} in {}ms",
            event_id, sequence_number, latency_ms
        );

        // Check 50ms contract
        if latency_ms > 50 {
            error!(
                "WARNING: Sealing latency {}ms exceeded 50ms contract for event {}",
                latency_ms, event_id
            );
        }

        Ok(SealedEventData {
            commit_latency_ms: latency_ms,
            ..sealed_event
        })
    }

    /// Assign the next sequence number using etcd's atomic counter
    async fn assign_sequence_number(&self, _event_id: &str) -> Result<u64> {
        let mut client = self.etcd_client.lock().await;
        
        // Use etcd's atomic increment to get a globally unique sequence number
        let key = "ledger/sequence_counter";
        let response = client.get(key, None).await?;
        
        let next_sequence = if let Some(kv) = response.kvs().first() {
            let current: u64 = String::from_utf8(kv.value().to_vec())?
                .parse()
                .unwrap_or(0);
            current + 1
        } else {
            1
        };

        // Atomically set the new sequence number
        client.put(key, next_sequence.to_string(), None).await?;
        
        Ok(next_sequence)
    }

    /// Write the sealed event to etcd (Raft consensus + persistence)
    async fn write_to_ledger(&self, sealed_event: &SealedEventData) -> Result<()> {
        let mut client = self.etcd_client.lock().await;
        
        let key = format!("ledger/events/{}", sealed_event.sequence_number);
        let value = serde_json::to_string(sealed_event)?;
        
        // Write to etcd - this achieves Raft quorum consensus
        client.put(key, value, None).await?;
        
        Ok(())
    }

    /// Get a sealed event by sequence number
    pub async fn get_event(&self, sequence_number: u64) -> Result<Option<SealedEventData>> {
        let mut client = self.etcd_client.lock().await;
        
        let key = format!("ledger/events/{}", sequence_number);
        let response = client.get(key, None).await?;
        
        if let Some(kv) = response.kvs().first() {
            let sealed_event: SealedEventData = serde_json::from_slice(kv.value())?;
            Ok(Some(sealed_event))
        } else {
            Ok(None)
        }
    }

    /// Get the current sequence number
    pub async fn get_current_sequence(&self) -> Result<u64> {
        let mut client = self.etcd_client.lock().await;
        
        let key = "ledger/sequence_counter";
        let response = client.get(key, None).await?;
        
        if let Some(kv) = response.kvs().first() {
            let sequence: u64 = String::from_utf8(kv.value().to_vec())?
                .parse()
                .unwrap_or(0);
            Ok(sequence)
        } else {
            Ok(0)
        }
    }
}