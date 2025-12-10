use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};

/// The Sealing Engine - manages the sealing process
pub struct SealingEngine;

impl SealingEngine {
    pub fn new() -> Self {
        Self
    }

    /// Compute the cryptographic hash for an event
    /// Hash includes: sequence_number + event_id + payload + previous_hash
    /// This creates the hash chain (Merkle-like structure)
    pub fn compute_event_hash(
        &self,
        sequence_number: u64,
        event_id: &str,
        payload: &[u8],
        previous_hash: &str,
    ) -> String {
        let mut hasher = Sha256::new();
        
        // Hash the components in order
        hasher.update(sequence_number.to_le_bytes());
        hasher.update(event_id.as_bytes());
        hasher.update(payload);
        hasher.update(previous_hash.as_bytes());
        
        let result = hasher.finalize();
        hex::encode(result)
    }
}

/// Sealed event data structure
/// This is what gets stored in etcd and returned to clients
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SealedEventData {
    pub sequence_number: u64,
    pub event_id: String,
    pub payload: Vec<u8>,
    pub event_hash: String,
    pub previous_hash: String,
    pub sealed_timestamp: i64,
    pub commit_latency_ms: i64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_determinism() {
        let engine = SealingEngine::new();
        
        let hash1 = engine.compute_event_hash(
            1,
            "test-event",
            b"test payload",
            "0000000000000000",
        );
        
        let hash2 = engine.compute_event_hash(
            1,
            "test-event",
            b"test payload",
            "0000000000000000",
        );
        
        // Same inputs should produce same hash
        assert_eq!(hash1, hash2);
        
        // Different sequence should produce different hash
        let hash3 = engine.compute_event_hash(
            2,
            "test-event",
            b"test payload",
            "0000000000000000",
        );
        
        assert_ne!(hash1, hash3);
    }
}