package relay

import (
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	"github.com/cosmos/ibc-go/v7/modules/core/exported"
)

// RegisterInterfaces register the ibc channel submodule interfaces to protobuf
// Any.
func RegisterInterfaces(registry codectypes.InterfaceRegistry) {
	registry.RegisterImplementations(
		(*exported.ClientState)(nil),
		&ClientState{},
	)
	registry.RegisterImplementations(
		(*exported.ConsensusState)(nil),
		&ConsensusState{},
	)
}

// Interface implementation checks.
var _, _ codectypes.UnpackInterfacesMessage = &ClientState{}, &ConsensusState{}

// UnpackInterfaces implements the UnpackInterfaceMessages.UnpackInterfaces method
func (cs ClientState) UnpackInterfaces(unpacker codectypes.AnyUnpacker) error {
	return nil
}

// UnpackInterfaces implements the UnpackInterfaceMessages.UnpackInterfaces method
func (cs ConsensusState) UnpackInterfaces(unpacker codectypes.AnyUnpacker) error {
	return nil
}
