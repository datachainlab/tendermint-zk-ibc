package groth16

import (
	fmt "fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/datachainlab/tendermint-zk-ibc/go/relay/zkp"
)

var (
	groth16CommitmentProofABI, _ = abi.NewType("tuple", "Groth16CommitmentProof", []abi.ArgumentMarshaling{
		{Name: "proof", Type: "uint256[8]"},
		{Name: "commitments", Type: "uint256[2]"},
		{Name: "commitment_pok", Type: "uint256[2]"},
	})
)

type Groth16CommitmentProof struct {
	Proof         [8]*big.Int `json:"proof"`
	Commitments   [2]*big.Int `json:"commitments"`
	CommitmentPok [2]*big.Int `json:"commitment_pok"`
}

var _ zkp.ZKProof = (*Groth16CommitmentProof)(nil)

func (p Groth16CommitmentProof) EncodeEthABI() []byte {
	bz, err := EthABIEncodeGroth16CommitmentProof(p)
	if err != nil {
		panic(err)
	}
	return bz
}

func ParseGroth16CommitmentProof(proofBytes []byte) (*Groth16CommitmentProof, error) {
	var proof Groth16CommitmentProof
	// proof.Ar, proof.Bs, proof.Krs
	for i := 0; i < 8; i++ {
		proof.Proof[i] = new(big.Int).SetBytes(proofBytes[fpSize*i : fpSize*(i+1)])
	}
	c := new(big.Int).SetBytes(proofBytes[fpSize*8 : fpSize*8+4])
	commitmentCount := int(c.Int64())
	if commitmentCount != nbCommitments {
		return nil, fmt.Errorf("commitmentCount != nbCommitments: %d != %d", commitmentCount, nbCommitments)
	}
	// commitments
	for i := 0; i < 2*commitmentCount; i++ {
		proof.Commitments[i] = new(big.Int).SetBytes(proofBytes[fpSize*8+4+i*fpSize : fpSize*8+4+(i+1)*fpSize])
	}
	// commitmentPok
	proof.CommitmentPok[0] = new(big.Int).SetBytes(proofBytes[fpSize*8+4+2*commitmentCount*fpSize : fpSize*8+4+2*commitmentCount*fpSize+fpSize])
	proof.CommitmentPok[1] = new(big.Int).SetBytes(proofBytes[fpSize*8+4+2*commitmentCount*fpSize+fpSize : fpSize*8+4+2*commitmentCount*fpSize+2*fpSize])

	return &proof, nil
}

func EthABIEncodeGroth16CommitmentProof(proof Groth16CommitmentProof) ([]byte, error) {
	packer := abi.Arguments{
		{Type: groth16CommitmentProofABI},
	}
	return packer.Pack(proof)
}

func EthABIDecodeGroth16CommitmentProof(data []byte) (Groth16CommitmentProof, error) {
	packer := abi.Arguments{
		{Type: groth16CommitmentProofABI},
	}
	v, err := packer.Unpack(data)
	if err != nil {
		return Groth16CommitmentProof{}, err
	}
	return Groth16CommitmentProof(v[0].(struct {
		Proof         [8]*big.Int `json:"proof"`
		Commitments   [2]*big.Int `json:"commitments"`
		CommitmentPok [2]*big.Int `json:"commitment_pok"`
	})), nil
}
