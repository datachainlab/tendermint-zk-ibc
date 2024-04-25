package simapp

import (
	cometbfttypes "github.com/cometbft/cometbft/types"
	"github.com/cosmos/cosmos-sdk/codec"
	storetypes "github.com/cosmos/cosmos-sdk/store/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	sdkerrors "github.com/cosmos/cosmos-sdk/types/errors"
	paramtypes "github.com/cosmos/cosmos-sdk/x/params/types"
	stakingkeeper "github.com/cosmos/cosmos-sdk/x/staking/keeper"
	clientkeeper "github.com/cosmos/ibc-go/v7/modules/core/02-client/keeper"
	clienttypes "github.com/cosmos/ibc-go/v7/modules/core/02-client/types"
	connectionkeeper "github.com/cosmos/ibc-go/v7/modules/core/03-connection/keeper"
	connectiontypes "github.com/cosmos/ibc-go/v7/modules/core/03-connection/types"
	channeltypes "github.com/cosmos/ibc-go/v7/modules/core/04-channel/types"
	"github.com/cosmos/ibc-go/v7/modules/core/exported"
	ibckeeper "github.com/cosmos/ibc-go/v7/modules/core/keeper"
	tendermintzk "github.com/datachainlab/tendermint-zk-ibc/e2e/chains/tendermint/simapp/relay"
)

func overrideIBCClientKeeper(k ibckeeper.Keeper, cdc codec.BinaryCodec, key storetypes.StoreKey, paramSpace paramtypes.Subspace, stakingKeeper *stakingkeeper.Keeper) *ibckeeper.Keeper {
	clientKeeper := NewClientKeeper(k.ClientKeeper, stakingKeeper)
	k.ConnectionKeeper = connectionkeeper.NewKeeper(cdc, key, paramSpace, clientKeeper)
	return &k
}

var _ connectiontypes.ClientKeeper = (*ClientKeeper)(nil)
var _ channeltypes.ClientKeeper = (*ClientKeeper)(nil)

// ClientKeeper override `ValidateSelfClient` and `GetSelfConsensusState` in the keeper of ibc-client
// original method doesn't yet support a consensus state for general client
type ClientKeeper struct {
	clientkeeper.Keeper
	stakingKeeper *stakingkeeper.Keeper
}

func NewClientKeeper(k clientkeeper.Keeper, stakingKeeper *stakingkeeper.Keeper) ClientKeeper {
	return ClientKeeper{Keeper: k, stakingKeeper: stakingKeeper}
}

func (k ClientKeeper) ValidateSelfClient(ctx sdk.Context, clientState exported.ClientState) error {
	tmClient, ok := clientState.(*tendermintzk.ClientState)
	if !ok {
		return sdkerrors.Wrapf(sdkerrors.ErrInvalidType, "expected %T, got %T", &tendermintzk.ClientState{}, clientState)
	}
	if tmClient.Frozen {
		return sdkerrors.Wrap(clienttypes.ErrClientFrozen, "client is frozen")
	}
	revision := clienttypes.ParseChainID(ctx.ChainID())
	selfHeight := clienttypes.NewHeight(revision, uint64(ctx.BlockHeight()))
	if tmClient.LatestHeight.GTE(selfHeight) {
		return sdkerrors.Wrapf(sdkerrors.ErrInvalidHeight, "client has LatestHeight %d greater than or equal to chain height %d", tmClient.LatestHeight, selfHeight)
	}
	unbondingPeriod := uint64(k.stakingKeeper.UnbondingTime(ctx).Nanoseconds())
	if unbondingPeriod < tmClient.TrustingPeriod {
		return sdkerrors.Wrapf(clienttypes.ErrInvalidClient, "unbonding period must be greater than trusting period. unbonding period (%d) < trusting period (%d)",
			unbondingPeriod, tmClient.TrustingPeriod)
	}
	return nil
}

func (k ClientKeeper) GetSelfConsensusState(ctx sdk.Context, height exported.Height) (exported.ConsensusState, error) {
	selfHeight, ok := height.(clienttypes.Height)
	if !ok {
		return nil, sdkerrors.Wrapf(sdkerrors.ErrInvalidType, "expected %T, got %T", clienttypes.Height{}, height)
	}
	// check that height revision matches chainID revision
	revision := clienttypes.ParseChainID(ctx.ChainID())
	if revision != height.GetRevisionNumber() {
		return nil, sdkerrors.Wrapf(clienttypes.ErrInvalidHeight, "chainID revision number does not match height revision number: expected %d, got %d", revision, height.GetRevisionNumber())
	}
	histInfo, found := k.stakingKeeper.GetHistoricalInfo(ctx, int64(selfHeight.RevisionHeight))
	if !found {
		return nil, sdkerrors.Wrapf(sdkerrors.ErrNotFound, "no historical info found at height %d", selfHeight.RevisionHeight)
	}
	header, err := cometbfttypes.HeaderFromProto(&histInfo.Header)
	if err != nil {
		return nil, err
	}
	consensusState := &tendermintzk.ConsensusState{
		BlockHash: header.Hash(),
		AppHash:   header.AppHash,
		Timestamp: uint64(histInfo.Header.Time.UnixNano()),
	}
	return consensusState, nil
}
