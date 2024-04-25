FORGE ?= forge

.PHONY: gnark-verifier
gnark-verifier:
	cd go/ && go build -o ./build/gnark-verifier .

.PHONY: fmt
fmt:
	@$(FORGE) fmt $(FORGE_FMT_OPTS) \
		./contracts/*.sol \
		./test
