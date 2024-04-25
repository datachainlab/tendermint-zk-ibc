package relay

import (
	"bytes"
	"context"
	"encoding/hex"
	"fmt"
	"time"

	cometbfttypes "github.com/cometbft/cometbft/types"
	"github.com/cosmos/cosmos-sdk/codec"
	clienttypes "github.com/cosmos/ibc-go/v7/modules/core/02-client/types"
	commitmenttypes "github.com/cosmos/ibc-go/v7/modules/core/23-commitment/types"
	ibcclient "github.com/cosmos/ibc-go/v7/modules/core/client"
	ibcexported "github.com/cosmos/ibc-go/v7/modules/core/exported"
	tmclient "github.com/cosmos/ibc-go/v7/modules/light-clients/07-tendermint"
	"github.com/hyperledger-labs/yui-relayer/chains/tendermint"
	"github.com/hyperledger-labs/yui-relayer/core"
	"github.com/hyperledger-labs/yui-relayer/log"
)

var _ core.Prover = (*Prover)(nil)

type Prover struct {
	chain  *tendermint.Chain
	config ProverConfig

	zkProverClient ZKProverClient
}

func NewProver(chain *tendermint.Chain, config ProverConfig) *Prover {
	return &Prover{chain: chain, config: config, zkProverClient: NewZKProverClient(config.ProverType, config.ZkProverAddr, config.GetStepVerifierDigest(), config.GetSkipVerifierDigest(), chain.Client)}
}

func (pr *Prover) Init(homePath string, timeout time.Duration, codec codec.ProtoCodecMarshaler, debug bool) error {
	// TODO fix this
	pr.zkProverClient.TMClient = pr.chain.Client
	return nil
}

// SetRelayInfo sets source's path and counterparty's info to the chain
func (pr *Prover) SetRelayInfo(_ *core.PathEnd, _ *core.ProvableChain, _ *core.PathEnd) error {
	return nil // prover uses chain's path instead
}

func (pr *Prover) SetupForRelay(ctx context.Context) error {
	return nil
}

// ProveState returns the proof of an IBC state specified by `path` and `value`
func (pr *Prover) ProveState(ctx core.QueryContext, path string, value []byte) ([]byte, clienttypes.Height, error) {
	clientCtx := pr.chain.CLIContext(int64(ctx.Height().GetRevisionHeight()))
	height := int64(ctx.Height().GetRevisionHeight())
	res, err := pr.chain.Client.Header(ctx.Context(), &height)
	if err != nil {
		return nil, clienttypes.ZeroHeight(), err
	}
	if v, proof, proofHeight, err := ibcclient.QueryTendermintProof(clientCtx, []byte(path)); err != nil {
		return nil, clienttypes.Height{}, err
	} else if !bytes.Equal(v, value) {
		return nil, clienttypes.Height{}, fmt.Errorf("value unmatch: %x != %x", v, value)
	} else {
		var merkleProof commitmenttypes.MerkleProof
		if err := pr.chain.Codec().Unmarshal(proof, &merkleProof); err != nil {
			return nil, clienttypes.Height{}, fmt.Errorf("failed to unmarshal merkle proof: %v", err)
		}
		if len(merkleProof.Proofs) != 2 {
			return nil, clienttypes.Height{}, fmt.Errorf("invalid merkle proof: %v", merkleProof)
		}
		exitProof, err := verifyAndConvertToExistenceProof([32]byte(res.Header.AppHash), path, value, &merkleProof)
		if err != nil {
			return nil, clienttypes.Height{}, err
		}
		return exitProof, proofHeight, nil
	}
}

// ProveHostConsensusState returns the existence proof of the consensus state at `height`
// ibc-go doesn't use this proof, so it returns nil
func (pr *Prover) ProveHostConsensusState(ctx core.QueryContext, height ibcexported.Height, consensusState ibcexported.ConsensusState) ([]byte, error) {
	return nil, nil
}

