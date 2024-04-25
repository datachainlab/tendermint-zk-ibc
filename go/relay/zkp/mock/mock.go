package mock

import "github.com/datachainlab/tendermint-zk-ibc/go/relay/zkp"

const (
	MockProverType = "mock"
)

type mockProof struct{}

var _ zkp.ZKProof = (*mockProof)(nil)

func (p mockProof) EncodeEthABI() []byte {
	return []byte("mock")
}

func GetMockProof() zkp.ZKProof {
	return mockProof{}
}
