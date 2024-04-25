// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";
import {GoogleProtobufAny as Any} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/GoogleProtobufAny.sol";
import {
    IbcLightclientsTendermintzkV1ClientState as ProtoClientState,
    IbcLightclientsTendermintzkV1ConsensusState as ProtoConsensusState,
    IbcLightclientsTendermintzkV1UpdateStateMessage as ProtoUpdateStateMessage
} from "./proto/ibc/lightclients/tendermintzk/v1/TendermintZKLightClient.sol";
import {ITendermintZKLightClient} from "./ITendermintZKLightClient.sol";

library TendermintZKLightClientProtoMarshaler {
    string constant CLIENT_STATE_TYPE_URL = "/ibc.lightclients.tendermintzk.v1.ClientState";
    string constant CONSENSUS_STATE_TYPE_URL = "/ibc.lightclients.tendermintzk.v1.ConsensusState";
    bytes32 constant CLIENT_STATE_TYPE_URL_KECCAK256 = keccak256(bytes(CLIENT_STATE_TYPE_URL));
    bytes32 constant CONSENSUS_STATE_TYPE_URL_KECCAK256 = keccak256(bytes(CONSENSUS_STATE_TYPE_URL));

    string constant UPDATE_STATE_MESSAGE_TYPE_URL = "/ibc.lightclients.tendermintzk.v1.UpdateStateMessage";
    bytes32 constant UPDATE_STATE_MESSAGE_TYPE_URL_KECCAK256 = keccak256(bytes(UPDATE_STATE_MESSAGE_TYPE_URL));

    function marshal(ProtoClientState.Data memory clientState) public pure returns (bytes memory) {
        bytes memory bz = ProtoClientState.encode(clientState);
        return Any.encode(Any.Data({type_url: CLIENT_STATE_TYPE_URL, value: bz}));
    }

    function marshalClientState(
        bytes32 stepVerifierDigest,
        bytes32 skipVerifierDigest,
        uint64 trustingPeriod,
        bool frozen,
        uint64 revisionNumber,
        uint64 revisionHeight
    ) public pure returns (bytes memory) {
        return marshal(
            ProtoClientState.Data({
                step_verifier_digest: abi.encodePacked(stepVerifierDigest),
                skip_verifier_digest: abi.encodePacked(skipVerifierDigest),
                trusting_period: trustingPeriod,
                frozen: frozen,
                latest_height: Height.Data({revision_number: revisionNumber, revision_height: revisionHeight})
            })
        );
    }

    function marshal(ProtoConsensusState.Data memory consensusState) public pure returns (bytes memory) {
        return Any.encode(
            Any.Data({type_url: CONSENSUS_STATE_TYPE_URL, value: ProtoConsensusState.encode(consensusState)})
        );
    }

    function marshalConsensusState(bytes32 blockHash, bytes32 appHash, uint64 timestamp)
        public
        pure
        returns (bytes memory)
    {
        return marshal(
            ProtoConsensusState.Data({
                block_hash: abi.encodePacked(blockHash),
                app_hash: abi.encodePacked(appHash),
                timestamp: timestamp
            })
        );
    }

    function unmarshalAny(bytes calldata bz) public pure returns (Any.Data memory) {
        return Any.decode(bz);
    }

    function unmarshalClientState(bytes calldata bz) public pure returns (ProtoClientState.Data memory) {
        Any.Data memory any = Any.decode(bz);
        if (keccak256(bytes(any.type_url)) != CLIENT_STATE_TYPE_URL_KECCAK256) {
            revert("invalid type url");
        }
        return ProtoClientState.decode(any.value);
    }

    function unmarshalConsensusState(bytes calldata bz) public pure returns (ProtoConsensusState.Data memory) {
        Any.Data memory any = Any.decode(bz);
        if (keccak256(bytes(any.type_url)) != CONSENSUS_STATE_TYPE_URL_KECCAK256) {
            revert("invalid type url");
        }
        return ProtoConsensusState.decode(any.value);
    }

    function convertUpdateStateMessage(bytes memory protoMessageBytes)
        public
        pure
        returns (ITendermintZKLightClient.UpdateStateInput memory, bytes memory)
    {
        ProtoUpdateStateMessage.Data memory protoMessage = ProtoUpdateStateMessage.decode(protoMessageBytes);
        require(protoMessage.input.length == 3);
        uint256[3] memory publicInput;
        for (uint256 i = 0; i < 3; i++) {
            publicInput[i] = uint256(bytes32(protoMessage.input[i]));
        }
        return (
            ITendermintZKLightClient.UpdateStateInput({
                trustedHeight: protoMessage.trusted_height,
                untrustedHeight: protoMessage.untrusted_height,
                untrustedBlockHash: bytes32(protoMessage.untrusted_block_hash),
                timestamp: protoMessage.timestamp,
                appHash: bytes32(protoMessage.app_hash),
                simpleTreeProof: convertSimpleTreeProof(protoMessage.simple_tree_proof),
                input: publicInput
            }),
            protoMessage.zk_proof
        );
    }

    function convertSimpleTreeProof(bytes[] memory proof) public pure returns (bytes32[6] memory simpleTreeProof) {
        for (uint256 i = 0; i < 6; i++) {
            require(proof[i].length == 32);
            simpleTreeProof[i] = bytes32(proof[i]);
        }
    }
}
