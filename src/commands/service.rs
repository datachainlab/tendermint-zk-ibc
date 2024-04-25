use crate::circuits::{
    build_wrapped_skip_circuit, build_wrapped_step_circuit, WrappedSkipCircuitBuild,
    WrappedStepCircuitBuild,
};
use crate::config::{ChainConfig, CHAIN_ID_SIZE_BYTES, MAX_VALIDATOR_SET_SIZE};
use crate::gnark_verifier::{self, ProveRequest};
use anyhow::Result;
use axum::extract::{Json, Query, State};
use axum::{routing::get, Router};
use clap::Parser;
use ethers::types::H256;
use log::*;
use plonky2x::backend::{circuit::Groth16WrapperParameters, wrapper::wrap::WrappedOutput};
use serde_json::Value;
use std::env;
use std::sync::Arc;
use tendermintx::config::SKIP_MAX;
use tower::limit::ConcurrencyLimitLayer;
use tower::ServiceBuilder;
use tower_http::catch_panic::CatchPanicLayer;

#[derive(Debug, Parser)]
pub struct ServiceCommand {
    #[clap(
        long = "addr",
        default_value = "0.0.0.0:3000",
        help = "Address of the service"
    )]
    pub addr: String,
    #[clap(
        long = "gnark-verifier-address",
        default_value = "http://127.0.0.1:3030",
        help = "Address of the gnark verifier service"
    )]
    pub gnark_verifier_address: String,
}

#[derive(serde::Deserialize)]
pub struct ProveArgs {
    pub trusted_height: u64,
    pub target_height: u64,
}

impl ProveArgs {
    pub fn validate(&self) -> Result<()> {
        if self.target_height <= self.trusted_height {
            panic!("target_height must be greater than trusted_height");
        }
        if self.target_height - self.trusted_height > SKIP_MAX as u64 {
            panic!("target_height - trusted_height must be less than or equal to SKIP_MAX");
        }
        Ok(())
    }
}

impl ServiceCommand {
    pub async fn run(self) -> Result<()> {
        let tm_url = env::var("TENDERMINT_RPC_URL").expect("TENDERMINT_RPC_URL is not set in .env");
        let shared_state = Arc::new(ServiceState {
            tm_url,
            gnark_verifier_address: self.gnark_verifier_address,
            #[cfg(feature = "step")]
            wrapped_step_circuit: build_wrapped_step_circuit::<
                CHAIN_ID_SIZE_BYTES,
                MAX_VALIDATOR_SET_SIZE,
                ChainConfig,
            >(),
            wrapped_skip_circuit: build_wrapped_skip_circuit::<
                CHAIN_ID_SIZE_BYTES,
                MAX_VALIDATOR_SET_SIZE,
                ChainConfig,
            >(),
        });
        let app = Router::new()
            .route("/health", get(health))
            .route("/prove", get(prove).layer(ConcurrencyLimitLayer::new(1)))
            .with_state(shared_state)
            .layer(
                ServiceBuilder::new()
                    .layer(CatchPanicLayer::new())
                    .into_inner(),
            );
        let listener = tokio::net::TcpListener::bind(&self.addr).await.unwrap();
        info!("Listening on {}", self.addr);
        axum::serve(listener, app).await.unwrap();
        Ok(())
    }
}

pub struct ServiceState {
    pub tm_url: String,

    pub gnark_verifier_address: String,

    #[cfg(feature = "step")]
    pub wrapped_step_circuit: WrappedStepCircuitBuild,
    pub wrapped_skip_circuit: WrappedSkipCircuitBuild,
}

#[cfg(feature = "step")]
fn prove_step_circuit(
    state: Arc<ServiceState>,
    trusted_height: u64,
    block_hash: H256,
) -> Result<WrappedOutput<Groth16WrapperParameters, 2>> {
    info!("Using step circuit");
    let output = state
        .wrapped_step_circuit
        .prove(trusted_height, block_hash)
        .unwrap();
    info!("Input hash: {:?}", output.truncated_input_hash());
    info!("Output hash: {:?}", output.truncated_output_hash());
    info!("Next header: {:?}", output.next_header);
    Ok(output.wrapped_proof)
}

fn prove_skip_circuit(
    state: Arc<ServiceState>,
    trusted_height: u64,
    target_height: u64,
    block_hash: H256,
) -> Result<WrappedOutput<Groth16WrapperParameters, 2>> {
    info!("Using skip circuit");
    let output = state
        .wrapped_skip_circuit
        .prove(block_hash, trusted_height, target_height)
        .unwrap();
    info!("Input hash: {:?}", output.truncated_input_hash());
    info!("Output hash: {:?}", output.truncated_output_hash());
    info!("Target header: {:?}", output.target_header);
    Ok(output.wrapped_proof)
}

async fn prove(
    State(state): State<Arc<ServiceState>>,
    Query(params): Query<ProveArgs>,
) -> Json<Value> {
    params.validate().unwrap();

    let hash =
        crate::tendermint_client::fetch_trusted_block_hash(&state.tm_url, params.trusted_height)
            .await;

    // get current time
    let start = std::time::Instant::now();
    let wrapped_proof = if params.target_height - params.trusted_height == 1 {
        cfg_if::cfg_if! {
            if #[cfg(feature = "step")] {
                prove_step_circuit(state.clone(), params.trusted_height, hash).unwrap()
            } else {
                panic!("step circuit is not enabled")
            }
        }
    } else {
        prove_skip_circuit(
            state.clone(),
            params.trusted_height,
            params.target_height,
            hash,
        )
        .unwrap()
    };
    // get elapsed time
    let elapsed = start.elapsed();
    info!("Elapsed time: {:?}", elapsed);

    let req = ProveRequest::new(&wrapped_proof);
    Json(
        serde_json::from_slice(
            gnark_verifier::prove(&state.gnark_verifier_address, req)
                .await
                .unwrap()
                .as_ref(),
        )
        .unwrap(),
    )
}

async fn health(State(state): State<Arc<ServiceState>>) -> Json<Value> {
    let res = gnark_verifier::health(&state.gnark_verifier_address).await;
    if res.is_ok() {
        Json(serde_json::json!({"gnark_verifier": "healthy"}))
    } else {
        Json(serde_json::json!({"gnark_verifier": "unhealthy"}))
    }
}
