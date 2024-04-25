package relay

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"strings"

	rpcclient "github.com/cometbft/cometbft/rpc/client"
	"github.com/datachainlab/tendermint-zk-ibc/go/relay/zkp"
	"github.com/datachainlab/tendermint-zk-ibc/go/relay/zkp/groth16"
	"github.com/datachainlab/tendermint-zk-ibc/go/relay/zkp/mock"
)

type ZKProverClient struct {
	ProverAddress      string
	ProverType         string
	TMClient           rpcclient.Client
	StepVerifierDigest []byte
	SkipVerifierDigest []byte
}

func NewZKProverClient(proverType string, addr string, stepVerifierDigest, skipVerifierDigest []byte, tmClient rpcclient.Client) ZKProverClient {
	return ZKProverClient{ProverAddress: addr, ProverType: proverType, StepVerifierDigest: stepVerifierDigest, SkipVerifierDigest: skipVerifierDigest, TMClient: tmClient}
}

func (zpc ZKProverClient) Prove(trustedHeight uint64, targetHeight uint64) (*ZKProofAndInput, error) {
	if zpc.ProverType == mock.MockProverType {
		return zpc.proveMock(trustedHeight, targetHeight)
	}

	url := fmt.Sprintf("%s/prove?trusted_height=%d&target_height=%d", zpc.ProverAddress, trustedHeight, targetHeight)
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var res ZKProofAndInputResponse
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		return nil, err
	}
	in, err := zpc.proveMock(trustedHeight, targetHeight)
	if err != nil {
		return nil, err
	}
	switch zpc.ProverType {
	case groth16.Groth16ProverType:
		p, err := groth16.ParseGroth16Proof(res.Proof)
		if err != nil {
			return nil, fmt.Errorf("failed to parse proof: data=%v err=%w", string(res.Proof), err)
		}
		for i := range in.Input {
			if !bytes.Equal(in.Input[i].Bytes(), res.Input[i].Bytes()) {
				return nil, fmt.Errorf("input mismatch(%v): expected=%v actual=%v", i, in.Input[i], res.Input[i])
			}
		}
		return &ZKProofAndInput{
			Input: res.Input,
			Proof: p,
		}, nil
	case groth16.Groth16CommitmentProverType:
		cp, err := groth16.ParseGroth16CommitmentProof(res.Proof)
		if err != nil {
			return nil, fmt.Errorf("failed to parse proof: data=%v err=%w", string(res.Proof), err)
		}
		for i := range in.Input {
			if !bytes.Equal(in.Input[i].Bytes(), res.Input[i].Bytes()) {
				return nil, fmt.Errorf("input mismatch(%v): expected=%v actual=%v", i, in.Input[i], res.Input[i])
			}
		}
		return &ZKProofAndInput{
			Input: res.Input,
			Proof: cp,
		}, nil
	default:
		return nil, fmt.Errorf("unsupported proof type: %s", zpc.ProverType)
	}
}

func int64Ptr(i uint64) *int64 {
	i64 := int64(i)
	return &i64
}

func (zpc ZKProverClient) proveMock(trustedHeight uint64, targetHeight uint64) (*ZKProofAndInput, error) {
	if trustedHeight >= targetHeight {
		return nil, fmt.Errorf("trustedHeight(%d) should be less than targetHeight(%d)", trustedHeight, targetHeight)
	}

	var input [3][32]byte

	res, err := zpc.TMClient.Header(context.TODO(), int64Ptr(targetHeight))
	if err != nil {
		return nil, err
	}
	var input2 [32]byte
	copy(input2[:], res.Header.Hash())
	input[2] = sha256.Sum256(input2[:])
	input[2][0] &= 0x1f

	res, err = zpc.TMClient.Header(context.TODO(), int64Ptr(trustedHeight))
	if err != nil {
		return nil, err
	}
	trustedBlockHash := res.Header.Hash()

	if targetHeight-trustedHeight == 1 {
		copy(input[0][:], zpc.StepVerifierDigest)
		var input1 [40]byte
		binary.BigEndian.PutUint64(input1[:8], trustedHeight)
		copy(input1[8:], trustedBlockHash)
		input[1] = sha256.Sum256(input1[:])
		input[1][0] &= 0x1f
	} else {
		copy(input[0][:], zpc.SkipVerifierDigest)
		var input1 [48]byte
		binary.BigEndian.PutUint64(input1[:8], trustedHeight)
		copy(input1[8:], trustedBlockHash)
		binary.BigEndian.PutUint64(input1[40:], targetHeight)
		input[1] = sha256.Sum256(input1[:])
		input[1][0] &= 0x1f
	}

	var pi ZKProofAndInput
	for i := range input {
		pi.Input[i] = HexBigInt(*new(big.Int).SetBytes(input[i][:]))
	}
	pi.Proof = mock.GetMockProof()
	return &pi, nil
}

func (zpc ZKProverClient) AsyncProve(trustedHeight uint64, targetHeight uint64) <-chan *ZKProofAndInput {
	ch := make(chan *ZKProofAndInput)
	go func() {
		proof, err := zpc.Prove(trustedHeight, targetHeight)
		if err != nil {
			log := getLogger()
			log.Error("failed to get proof", err)
			close(ch)
			return
		}
		ch <- proof
		close(ch)
	}()
	return ch
}

type ZKProofAndInput struct {
	Input [3]HexBigInt
	Proof zkp.ZKProof
}

type ZKProofAndInputResponse struct {
	Input [3]HexBigInt `json:"input"`
	Proof []byte       `json:"proof"`
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
