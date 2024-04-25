package relay

import (
	"fmt"
	"reflect"

	"github.com/cometbft/cometbft/crypto/tmhash"
	"github.com/cometbft/cometbft/libs/bytes"
	cometbfttypes "github.com/cometbft/cometbft/types"
	gogotypes "github.com/cosmos/gogoproto/types"
	commitmenttypes "github.com/cosmos/ibc-go/v7/modules/core/23-commitment/types"
	ics23 "github.com/cosmos/ics23/go"
)

var IBCStoreKey = "ibc"

func getSimpleTreeProof(h *cometbfttypes.Header) [6][]byte {
	leaves := headerToLeaves(h)
	if leaves == nil {
		panic("leaves is nil")
	}
	idx7 := innerHash(leaves[0], leaves[1])
	idx17 := leaves[2]
	idx6 := innerHash(leaves[12], leaves[13])
	idx26 := leaves[11]
	idx11 := innerHash(leaves[8], leaves[9])
	idx4 := innerHash(
		innerHash(leaves[4], leaves[5]),
		innerHash(leaves[6], leaves[7]),
	)
	return [6][]byte{idx4, idx6, idx7, idx11, idx17, idx26}
}

func headerToLeaves(h *cometbfttypes.Header) [][]byte {
	if h == nil || len(h.ValidatorsHash) == 0 {
		return nil
	}
	hbz, err := h.Version.Marshal()
	if err != nil {
		return nil
	}

	pbt, err := gogotypes.StdTimeMarshal(h.Time)
	if err != nil {
		return nil
	}

	pbbi := h.LastBlockID.ToProto()
	bzbi, err := pbbi.Marshal()
	if err != nil {
		return nil
	}

	fields := [][]byte{
		hbz,
		cdcEncode(h.ChainID),
		cdcEncode(h.Height),
		pbt,
		bzbi,
		cdcEncode(h.LastCommitHash),
		cdcEncode(h.DataHash),
		cdcEncode(h.ValidatorsHash),
		cdcEncode(h.NextValidatorsHash),
		cdcEncode(h.ConsensusHash),
		cdcEncode(h.AppHash),
		cdcEncode(h.LastResultsHash),
		cdcEncode(h.EvidenceHash),
		cdcEncode(h.ProposerAddress),
	}
	// hash each field
	for i, field := range fields {
		fields[i] = leafHash(field)
	}
	return fields
}

var (
	leafPrefix  = []byte{0}
	innerPrefix = []byte{1}
)

// returns tmhash(0x00 || leaf)
func leafHash(leaf []byte) []byte {
	return tmhash.Sum(append(leafPrefix, leaf...))
}

// returns tmhash(0x01 || left || right)
func innerHash(left []byte, right []byte) []byte {
	return tmhash.Sum(append(innerPrefix, append(left, right...)...))
}

// cdcEncode returns nil if the input is nil, otherwise returns
// proto.Marshal(<type>Value{Value: item})
func cdcEncode(item interface{}) []byte {
	if item != nil && !isTypedNil(item) && !isEmpty(item) {
		switch item := item.(type) {
		case string:
			i := gogotypes.StringValue{
				Value: item,
			}
			bz, err := i.Marshal()
			if err != nil {
				return nil
			}
			return bz
		case int64:
			i := gogotypes.Int64Value{
				Value: item,
			}
			bz, err := i.Marshal()
			if err != nil {
				return nil
			}
			return bz
		case bytes.HexBytes:
			i := gogotypes.BytesValue{
				Value: item,
			}
			bz, err := i.Marshal()
			if err != nil {
				return nil
			}
			return bz
		default:
			return nil
		}
	}

	return nil
}

// Go lacks a simple and safe way to see if something is a typed nil.
// See:
//   - https://dave.cheney.net/2017/08/09/typed-nils-in-go-2
//   - https://groups.google.com/forum/#!topic/golang-nuts/wnH302gBa4I/discussion
//   - https://github.com/golang/go/issues/21538
func isTypedNil(o interface{}) bool {
	rv := reflect.ValueOf(o)
	switch rv.Kind() {
	case reflect.Chan, reflect.Func, reflect.Map, reflect.Ptr, reflect.Slice:
		return rv.IsNil()
	default:
		return false
	}
}

// Returns true if it has zero length.
func isEmpty(o interface{}) bool {
	rv := reflect.ValueOf(o)
	switch rv.Kind() {
	case reflect.Array, reflect.Chan, reflect.Map, reflect.Slice, reflect.String:
		return rv.Len() == 0
	default:
		return false
	}
}

func verifyAndConvertToExistenceProof(root [32]byte, path string, value []byte, merkleProof *commitmenttypes.MerkleProof) ([]byte, error) {
	if len(merkleProof.Proofs) != 2 {
		return nil, fmt.Errorf("invalid merkle proof: %v", merkleProof)
	}
	pe0, ok := merkleProof.Proofs[0].Proof.(*ics23.CommitmentProof_Exist)
	if !ok {
		return nil, fmt.Errorf("invalid merkle proof[0]: %v", merkleProof)
	}
	pe1, ok := merkleProof.Proofs[1].Proof.(*ics23.CommitmentProof_Exist)
	if !ok {
		return nil, fmt.Errorf("invalid merkle proof[1]: %v", merkleProof)
	}

	err := merkleProof.VerifyMembership(commitmenttypes.GetSDKSpecs(), commitmenttypes.NewMerkleRoot(root[:]), commitmenttypes.NewMerklePath(IBCStoreKey, path), value)
	if err != nil {
		return nil, err
	}

	p0, err := buildExistenceProofIAVL(pe0.Exist)
	if err != nil {
		return nil, err
	}
	p1, err := buildExistenceProofSimpleTree(pe1.Exist)
	if err != nil {
		return nil, err
	}

	var ep []ExistenceProof
	ep = append(ep, *p0, *p1)

	return EthABIEncodeExistenceProofs(ep)
}

const (
	SimpleTree uint8 = 0
	IAVLSpec         = 1
)

func buildExistenceProofIAVL(proof *ics23.ExistenceProof) (*ExistenceProof, error) {
	ep := ExistenceProof{
		Spec:   IAVLSpec,
		Prefix: proof.Leaf.Prefix,
		Key:    proof.Key,
		Value:  proof.Value,
	}
	for _, step := range proof.Path {
		ep.Path = append(ep.Path, struct {
			Prefix []byte `json:"prefix"`
			Suffix []byte `json:"suffix"`
		}{
			Prefix: step.Prefix,
			Suffix: step.Suffix,
		})
	}
	return &ep, nil
}

func buildExistenceProofSimpleTree(proof *ics23.ExistenceProof) (*ExistenceProof, error) {
	ep := ExistenceProof{
		Spec:   SimpleTree,
		Prefix: proof.Leaf.Prefix,
		Key:    proof.Key,
		Value:  proof.Value,
	}
	for _, step := range proof.Path {
		ep.Path = append(ep.Path, struct {
			Prefix []byte `json:"prefix"`
			Suffix []byte `json:"suffix"`
		}{
			Prefix: step.Prefix,
			Suffix: step.Suffix,
		})
	}
	return &ep, nil
}
