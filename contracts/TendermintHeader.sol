// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ProtoBufRuntime} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/ProtoBufRuntime.sol";
import {IbcLightclientsTendermintzkV1Timestamp as Timestamp} from
    "./proto/ibc/lightclients/tendermintzk/v1/TendermintZKLightClient.sol";

library TendermintHeader {
    /// @param proof generalized indexes: 4,6,7,11,17,26
    function merkleRoot(uint64 timestampNanos, bytes32 appHash, bytes32[6] calldata proof)
        internal
        pure
        returns (bytes32 blockHash)
    {
        bytes32 timestampLeaf = leafHash(
            Timestamp.encode(
                Timestamp.Data({seconds_: int64(timestampNanos / 1e9), nanos: int32(uint32(timestampNanos % 1e9))})
            )
        );
        bytes32 appHashLeaf = leafHash(cdcEncode(appHash));
        return innerHash(
            innerHash(innerHash(proof[2], innerHash(proof[4], timestampLeaf)), proof[0]),
            innerHash(innerHash(proof[3], innerHash(appHashLeaf, proof[5])), proof[1])
        );
    }

    /// @param proof generalized indexes: 4,6,7,11,17,26
    function merkleRoot2(uint64 timestampNanos, bytes32 appHash, bytes32[6] memory proof)
        internal
        pure
        returns (bytes32 blockHash)
    {
        bytes32 timestampLeaf = leafHash(
            Timestamp.encode(
                Timestamp.Data({seconds_: int64(timestampNanos / 1e9), nanos: int32(uint32(timestampNanos % 1e9))})
            )
        );
        bytes32 appHashLeaf = leafHash(cdcEncode(appHash));
        return innerHash(
            innerHash(innerHash(proof[2], innerHash(proof[4], timestampLeaf)), proof[0]),
            innerHash(innerHash(proof[3], innerHash(appHashLeaf, proof[5])), proof[1])
        );
    }

    /**
     * @dev returns tmhash(0x00 || leaf)
     *
     */
    function leafHash(bytes memory leaf) internal pure returns (bytes32) {
        uint8 leafPrefix = 0x00;
        return sha256(abi.encodePacked(leafPrefix, leaf));
    }

    /**
     * @dev returns tmhash(0x01 || left || right)
     */
    function innerHash(bytes32 leaf, bytes32 right) internal pure returns (bytes32) {
        uint8 innerPrefix = 0x01;
        return sha256(abi.encodePacked(innerPrefix, leaf, right));
    }

    function cdcEncode(bytes32 bz) internal pure returns (bytes memory) {
        // 1 + ProtoBufRuntime._sz_lendelim(32) = 34
        bytes memory bs = new bytes(34);
        uint256 pointer = 32;
        unchecked {
            pointer += ProtoBufRuntime._encode_key(1, ProtoBufRuntime.WireType.LengthDelim, pointer, bs);
            pointer += ProtoBufRuntime._encode_bytes(abi.encodePacked(bz), pointer, bs);
            assembly {
                mstore(bs, sub(pointer, 32))
            }
        }
        return bs;
    }
}
