include ../../docker.mk

HARDHAT ?= npx hardhat
SCRIPT_DIR ?= $(CURDIR)/scripts

.PHONY: deps
deps:
	cd contracts && npm install

.PHONY: deploy-contract
deploy-contract:
	cd contracts && $(HARDHAT) run ./scripts/deploy.js --network local

.PHONY: image
image:
	$(DOCKER_BUILD) \
		--tag ethereum-geth:$(DOCKER_TAG) ./geth
