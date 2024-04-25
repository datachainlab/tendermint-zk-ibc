package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/frontend/cs/r1cs"
	"github.com/consensys/gnark/logger"
	"github.com/consensys/gnark/profile"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"github.com/succinctlabs/gnark-plonky2-verifier/types"
	"github.com/succinctlabs/gnark-plonky2-verifier/variables"
)

type ProvingSystem string

const (
	Groth16           ProvingSystem = "groth16"
	Groth16Commitment ProvingSystem = "groth16-commitment"
)

func parseProvingSystem(ps string) (ProvingSystem, error) {
	switch ps {
	case "groth16":
		return Groth16, nil
	case "groth16-commitment":
		return Groth16Commitment, nil
	default:
		return "", fmt.Errorf("unknown proving system %s", ps)
	}
}

func setupCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use: "setup",
		RunE: func(cmd *cobra.Command, args []string) error {
			log := logger.Logger()
			ps, err := parseProvingSystem(viper.GetString(flagProvingSystem))
			if err != nil {
				log.Error().Msgf("error parsing proving system: %v", err)
				os.Exit(1)
			}
			dataDir := viper.GetString(flagDataDir)
			if len(dataDir) == 0 {
				panic("data directory is required")
			}
			dummyDir := viper.GetString(flagDummyPlonky2DataDir)
			if err := dirExists(dummyDir); err != nil {
				log.Error().Msgf("dummy data directory %s does not exist", dummyDir)
			}
			// if not exists, create it
			if err := dirExists(dataDir); err != nil {
				log.Printf("creating data directory %s", dataDir)
				if err := os.MkdirAll(dataDir, 0700); err != nil {
					log.Fatal().Msgf("error creating data directory %s: %v", dataDir, err)
					os.Exit(1)
				}
			}
			return setup(ps, dataDir, dummyDir)
		},
	}
	cmd = dummyPlonky2DataDirFlag(dataDirFlag(provingSystemFlag(cmd)))
	cobra.MarkFlagRequired(
		cmd.Flags(),
		flagProvingSystem,
	)
	cobra.MarkFlagRequired(
		cmd.Flags(),
		flagDataDir,
	)
	cobra.MarkFlagRequired(
		cmd.Flags(),
		flagDummyPlonky2DataDir,
	)
	return cmd
}

func setup(ps ProvingSystem, dataDir string, dummyDataDir string) error {
	log := logger.Logger()

	if ps == Groth16 {
		os.Setenv("USE_BIT_DECOMPOSITION_RANGE_CHECK", "true")
	} else if ps == Groth16Commitment {
		os.Unsetenv("USE_BIT_DECOMPOSITION_RANGE_CHECK")
	}

	var circuit Plonky2xVerifierCircuit
	circuit.ProofWithPis = variables.DeserializeProofWithPublicInputs(types.ReadProofWithPublicInputs(dummyDataDir + "/proof_with_public_inputs.json"))
	circuit.VerifierData = variables.DeserializeVerifierOnlyCircuitData(types.ReadVerifierOnlyCircuitData(dummyDataDir + "/verifier_only_circuit_data.json"))
	circuit.CommonCircuitData = types.ReadCommonCircuitData(commonCircuitData(dummyDataDir))

	p := profile.Start()

	log.Info().Msg("Building circuit")
	cs, err := frontend.Compile(ecc.BN254.ScalarField(), r1cs.NewBuilder, &circuit)
	if err != nil {
		log.Error().Msgf("error in building circuit: %v", err)
		os.Exit(1)
	}
	log.Info().Msg("Circuit built")
	f, err := os.Create(r1csPath(dataDir))
	if err != nil {
		return err
	}
	_, err = cs.WriteTo(f)
	if err != nil {
		return err
	}

	p.Stop()
	p.Top()
	log.Info().Msgf("r1cs.GetNbCoefficients(): %v", cs.GetNbCoefficients())
	log.Info().Msgf("r1cs.GetNbConstraints(): %v", cs.GetNbConstraints())
	log.Info().Msgf("r1cs.GetNbSecretVariables(): %v", cs.GetNbSecretVariables())
	log.Info().Msgf("r1cs.GetNbPublicVariables(): %v", cs.GetNbPublicVariables())
	log.Info().Msgf("r1cs.GetNbInternalVariables(): %v", cs.GetNbInternalVariables())

	log.Info().Msg("Running circuit setup")
	log.Info().Msg("Using real setup")
	pk, vk, err := groth16.Setup(cs)
	if err != nil {
		return err
	}
	fVK, err := os.Create(verifyingKeyPath(dataDir))
	if err != nil {
		return err
	}
	vk.WriteTo(fVK)
	fVK.Close()
	fSolidity, err := os.Create(filepath.Join(dataDir, "Plonky2Verifier.sol"))
	if err != nil {
		return err
	}
	err = vk.ExportSolidity(fSolidity)
	if err != nil {
		return err
	}
	fPK, _ := os.Create(provingKeyPath(dataDir))
	pk.WriteTo(fPK)
	fPK.Close()

	return nil
}

func r1csPath(dataDir string) string {
	return filepath.Join(dataDir, "r1cs.bin")
}

func verifyingKeyPath(dataDir string) string {
	return filepath.Join(dataDir, "vk.bin")
}

func provingKeyPath(dataDir string) string {
	return filepath.Join(dataDir, "pk.bin")
}

func commonCircuitData(dummyDataDir string) string {
	return filepath.Join(dummyDataDir, "common_circuit_data.json")
}