// CreateInitialLightClientState creates a pair of ClientState and ConsensusState submitted to the counterparty chain as MsgCreateClient
func (pr *Prover) CreateInitialLightClientState(height ibcexported.Height) (ibcexported.ClientState, ibcexported.ConsensusState, error) {
	var tmHeight int64
	if height != nil {
		tmHeight = int64(height.GetRevisionHeight())
	}
	selfHeader, err := pr.UpdateLightClient(tmHeight)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to update the local light client and get the header@%d: %v", tmHeight, err)
	}
	clientState := ClientState{
		StepVerifierDigest: pr.config.GetStepVerifierDigest(),
		SkipVerifierDigest: pr.config.GetSkipVerifierDigest(),
		TrustingPeriod:     uint64(pr.config.GetTrustingPeriod().Nanoseconds()),
		Frozen:             false,
		LatestHeight:       selfHeader.GetHeight().(clienttypes.Height),
	}
	if len(clientState.StepVerifierDigest) != 32 {
		return nil, nil, fmt.Errorf("relayer: invalid step verifier digest: %x", clientState.StepVerifierDigest)
	}
	if len(clientState.SkipVerifierDigest) != 32 {
		return nil, nil, fmt.Errorf("relayer: invalid skip verifier digest: %x", clientState.SkipVerifierDigest)
	}
	consensusState := ConsensusState{
		BlockHash: selfHeader.Commit.BlockID.Hash,
		AppHash:   selfHeader.Header.AppHash,
		Timestamp: uint64(selfHeader.Header.Time.UnixNano()),
	}
	log := getLogger()
	log.Info("created initial state", "height", clientState.LatestHeight.String(), "blockHash", "0x"+hex.EncodeToString(consensusState.BlockHash), "appHash", "0x"+hex.EncodeToString(consensusState.AppHash), "timestamp", consensusState.Timestamp)
	return &clientState, &consensusState, nil
}

// SetupHeadersForUpdate returns the finalized header and any intermediate headers needed to apply it to the client on the counterpaty chain
func (pr *Prover) SetupHeadersForUpdate(counterparty core.FinalityAwareChain, latestFinalizedHeader core.Header) ([]core.Header, error) {
	h := latestFinalizedHeader.(*tmclient.Header)
	cph, err := counterparty.LatestHeight()
	if err != nil {
		return nil, err
	}

	// retrieve the client state from the counterparty chain
	counterpartyClientRes, err := counterparty.QueryClientState(core.NewQueryContext(context.TODO(), cph))
	if err != nil {
		return nil, err
	}

	var cs ibcexported.ClientState
	if err := pr.chain.Codec().UnpackAny(counterpartyClientRes.ClientState, &cs); err != nil {
		return nil, err
	}

	log := getLogger()

	trustedHeight := cs.GetLatestHeight().GetRevisionHeight()
	targetHeight := h.GetHeight().GetRevisionHeight()
	if trustedHeight >= targetHeight {
		return nil, fmt.Errorf("trusted height is greater than target height: trusted_height: %d, target_height: %d", trustedHeight, targetHeight)
	}
	targetHeightInt := int64(targetHeight)
	res, err := pr.chain.Client.Header(context.TODO(), &targetHeightInt)
	if err != nil {
		return nil, err
	}

	proofCh := pr.zkProverClient.AsyncProve(cs.GetLatestHeight().GetRevisionHeight(), h.GetHeight().GetRevisionHeight())
	tick := time.NewTicker(10 * time.Second)
	defer tick.Stop()
	timeout := time.After(10 * time.Minute)
	var (
		zkProof *ZKProofAndInput
		ok      bool
	)
L:
	for range tick.C {
		select {
		case zkProof, ok = <-proofCh:
			if !ok {
				return nil, fmt.Errorf("failed to get proof trusted_height: %d, target_height: %d", trustedHeight, targetHeight)
			}
			log.Info("got proof", "trusted_height", trustedHeight, "target_height", targetHeight)
			break L
		case <-timeout:
			return nil, fmt.Errorf("timeout trusted_height: %d, target_height: %d", trustedHeight, targetHeight)
		default:
			log.Info("waiting for proving", "trusted_height", trustedHeight, "target_height", targetHeight)
		}
	}
	tmHeader, err := cometbfttypes.HeaderFromProto(h.SignedHeader.Header)
	if err != nil {
		return nil, err
	}
	simpleTreeProof := getSimpleTreeProof(&tmHeader)
	msg := UpdateStateMessage{
		TrustedHeight:      trustedHeight,
		UntrustedHeight:    targetHeight,
		UntrustedBlockHash: res.Header.Hash(),
		Timestamp:          uint64(h.Header.Time.UnixNano()),
		AppHash:            h.Header.AppHash,
		SimpleTreeProof:    simpleTreeProof[:],
		Input:              [][]byte{zkProof.Input[0].Bytes(), zkProof.Input[1].Bytes(), zkProof.Input[2].Bytes()},
		ZkProof:            zkProof.Proof.EncodeEthABI(),
	}
	log.Info("created update state message", "msg", msg)
	return []core.Header{&msg}, nil
}

// GetLatestFinalizedHeader returns the latest finalized header
func (pr *Prover) GetLatestFinalizedHeader() (core.Header, error) {
	return pr.UpdateLightClient(0)
}

func (pr *Prover) CheckRefreshRequired(counterparty core.ChainInfoICS02Querier) (bool, error) {
	// TODO implement
	return false, nil
}

func getLogger() *log.RelayLogger {
	return log.GetLogger().
		WithModule("tendermintzk.prover")
}
