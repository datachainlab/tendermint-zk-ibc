package main

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

const (
	flagDataDir             = "data"
	flagProofPath           = "proof"
	flagDummyPlonky2DataDir = "dummydata"
	flagProvingSystem       = "proving-system"
)

var rootCmd = &cobra.Command{
	Use: "gnark-plonky2-verifier",
}

func provingSystemFlag(cmd *cobra.Command) *cobra.Command {
	cmd.Flags().StringP(flagProvingSystem, "s", "", "proving system to use")
	if err := viper.BindPFlag(flagProvingSystem, cmd.Flags().Lookup(flagProvingSystem)); err != nil {
		panic(err)
	}
	return cmd
}

func dataDirFlag(cmd *cobra.Command) *cobra.Command {
	cmd.Flags().StringP(flagDataDir, "d", "", "path to the data directory")
	if err := viper.BindPFlag(flagDataDir, cmd.Flags().Lookup(flagDataDir)); err != nil {
		panic(err)
	}
	return cmd
}

func proofFlag(cmd *cobra.Command) *cobra.Command {
	cmd.Flags().StringP(flagProofPath, "p", "", "path to the proof file")
	if err := viper.BindPFlag(flagProofPath, cmd.Flags().Lookup(flagProofPath)); err != nil {
		panic(err)
	}
	return cmd
}

func dummyPlonky2DataDirFlag(cmd *cobra.Command) *cobra.Command {
	cmd.Flags().StringP(flagDummyPlonky2DataDir, "", "", "path to the dummy plonky2 data directory")
	if err := viper.BindPFlag(flagDummyPlonky2DataDir, cmd.Flags().Lookup(flagDummyPlonky2DataDir)); err != nil {
		panic(err)
	}
	return cmd
}

func main() {
	rootCmd.PersistentPreRunE = func(cmd *cobra.Command, _ []string) error {
		if err := viper.BindPFlags(cmd.Flags()); err != nil {
			return fmt.Errorf("failed to bind the flag set to the configuration: %v", err)
		}
		return nil
	}
	rootCmd.AddCommand(setupCmd(), proveCmd(), serviceCmd())
	if err := rootCmd.Execute(); err != nil {
		panic(err)
	}
}
