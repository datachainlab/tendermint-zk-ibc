// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";
import {ProtoBufRuntime} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/ProtoBufRuntime.sol";
import {TendermintZKLightClientGroth16Commitment} from
    "../contracts/groth16/TendermintZKLightClientGroth16Commitment.sol";
import {ITendermintZKLightClient} from "../contracts/TendermintZKLightClient.sol";
import {TendermintHeader} from "../contracts/TendermintHeader.sol";
import {
    IbcLightclientsTendermintzkV1ClientState as ProtoClientState,
    IbcLightclientsTendermintzkV1ConsensusState as ProtoConsensusState
} from "../contracts/proto/ibc/lightclients/tendermintzk/v1/TendermintZKLightClient.sol";
import {TendermintZKLightClientProtoMarshaler} from "../contracts/TendermintZKLightClientProtoMarshaler.sol";
import {TendermintTreeVerifier} from "../contracts/TendermintTreeVerifier.sol";

contract Groth16CommitmentVerifierTest is Test {
    uint256 internal immutable stepVerifierDigest =
        uint256(bytes32(hex"09bf185e9e478bac323981a844afe484dcd73823f6a34f5adb8cffe6c4436111"));
    uint256 internal immutable skipVerifierDigest =
        uint256(bytes32(hex"286fd609266936f71d552671b7553f1a0e59c7cf296112996bded1ca3bafa4a4"));

    TendermintZKLightClientGroth16Commitment public lc;

    function setUp() public {
        lc = new TendermintZKLightClientGroth16Commitment(address(this), stepVerifierDigest, skipVerifierDigest, 0);
    }

    function test_verifyProof() public {
        ProofData memory proofData = readSkipProofData("./test/data/groth16-commitment_proof.json");
        lc.verifyProof(proofData.proof, proofData.commitments, proofData.commitmentPok, proofData.input);
    }

    function test_verifyCompressedProof() public {
        ProofData memory proofData = readSkipProofData("./test/data/groth16-commitment_proof.json");
        (uint256[4] memory compressed, uint256[1] memory compressedCommitments, uint256 compressedCommitmentPok) =
            lc.compressProof(proofData.proof, proofData.commitments, proofData.commitmentPok);
        lc.verifyCompressedProof(compressed, compressedCommitments, compressedCommitmentPok, proofData.input);
    }

    function test_inputOutputHash() public {
        ProofData memory proofData = readSkipProofData("./test/data/groth16-commitment_proof.json");
        uint256 expectedInputHash = uint256(
            sha256(
                abi.encodePacked(
                    uint64(4), bytes32(hex"B0C0176E960C4679C21D4AE5508025D5D4658F8587978786D9B76540F0EF68F3"), uint64(6)
                )
            )
        ) & ((1 << 253) - 1);
        assertEq(proofData.input[1], expectedInputHash, "invalid input hash");

        uint256 expectedOutputHash = uint256(
            sha256(abi.encodePacked(bytes32(hex"1FEA97C83E7345F1843B91D13889CEA2487E223A5C30CE70293C8064844D6C4F")))
        ) & ((1 << 253) - 1);
        assertEq(proofData.input[2], expectedOutputHash, "invalid output hash");
    }

    function test_headerMerkleRoot() public {
        bytes32 blockHash = bytes32(hex"1FEA97C83E7345F1843B91D13889CEA2487E223A5C30CE70293C8064844D6C4F");
        bytes32 appHash = bytes32(hex"C66BA59FABC9F81A90FA304F294CDF56C40DE50EC4D0CE432514B96BCE3530D0");
        uint64 timestampNano = 1711326382760122626;
        bytes32[6] memory proof = [
            bytes32(hex"a9a18bfeecfc57b342ccf62215a105a32d43282e5de26fd2ca962a481fce9deb"),
            bytes32(hex"e37aaf4da6664628ecd8cc9a6be2b3e025ec09fd0b0b7d96b6fb4c23a72a56c1"),
            bytes32(hex"951da166ea46111da5bad0515cf715edd4eed23e10bf2e342c6286de4b989720"),
            bytes32(hex"edc9aa6f5b6e119d47c4dea8f0323ff27f2324ff4321cb9111e60b31c7cfb0ee"),
            bytes32(hex"c9132701e052d8897ca5f14e40560d42fb10cc1a84316c632142305321badfd3"),
            bytes32(hex"9fb9c7533caf1d218da3af6d277f6b101c42e3c3b75d784242da663604dd53c2")
        ];
        bytes32 root = TendermintHeader.merkleRoot2(timestampNano, appHash, proof);
        assertEq(blockHash, root, "invalid merkle root");
    }

    function test_initializeClient() public {
        initializeClient();
    }

    function test_updateClient() public {
        initializeClient();

        ProofData memory proof = readSkipProofData("./test/data/groth16-commitment_proof.json");
        ITendermintZKLightClient.UpdateStateInput memory m = ITendermintZKLightClient.UpdateStateInput({
            trustedHeight: 4,
            untrustedHeight: 6,
            untrustedBlockHash: bytes32(hex"1FEA97C83E7345F1843B91D13889CEA2487E223A5C30CE70293C8064844D6C4F"),
            timestamp: 1711326382760122626,
            appHash: bytes32(hex"C66BA59FABC9F81A90FA304F294CDF56C40DE50EC4D0CE432514B96BCE3530D0"),
            simpleTreeProof: [
                bytes32(hex"a9a18bfeecfc57b342ccf62215a105a32d43282e5de26fd2ca962a481fce9deb"),
                bytes32(hex"e37aaf4da6664628ecd8cc9a6be2b3e025ec09fd0b0b7d96b6fb4c23a72a56c1"),
                bytes32(hex"951da166ea46111da5bad0515cf715edd4eed23e10bf2e342c6286de4b989720"),
                bytes32(hex"edc9aa6f5b6e119d47c4dea8f0323ff27f2324ff4321cb9111e60b31c7cfb0ee"),
                bytes32(hex"c9132701e052d8897ca5f14e40560d42fb10cc1a84316c632142305321badfd3"),
                bytes32(hex"9fb9c7533caf1d218da3af6d277f6b101c42e3c3b75d784242da663604dd53c2")
            ],
            input: proof.input
        });
        vm.warp(m.timestamp + 100_000_000);
        lc.updateStateGroth16Commitment("tendermint-zk", m, proof.proof, proof.commitments, proof.commitmentPok);
    }

    function test_decodeExistenceProof() public {
        bytes memory proofBz =
            hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000380000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000001040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000001060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000108000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000010b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010c00000000000000000000000000000000000000000000000000000000000000";
        TendermintTreeVerifier.ExistenceProof[] memory eproof =
            abi.decode(proofBz, (TendermintTreeVerifier.ExistenceProof[]));
        assertEq(eproof.length, 2, "invalid existence proof length");
        assertTrue(eproof[0].spec == TendermintTreeVerifier.ProofSpec.SimpleTree);
        assertTrue(eproof[1].spec == TendermintTreeVerifier.ProofSpec.IAVLTree);
    }

    // ---------------------------- Intenal functions ----------------------------

    function initializeClient() internal {
        ProtoClientState.Data memory clientState = ProtoClientState.Data({
            step_verifier_digest: abi.encodePacked(bytes32(stepVerifierDigest)),
            skip_verifier_digest: abi.encodePacked(bytes32(skipVerifierDigest)),
            frozen: false,
            trusting_period: 1209600000000000, // 2 weeks in nanoseconds
            latest_height: Height.Data({revision_number: 0, revision_height: 4})
        });
        ProtoConsensusState.Data memory consensusState = ProtoConsensusState.Data({
            block_hash: abi.encodePacked(bytes32(hex"B0C0176E960C4679C21D4AE5508025D5D4658F8587978786D9B76540F0EF68F3")),
            app_hash: abi.encodePacked(bytes32(hex"5ABF44E16071E1961BFF682B62E3CEAAEDD2DBBAA070F88E22DC4987E7CD93B8")),
            timestamp: 1711326380725084999
        });

        lc.initializeClient(
            "tendermint-zk",
            TendermintZKLightClientProtoMarshaler.marshal(clientState),
            TendermintZKLightClientProtoMarshaler.marshal(consensusState)
        );
    }

    struct ProofData {
        uint256[8] proof;
        uint256[2] commitments;
        uint256[2] commitmentPok;
        uint256[3] input;
    }

    function readSkipProofData(string memory path) internal returns (ProofData memory) {
        string memory data = vm.readFile(path);
        uint256[] memory inputs = vm.parseJsonUintArray(data, ".input");
        assertEq(inputs.length, 3, "invalid input length");
        assertEq(inputs[0], skipVerifierDigest, "invalid skipVerifierDigest");

        uint256[] memory proof = vm.parseJsonUintArray(data, ".proof");
        assertEq(proof.length, 8, "invalid proof length");
        uint256[] memory commitments = vm.parseJsonUintArray(data, ".commitments");
        assertEq(commitments.length, 2, "invalid commitments length");
        uint256[] memory commitmentPok = vm.parseJsonUintArray(data, ".commitment_pok");
        assertEq(commitmentPok.length, 2, "invalid commitmentPok length");

        return ProofData({
            proof: [proof[0], proof[1], proof[2], proof[3], proof[4], proof[5], proof[6], proof[7]],
            commitments: [commitments[0], commitments[1]],
            commitmentPok: [commitmentPok[0], commitmentPok[1]],
            input: [inputs[0], inputs[1], inputs[2]]
        });
    }
}
