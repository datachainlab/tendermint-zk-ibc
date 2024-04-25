{
  "chain": {
    "@type": "/relayer.chains.ethereum.config.ChainConfig",
    "chain_id": "ibc1",
    "eth_chain_id": 2018,
    "rpc_addr": "http://localhost:8545",
    "signer": {
      "@type": "/relayer.chains.ethereum.signers.hd.SignerConfig",
      "mnemonic": "math razor capable expose worth grape metal sunset metal sudden usage scheme",
      "path": "m/44'/60'/0'/0/0"
    },
    "ibc_address": "0x727A5648832D2b317925CE043eA9b7fE04B4CD55",
    "initial_send_checkpoint": 1,
    "initial_recv_checkpoint": 1,
    "enable_debug_trace": true,
    "average_block_time_msec": 1000,
    "max_retry_for_inclusion": 5,
    "gas_estimate_rate": {
      "numerator": 3,
      "denominator": 2
    },
    "max_gas_limit": 10000000,
    "tx_type": "auto",
    "blocks_per_event_query": 1000,
    "allow_lc_functions": {
      "lc_address": "0xaa43d337145E8930d01cb4E60Abf6595C692921E",
      "allow_all": true
    }
  },
  "prover": {
    "@type": "/relayer.provers.mock.config.ProverConfig",
    "finality_delay": 0
  }
}
