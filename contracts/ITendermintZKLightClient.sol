// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface ITendermintZKLightClient {
    struct ClientState {
        uint64 latestHeight;
        uint64 trustingPeriod;
    }

    struct ConsensusState {
        // TODO remove blockHash
        bytes32 blockHash;
        bytes32 appHash;
        uint64 timestamp;
    }

    struct UpdateStateInput {
        uint64 trustedHeight;
        uint64 untrustedHeight;
        bytes32 untrustedBlockHash;
        uint64 timestamp;
        bytes32 appHash;
        bytes32[6] simpleTreeProof;
        uint256[3] input;
    }
}
