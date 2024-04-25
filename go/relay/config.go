package relay

import (
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"github.com/hyperledger-labs/yui-relayer/chains/tendermint"
	"github.com/hyperledger-labs/yui-relayer/core"
)

var _ core.ProverConfig = (*ProverConfig)(nil)

func (c ProverConfig) Build(chain core.Chain) (core.Prover, error) {
	chain_, ok := chain.(*tendermint.Chain)
	if !ok {
		return nil, fmt.Errorf("chain type must be %T, not %T", &tendermint.Chain{}, chain)
	}
	return NewProver(chain_, c), nil
}

func (c ProverConfig) Validate() error {
	if c.ProverType == "" {
		return fmt.Errorf("prover type cannot be empty")
	}
	if _, err := hex.DecodeString(strings.TrimPrefix(c.StepVerifierDigest, "0x")); err != nil {
		return fmt.Errorf("invalid step verifier digest: %w", err)
	}
	if _, err := hex.DecodeString(strings.TrimPrefix(c.SkipVerifierDigest, "0x")); err != nil {
		return fmt.Errorf("invalid skip verifier digest: %w", err)
	}
	if _, err := time.ParseDuration(c.TrustingPeriod); err != nil {
		return fmt.Errorf("invalid trusting period: %w", err)
	}
	return nil
}

func (c ProverConfig) GetStepVerifierDigest() []byte {
	if bz, err := hex.DecodeString(strings.TrimPrefix(c.StepVerifierDigest, "0x")); err != nil {
		panic(err)
	} else {
		return bz
	}
}

func (c ProverConfig) GetSkipVerifierDigest() []byte {
	if bz, err := hex.DecodeString(strings.TrimPrefix(c.SkipVerifierDigest, "0x")); err != nil {
		panic(err)
	} else {
		return bz
	}
}

func (c ProverConfig) GetTrustingPeriod() time.Duration {
	d, err := time.ParseDuration(c.TrustingPeriod)
	if err != nil {
		panic(err)
	}
	return d
}
