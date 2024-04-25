mod prove;
mod service;

use self::{prove::ProveCommand, service::ServiceCommand};
use anyhow::Result;
use clap::Parser;
use log::*;
use tendermintx::config::TendermintConfig;

#[derive(Debug, Parser)]
pub struct Cli {
    #[clap(subcommand)]
    pub command: Command,
}

impl Cli {
    pub async fn run(self) -> Result<()> {
        debug!("Running command: {:?}", self.command);
        debug!(
            "CHAIN_ID_BYTES: {:?}({:?})",
            crate::config::ChainConfig::CHAIN_ID_BYTES,
            String::from_utf8(crate::config::ChainConfig::CHAIN_ID_BYTES.to_vec())
        );
        debug!("SKIP_MAX: {}", crate::config::ChainConfig::SKIP_MAX);
        debug!(
            "MAX_VALIDATOR_SET_SIZE: {}",
            crate::config::MAX_VALIDATOR_SET_SIZE
        );
        match self.command {
            Command::Prove(prove) => prove.run().await?,
            Command::Service(service) => service.run().await?,
        }
        Ok(())
    }
}

#[derive(Debug, Parser)]
pub enum Command {
    #[clap(display_order = 1, about = "Prove subcommands")]
    Prove(ProveCommand),
    #[clap(display_order = 2, about = "Service subcommands")]
    Service(ServiceCommand),
}
