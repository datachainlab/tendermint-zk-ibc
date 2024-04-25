mod circuits;
mod commands;
mod config;
mod gnark_verifier;
mod tendermint_client;

use anyhow::Result;
use clap::Parser;
use commands::Cli;

#[tokio::main]
async fn main() -> Result<()> {
    dotenv::dotenv().ok();
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("debug"));
    Cli::parse().run().await
}
