package zkp

type ZKProof interface {
	EncodeEthABI() []byte
}
