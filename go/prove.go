package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark-crypto/ecc/bn254/fr"
	"github.com/consensys/gnark/backend"
	"github.com/consensys/gnark/backend/groth16"
	groth16_bn254 "github.com/consensys/gnark/backend/groth16/bn254"
	"github.com/consensys/gnark/backend/witness"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/logger"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"github.com/succinctlabs/gnark-plonky2-verifier/types"
	"github.com/succinctlabs/gnark-plonky2-verifier/variables"
)

const (
	// verifierDigest,inputHash,outputHash
	nbPublicInputs = 3
	nbCommitments  = 1
	fpSize         = 4 * 8
)

func proveCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use: "prove",
		RunE: func(cmd *cobra.Command, args []string) error {
			dataDir := viper.GetString(flagDataDir)
			proofDir := viper.GetString(flagProofPath)
			return prove(dataDir, proofDir)
		},
	}

	cmd = proofFlag(dataDirFlag(cmd))
	cobra.MarkFlagRequired(
		cmd.Flags(),
		flagDataDir,
	)
	cobra.MarkFlagRequired(
		cmd.Flags(),
		flagProofPath,
	)
	return cmd
}

func prove(dataDir, proofDir string) error {
	log := logger.Logger()

	proofWithPis := types.ReadProofWithPublicInputs(proofWithPublicInputsFile(proofDir))
	proofWithPisVariable := variables.DeserializeProofWithPublicInputs(proofWithPis)
	inputHash, outputHash, err := getInputHashOutputHash(proofWithPis)
	if err != nil {
		return err
	}
	verifierOnlyCircuitData := variables.DeserializeVerifierOnlyCircuitData(types.ReadVerifierOnlyCircuitData(verifierOnlyCircuitDataFile(proofDir)))
	assignment := Plonky2xVerifierCircuit{
		ProofWithPis:   proofWithPisVariable,
		VerifierData:   verifierOnlyCircuitData,
		VerifierDigest: verifierOnlyCircuitData.CircuitDigest,
		InputHash:      frontend.Variable(inputHash),
		OutputHash:     frontend.Variable(outputHash),
	}

	log.Info().Msg("Reading R1CS")
	f, err := os.Open(r1csPath(dataDir))
	if err != nil {
		return err
	}
	defer f.Close()
	cs := groth16.NewCS(ecc.BN254)
	_, err = cs.ReadFrom(f)
	if err != nil {
		return err
	}
	log.Info().Msg("Reading proving key")
	fPk, err := os.Open(provingKeyPath(dataDir))
	if err != nil {
		return err
	}
	defer fPk.Close()
	pk := groth16.NewProvingKey(ecc.BN254)
	if _, err = pk.UnsafeReadFrom(fPk); err != nil {
		return err
	}

	log.Info().Msg("Generating witness")
	witness, err := frontend.NewWitness(&assignment, ecc.BN254.ScalarField())
	if err != nil {
		return err
	}
	log.Info().Msg("Creating proof")
	proof, err := groth16.Prove(cs, pk, witness, backend.WithProverHashToFieldFunction(sha256.New()))
	if err != nil {
		return err
	}
	publicWitness, err := witness.Public()
	if err != nil {
		return err
	}
	_, err = parseInputAndProof(proof, publicWitness)
	return err
}

func getInputHashOutputHash(proofWithPis types.ProofWithPublicInputsRaw) (*big.Int, *big.Int, error) {
	publicInputs := proofWithPis.PublicInputs
	if len(publicInputs) != 64 {
		return nil, nil, fmt.Errorf("publicInputs must be 64 bytes")
	}
	publicInputsBytes := make([]byte, 64)
	for i, v := range publicInputs {
		publicInputsBytes[i] = byte(v & 0xFF)
	}
	inputHash := new(big.Int).SetBytes(publicInputsBytes[0:32])
	outputHash := new(big.Int).SetBytes(publicInputsBytes[32:64])
	if inputHash.BitLen() > 253 {
		return nil, nil, fmt.Errorf("inputHash must be at most 253 bits")
	}
	if outputHash.BitLen() > 253 {
		return nil, nil, fmt.Errorf("outputHash must be at most 253 bits")
	}
	return inputHash, outputHash, nil
}

type HexBigInt big.Int

func (b HexBigInt) Bytes() []byte {
	return (*big.Int)(&b).Bytes()
}

func (b HexBigInt) MarshalJSON() ([]byte, error) {
	bz := (*big.Int)(&b).Bytes()
	hexString := "0x" + hex.EncodeToString(bz)
	return json.Marshal(hexString)
}

func (b *HexBigInt) UnmarshalJSON(data []byte) (err error) {
	var hexString string
	if err = json.Unmarshal(data, &hexString); err != nil {
		return
	}
	bz, err := hex.DecodeString(strings.TrimPrefix(hexString, "0x"))
	if err != nil {
		return err
	}
	*b = *(*HexBigInt)(new(big.Int).SetBytes(bz))
	return
}

type GeneralInputsAndProof struct {
	Input [nbPublicInputs]HexBigInt `json:"input"`
	Proof []byte                    `json:"proof"`
}

func parseInputAndProof(proof groth16.Proof, publicWitness witness.Witness) (*GeneralInputsAndProof, error) {
	proofBytes := proof.(*groth16_bn254.Proof).MarshalSolidity()
	// public witness to hex
	bPublicWitness, err := publicWitness.MarshalBinary()
	if err != nil {
		return nil, err
	}
	// that's quite dirty...
	// first 4 bytes -> nbPublic
	// next 4 bytes -> nbSecret
	// next 4 bytes -> nb elements in the vector (== nbPublic + nbSecret)
	bPublicWitness = bPublicWitness[12:]
	publicWitnessStr := hex.EncodeToString(bPublicWitness)

	fmt.Printf("export HEX_PROOF=%s\n", hex.EncodeToString(proofBytes))
	fmt.Printf("export HEX_PUBLIC_INPUTS=%s\n", publicWitnessStr)

	// convert public inputs
	nbInputs := len(bPublicWitness) / fr.Bytes
	if nbInputs != nbPublicInputs {
		return nil, fmt.Errorf("nbInputs != nbPublicInputs: %d != %d", nbInputs, nbPublicInputs)
	}
	var input [nbPublicInputs]HexBigInt
	for i := 0; i < nbInputs; i++ {
		var e fr.Element
		e.SetBytes(bPublicWitness[fr.Bytes*i : fr.Bytes*(i+1)])
		in := new(big.Int)
		e.BigInt(in)
		input[i] = HexBigInt(*in)
	}

	return &GeneralInputsAndProof{
		Input: input,
		Proof: proofBytes,
	}, nil

}

func proofWithPublicInputsFile(dataDir string) string {
	return filepath.Join(dataDir, "proof_with_public_inputs.json")
}

func verifierOnlyCircuitDataFile(dataDir string) string {
	return filepath.Join(dataDir, "verifier_only_circuit_data.json")
}

func checkErr(err error, ctx string) {
	if err != nil {
		panic(ctx + " " + err.Error())
	}
}
