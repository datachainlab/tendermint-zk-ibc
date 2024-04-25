package main

import (
	"log"

	"github.com/datachainlab/ethereum-ibc-relay-chain/pkg/relay/ethereum"
	"github.com/datachainlab/ethereum-ibc-relay-chain/pkg/relay/ethereum/signers/hd"
	tendermint "github.com/hyperledger-labs/yui-relayer/chains/tendermint/module"
	"github.com/hyperledger-labs/yui-relayer/cmd"
	mock "github.com/hyperledger-labs/yui-relayer/provers/mock/module"
	tmzk "github.com/datachainlab/tendermint-zk-ibc/go/relay/module"
)

func main() {
	if err := cmd.Execute(
		tendermint.Module{},
		mock.Module{},
		ethereum.Module{},
		hd.Module{},
		tmzk.Module{},
	); err != nil {
		log.Fatal(err)
	}
}
