package relay

import (
	"context"
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"path/filepath"
	"time"

	"github.com/avast/retry-go"
	dbm "github.com/cometbft/cometbft-db"
	"github.com/cometbft/cometbft/libs/log"
	"github.com/cometbft/cometbft/light"
	lightp "github.com/cometbft/cometbft/light/provider"
	lighthttp "github.com/cometbft/cometbft/light/provider/http"
	dbs "github.com/cometbft/cometbft/light/store/db"
	"github.com/cometbft/cometbft/types"
	tmtypes "github.com/cometbft/cometbft/types"
	tmclient "github.com/cosmos/ibc-go/v7/modules/light-clients/07-tendermint"
)

// NOTE: currently we are discarding the very noisy light client logs
// it would be nice if we could add a setting the chain or otherwise
// that allowed users to enable light client logging. (maybe as a hidden prop
// on the Chain struct that users could pass in the config??)
var logger = light.Logger(log.NewTMLogger(log.NewSyncWriter(ioutil.Discard)))

// ErrLightNotInitialized returns the canonical error for a an uninitialized light client
var ErrLightNotInitialized = errors.New("light client is not initialized")

var (
	rtyAttNum = uint(5)
	rtyAtt    = retry.Attempts(rtyAttNum)
	rtyDel    = retry.Delay(time.Millisecond * 400)
	rtyErr    = retry.LastErrorOnly(true)
)

// LightClient initializes the light client for a given chain from the trusted store in the database
// this should be call for all other light client usage
func (pr *Prover) LightClient(db dbm.DB) (*light.Client, error) {
	prov := pr.LightHTTP()
	return light.NewClientFromTrustedStore(
		pr.chain.ChainID(),
		pr.getTrustingPeriod(),
		prov,
		// TODO: provide actual witnesses!
		// NOTE: This requires adding them to the chain config
		[]lightp.Provider{prov},
		dbs.New(db, ""),
		logger,
	)
}

// LightHTTP returns the http client for light clients
func (pr *Prover) LightHTTP() lightp.Provider {
	cl, err := lighthttp.New(pr.chain.ChainID(), pr.chain.Config().RpcAddr)
	if err != nil {
		panic(err)
	}
	return cl
}

func (pr *Prover) NewLightDB() (db *dbm.GoLevelDB, df func(), err error) {
	c := pr.chain
	if err := retry.Do(func() error {
		db, err = dbm.NewGoLevelDB(c.ChainID(), lightDir(c.HomePath))
		if err != nil {
			return fmt.Errorf("can't open light client database: %w", err)
		}
		return nil
	}, rtyAtt, rtyDel, rtyErr); err != nil {
		return nil, nil, err
	}

	df = func() {
		err := db.Close()
		if err != nil {
			panic(err)
		}
	}

	return
}

// DeleteLightDB removes the light client database on disk, forcing re-initialization
func (pr *Prover) DeleteLightDB() error {
	return os.RemoveAll(filepath.Join(lightDir(pr.chain.HomePath), fmt.Sprintf("%s.db", pr.chain.ChainID())))
}

// LightClientWithTrust takes a header from the chain and attempts to add that header to the light
// database.
func (pr *Prover) LightClientWithTrust(db dbm.DB, to light.TrustOptions) (*light.Client, error) {
	prov := pr.LightHTTP()
	return light.NewClient(
		context.Background(),
		pr.chain.ChainID(),
		to,
		prov,
		// TODO: provide actual witnesses!
		// NOTE: This requires adding them to the chain config
		[]lightp.Provider{prov},
		dbs.New(db, ""),
		logger)
}

