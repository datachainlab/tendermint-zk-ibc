package cmd

import (
	"github.com/cosmos/cosmos-sdk/codec"
	"github.com/hyperledger-labs/yui-relayer/config"
	"github.com/spf13/cobra"
)

func TendermintZKCmd(m codec.Codec, ctx *config.Context) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "tendermintzk",
		Short: "manage tendermint configurations",
	}

	cmd.AddCommand(
		lightCmd(ctx),
	)

	return cmd
}
