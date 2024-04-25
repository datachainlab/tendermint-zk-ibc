package groth16

import (
	"fmt"
	"math/big"
	"reflect"
	"testing"
	"testing/quick"
)

func TestGroth16ProofEncoding(t *testing.T) {
	f := func(data [8][32]byte) bool {
		var p Groth16Proof
		for i := 0; i < 8; i++ {
			p[i] = new(big.Int).SetBytes(data[i][:])
		}
		bz, err := EthABIEncodeGroth16Proof(p)
		if err != nil {
			return false
		}
		fmt.Printf("%x\n", bz)
		p2, err := EthABIDecodeGroth16Proof(bz)
		if err != nil {
			return false
		}
		return reflect.DeepEqual(p, p2)
	}
	if err := quick.Check(f, nil); err != nil {
		t.Error(err)
	}
}

func TestGroth16CommitmentProofEncoding(t *testing.T) {
	f := func(data [8 + 2 + 2][32]byte) bool {
		var cp Groth16CommitmentProof
		for i := 0; i < 8; i++ {
			cp.Proof[i] = new(big.Int).SetBytes(data[i][:])
		}
		for i := 0; i < 2; i++ {
			cp.Commitments[i] = new(big.Int).SetBytes(data[8+i][:])
		}
		for i := 0; i < 2; i++ {
			cp.CommitmentPok[i] = new(big.Int).SetBytes(data[10+i][:])
		}
		bz, err := EthABIEncodeGroth16CommitmentProof(cp)
		if err != nil {
			return false
		}
		cp2, err := EthABIDecodeGroth16CommitmentProof(bz)
		if err != nil {
			return false
		}
		return reflect.DeepEqual(cp, cp2)
	}
	if err := quick.Check(f, nil); err != nil {
		t.Error(err)
	}
}
