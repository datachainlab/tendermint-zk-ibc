use anyhow::Result;
use plonky2x::{
    backend::{circuit::PlonkParameters, wrapper::wrap::WrappedOutput},
    prelude::plonky2::plonk::{
        circuit_data::VerifierOnlyCircuitData, proof::ProofWithPublicInputs,
    },
};

#[derive(Debug, serde::Serialize)]
pub struct ProveRequest<L: PlonkParameters<D>, const D: usize>
where
    L::Config: serde::Serialize,
{
    #[serde(rename = "proofWithPublicInputs")]
    pub proof_with_public_inputs: ProofWithPublicInputs<L::Field, L::Config, D>,
    #[serde(rename = "verifierOnlyCircuitData")]
    pub verifier_only_circuit_data: VerifierOnlyCircuitData<L::Config, D>,
}

impl<L: PlonkParameters<D>, const D: usize> ProveRequest<L, D>
where
    L::Config: serde::Serialize,
{
    pub fn new(wrapped_output: &WrappedOutput<L, D>) -> Self {
        Self {
            proof_with_public_inputs: wrapped_output.proof.clone(),
            verifier_only_circuit_data: wrapped_output.verifier_data.clone(),
        }
    }
}

pub(crate) async fn prove<L: PlonkParameters<D>, const D: usize>(
    address: &str,
    req: ProveRequest<L, D>,
) -> Result<Vec<u8>>
where
    L::Config: serde::Serialize,
{
    let url = format!("{}/prove", address);
    let client = reqwest::Client::new();
    let res = client.post(url).json(&req).send().await?;
    Ok(res.bytes().await.map_err(|e| anyhow::anyhow!(e))?.to_vec())
}

pub(crate) async fn health(address: &str) -> Result<()> {
    let url = format!("{}/health", address);
    let client = reqwest::Client::new();
    let res = client.get(url).send().await?;
    res.error_for_status_ref()?;
    Ok(())
}
