use anyhow::Result;
use ethers::types::H256;
use log::*;
use plonky2x::backend::circuit::Circuit;
use plonky2x::backend::circuit::CircuitBuild;
use plonky2x::backend::circuit::DefaultParameters;
use plonky2x::backend::circuit::Groth16WrapperParameters;
use plonky2x::backend::wrapper::wrap::WrappedCircuit;
use plonky2x::backend::wrapper::wrap::WrappedOutput;
use plonky2x::frontend::uint::uint64::U64Variable;
use plonky2x::prelude::Bytes32Variable;
use plonky2x::prelude::DefaultBuilder;
use sha2::{Digest, Sha256};
use tendermintx::config::TendermintConfig;
use tendermintx::step::StepCircuit;

pub struct WrappedStepCircuitBuild(
    CircuitBuild<DefaultParameters, 2>,
    WrappedCircuit<DefaultParameters, Groth16WrapperParameters, 2>,
);

pub(crate) fn build_step_circuit<
    const CHAIN_ID_SIZE_BYTES: usize,
    const MAX_VALIDATOR_SET_SIZE: usize,
    C: TendermintConfig<CHAIN_ID_SIZE_BYTES>,
>() -> CircuitBuild<DefaultParameters, 2> {
    let mut builder = DefaultBuilder::new();

    debug!("Defining circuit");
    StepCircuit::<MAX_VALIDATOR_SET_SIZE, CHAIN_ID_SIZE_BYTES, C>::define(&mut builder);

    debug!("Building circuit");
    let circuit = builder.build();
    debug!("Done building circuit");
    circuit
}

pub(crate) fn build_wrapped_step_circuit<
    const CHAIN_ID_SIZE_BYTES: usize,
    const MAX_VALIDATOR_SET_SIZE: usize,
    C: TendermintConfig<CHAIN_ID_SIZE_BYTES>,
>() -> WrappedStepCircuitBuild {
    let wrapper = WrappedCircuit::<DefaultParameters, Groth16WrapperParameters, 2>::build(
        build_step_circuit::<CHAIN_ID_SIZE_BYTES, MAX_VALIDATOR_SET_SIZE, C>(),
    );
    WrappedStepCircuitBuild(
        build_step_circuit::<CHAIN_ID_SIZE_BYTES, MAX_VALIDATOR_SET_SIZE, C>(),
        wrapper,
    )
}

impl WrappedStepCircuitBuild {
    pub fn prove(
        &self,
        prev_height: u64,
        prev_header_hash: H256,
    ) -> Result<WrappedStepCircuitOutput> {
        let mut input = self.0.input();
        input.evm_write::<U64Variable>(prev_height);
        input.evm_write::<Bytes32Variable>(prev_header_hash);

        debug!("Generating proof");
        let (proof, mut output) = self.0.prove(&input);
        debug!("Done generating proof");

        let next_header = output.evm_read::<Bytes32Variable>();
        info!("next_header {:?}", next_header);

        let wrapped_proof = self.1.prove(&proof)?;

        let input_hash = {
            let mut hasher = Sha256::new();
            hasher.update(prev_height.to_be_bytes());
            hasher.update(prev_header_hash.as_bytes());
            H256::from_slice(&hasher.finalize())
        };
        Ok(WrappedStepCircuitOutput {
            input_hash,
            output_hash: H256::from_slice(Sha256::digest(next_header).as_slice()),
            next_header,
            wrapped_proof,
        })
    }
}

pub struct WrappedStepCircuitOutput {
    pub input_hash: H256,
    pub output_hash: H256,
    pub next_header: H256,
    pub wrapped_proof: WrappedOutput<Groth16WrapperParameters, 2>,
}

impl WrappedStepCircuitOutput {
    pub fn truncated_input_hash(&self) -> H256 {
        let mut hasher = Sha256::new();
        hasher.update(self.input_hash.as_bytes());
        H256::from_slice(&hasher.finalize())
    }

    pub fn truncated_output_hash(&self) -> H256 {
        let mut hasher = Sha256::new();
        hasher.update(self.output_hash.as_bytes());
        H256::from_slice(&hasher.finalize())
    }
}
