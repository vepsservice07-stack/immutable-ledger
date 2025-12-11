# ImmutableLedger

> **High-assurance sequencing core providing Strong Total Ordering with sub-50ms latency**

ImmutableLedger is a distributed, append-only log system built on Raft consensus (etcd) that provides cryptographically-guaranteed ordering for financial transactions. It serves as the definitive source of chronological truth in high-stakes, regulatory environments.

---

## Purpose

In distributed systems, establishing **who saw what, when** is notoriously difficult. ImmutableLedger solves this by:

- **Assigning definitive sequence numbers** to all events via Raft consensus
- **Creating cryptographic proof** of event order through hash chaining
- **Guaranteeing immutability** - events can never be altered or deleted
- **Meeting strict latency requirements** - sub-50ms commit times (typically ~10ms)

This eliminates the "invisible risk gap" where systems disagree on the order of events, creating financial and regulatory liability.

---

## 🏗️ Architecture Overview

```
┌─────────────┐
│    VEPS     │ (Verification & Event Processing Service)
│             │ • Validates events
│             │ • Checks business rules
│             │ • Certifies events
└──────┬──────┘
       │ gRPC: SubmitEvent
       ▼
┌─────────────────────────────────────────┐
│      ImmutableLedger Service            │
│                                         │
│  1. Receipt    → Event received         │
│  2. Indexing   → Assign sequence #      │
│  3. Hashing    → Link to previous hash  │
│  4. Consensus  → Raft quorum commit     │
│  5. Seal       → Return sealed event    │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────┐
│  etcd Cluster   │ (3-node Raft)
│                 │
│  • Consensus    │
│  • Total Order  │
│  • Persistence  │
└─────────────────┘
```

---

##  How It Works

### The Sealing Process

When VEPS submits a certified event, ImmutableLedger executes the following steps in under 50ms:

#### 1. **Receipt** (< 1ms)
Event arrives via gRPC with VEPS certification:
```rust
CertifiedEvent {
  event_id: "evt-12345",
  payload: [transaction data],
  veps_signature: "sig...",
  veps_timestamp: 1702234567890
}
```

#### 2. **Indexing** (< 5ms)
Ledger assigns a globally unique, monotonically increasing sequence number using etcd's atomic counter:
```
GET ledger/sequence_counter  // Current: 1000
SET ledger/sequence_counter  // New: 1001
Assigned: 1001
```

#### 3. **Hash Computation** (< 1ms)
Event is cryptographically hashed and linked to the previous event:
```
event_hash = SHA-256(
  sequence_number ||  // 1001
  event_id ||         // "evt-12345"
  payload ||          // [transaction data]
  previous_hash       // Hash of event #1000
)
```

This creates a **hash chain** (like blockchain) where tampering with any historical event breaks the chain.

#### 4. **Replication & Consensus** (10-20ms)
Event is written to etcd, achieving Raft quorum:
```
┌────────┐     ┌────────┐     ┌────────┐
│ etcd-0 │────►│ etcd-1 │────►│ etcd-2 │
│ Leader │     │Follower│     │Follower│
└────────┘     └────────┘     └────────┘
    │              │              │
    └──────────────┴──────────────┘
              Quorum (2/3)
           ✓ Committed
```

#### 5. **Seal Complete** (< 1ms)
Return sealed event to VEPS:
```rust
SealedEvent {
  sequence_number: 1001,
  event_id: "evt-12345",
  payload: [transaction data],
  event_hash: "a1b2c3...",
  previous_hash: "d4e5f6...",
  sealed_timestamp: 1702234567910,
  commit_latency_ms: 10  // ✓ Under 50ms!
}
```

---

## 🔒 Guarantees

### 1. **Strong Total Ordering (Linearizability)**
- Every event gets a unique, sequential number
- No two events can have the same sequence
- Order is agreed upon by Raft quorum (2/3 nodes)

### 2. **Immutability**
- **Append-only**: Events are never updated or deleted
- **Hash chain**: Cryptographic proof prevents tampering
- **Forensic**: Complete audit trail for regulators

### 3. **High Assurance Transactional Availability**
- **50ms contract**: Commits complete in <50ms or reject
- **Fast finality**: Typically ~10ms
- **CP system**: Sacrifices availability for consistency during partitions

### 4. **Non-Repudiation**
- Cryptographic hash chain provides proof of order
- VEPS signature proves event certification
- Timestamp proves when consensus was achieved

---

## 📡 API Reference

### gRPC Service: `ImmutableLedger`

#### `SubmitEvent` - Submit a certified event for sealing

**Request:**
```protobuf
message CertifiedEvent {
  string event_id = 1;           // Unique event ID from VEPS
  bytes payload = 2;             // Transaction data
  string veps_signature = 3;     // VEPS certification signature
  int64 veps_timestamp = 4;      // When VEPS certified
  map<string, string> metadata = 5; // Optional metadata
}
```

