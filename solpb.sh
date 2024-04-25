#!/usr/bin/env bash
set -e

if [ -z "$SOLPB_DIR" ]; then
    echo "variable SOLPB_DIR must be set"
    exit 1
fi

GEN_DIR="$(pwd)/generated"
mkdir "$GEN_DIR"
for file in $(find ./proto -name '*.proto')
do
  echo "Generating "$file
  protoc \
    -I$(pwd)/proto \
    -I$(pwd)/node_modules \
    -I${SOLPB_DIR}/protobuf-solidity/src/protoc/include \
    -Ilib \
     --plugin=protoc-gen-sol=${SOLPB_DIR}/protobuf-solidity/src/protoc/plugin/gen_sol.py --"sol_out=use_runtime=@hyperledger-labs/yui-ibc-solidity/contracts/proto/ProtoBufRuntime.sol&solc_version=0.8.12&ignore_protos=gogoproto/gogo.proto:$GEN_DIR" $(pwd)/$file
done
mkdir -p ./contracts/proto
mv "$GEN_DIR/ibc" "$(pwd)/contracts/proto"
rm -rf "$GEN_DIR"
