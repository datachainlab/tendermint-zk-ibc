{
  "chain": {
    "@type": "/relayer.chains.tendermint.config.ChainConfig",
    "key": "testkey",
    "chain_id": "ibc0",
    "rpc_addr": "http://localhost:26657",
    "account_prefix": "cosmos",
    "gas_adjustment": 1.5,
    "gas_prices": "0.025stake",
    "average_block_time_msec": 1000,
    "max_retry_for_commit": 5
  },
  "prover": {
    "@type": "/relayer.provers.tendermintzk.config.ProverConfig",
    "zk_prover_addr": "http://127.0.0.1:3000",
    "step_verifier_digest": "0x09bf185e9e478bac323981a844afe484dcd73823f6a34f5adb8cffe6c4436111",
    "skip_verifier_digest": "0x286fd609266936f71d552671b7553f1a0e59c7cf296112996bded1ca3bafa4a4",
    "prover_type": "",
    "trusting_period": "336h"
  }
}
