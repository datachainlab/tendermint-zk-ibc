package relay

import (
	"github.com/ethereum/go-ethereum/accounts/abi"
)

var (
	existenceProofsABI, _ = abi.NewType("tuple[2]", "ExistenceProof[]", []abi.ArgumentMarshaling{
		{Name: "spec", Type: "uint8"},
		{Name: "prefix", Type: "bytes"},
		{Name: "key", Type: "bytes"},
		{Name: "value", Type: "bytes"},
		{Name: "path", Type: "tuple[]", Components: []abi.ArgumentMarshaling{
			{Name: "prefix", Type: "bytes"},
			{Name: "suffix", Type: "bytes"},
		}},
	})
)

type ExistenceProof struct {
	Spec   uint8  `json:"spec"`
	Prefix []byte `json:"prefix"`
	Key    []byte `json:"key"`
	Value  []byte `json:"value"`
	Path   []struct {
		Prefix []byte `json:"prefix"`
		Suffix []byte `json:"suffix"`
	} `json:"path"`
}

func EthABIEncodeExistenceProofs(proofs []ExistenceProof) ([]byte, error) {
	packer := abi.Arguments{
		{Type: existenceProofsABI},
	}
	return packer.Pack(proofs)
}

func EthABIDecodeExistenceProofs(data []byte) ([]ExistenceProof, error) {
	packer := abi.Arguments{
		{Type: existenceProofsABI},
	}
	v, err := packer.Unpack(data)
	if err != nil {
		return nil, err
	}
	ps := v[0].([]struct {
		Spec   uint8  `json:"spec"`
		Prefix []byte `json:"prefix"`
		Key    []byte `json:"key"`
		Value  []byte `json:"value"`
		Path   []struct {
			Prefix []byte `json:"prefix"`
			Suffix []byte `json:"suffix"`
		} `json:"path"`
	})
	proofs := make([]ExistenceProof, 0)
	for _, proof := range ps {
		proofs = append(proofs, ExistenceProof(proof))
	}
	return proofs, nil
}
