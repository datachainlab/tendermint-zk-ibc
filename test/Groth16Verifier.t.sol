// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";
import {ProtoBufRuntime} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/ProtoBufRuntime.sol";
import {TendermintZKLightClientGroth16} from "../contracts/groth16/TendermintZKLightClientGroth16.sol";
import {ITendermintZKLightClient} from "../contracts/TendermintZKLightClient.sol";
import {TendermintHeader} from "../contracts/TendermintHeader.sol";
import {
    IbcLightclientsTendermintzkV1ClientState as ProtoClientState,
    IbcLightclientsTendermintzkV1ConsensusState as ProtoConsensusState
} from "../contracts/proto/ibc/lightclients/tendermintzk/v1/TendermintZKLightClient.sol";
import {TendermintZKLightClientProtoMarshaler} from "../contracts/TendermintZKLightClientProtoMarshaler.sol";
import {TendermintTreeVerifier} from "../contracts/TendermintTreeVerifier.sol";

contract Groth16VerifierTest is Test {
    uint256 internal immutable stepVerifierDigest =
        uint256(bytes32(hex"09bf185e9e478bac323981a844afe484dcd73823f6a34f5adb8cffe6c4436111"));
    uint256 internal immutable skipVerifierDigest =
        uint256(bytes32(hex"286fd609266936f71d552671b7553f1a0e59c7cf296112996bded1ca3bafa4a4"));

    TendermintZKLightClientGroth16 public lc;

    function setUp() public {
        lc = new TendermintZKLightClientGroth16(address(this), stepVerifierDigest, skipVerifierDigest, 0);
    }

    function test_verifyProof() public {
        ProofData memory proofData = readSkipProofData("./test/data/groth16_proof_01.json");
        lc.verifyProof(proofData.proof, proofData.input);
    }

    function test_verifyCompressedProof() public {
        ProofData memory proofData = readSkipProofData("./test/data/groth16_proof_01.json");
        uint256[4] memory compressed = lc.compressProof(proofData.proof);
        lc.verifyCompressedProof(compressed, proofData.input);
    }

    function test_inputOutputHash() public {
        ProofData memory proofData = readSkipProofData("./test/data/groth16_proof_01.json");
        uint256 expectedInputHash = uint256(
            sha256(
                abi.encodePacked(
                    uint64(71),
                    bytes32(hex"735FD53BF3DB0701830669F7EF935C7287D767C0D5F288E2212545C0B0FAABEC"),
                    uint64(157)
                )
            )
        ) & ((1 << 253) - 1);
        assertEq(proofData.input[1], expectedInputHash, "invalid input hash");

        uint256 expectedOutputHash = uint256(
            sha256(abi.encodePacked(bytes32(hex"1e004c04975c003b4bcac98394c0bf8612aa5461a597e14de1b52ccaf38f6611")))
        ) & ((1 << 253) - 1);
        assertEq(proofData.input[2], expectedOutputHash, "invalid output hash");
    }

    function test_updateClient() public {
        initializeClient();

        ProofData memory proof = readSkipProofData("./test/data/groth16_proof_01.json");
        ITendermintZKLightClient.UpdateStateInput memory m = ITendermintZKLightClient.UpdateStateInput({
            trustedHeight: 71,
            untrustedHeight: 157,
            untrustedBlockHash: bytes32(hex"1e004c04975c003b4bcac98394c0bf8612aa5461a597e14de1b52ccaf38f6611"),
            timestamp: 1713799305285796610,
            appHash: bytes32(hex"090ef3829ce557efa367796fc71e1d7970bc44d79cbeb9e61ddf43addf14044d"),
            simpleTreeProof: [
                bytes32(hex"562d84b15d6b3272a6e48b940b55afbd0e440c7af3266a8b92aafa2e2b8df5b1"),
                bytes32(hex"55fc96a99b65e8eb50a7691fa9b2d8f20f3afd951b77ea14ba7dcca5a8447ad0"),
                bytes32(hex"951da166ea46111da5bad0515cf715edd4eed23e10bf2e342c6286de4b989720"),
                bytes32(hex"25256014ce4ba2961128a3cdb666270b2a0d052b96ddfbd8f6338778c9edce0d"),
                bytes32(hex"4ef01b65f45d1291a2c81098282366484ba3b71d0091c0c599a5db5ea6e55eaa"),
                bytes32(hex"9fb9c7533caf1d218da3af6d277f6b101c42e3c3b75d784242da663604dd53c2")
            ],
            input: proof.input
        });
        vm.warp(m.timestamp + 100_000_000);
        lc.updateStateGroth16Commitment("tendermint-zk", m, proof.proof);
    }

    function test_updateClient2() public {
        initializeClient();

        assertEq(lc.getLatestHeight("tendermint-zk").revision_height, 71, "invalid latest height");
        {
            ProofData memory proof = readSkipProofData("./test/data/groth16_proof_01.json");
            ITendermintZKLightClient.UpdateStateInput memory m = ITendermintZKLightClient.UpdateStateInput({
                trustedHeight: 71,
                untrustedHeight: 157,
                untrustedBlockHash: bytes32(hex"1e004c04975c003b4bcac98394c0bf8612aa5461a597e14de1b52ccaf38f6611"),
                timestamp: 1713799305285796610,
                appHash: bytes32(hex"090ef3829ce557efa367796fc71e1d7970bc44d79cbeb9e61ddf43addf14044d"),
                simpleTreeProof: [
                    bytes32(hex"562d84b15d6b3272a6e48b940b55afbd0e440c7af3266a8b92aafa2e2b8df5b1"),
                    bytes32(hex"55fc96a99b65e8eb50a7691fa9b2d8f20f3afd951b77ea14ba7dcca5a8447ad0"),
                    bytes32(hex"951da166ea46111da5bad0515cf715edd4eed23e10bf2e342c6286de4b989720"),
                    bytes32(hex"25256014ce4ba2961128a3cdb666270b2a0d052b96ddfbd8f6338778c9edce0d"),
                    bytes32(hex"4ef01b65f45d1291a2c81098282366484ba3b71d0091c0c599a5db5ea6e55eaa"),
                    bytes32(hex"9fb9c7533caf1d218da3af6d277f6b101c42e3c3b75d784242da663604dd53c2")
                ],
                input: proof.input
            });
            vm.warp(m.timestamp + 100_000_000);
            lc.updateStateGroth16Commitment("tendermint-zk", m, proof.proof);
            assertEq(lc.getLatestHeight("tendermint-zk").revision_height, 157, "invalid latest height");
        }
        {
            ProofData memory proof = readSkipProofData("./test/data/groth16_proof_02.json");
            ITendermintZKLightClient.UpdateStateInput memory m = ITendermintZKLightClient.UpdateStateInput({
                trustedHeight: 157,
                untrustedHeight: 240,
                untrustedBlockHash: bytes32(hex"0cee2695ed179e0ecd94d478d663eb46a709c5a9f5cc0c173b9130de677e32a4"),
                timestamp: 1713799387005979741,
                appHash: bytes32(hex"ba21a864f753327067fcccede927114b71c6696ecca9bf4e02810e533f79867e"),
                simpleTreeProof: [
                    bytes32(hex"9a8e683aa1bc66314ef0a99b046c7e69db1d2b3a4603a0b913a41be479ba69ab"),
                    bytes32(hex"55fc96a99b65e8eb50a7691fa9b2d8f20f3afd951b77ea14ba7dcca5a8447ad0"),
                    bytes32(hex"951da166ea46111da5bad0515cf715edd4eed23e10bf2e342c6286de4b989720"),
                    bytes32(hex"25256014ce4ba2961128a3cdb666270b2a0d052b96ddfbd8f6338778c9edce0d"),
                    bytes32(hex"b8af2748c6abbf651c948f579bdb1382aad53ba6920f875ef7e313a1788d874d"),
                    bytes32(hex"9fb9c7533caf1d218da3af6d277f6b101c42e3c3b75d784242da663604dd53c2")
                ],
                input: proof.input
            });
            vm.warp(m.timestamp + 100_000_000);
            lc.updateStateGroth16Commitment("tendermint-zk", m, proof.proof);
            assertEq(lc.getLatestHeight("tendermint-zk").revision_height, 240, "invalid latest height");
        }
    }

    // ---------------------------- Intenal functions ----------------------------

    function initializeClient() internal {
        ProtoClientState.Data memory clientState = ProtoClientState.Data({
            step_verifier_digest: abi.encodePacked(bytes32(stepVerifierDigest)),
            skip_verifier_digest: abi.encodePacked(bytes32(skipVerifierDigest)),
            frozen: false,
            trusting_period: 1209600000000000, // 2 weeks in nanoseconds
            latest_height: Height.Data({revision_number: 0, revision_height: 71})
        });
        ProtoConsensusState.Data memory consensusState = ProtoConsensusState.Data({
            block_hash: abi.encodePacked(bytes32(hex"735FD53BF3DB0701830669F7EF935C7287D767C0D5F288E2212545C0B0FAABEC")),
            app_hash: abi.encodePacked(bytes32(hex"665700d55a782e879cf6bec2ff238970df23553473f5b99405337597d4f4449c")),
            timestamp: 1713799218801174900
        });

        lc.initializeClient(
            "tendermint-zk",
            TendermintZKLightClientProtoMarshaler.marshal(clientState),
            TendermintZKLightClientProtoMarshaler.marshal(consensusState)
        );
    }

    struct ProofData {
        uint256[8] proof;
        uint256[3] input;
    }

    function readSkipProofData(string memory path) internal returns (ProofData memory) {
        string memory data = vm.readFile(path);
        uint256[] memory inputs = vm.parseJsonUintArray(data, ".input");
        assertEq(inputs.length, 3, "invalid input length");
        assertEq(inputs[0], skipVerifierDigest, "invalid skipVerifierDigest");

        uint256[] memory proof = vm.parseJsonUintArray(data, ".proof");
        assertEq(proof.length, 8, "invalid proof length");

        return ProofData({
            proof: [proof[0], proof[1], proof[2], proof[3], proof[4], proof[5], proof[6], proof[7]],
            input: [inputs[0], inputs[1], inputs[2]]
        });
    }
}
