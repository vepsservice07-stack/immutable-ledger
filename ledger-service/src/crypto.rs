use std::collections::BTreeMap;

/// Hash Chain - maintains the cryptographic chain of hashes (Merkle tree / hash chaining)
pub struct HashChain {
    // Ordered map of sequence_number -> hash
    chain: BTreeMap<u64, String>,
    // Genesis hash (start of chain)
    genesis_hash: String,
}

impl HashChain {
    pub fn new() -> Self {
        // Genesis hash - the "root of trust" for the chain
        let genesis_hash = "0".repeat(64); // 64-char hex string of zeros
        
        Self {
            chain: BTreeMap::new(),
            genesis_hash,
        }
    }

    /// Get the latest hash in the chain
    /// This is what the next event will link to
    pub fn get_latest_hash(&self) -> String {
        if let Some((_, hash)) = self.chain.iter().next_back() {
            hash.clone()
        } else {
            // No events yet, return genesis hash
            self.genesis_hash.clone()
        }
    }

    /// Add a new hash to the chain
    pub fn add_hash(&mut self, sequence_number: u64, hash: String) {
        self.chain.insert(sequence_number, hash);
    }

    /// Get a specific hash by sequence number
    pub fn get_hash(&self, sequence_number: u64) -> Option<String> {
        self.chain.get(&sequence_number).cloned()
    }

    /// Verify the integrity of the chain
    /// Returns true if the chain is valid (no tampering detected)
    pub fn verify_integrity(&self) -> bool {
        if self.chain.is_empty() {
            return true;
        }

        let mut expected_sequences: Vec<u64> = self.chain.keys().copied().collect();
        expected_sequences.sort();

        // Check that sequence numbers are consecutive
        for i in 0..expected_sequences.len() - 1 {
            if expected_sequences[i + 1] != expected_sequences[i] + 1 {
                return false; // Gap in sequence
            }
        }

        true
    }

    /// Get the current chain length
    pub fn length(&self) -> usize {
        self.chain.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_genesis_hash() {
        let chain = HashChain::new();
        let genesis = chain.get_latest_hash();
        assert_eq!(genesis.len(), 64);
        assert_eq!(genesis, "0".repeat(64));
    }

    #[test]
    fn test_add_and_retrieve() {
        let mut chain = HashChain::new();
        
        chain.add_hash(1, "hash1".to_string());
        chain.add_hash(2, "hash2".to_string());
        
        assert_eq!(chain.get_hash(1), Some("hash1".to_string()));
        assert_eq!(chain.get_hash(2), Some("hash2".to_string()));
        assert_eq!(chain.get_latest_hash(), "hash2".to_string());
    }

    #[test]
    fn test_chain_integrity() {
        let mut chain = HashChain::new();
        
        chain.add_hash(1, "hash1".to_string());
        chain.add_hash(2, "hash2".to_string());
        chain.add_hash(3, "hash3".to_string());
        
        assert!(chain.verify_integrity());
        
        // Add non-consecutive sequence
        chain.add_hash(5, "hash5".to_string());
        assert!(!chain.verify_integrity());
    }
}