// LightClientWithoutTrust querys the latest header from the chain and initializes a new light client
// database using that header. This should only be called when first initializing the light client
func (pr *Prover) LightClientWithoutTrust(db dbm.DB) (*light.Client, error) {
	var (
		height int64
		err    error
	)
	prov := pr.LightHTTP()

	if err := retry.Do(func() error {
		h, err := pr.chain.LatestHeight()
		switch {
		case err != nil:
			return err
		case h.GetRevisionHeight() == 0:
			return fmt.Errorf("shouldn't be here")
		default:
			t, err := pr.chain.Timestamp(h)
			if err != nil {
				return err
			}
			if time.Since(t) > pr.getTrustingPeriod() {
				return fmt.Errorf("trusting period has expired")
			}
			height = int64(h.GetRevisionHeight())
			return nil
		}
	}, rtyAtt, rtyDel, rtyErr); err != nil {
		return nil, err
	}

	lb, err := prov.LightBlock(context.Background(), height)
	if err != nil {
		return nil, err
	}
	return light.NewClient(
		context.Background(),
		pr.chain.ChainID(),
		light.TrustOptions{
			Period: pr.getTrustingPeriod(),
			Height: height,
			Hash:   lb.SignedHeader.Hash(),
		},
		prov,
		// TODO: provide actual witnesses!
		// NOTE: This requires adding them to the chain config
		[]lightp.Provider{prov},
		dbs.New(db, ""),
		logger)
}

// GetLatestLightHeader returns the header to be used for client creation
func (pr *Prover) GetLatestLightHeader() (*tmclient.Header, error) {
	return pr.GetLightSignedHeaderAtHeight(0)
}

// GetLightSignedHeaderAtHeight returns a signed header at a particular height.
func (pr *Prover) GetLightSignedHeaderAtHeight(height int64) (*tmclient.Header, error) {
	// create database connection
	db, df, err := pr.NewLightDB()
	if err != nil {
		return nil, err
	}
	defer df()

	client, err := pr.LightClient(db)
	if err != nil {
		return nil, err
	}

	sh, err := client.TrustedLightBlock(height)
	if err != nil {
		return nil, err
	}

	valSet := tmtypes.NewValidatorSet(sh.ValidatorSet.Validators)
	protoVal, err := valSet.ToProto()
	if err != nil {
		return nil, err
	}
	protoVal.TotalVotingPower = valSet.TotalVotingPower()

	return &tmclient.Header{SignedHeader: sh.SignedHeader.ToProto(), ValidatorSet: protoVal}, nil
}

func lightDir(home string) string {
	return path.Join(home, "light")
}

/* Local LightClient implementation */

// GetLatestLightHeight uses the CLI utilities to pull the latest height from a given chain
func (pr *Prover) GetLatestLightHeight() (int64, error) {
	db, df, err := pr.NewLightDB()
	if err != nil {
		return -1, err
	}
	defer df()

	client, err := pr.LightClient(db)
	if err != nil {
		return -1, err
	}

	return client.LastTrustedHeight()
}

func (pr *Prover) UpdateLightClient(height int64) (*tmclient.Header, error) {
	// create database connection
	db, df, err := pr.NewLightDB()
	if err != nil {
		return nil, lightError(err)
	}
	defer df()

	client, err := pr.LightClient(db)
	if err != nil {
		return nil, lightError(err)
	}

	var sh *types.LightBlock
	if height == 0 {
		if sh, err = client.Update(context.Background(), time.Now()); err != nil {
			return nil, lightError(err)
		} else if sh == nil {
			sh, err = client.TrustedLightBlock(0)
			if err != nil {
				return nil, lightError(err)
			}
		}
	} else {
		if sh, err = client.VerifyLightBlockAtHeight(context.Background(), height, time.Now()); err != nil {
			return nil, lightError(err)
		}
	}

	valSet := tmtypes.NewValidatorSet(sh.ValidatorSet.Validators)
	protoVal, err := valSet.ToProto()
	if err != nil {
		return nil, err
	}
	protoVal.TotalVotingPower = valSet.TotalVotingPower()

	return &tmclient.Header{
		SignedHeader: sh.SignedHeader.ToProto(),
		ValidatorSet: protoVal,
	}, nil
}

// TrustOptions returns light.TrustOptions given a height and hash
func (pr *Prover) TrustOptions(height int64, hash []byte) light.TrustOptions {
	return light.TrustOptions{
		Period: pr.getTrustingPeriod(),
		Height: height,
		Hash:   hash,
	}
}

/// internal method ///

// getTrustingPeriod returns the trusting period for the chain
func (pr *Prover) getTrustingPeriod() time.Duration {
	tp, _ := time.ParseDuration(pr.config.TrustingPeriod)
	return tp
}

func lightError(err error) error { return fmt.Errorf("light client: %w", err) }
