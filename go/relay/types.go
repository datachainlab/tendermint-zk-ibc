package relay

import (
	"encoding/hex"
	"encoding/json"
)

// implement json marshaler for UpdateStateMessage
func (msg UpdateStateMessage) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		TrustedHeight      uint64
		UntrustedHeight    uint64
		UntrustedBlockHash string
		Timestamp          uint64
		AppHash            string
		SimpleTreeProof    []string
		Input              []string
		ZkProof            string
	}{
		TrustedHeight:      msg.TrustedHeight,
		UntrustedHeight:    msg.UntrustedHeight,
		UntrustedBlockHash: encodeHexString(msg.UntrustedBlockHash),
		Timestamp:          msg.Timestamp,
		AppHash:            encodeHexString(msg.AppHash),
		SimpleTreeProof:    bytesSliceToHexSlice(msg.SimpleTreeProof),
		Input:              bytesSliceToHexSlice(msg.Input),
		ZkProof:            encodeHexString(msg.ZkProof),
	})
}

func bytesSliceToHexSlice(bzs [][]byte) []string {
	res := make([]string, len(bzs))
	for i, bz := range bzs {
		res[i] = encodeHexString(bz)
	}
	return res
}

func encodeHexString(bz []byte) string {
	return "0x" + hex.EncodeToString(bz)
}
