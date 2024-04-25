include ../../docker.mk

.PHONY: build
build: zklc
	go build -o ./build/simd ./simapp/simd

.PHONY: image
image: zklc
	$(DOCKER_BUILD) \
		--build-arg CHAINID=ibc0 \
		--tag tendermint-chain:$(DOCKER_TAG) .

.PHONY: zklc
zklc:
	mkdir -p ./simapp/relay
	cp ../../../go/relay/lightclient.go ./simapp/relay
	cp ../../../go/relay/TendermintZKLightClient.pb.go ./simapp/relay