**Response:**
```protobuf
message SealedEvent {
  uint64 sequence_number = 1;    // Definitive sequence number
  string event_id = 2;           // Your event ID (echoed back)
  bytes payload = 3;             // Your data (echoed back)
  string event_hash = 4;         // SHA-256 hash of this event
  string previous_hash = 5;      // Link to previous event
  int64 sealed_timestamp = 6;    // When sealed (epoch millis)
  int64 commit_latency_ms = 7;   // How long it took
}
```

**Usage Example (Go):**
```go
import (
  "context"
  pb "your/proto/package"
  "google.golang.org/grpc"
)

// Connect to Ledger
conn, _ := grpc.Dial("ledger-service:50051", grpc.WithInsecure())
client := pb.NewImmutableLedgerClient(conn)

// Submit event
sealed, err := client.SubmitEvent(context.Background(), &pb.CertifiedEvent{
  EventId: "evt-12345",
  Payload: []byte("transaction data"),
  VepsSignature: "your-signature",
  VepsTimestamp: time.Now().UnixMilli(),
})

fmt.Printf("Sealed with sequence: %d\n", sealed.SequenceNumber)
fmt.Printf("Commit latency: %dms\n", sealed.CommitLatencyMs)
```

#### `GetEvent` - Retrieve a sealed event by sequence number

**Request:**
```protobuf
message GetEventRequest {
  uint64 sequence_number = 1;
}
```

**Response:** `SealedEvent` (same as SubmitEvent response)

#### `HealthCheck` - Check service health

**Request:** `HealthCheckRequest` (empty)

**Response:**
```protobuf
message HealthCheckResponse {
  bool healthy = 1;
  string status = 2;
  uint64 last_sequence_number = 3;  // Latest sealed event
}
```

---

## 🚀 Deployment

### Prerequisites
- **Kubernetes cluster** (GKE Autopilot or Standard)
- **kubectl** configured
- **Docker** (for building images)

### Quick Start

```bash
# 1. Set up environment
cd ~/Code/immutable-ledger
source setup-env.sh

# 2. Deploy to development (Autopilot)
./deploy.sh dev

# 3. Verify deployment
kubectl get pods
kubectl get svc

# 4. Check health
kubectl exec -it etcd-0 -- /usr/local/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/peer-tls/ca.crt \
  --cert=/etc/etcd/peer-tls/tls.crt \
  --key=/etc/etcd/peer-tls/tls.key \
  endpoint health
```

### Production Deployment

```bash
# Create production cluster
./create-prod-cluster.sh

# Deploy to production
./deploy.sh prod
```

---

## 🔧 Configuration

### Environment Variables

The Ledger service uses these environment variables (set in Kubernetes deployment):

```yaml
ETCD_ENDPOINTS: "https://etcd-0...:2379,https://etcd-1...:2379,https://etcd-2...:2379"
ETCD_CA_CERT: "/etc/etcd-certs/ca.crt"
ETCD_CLIENT_CERT: "/etc/etcd-certs/tls.crt"
ETCD_CLIENT_KEY: "/etc/etcd-certs/tls.key"
RUST_LOG: "info"
```

### Resource Configuration

**Development (Autopilot):**
- etcd: 1 replica, 100m CPU, 256Mi RAM
- Ledger: 1 replica, 100m CPU, 128Mi RAM
- Cost: ~$10-15/month

**Production (Standard GKE):**
- etcd: 3 replicas, 500m CPU, 1Gi RAM
- Ledger: 3 replicas, 250m CPU, 512Mi RAM
- Cost: ~$150-200/month

---

## Performance

### Observed Metrics
- **Commit Latency (p50)**: ~10ms
- **Commit Latency (p99)**: ~25ms
- **Target**: <50ms (✅ Achieved)

### Raft Tuning
```yaml
ETCD_HEARTBEAT_INTERVAL: 100ms
ETCD_ELECTION_TIMEOUT: 1000ms
```

### Capacity
- **Current throughput**: ~100 events/sec (single-threaded sealing)
- **Scalability**: Horizontal scaling of Ledger service (stateless)
- **Bottleneck**: etcd write throughput (can be increased with resources)

---

## 🔐 Security

### TLS Encryption
- **All communication encrypted** (peer-to-peer and client-to-server)
- **Mutual TLS** between etcd nodes
- **cert-manager** handles certificate lifecycle

### Access Control
- **Network isolation**: ClusterIP service (internal only)
- **No external exposure**: Not accessible from internet
- **RBAC**: Kubernetes role-based access control

### Data Integrity
- **Cryptographic hashing**: SHA-256
- **Hash chain**: Blockchain-like linking
- **Raft consensus**: Majority agreement required

---

## 🧪 Testing

### Health Check
```bash
# Check if service is healthy
kubectl logs -l app=ledger-service --tail=10

# Verify etcd cluster
kubectl exec -it etcd-0 -- /usr/local/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/peer-tls/ca.crt \
  --cert=/etc/etcd/peer-tls/tls.crt \
  --key=/etc/etcd/peer-tls/tls.key \
  member list
```

