# Build stage
FROM rust:1.83 AS builder

# Install protobuf compiler
RUN apt-get update && \
    apt-get install -y protobuf-compiler && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy everything
COPY . .

# Build the binary
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

# Install required runtime dependencies
RUN apt-get update && \
    apt-get install -y ca-certificates libssl3 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/target/release/ledger-service /app/ledger-service

# Create directory for certificates
RUN mkdir -p /etc/etcd-certs

# Expose gRPC port
EXPOSE 50051

# Run the service
CMD ["/app/ledger-service"]