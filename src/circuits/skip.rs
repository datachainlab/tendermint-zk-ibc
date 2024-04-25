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
use tendermintx::skip::SkipCircuit;

pub struct WrappedSkipCircuitBuild(
    CircuitBuild<DefaultParameters, 2>,
    WrappedCircuit<DefaultParameters, Groth16WrapperParameters, 2>,
);

pub(crate) fn build_skip_circuit<
    const CHAIN_ID_SIZE_BYTES: usize,
    const MAX_VALIDATOR_SET_SIZE: usize,
    C: TendermintConfig<CHAIN_ID_SIZE_BYTES>,
>() -> CircuitBuild<DefaultParameters, 2> {
    let mut builder = DefaultBuilder::new();

    debug!("Defining circuit");
    SkipCircuit::<MAX_VALIDATOR_SET_SIZE, CHAIN_ID_SIZE_BYTES, C>::define(&mut builder);

    debug!("Building circuit");
    let circuit = builder.build();
    debug!("Done building circuit");
    circuit
}

pub(crate) fn build_wrapped_skip_circuit<
    const CHAIN_ID_SIZE_BYTES: usize,
    const MAX_VALIDATOR_SET_SIZE: usize,
    C: TendermintConfig<CHAIN_ID_SIZE_BYTES>,
>() -> WrappedSkipCircuitBuild {
    let wrapper = WrappedCircuit::<DefaultParameters, Groth16WrapperParameters, 2>::build(
        build_skip_circuit::<CHAIN_ID_SIZE_BYTES, MAX_VALIDATOR_SET_SIZE, C>(),
    );
    WrappedSkipCircuitBuild(
        build_skip_circuit::<CHAIN_ID_SIZE_BYTES, MAX_VALIDATOR_SET_SIZE, C>(),
        wrapper,
    )
}

impl WrappedSkipCircuitBuild {
    pub fn prove(
        &self,
        trusted_header: H256,
        trusted_height: u64,
        target_height: u64,
    ) -> Result<WrappedSkipCircuitOutput> {
        let mut input = self.0.input();
        input.evm_write::<U64Variable>(trusted_height);
        input.evm_write::<Bytes32Variable>(trusted_header);
        input.evm_write::<U64Variable>(target_height);

        debug!("Generating proof");
        let (proof, mut output) = self.0.prove(&input);
        debug!("Done generating proof");

        // self.0.verify(&proof, &input, &output);
        let target_header = output.evm_read::<Bytes32Variable>();
        info!("target_header {:?}", target_header);

        let wrapped_proof = self.1.prove(&proof).unwrap();

        let input_hash = {
            let mut hasher = Sha256::new();
            hasher.update(trusted_height.to_be_bytes());
            hasher.update(trusted_header.as_bytes());
            hasher.update(target_height.to_be_bytes());
            H256::from_slice(hasher.finalize().as_slice())
        };
        Ok(WrappedSkipCircuitOutput {
            input_hash,
            output_hash: H256::from_slice(Sha256::digest(target_header).as_slice()),
            target_header,
            wrapped_proof,
        })
    }
}

pub struct WrappedSkipCircuitOutput {
    pub input_hash: H256,
    pub output_hash: H256,
    pub target_header: H256,
    pub wrapped_proof: WrappedOutput<Groth16WrapperParameters, 2>,
}

impl WrappedSkipCircuitOutput {
    pub fn truncated_input_hash(&self) -> H256 {
        let mut input_hash = self.input_hash.clone();
        input_hash.0[0] &= 0x1F;
        input_hash
    }
    pub fn truncated_output_hash(&self) -> H256 {
        let mut output_hash = self.output_hash.clone();
        output_hash.0[0] &= 0x1F;
        output_hash
    }
}