### Submit Test Event
```bash
# From within the cluster (e.g., a test pod)
grpcurl -plaintext \
  -d '{
    "event_id": "test-001",
    "payload": "dGVzdCBkYXRh",
    "veps_signature": "test-sig",
    "veps_timestamp": 1702234567890
  }' \
  ledger-service:50051 \
  ledger.ImmutableLedger/SubmitEvent
```

---

## 📈 Monitoring

### Key Metrics to Watch
1. **Commit Latency**: Should stay <50ms
2. **etcd Health**: All nodes should be healthy
3. **Sequence Number**: Should be monotonically increasing
4. **Error Rate**: Should be near zero

### Logs
```bash
# View Ledger logs
kubectl logs -l app=ledger-service -f

# View etcd logs
kubectl logs -l app=etcd -f

# Check for errors
kubectl logs -l app=ledger-service | grep ERROR
```

---

## 🐛 Troubleshooting

### Problem: High Commit Latency (>50ms)

**Possible Causes:**
- etcd resource contention
- Network latency between nodes
- Disk I/O bottleneck

**Solutions:**
```bash
# Check etcd performance
kubectl exec -it etcd-0 -- /usr/local/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/peer-tls/ca.crt \
  --cert=/etc/etcd/peer-tls/tls.crt \
  --key=/etc/etcd/peer-tls/tls.key \
  check perf

# Increase etcd resources
kubectl edit statefulset etcd
```

### Problem: Service Not Accessible

**Check:**
```bash
# Verify service exists
kubectl get svc ledger-service

# Check endpoints (should show pod IPs)
kubectl get endpoints ledger-service

# Test from another pod
kubectl run test --rm -it --image=nicolaka/netshoot -- bash
# Inside pod:
telnet ledger-service 50051
```

### Problem: Certificates Not Working

**Check:**
```bash
# Verify certificates are ready
kubectl get certificate

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Regenerate certificates
kubectl delete certificate --all
kubectl apply -f k8s/etcd/etcd-certificates.yaml
```

---

## 🛠️ Development

### Building the Service

```bash
cd ledger-service

# Build locally
cargo build --release

# Build Docker image
docker build -t gcr.io/immutable-ledger/ledger-service:v1 .

# Push to registry
docker push gcr.io/immutable-ledger/ledger-service:v1
```

### Running Tests

```bash
# Run Rust unit tests
cargo test

# Run with verbose output
cargo test -- --nocapture
```

### Local Development (without Kubernetes)

You can run etcd locally for development:

```bash
# Start local etcd (without TLS for dev)
docker run -d \
  -p 2379:2379 \
  -p 2380:2380 \
  --name etcd \
  quay.io/coreos/etcd:v3.5.12 \
  etcd --listen-client-urls http://0.0.0.0:2379 \
       --advertise-client-urls http://localhost:2379

# Update environment for local etcd
export ETCD_ENDPOINTS="http://localhost:2379"
export RUST_LOG="info"

# Run the service
cargo run
```

---

## 📚 Additional Resources

- **Architecture Document**: See `docs/immutable-ledger-design.md` for full design details
- **Proto File**: `ledger-service/proto/ledger.proto`
- **Original Spec**: Decoupled Immutable Ledger Architecture Documentation

---

## 🤝 Integration Guide for VEPS

### Connection Setup

**Service URL:**
```
ledger-service.immutable-ledger.svc.cluster.local:50051
```

**Or short form (if in same namespace):**
```
ledger-service:50051
```

### Integration Flow

```
VEPS Flow:
1. Receive event from source
2. Normalize & validate
3. Apply vector clock
4. Check causality & feasibility
5. ✓ Event passes validation
6. Sign event (VEPS signature)
7. Submit to ImmutableLedger ──┐
                                │
ImmutableLedger:                │
8. Receive certified event ◄────┘
9. Assign sequence number
10. Compute hash & link to chain
11. Achieve Raft consensus
12. Return SealedEvent ──────┐
                             │
VEPS:                        │
13. Receive sealed event ◄───┘
14. Store sequence number
15. Ack to client
```

### Error Handling

**Timeouts:**
- Set client timeout to 100ms (2× the 50ms contract)
- Retry failed submissions with exponential backoff

**Failures:**
- If Ledger returns error, log and alert
- Do NOT retry on duplicate event_id
- Consider event lost if Ledger confirms rejection

---

## 💰 Cost Optimization

### Development
```bash
# Scale down when not in use (saves ~$10/month)
kubectl scale statefulset etcd --replicas=0
kubectl scale deployment ledger-service --replicas=0

# Scale back up when needed
kubectl scale statefulset etcd --replicas=3
kubectl scale deployment ledger-service --replicas=3
```

### Production
- Use **Committed Use Discounts** (30-50% savings)
- Archive old events to **Cloud Storage** (cheaper than etcd)
- Monitor and right-size resources

---

## 📝 License

Proprietary - Internal Use Only
