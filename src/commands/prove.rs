use crate::circuits::{build_wrapped_skip_circuit, build_wrapped_step_circuit};
use crate::config::{ChainConfig, CHAIN_ID_SIZE_BYTES, MAX_VALIDATOR_SET_SIZE};
use crate::tendermint_client::fetch_trusted_block_hash;
use anyhow::Result;
use clap::Parser;
use log::*;
use std::env;
use std::path;
use tendermintx::config::SKIP_MAX;

#[derive(Debug, Parser)]
pub struct ProveCommand {
    #[clap(long = "trusted-height", help = "Trusted height")]
    pub trusted_height: u64,
    #[clap(long = "target-height", help = "Target height")]
    pub target_height: u64,
    #[clap(long = "data-dir")]
    pub data_dir: String,
    #[clap(long = "proof-dir")]
    pub proof_dir: String,
    #[clap(
        long = "gnark-verifier-bin",
        default_value = "gnark-verifier",
        help = "Path to the gnark verifier binary"
    )]
    pub gnark_verifier_bin: String,
}

impl ProveCommand {
    pub async fn run(self) -> Result<()> {
        let url = env::var("TENDERMINT_RPC_URL").expect("TENDERMINT_RPC_URL is not set in .env");

        let data_dir = self.data_dir.as_str();
        let proof_dir = self.proof_dir.as_str();

        // check if data_dir exists
        if !path::Path::new(data_dir).exists() {
            panic!("data_dir does not exist");
        }
        // if proof_dir does not exist, create it
        if !path::Path::new(proof_dir).exists() {
            std::fs::create_dir(proof_dir).unwrap();
        }

        if self.target_height <= self.trusted_height {
            panic!("target_height must be greater than trusted_height");
        }
        if self.target_height - self.trusted_height > SKIP_MAX as u64 {
            panic!("target_height - trusted_height must be less than or equal to SKIP_MAX");
        }

        let hash = fetch_trusted_block_hash(&url, self.trusted_height).await;

        if self.target_height - self.trusted_height == 1 {
            let wrapped_step_circuit = build_wrapped_step_circuit::<
                CHAIN_ID_SIZE_BYTES,
                MAX_VALIDATOR_SET_SIZE,
                ChainConfig,
            >();
            let output = wrapped_step_circuit
                .prove(self.trusted_height, hash)
                .unwrap();
            info!("Input hash: {:?}", output.truncated_input_hash());
            info!("Output hash: {:?}", output.truncated_output_hash());
            info!("Next header: {:?}", output.next_header);
            output.wrapped_proof.save(proof_dir).unwrap();
            info!("Proof saved to {}", proof_dir);
        } else {
            let wrapped_skip_circuit = build_wrapped_skip_circuit::<
                CHAIN_ID_SIZE_BYTES,
                MAX_VALIDATOR_SET_SIZE,
                ChainConfig,
            >();
            let output = wrapped_skip_circuit
                .prove(hash, self.trusted_height, self.target_height)
                .unwrap();
            info!("Input hash: {:?}", output.truncated_input_hash());
            info!("Output hash: {:?}", output.truncated_output_hash());
            info!("Target header: {:?}", output.target_header);
            output.wrapped_proof.save(proof_dir).unwrap();
            info!("Proof saved to {}", proof_dir);
        }

        let mut child_process =
            std::process::Command::new(path::Path::new(self.gnark_verifier_bin.as_str()))
                .arg("prove")
                .arg("--data")
                .arg(data_dir)
                .arg("--proof")
                .arg(proof_dir)
                .stdout(std::process::Stdio::inherit())
                .stderr(std::process::Stdio::inherit())
                .stdin(std::process::Stdio::piped())
                .spawn()
                .expect("Failed to start gnark verifier");
        child_process
            .wait()
            .expect("Failed to wait for gnark verifier");

        Ok(())
    }
}
