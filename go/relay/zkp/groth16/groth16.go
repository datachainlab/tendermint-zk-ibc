package groth16

import (
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/datachainlab/tendermint-zk-ibc/go/relay/zkp"
)

const (
	// verifierDigest,inputHash,outputHash
	nbPublicInputs = 3
	nbCommitments  = 1
	fpSize         = 4 * 8

	Groth16ProverType           = "groth16"
	Groth16CommitmentProverType = "groth16-commitment"
)

var (
	groth16ProofABI, _ = abi.NewType("uint256[8]", "Groth16Proof", nil)
)

type Groth16Proof [8]*big.Int

var _ zkp.ZKProof = (*Groth16Proof)(nil)

func (p Groth16Proof) EncodeEthABI() []byte {
	bz, err := EthABIEncodeGroth16Proof(p)
	if err != nil {
		panic(err)
	}
	return bz
}

func ParseGroth16Proof(proofBytes []byte) (*Groth16Proof, error) {
	var proof Groth16Proof
	for i := 0; i < 8; i++ {
		proof[i] = new(big.Int).SetBytes(proofBytes[fpSize*i : fpSize*(i+1)])
	}
	return &proof, nil
}

func EthABIEncodeGroth16Proof(proof Groth16Proof) ([]byte, error) {
	packer := abi.Arguments{
		{Type: groth16ProofABI},
	}
	return packer.Pack(proof[:])
}

func EthABIDecodeGroth16Proof(bz []byte) (Groth16Proof, error) {
	packer := abi.Arguments{
		{Type: groth16ProofABI},
	}
	v, err := packer.Unpack(bz)
	if err != nil {
		return Groth16Proof{}, err
	}
	return Groth16Proof(v[0].([8]*big.Int)), nil
}
