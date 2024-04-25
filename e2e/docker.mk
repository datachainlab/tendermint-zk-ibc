DOCKER         ?= docker
DOCKER_COMPOSE ?= $(DOCKER) compose
DOCKER_TAG     ?= latest
DOCKER_BUILD   ?= $(DOCKER) build --rm --no-cache --pull
