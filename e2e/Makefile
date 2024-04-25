include ./docker.mk

.PHONY: yrly
yrly:
	go build -o ./build/yrly ./relayer

.PHONY: network
network:
	TAG=${DOCKER_TAG} $(DOCKER_COMPOSE) up -d

.PHONY: setup
setup:
	$(MAKE) -C ./chains/ethereum deploy-contract

.PHONY: network-down
network-down:
	TAG=${DOCKER_TAG} $(DOCKER_COMPOSE) down --volumes --remove-orphans

.PHONY: test
test:
	./scripts/fixture
	./scripts/init-rly
	./scripts/handshake
	./scripts/transfer

.PHONY: build-images
build-images:
	$(MAKE) -C ./chains/ethereum image
	$(MAKE) -C ./chains/tendermint image

.PHONY: deps
deps:
	$(MAKE) -C ./chains/ethereum deps
