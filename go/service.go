package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sync"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/constraint"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/logger"
	"github.com/rs/zerolog"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"github.com/succinctlabs/gnark-plonky2-verifier/types"
	"github.com/succinctlabs/gnark-plonky2-verifier/variables"
)

const (
	flagAddr = "addr"
)

func serviceCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use: "service",
		RunE: func(cmd *cobra.Command, args []string) error {
			dataDir := viper.GetString(flagDataDir)
			srv, err := NewService(dataDir)
			if err != nil {
				return err
			}
			return srv.Start(
				viper.GetString(flagAddr),
			)
		},
	}
	return addrFlag(
		dataDirFlag(cmd),
	)
}

func addrFlag(cmd *cobra.Command) *cobra.Command {
	cmd.Flags().StringP(flagAddr, "a", ":3030", "address to listen on")
	if err := viper.BindPFlag(flagAddr, cmd.Flags().Lookup(flagAddr)); err != nil {
		panic(err)
	}
	return cmd
}

type Service struct {
	pk groth16.ProvingKey
	cs constraint.ConstraintSystem

	dataDir string
	logger  zerolog.Logger
}

func NewService(dataDir string) (*Service, error) {
	log := logger.Logger()
	log.Info().Msg("Reading R1CS")
	f, err := os.Open(r1csPath(dataDir))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	cs := groth16.NewCS(ecc.BN254)
	_, err = cs.ReadFrom(f)
	if err != nil {
		return nil, err
	}
	log.Info().Msg("Reading proving key")
	fPk, err := os.Open(provingKeyPath(dataDir))
	if err != nil {
		return nil, err
	}
	defer fPk.Close()
	pk := groth16.NewProvingKey(ecc.BN254)
	if _, err = pk.UnsafeReadFrom(fPk); err != nil {
		return nil, err
	}
	return &Service{pk: pk, cs: cs, dataDir: dataDir, logger: log}, nil
}

type ProveRequest struct {
	ProofWithPublicInputs   types.ProofWithPublicInputsRaw   `json:"proofWithPublicInputs"`
	VerifierOnlyCircuitData types.VerifierOnlyCircuitDataRaw `json:"verifierOnlyCircuitData"`
}

func (s *Service) Start(addr string) error {
	s.logger.Info().Str("addr", addr).Msg("starting service")
	var mu sync.Mutex
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/prove", func(w http.ResponseWriter, r *http.Request) {
		s.logger.Info().Msg("Received prove request")
		var req ProveRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			s.logger.Error().Msg("Error decoding request")
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		proofWithPisVariable := variables.DeserializeProofWithPublicInputs(req.ProofWithPublicInputs)
		inputHash, outputHash, err := getInputHashOutputHash(req.ProofWithPublicInputs)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		verifierOnlyCircuitData := variables.DeserializeVerifierOnlyCircuitData(req.VerifierOnlyCircuitData)
		assignment := Plonky2xVerifierCircuit{
			ProofWithPis:   proofWithPisVariable,
			VerifierData:   verifierOnlyCircuitData,
			VerifierDigest: verifierOnlyCircuitData.CircuitDigest,
			InputHash:      frontend.Variable(inputHash),
			OutputHash:     frontend.Variable(outputHash),
		}
		s.logger.Info().Msg("Generating witness")
		witness, err := frontend.NewWitness(&assignment, ecc.BN254.ScalarField())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		mu.Lock()
		defer mu.Unlock()
		s.logger.Info().Msg("Creating proof")
		proof, err := groth16.Prove(s.cs, s.pk, witness, backend.WithProverHashToFieldFunction(sha256.New()))
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		publicWitness, err := witness.Public()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		jsonData, err := parseInputAndProof(proof, publicWitness)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		res := ZKProofAndInputResponse{
			Input: jsonData.Input,
			Proof: jsonData.Proof,
		}
		bz, err := json.Marshal(res)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		s.logger.Info().Msg("Proof generated")
		w.Header().Set("Content-Type", "application/json")
		s.logger.Debug().Msg(string(bz))
		fmt.Fprint(w, string(bz))
	})
	return http.ListenAndServe(addr, nil)
}

type ZKProofAndInputResponse struct {
	Input [nbPublicInputs]HexBigInt `json:"input"`
	Proof []byte                    `json:"proof"`
}
