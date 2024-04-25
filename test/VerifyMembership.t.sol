// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";
import {ProtoBufRuntime} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/ProtoBufRuntime.sol";
import {TendermintTreeVerifier as TV} from "../contracts/TendermintTreeVerifier.sol";
import {TendermintZKLightClientMock} from "../contracts/mock/TendermintZKLightClientMock.sol";
import {
    IbcLightclientsTendermintzkV1ClientState as ProtoClientState,
    IbcLightclientsTendermintzkV1ConsensusState as ProtoConsensusState
} from "../contracts/proto/ibc/lightclients/tendermintzk/v1/TendermintZKLightClient.sol";
import {TendermintZKLightClientProtoMarshaler} from "../contracts/TendermintZKLightClientProtoMarshaler.sol";

contract VerifyMembershipTest is Test {
    uint256 internal immutable stepVerifierDigest =
        uint256(bytes32(hex"09bf185e9e478bac323981a844afe484dcd73823f6a34f5adb8cffe6c4436111"));
    uint256 internal immutable skipVerifierDigest =
        uint256(bytes32(hex"286fd609266936f71d552671b7553f1a0e59c7cf296112996bded1ca3bafa4a4"));

    TendermintZKLightClientMock public lc;

    function setUp() public {
        lc = new TendermintZKLightClientMock(address(this), stepVerifierDigest, skipVerifierDigest, 0);
    }

    function test_verifySimpleMerkleTree() public {
        bytes32 root = 0xbb76430c4007e046fe0fa0e81c78e8af308aa60f83893f3f8938a94593b7063e;
        bytes memory path = bytes("ibc");
        bytes memory value = hex"45824db700cfd1a8fe2c389c51a924b8d223a0e2f65046ab5c63a548fbf25179";
        TV.InnerOp[] memory innerOps = new TV.InnerOp[](5);
        innerOps[0] = TV.InnerOp(hex"01", hex"c505c0fd48b1cf2b65619f12b3144e19c60b4e6b62525ee936be93d041623ebf");
        innerOps[1] = TV.InnerOp(hex"01", hex"ffdc8cd34f3195f416db30c94ee9ef65ecb3174668eb51309cb283e3149a75d8");
        innerOps[2] = TV.InnerOp(hex"01470e2a731014a624f268dc7bc9842dc5b165059eb8c7e0b15c734e1d1b4253e4", hex"");
        innerOps[3] = TV.InnerOp(hex"01cfef7c8740c6d63614e2a388a33c1868c7dce81cd98c063b2166d08b0c751e0e", hex"");
        innerOps[4] = TV.InnerOp(hex"01", hex"30ee99c3a68506ac7ba9cee895e3341f921cf0042f62b0e5bf440affc8ce52cb");

        bytes32 appHash = TV.verifyMembershipTendermintSpec(hex"00", path, value, innerOps);
        assertEq(appHash, root);
    }

    function test_verifyIAVLTree() public {
        bytes32 root = hex"45824db700cfd1a8fe2c389c51a924b8d223a0e2f65046ab5c63a548fbf25179";
        bytes memory path = bytes("channelEnds/ports/transfer/channels/channel-0");
        // serialized channel state
        bytes memory value = hex"080110011a0a0a087472616e73666572220c636f6e6e656374696f6e2d302a0769637332302d31";
        TV.InnerOp[] memory innerOps = new TV.InnerOp[](5);
        innerOps[0] = TV.InnerOp(hex"02042c20", hex"205c6b0488096417c2fd1896fa89c67ec9ec95044447609bcd988099ed94c5735b");
        innerOps[1] = TV.InnerOp(hex"04082c20", hex"20e020e70801dce90a213e1b5e8710ad77f2493cf6c032df1dda30d556a3b0a918");
        innerOps[2] = TV.InnerOp(hex"06102c20", hex"20421e2064f7d522bc3cb7ae85ebde2295f3431318f233784324cbea2604024d01");
        innerOps[3] = TV.InnerOp(hex"081e2c20", hex"205cce3f3871c523a40e4bb7dc1712422f1cec7b3026f6bd83bc64fa08f2121981");
        innerOps[4] = TV.InnerOp(hex"0a302e20", hex"20c389135ce0c86273dfc3b6c63fd45aa6ba3838f9c38e467814db331d000abb35");
        bytes32 v = TV.verifyMembershipIAVLSpec(hex"00022c", path, value, innerOps);
        console2.logBytes32(v);
        assertEq(v, root);
    }

    function test_verifyNonMembershipIAVL() public {
        bytes32 root = hex"e8589c5532539d0dd1cdf4bad00bd594ccd177b18c8279cb05198259333d6bbd";
        bytes memory path = bytes("clients/07-tendermint-0/consensusStates/0-256");
        TV.ExistenceProof memory left;
        {
            left.spec = TV.ProofSpec.IAVLTree;
            left.prefix = hex"000206";
            left.key =
                hex"636c69656e74732f30372d74656e6465726d696e742d302f636f6e73656e7375735374617465732f302d322f70726f63657373656454696d65";
            left.value = hex"17c83a9a7e12cb78";
            left.path = new TV.InnerOp[](6);
            left.path[0] =
                TV.InnerOp(hex"02041220", hex"204d79123ec020d352fdc8792d53e7e62e1a2b8635b08e72240a2311c6716519c7");
            left.path[1] =
                TV.InnerOp(hex"04081e20", hex"2077504b539f15b8a365f4cb835ae6ad1848b0b031b6ef9f85606775c92108ed6a");
            left.path[2] =
                TV.InnerOp(hex"060cda0120", hex"2007e3768cbd4dbf35a6ef1d99ae6bcc1dd048b8c810f20c1f7cc72386e3524a58");
            left.path[3] =
                TV.InnerOp(hex"081cda01209ec0e431e03c8ee3ef4e0cc89bf6dae15060a0fe648b93b324deda4dab94efbd20", hex"");
            left.path[4] =
                TV.InnerOp(hex"0a32da0120", hex"207eae9ff1ef51f05f00b25074402af80331a6e4f7c2da38a50856867044f848f6");
            left.path[5] =
                TV.InnerOp(hex"0c46e20120", hex"2018430573e64c3a6bbf66ab2666920e2a015221f0213d7890c76a141c3bf10316");
        }
        TV.ExistenceProof memory right;
        {
            right.spec = TV.ProofSpec.IAVLTree;
            right.prefix = hex"000212";
            right.key = hex"636c69656e74732f30372d74656e6465726d696e742d302f636f6e73656e7375735374617465732f302d38";
            right.value =
                hex"0a2e2f6962632e6c69676874636c69656e74732e74656e6465726d696e742e76312e436f6e73656e737573537461746512540a0c0882fd92b10610f88ef3930212220a20fbace06b5a7c4b094abf5cef8de0fe508306fe9b5ee5c3be1cb054355bfeb49c1a205816fbc42d2cd26840e36bdd1190daa0fd37569ecb8617fb4f4287a5b25b3376";
            right.path = new TV.InnerOp[](6);
            right.path[0] =
                TV.InnerOp(hex"020412202057aca9193b9175ceeae269a8b9bb7fe034b0b829b5d8279b650df8028bf3ee20", hex"");
            right.path[1] =
                TV.InnerOp(hex"04081e20", hex"2077504b539f15b8a365f4cb835ae6ad1848b0b031b6ef9f85606775c92108ed6a");
            right.path[2] =
                TV.InnerOp(hex"060cda0120", hex"2007e3768cbd4dbf35a6ef1d99ae6bcc1dd048b8c810f20c1f7cc72386e3524a58");
            right.path[3] =
                TV.InnerOp(hex"081cda01209ec0e431e03c8ee3ef4e0cc89bf6dae15060a0fe648b93b324deda4dab94efbd20", hex"");
            right.path[4] =
                TV.InnerOp(hex"0a32da0120", hex"207eae9ff1ef51f05f00b25074402af80331a6e4f7c2da38a50856867044f848f6");
            right.path[5] =
                TV.InnerOp(hex"0c46e20120", hex"2018430573e64c3a6bbf66ab2666920e2a015221f0213d7890c76a141c3bf10316");
        }
        bytes32 v = TV.verifyNonMembershipIAVL(TV.NonExistenceProof({key: path, left: left, right: right}));
        console2.logBytes32(v);
        assertEq(v, root);
    }

    function test_verifyMembership() public {
        ProtoClientState.Data memory clientState = ProtoClientState.Data({
            step_verifier_digest: abi.encodePacked(bytes32(stepVerifierDigest)),
            skip_verifier_digest: abi.encodePacked(bytes32(skipVerifierDigest)),
            frozen: false,
            trusting_period: 1209600000000000, // 2 weeks in nanoseconds
            latest_height: Height.Data({revision_number: 0, revision_height: 4})
        });
        ProtoConsensusState.Data memory consensusState = ProtoConsensusState.Data({
            block_hash: abi.encodePacked(bytes32(0)),
            app_hash: abi.encodePacked(bytes32(hex"bb76430c4007e046fe0fa0e81c78e8af308aa60f83893f3f8938a94593b7063e")),
            timestamp: 1711326380725084999
        });

        lc.initializeClient(
            "tendermint-zk",
            TendermintZKLightClientProtoMarshaler.marshal(clientState),
            TendermintZKLightClientProtoMarshaler.marshal(consensusState)
        );
        // serialized channel state
        bytes memory value = hex"080110011a0a0a087472616e73666572220c636f6e6e656374696f6e2d302a0769637332302d31";
        TV.ExistenceProof[2] memory eproof;
        {
            eproof[0] = TV.ExistenceProof({
                spec: TV.ProofSpec.IAVLTree,
                prefix: hex"00022c",
                key: bytes("channelEnds/ports/transfer/channels/channel-0"),
                value: value,
                path: new TV.InnerOp[](5)
            });
            eproof[0].path[0] =
                TV.InnerOp(hex"02042c20", hex"205c6b0488096417c2fd1896fa89c67ec9ec95044447609bcd988099ed94c5735b");
            eproof[0].path[1] =
                TV.InnerOp(hex"04082c20", hex"20e020e70801dce90a213e1b5e8710ad77f2493cf6c032df1dda30d556a3b0a918");
            eproof[0].path[2] =
                TV.InnerOp(hex"06102c20", hex"20421e2064f7d522bc3cb7ae85ebde2295f3431318f233784324cbea2604024d01");
            eproof[0].path[3] =
                TV.InnerOp(hex"081e2c20", hex"205cce3f3871c523a40e4bb7dc1712422f1cec7b3026f6bd83bc64fa08f2121981");
            eproof[0].path[4] =
                TV.InnerOp(hex"0a302e20", hex"20c389135ce0c86273dfc3b6c63fd45aa6ba3838f9c38e467814db331d000abb35");
        }
        {
            eproof[1] = TV.ExistenceProof({
                spec: TV.ProofSpec.SimpleTree,
                prefix: hex"00",
                key: bytes("ibc"),
                value: hex"45824db700cfd1a8fe2c389c51a924b8d223a0e2f65046ab5c63a548fbf25179",
                path: new TV.InnerOp[](5)
            });
            eproof[1].path[0] =
                TV.InnerOp(hex"01", hex"c505c0fd48b1cf2b65619f12b3144e19c60b4e6b62525ee936be93d041623ebf");
            eproof[1].path[1] =
                TV.InnerOp(hex"01", hex"ffdc8cd34f3195f416db30c94ee9ef65ecb3174668eb51309cb283e3149a75d8");
            eproof[1].path[2] =
                TV.InnerOp(hex"01470e2a731014a624f268dc7bc9842dc5b165059eb8c7e0b15c734e1d1b4253e4", hex"");
            eproof[1].path[3] =
                TV.InnerOp(hex"01cfef7c8740c6d63614e2a388a33c1868c7dce81cd98c063b2166d08b0c751e0e", hex"");
            eproof[1].path[4] =
                TV.InnerOp(hex"01", hex"30ee99c3a68506ac7ba9cee895e3341f921cf0042f62b0e5bf440affc8ce52cb");
        }

        lc.verifyMembership(
            "tendermint-zk",
            clientState.latest_height,
            0,
            0,
            abi.encode(eproof),
            bytes("ibc"),
            bytes("channelEnds/ports/transfer/channels/channel-0"),
            value
        );
    }
}
