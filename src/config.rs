use konst::{primitive::parse_usize, result::unwrap_ctx};
use tendermintx::config::{TendermintConfig, SKIP_MAX};

pub const CHAIN_ID_BYTES: &[u8] = match option_env!("TENDERMINT_CHAIN_ID") {
    Some(chain_id) => chain_id.as_bytes(),
    None => b"ibc0",
};
pub const CHAIN_ID_SIZE_BYTES: usize = CHAIN_ID_BYTES.len();
pub const MAX_VALIDATOR_SET_SIZE: usize = match option_env!("TENDERMINT_MAX_VALIDATOR_SET_SIZE") {
    Some(max_validator_set_size) => unwrap_ctx!(parse_usize(max_validator_set_size)),
    None => 4,
};

#[derive(Debug, Clone, PartialEq)]
pub struct ChainConfig;

impl TendermintConfig<CHAIN_ID_SIZE_BYTES> for ChainConfig {
    const CHAIN_ID_BYTES: &'static [u8] = CHAIN_ID_BYTES;
    const SKIP_MAX: usize = SKIP_MAX;
}
