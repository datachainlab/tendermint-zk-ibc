package relay

import (
	"reflect"
	"testing"
)

func TestExistenceProofEncoding(t *testing.T) {
	var proofs = []ExistenceProof{
		{
			Spec:   1,
			Prefix: []byte{0x01},
			Key:    []byte{0x02},
			Value:  []byte{0x03},
			Path: []struct {
				Prefix []byte `json:"prefix"`
				Suffix []byte `json:"suffix"`
			}{
				{
					Prefix: []byte{0x04},
					Suffix: []byte{0x05},
				},
				{
					Prefix: []byte{0x06},
					Suffix: []byte{0x07},
				},
			},
		},
		{
			Spec:   2,
			Prefix: []byte{0x08},
			Key:    []byte{0x09},
			Value:  []byte{0x0a},
			Path: []struct {
				Prefix []byte `json:"prefix"`
				Suffix []byte `json:"suffix"`
			}{
				{
					Prefix: []byte{0x0b},
					Suffix: []byte{0x0c},
				},
			},
		},
	}
	bz, err := EthABIEncodeExistenceProofs(proofs)
	if err != nil {
		t.Fatalf("EthABIEncodeExistenceProofs failed: %v", err)
	}
	proofs2, err := EthABIDecodeExistenceProofs(bz)
	if err != nil {
		t.Fatalf("EthABIDecodeExistenceProofs failed: %v", err)
	}
	if len(proofs) != len(proofs2) {
		t.Fatalf("EthABIDecodeExistenceProofs failed: length mismatch")
	}
	for i := range proofs {
		if !reflect.DeepEqual(proofs[i], proofs2[i]) {
			t.Fatalf("EthABIDecodeExistenceProofs failed: mismatch")
		}
	}
}
