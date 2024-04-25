// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {GoogleProtobufAny as Any} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/GoogleProtobufAny.sol";
import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";
import {ILightClient} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/ILightClient.sol";
import {
    IbcLightclientsTendermintzkV1ClientState as ProtoClientState,
    IbcLightclientsTendermintzkV1ConsensusState as ProtoConsensusState
} from "./proto/ibc/lightclients/tendermintzk/v1/TendermintZKLightClient.sol";
import {TendermintHeader} from "./TendermintHeader.sol";
import {ITendermintZKLightClient} from "./ITendermintZKLightClient.sol";
import {TendermintZKLightClientProtoMarshaler} from "./TendermintZKLightClientProtoMarshaler.sol";
import {ITendermintZKLightClientErrors} from "./ITendermintZKLightClientErrors.sol";
import {TendermintTreeVerifier} from "./TendermintTreeVerifier.sol";

abstract contract TendermintZKLightClient is ITendermintZKLightClient, ITendermintZKLightClientErrors, ILightClient {
    address internal immutable ibcHandler;
    uint64 internal immutable revisionNumber;
    uint256 internal immutable stepVerifierDigest;
    uint256 internal immutable skipVerifierDigest;

    mapping(string => ClientState) internal clientStates;
    mapping(string => mapping(uint64 => ConsensusState)) internal consensusStates;

    constructor(address ibcHandler_, uint256 stepVerifierDigest_, uint256 skipVerifierDigest_, uint64 revisionNumber_) {
        ibcHandler = ibcHandler_;
        stepVerifierDigest = stepVerifierDigest_;
        skipVerifierDigest = skipVerifierDigest_;
        revisionNumber = revisionNumber_;
    }

    function initializeClient(
        string calldata clientId,
        bytes calldata protoClientState,
        bytes calldata protoConsensusState
    ) public returns (Height.Data memory height) {
        if (msg.sender != ibcHandler) {
            revert ITendermintZKLightClientOnlyIBC();
        }
        ProtoClientState.Data memory clientState =
            TendermintZKLightClientProtoMarshaler.unmarshalClientState(protoClientState);
        ProtoConsensusState.Data memory consensusState =
            TendermintZKLightClientProtoMarshaler.unmarshalConsensusState(protoConsensusState);

        if (clientState.step_verifier_digest.length != 32) {
            revert ITendermintZKLightClientInvalidStepVerifierDigest();
        } else if (clientState.skip_verifier_digest.length != 32) {
            revert ITendermintZKLightClientInvalidSkipVerifierDigest();
        }

        if (uint256(bytes32(clientState.step_verifier_digest)) != stepVerifierDigest) {
            revert ITendermintZKLightClientInvalidStepVerifierDigest();
        } else if (uint256(bytes32(clientState.skip_verifier_digest)) != skipVerifierDigest) {
            revert ITendermintZKLightClientInvalidSkipVerifierDigest();
        } else if (clientState.trusting_period == 0) {
            revert ITendermintZKLightClientInvalidTrustingPeriod();
        } else if (clientState.frozen) {
            revert ITendermintZKLightClientClientStateFrozen();
        } else if (clientState.latest_height.revision_height == 0) {
            revert ITendermintZKLightClientClientInvalidRevisionHeight();
        } else if (clientState.latest_height.revision_number != revisionNumber) {
            revert ITendermintZKLightClientClientInvalidRevisionNumber();
        }

        if (consensusState.block_hash.length != 32) {
            revert ITendermintZKLightClientClientInvalidBlockHash();
        } else if (consensusState.app_hash.length != 32) {
            revert ITendermintZKLightClientClientInvalidAppHash();
        } else if (consensusState.timestamp == 0) {
            revert ITendermintZKLightClientClientInvalidTimestamp();
        }

        ConsensusState storage newConsensusState = consensusStates[clientId][clientState.latest_height.revision_height];
        newConsensusState.blockHash = bytes32(consensusState.block_hash);
        newConsensusState.appHash = bytes32(consensusState.app_hash);
        newConsensusState.timestamp = consensusState.timestamp;

        clientStates[clientId].latestHeight = clientState.latest_height.revision_height;
        clientStates[clientId].trustingPeriod = clientState.trusting_period;

        return clientState.latest_height;
    }

    function updateState(string calldata clientId, UpdateStateInput calldata message)
        internal
        returns (Height.Data[] memory heights)
    {
        if (message.untrustedHeight <= message.trustedHeight) {
            revert ITendermintZKLightClientInvalidUpdateStateMessageInvalidHeight();
        }

        ClientState storage clientState = clientStates[clientId];
        ConsensusState storage consensusState = consensusStates[clientId][message.trustedHeight];
        if (consensusState.blockHash == bytes32(0)) {
            revert ITendermintZKLightClientConsensusStateNotFound();
        }

        unchecked {
            if (block.timestamp > uint256(consensusState.timestamp) + uint256(clientState.trustingPeriod)) {
                revert ITendermintZKLightClientOldConsensusExpired();
            }

            if (message.untrustedHeight - message.trustedHeight == 1) {
                // step
                if (message.input[0] != stepVerifierDigest) {
                    revert ITendermintZKLightClientZKProofUnexpectedStepVerifierDigest();
                }
                if (
                    message.input[1]
                        != uint256(sha256(abi.encodePacked(message.trustedHeight, consensusState.blockHash)))
                            & ((1 << 253) - 1)
                ) {
                    revert ITendermintZKLightClientZKProofUnexpectedStepInput();
                }
            } else {
                // skip
                if (message.input[0] != skipVerifierDigest) {
                    revert ITendermintZKLightClientZKProofUnexpectedSkipVerifierDigest();
                }
                if (
                    message.input[1]
                        != uint256(
                            sha256(
                                abi.encodePacked(message.trustedHeight, consensusState.blockHash, message.untrustedHeight)
                            )
                        ) & ((1 << 253) - 1)
                ) {
                    revert ITendermintZKLightClientZKProofUnexpectedSkipInput();
                }
            }
            // truncated to 253 bits
            if (message.input[2] != uint256(sha256(abi.encodePacked(message.untrustedBlockHash))) & ((1 << 253) - 1)) {
                revert ITendermintZKLightClientZKProofUnexpectedOutput();
            }
        }

        if (
            message.untrustedBlockHash
                != TendermintHeader.merkleRoot(message.timestamp, message.appHash, message.simpleTreeProof)
        ) {
            revert ITendermintZKLightClientInvalidSimpleTreeProof();
        }

        ConsensusState storage newConsensusState = consensusStates[clientId][message.untrustedHeight];
        newConsensusState.blockHash = message.untrustedBlockHash;
        newConsensusState.appHash = message.appHash;
        newConsensusState.timestamp = message.timestamp;

        heights = new Height.Data[](1);
        heights[0] = Height.Data({revision_number: revisionNumber, revision_height: message.untrustedHeight});
        if (clientState.latestHeight < message.untrustedHeight) {
            clientState.latestHeight = message.untrustedHeight;
        }
        return heights;
    }

    function routeUpdateClient(string calldata clientId, bytes calldata protoClientMessage)
        public
        pure
        override
        returns (bytes4 selector, bytes memory args)
    {
        Any.Data memory any = TendermintZKLightClientProtoMarshaler.unmarshalAny(protoClientMessage);
        if (
            keccak256(bytes(any.type_url))
                == TendermintZKLightClientProtoMarshaler.UPDATE_STATE_MESSAGE_TYPE_URL_KECCAK256
        ) {
            (UpdateStateInput memory m, bytes memory zkp) =
                TendermintZKLightClientProtoMarshaler.convertUpdateStateMessage(any.value);
            return routeUpdateState(clientId, m, zkp);
        } else {
            revert ITendermintZKLightClientUnsupportedProtoMessageType();
        }
    }

    function routeUpdateState(string calldata clientId, UpdateStateInput memory m, bytes memory zkp)
        public
        pure
        virtual
        returns (bytes4 selector, bytes memory args);

    function verifyMembership(
        string calldata clientId,
        Height.Data calldata height,
        uint64,
        uint64,
        bytes calldata proof,
        bytes memory prefix,
        bytes calldata path,
        bytes calldata value
    ) public view returns (bool) {
        require(height.revision_number == revisionNumber);
        TendermintTreeVerifier.ExistenceProof[2] memory eproof =
            abi.decode(proof, (TendermintTreeVerifier.ExistenceProof[2]));
        // require(eproof[0].spec == TendermintTreeVerifier.ProofSpec.IAVLTree);
        // require(eproof[1].spec == TendermintTreeVerifier.ProofSpec.SimpleTree);
        // require(keccak256(eproof[0].key) == keccak256(path));
        // require(keccak256(eproof[0].value) == keccak256(value));
        bytes32 ibcCommitmentRoot =
            TendermintTreeVerifier.verifyMembershipIAVLSpec(eproof[0].prefix, path, value, eproof[0].path);
        // require(eproof[1].value.length == 32 && ibcCommitmentRoot == bytes32(eproof[1].value));
        // require(keccak256(eproof[1].key) == keccak256(prefix));
        require(
            TendermintTreeVerifier.verifyMembershipTendermintSpec(
                eproof[1].prefix, prefix, abi.encodePacked(ibcCommitmentRoot), eproof[1].path
            ) == consensusStates[clientId][height.revision_height].appHash
        );
        return true;
    }

    function verifyNonMembership(
        string calldata clientId,
        Height.Data calldata height,
        uint64,
        uint64,
        bytes calldata proof,
        bytes memory prefix,
        bytes calldata path
    ) public view returns (bool) {
        require(height.revision_number == revisionNumber);
        TendermintTreeVerifier.NonMembershipProof memory p =
            abi.decode(proof, (TendermintTreeVerifier.NonMembershipProof));
        require(keccak256(p.proof0.key) == keccak256(path));
        require(keccak256(p.proof1.key) == keccak256(prefix));
        bytes32 ibcCommitmentRoot = TendermintTreeVerifier.verifyNonMembershipIAVL(p.proof0);
        // require(p.proof1.value.length == 32 && ibcCommitmentRoot == bytes32(p.proof1.value));
        require(
            TendermintTreeVerifier.verifyMembershipTendermintSpec(
                p.proof1.prefix, prefix, abi.encodePacked(ibcCommitmentRoot), p.proof1.path
            ) == consensusStates[clientId][height.revision_height].appHash
        );
        return true;
    }

    function getTimestampAtHeight(string calldata clientId, Height.Data calldata height) public view returns (uint64) {
        return consensusStates[clientId][height.revision_height].timestamp;
    }

    function getLatestHeight(string calldata clientId) public view returns (Height.Data memory) {
        return Height.Data({revision_number: revisionNumber, revision_height: clientStates[clientId].latestHeight});
    }

    function getLatestInfo(string calldata clientId)
        public
        view
        returns (Height.Data memory latestHeight, uint64 latestTimestamp, ClientStatus status)
    {
        latestHeight =
            Height.Data({revision_number: revisionNumber, revision_height: clientStates[clientId].latestHeight});
        latestTimestamp = consensusStates[clientId][latestHeight.revision_height].timestamp;
        status = ClientStatus.Active;
    }

    function getStatus(string calldata) public pure returns (ClientStatus) {
        return ClientStatus.Active;
    }

    function getClientState(string calldata clientId) public view returns (bytes memory, bool) {
        ClientState storage clientState = clientStates[clientId];
        if (clientState.latestHeight == 0) {
            return (new bytes(0), false);
        }
        return (
            TendermintZKLightClientProtoMarshaler.marshalClientState(
                bytes32(stepVerifierDigest),
                bytes32(skipVerifierDigest),
                clientState.trustingPeriod,
                false,
                revisionNumber,
                clientState.latestHeight
            ),
            true
        );
    }

    function getConsensusState(string calldata clientId, Height.Data calldata height)
        public
        view
        returns (bytes memory, bool)
    {
        ConsensusState storage consensusState = consensusStates[clientId][height.revision_height];
        if (consensusState.blockHash == bytes32(0)) {
            return (new bytes(0), false);
        }
        return (
            TendermintZKLightClientProtoMarshaler.marshalConsensusState(
                consensusState.blockHash, consensusState.appHash, consensusState.timestamp
            ),
            true
        );
    }
}
