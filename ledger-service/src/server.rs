use tonic::{transport::Server, Request, Response, Status};
use std::net::SocketAddr;
use std::sync::Arc;
use tracing::{info, error};

use crate::ledger::Ledger;

// Import the generated protobuf code
pub mod ledger_proto {
    tonic::include_proto!("ledger");
}

use ledger_proto::{
    immutable_ledger_server::{ImmutableLedger, ImmutableLedgerServer},
    CertifiedEvent, SealedEvent, GetEventRequest,
    HealthCheckRequest, HealthCheckResponse,
};

/// gRPC service implementation
pub struct LedgerService {
    ledger: Arc<Ledger>,
}

#[tonic::async_trait]
impl ImmutableLedger for LedgerService {
    /// Submit a certified event for sealing
    async fn submit_event(
        &self,
        request: Request<CertifiedEvent>,
    ) -> Result<Response<SealedEvent>, Status> {
        let event = request.into_inner();
        
        info!("Received SubmitEvent request for event_id: {}", event.event_id);

        // Call the core sealing logic
        let sealed = self.ledger
            .seal_event(
                event.event_id.clone(),
                event.payload,
                event.veps_signature,
                event.veps_timestamp,
            )
            .await
            .map_err(|e| {
                error!("Failed to seal event {}: {}", event.event_id, e);
                Status::internal(format!("Sealing failed: {}", e))
            })?;

        // Convert to protobuf response
        let response = SealedEvent {
            sequence_number: sealed.sequence_number,
            event_id: sealed.event_id,
            payload: sealed.payload,
            event_hash: sealed.event_hash,
            previous_hash: sealed.previous_hash,
            sealed_timestamp: sealed.sealed_timestamp,
            commit_latency_ms: sealed.commit_latency_ms,
        };

        Ok(Response::new(response))
    }

    /// Get a sealed event by sequence number
    async fn get_event(
        &self,
        request: Request<GetEventRequest>,
    ) -> Result<Response<SealedEvent>, Status> {
        let sequence_number = request.into_inner().sequence_number;
        
        info!("Received GetEvent request for sequence: {}", sequence_number);

        let sealed = self.ledger
            .get_event(sequence_number)
            .await
            .map_err(|e| {
                error!("Failed to get event {}: {}", sequence_number, e);
                Status::internal(format!("Get event failed: {}", e))
            })?;

        match sealed {
            Some(event) => {
                let response = SealedEvent {
                    sequence_number: event.sequence_number,
                    event_id: event.event_id,
                    payload: event.payload,
                    event_hash: event.event_hash,
                    previous_hash: event.previous_hash,
                    sealed_timestamp: event.sealed_timestamp,
                    commit_latency_ms: event.commit_latency_ms,
                };
                Ok(Response::new(response))
            }
            None => Err(Status::not_found(format!(
                "Event with sequence {} not found",
                sequence_number
            ))),
        }
    }

    /// Health check endpoint
    async fn health_check(
        &self,
        _request: Request<HealthCheckRequest>,
    ) -> Result<Response<HealthCheckResponse>, Status> {
        let current_sequence = self.ledger
            .get_current_sequence()
            .await
            .map_err(|e| {
                error!("Health check failed: {}", e);
                Status::internal("Health check failed")
            })?;

        let response = HealthCheckResponse {
            healthy: true,
            status: "ok".to_string(),
            last_sequence_number: current_sequence,
        };

        Ok(Response::new(response))
    }
}

/// Start the gRPC server
pub async fn start_server(addr: SocketAddr, ledger: Ledger) -> Result<(), anyhow::Error> {
    let service = LedgerService {
        ledger: Arc::new(ledger),
    };

    info!("ImmutableLedger gRPC server listening on {}", addr);

    Server::builder()
        .add_service(ImmutableLedgerServer::new(service))
        .serve(addr)
        .await
        .map_err(|e| anyhow::anyhow!("Server error: {}", e))?;

    Ok(())
}