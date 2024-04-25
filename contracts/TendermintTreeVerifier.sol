// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ProtoBufRuntime} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/ProtoBufRuntime.sol";
import {ITendermintZKLightClientErrors} from "./ITendermintZKLightClientErrors.sol";

library TendermintTreeVerifier {
    enum ProofSpec {
        None,
        SimpleTree,
        IAVLTree
    }

    struct InnerOp {
        bytes prefix;
        bytes suffix;
    }

    struct ExistenceProof {
        ProofSpec spec;
        bytes prefix;
        bytes key;
        bytes value;
        InnerOp[] path;
    }

    struct NonExistenceProof {
        bytes key;
        ExistenceProof left;
        ExistenceProof right;
    }

    struct NonMembershipProof {
        TendermintTreeVerifier.NonExistenceProof proof0;
        TendermintTreeVerifier.ExistenceProof proof1;
    }

    function verifyMembership(ExistenceProof memory proof) internal pure returns (bytes32) {
        if (proof.spec == ProofSpec.SimpleTree) {
            return verifyMembershipTendermintSpec(proof.prefix, proof.key, proof.value, proof.path);
        } else if (proof.spec == ProofSpec.IAVLTree) {
            return verifyMembershipIAVLSpec(proof.prefix, proof.key, proof.value, proof.path);
        } else {
            revert ITendermintZKLightClientErrors.ITendermintZKLightClientUnsupportedProofSpec();
        }
    }

    function verifyNonMembershipIAVL(NonExistenceProof memory proof) internal pure returns (bytes32) {
        require(proof.left.spec == proof.right.spec);
        require(proof.left.spec == ProofSpec.IAVLTree);

        bytes32 root;
        bool isLeftNil = proof.left.key.length == 0;
        bool isRightNil = proof.right.key.length == 0;
        if (isLeftNil && isRightNil) {
            revert("both proofs are nil");
        }
        ensureKeysInValidRange(proof.left.key, proof.key, proof.right.key);
        if (!isLeftNil) {
            root = verifyMembershipIAVLSpec(proof.left.prefix, proof.left.key, proof.left.value, proof.left.path);
        }
        if (!isRightNil) {
            bytes32 root1 =
                verifyMembershipIAVLSpec(proof.right.prefix, proof.right.key, proof.right.value, proof.right.path);
            if (isLeftNil) {
                root = root1;
            } else if (root != root1) {
                revert("root != root1");
            }
        }

        if (isLeftNil) {
            if (!isLeftMostIAVL(proof.right.path, proof.right.path.length)) {
                revert("");
            }
        } else if (isRightNil) {
            if (!isRightMostIAVL(proof.left.path, proof.left.path.length)) {
                revert("");
            }
        } else {
            if (!isLeftNeighborIAVL(proof.left.path, proof.right.path)) {
                revert("");
            }
        }

        return root;
    }

    function isLeftMostIAVL(InnerOp[] memory rightPath, uint256 maxLen) internal pure returns (bool) {
        // minPrefix, maxPrefix, suffix := getPadding(spec, 0)
        (uint256 minPrefix, uint256 maxPrefix, uint256 suffix) = getPaddingIAVL(0);
        for (uint256 i = 0; i < maxLen; i++) {
            // NOTE In IAVL, does not need to check whether the padding bytes correspond to all empty siblings on the left side of a branch
            // ref. https://github.com/cosmos/ics23/pull/61
            if (!hasPadding(rightPath[i], minPrefix, maxPrefix, suffix)) {
                return false;
            }
        }
        return true;
    }

    function isRightMostIAVL(InnerOp[] memory leftPath, uint256 maxLen) internal pure returns (bool) {
        // last := len(spec.ChildOrder) - 1
        // minPrefix, maxPrefix, suffix := getPadding(spec, int32(last))
        (uint256 minPrefix, uint256 maxPrefix, uint256 suffix) = getPaddingIAVL(1);
        for (uint256 i = 0; i < maxLen; i++) {
            // NOTE In IAVL, does not need to check whether the padding bytes correspond to all empty siblings on the left side of a branch
            // ref. https://github.com/cosmos/ics23/pull/61
            if (!hasPadding(leftPath[i], minPrefix, maxPrefix, suffix)) {
                return false;
            }
        }
        return true;
    }

    function isLeftNeighborIAVL(InnerOp[] memory leftPath, InnerOp[] memory rightPath) internal pure returns (bool) {
        uint256 leftIdx = leftPath.length - 1;
        uint256 rightIdx = rightPath.length - 1;
        while (
            keccak256(leftPath[leftIdx].prefix) == keccak256(rightPath[rightIdx].prefix)
                && keccak256(leftPath[leftIdx].suffix) == keccak256(rightPath[rightIdx].suffix)
        ) {
            leftIdx -= 1;
            rightIdx -= 1;
        }

        if (!isLeftStepIAVL(leftPath[leftIdx], rightPath[rightIdx])) {
            return false;
        }
        if (!isRightMostIAVL(leftPath, leftIdx)) {
            return false;
        }
        if (!isLeftMostIAVL(rightPath, rightIdx)) {
            return false;
        }
        return true;
    }

    function getPaddingIAVL(uint256 branch)
        internal
        pure
        returns (uint256 minPrefix, uint256 maxPrefix, uint256 suffix)
    {
        uint256 idx = getPositionIAVL(branch);
        // prefix := idx * int(spec.ChildSize)
        uint256 prefix = idx * 33;
        minPrefix = prefix + 4;
        maxPrefix = prefix + 12;

        // suffix = (len(spec.ChildOrder) - 1 - idx) * int(spec.ChildSize)
        suffix = (1 - idx) * 33;
    }

    function getPositionIAVL(uint256 branch) internal pure returns (uint256) {
        if (branch == 0) {
            return 0;
        } else if (branch == 1) {
            return 1;
        } else {
            revert("");
        }
    }

    function hasPadding(InnerOp memory op, uint256 minPrefix, uint256 maxPrefix, uint256 suffix)
        internal
        pure
        returns (bool)
    {
        if (op.prefix.length < minPrefix || op.prefix.length > maxPrefix) {
            return false;
        }
        return op.suffix.length == suffix;
    }

    function isLeftStepIAVL(InnerOp memory left, InnerOp memory right) internal pure returns (bool) {
        return orderFromPaddingIAVL(right) == orderFromPaddingIAVL(left) + 1;
    }

    function orderFromPaddingIAVL(InnerOp memory inner) internal pure returns (uint256) {
        for (uint256 b = 0; b < 2; b++) {
            (uint256 minPrefix, uint256 maxPrefix, uint256 suffix) = getPaddingIAVL(b);
            if (hasPadding(inner, minPrefix, maxPrefix, suffix)) {
                return b;
            }
        }
        revert("");
    }

    function ensureKeysInValidRange(bytes memory leftKey, bytes memory targetKey, bytes memory rightKey)
        internal
        pure
    {
        if (leftKey.length == 0 || bytesCompare(leftKey, targetKey) < 0) {
            if (rightKey.length == 0 || bytesCompare(targetKey, rightKey) < 0) {
                return;
            }
        }
        revert("F");
    }

    function bytesCompare(bytes memory a, bytes memory b) internal pure returns (int256) {
        uint256 aLen = a.length;
        uint256 bLen = b.length;
        uint256 minLen = aLen < bLen ? aLen : bLen;
        for (uint256 i = 0; i < minLen; i++) {
            if (uint8(a[i]) < uint8(b[i])) {
                return -1;
            } else if (uint8(a[i]) > uint8(b[i])) {
                return 1;
            }
        }
        if (aLen > minLen) {
            return 1;
        }
        if (bLen > minLen) {
            return -1;
        }
        return 0;
    }

    /**
     * @dev Verify a simple tree proof
     * var TendermintSpec = &ProofSpec{
     *     LeafSpec: &LeafOp{
     *         Prefix:       []byte{0},
     *         PrehashKey:   HashOp_NO_HASH,
     *         Hash:         HashOp_SHA256,
     *         PrehashValue: HashOp_SHA256,
     *         Length:       LengthOp_VAR_PROTO,
     *     },
     *     InnerSpec: &InnerSpec{
     *         ChildOrder:      []int32{0, 1},
     *         MinPrefixLength: 1,
     *         MaxPrefixLength: 1,
     *         ChildSize:       32, // (no length byte)
     *         Hash:            HashOp_SHA256,
     *     },
     * }
     * @return appHash
     */
    function verifyMembershipTendermintSpec(
        bytes memory prefix,
        bytes memory key,
        bytes memory value,
        InnerOp[] memory path
    ) internal pure returns (bytes32) {
        if (prefix.length != 1) {
            // revert("prefix length is not 1");
            revert ITendermintZKLightClientErrors.ITendermintZKLightClientTendermintSpecInvalidProof();
        } else if (prefix[0] != 0) {
            // revert("prefix is not 0");
            revert ITendermintZKLightClientErrors.ITendermintZKLightClientTendermintSpecInvalidProof();
        }
        // 1. caclulate the hash of the leaf
        bytes32 h = sha256(bytes.concat(prefix, prepareLeafData(key), prepareLeafData(sha256(value))));
        // 2. calculate the hash of the root
        for (uint256 i = 0; i < path.length; i++) {
            bytes memory p = path[i].prefix;
            if (p.length < 1) {
                // revert("prefix length is less than 1");
                revert ITendermintZKLightClientErrors.ITendermintZKLightClientTendermintSpecInvalidProof();
            } else if (p.length > 33) {
                // revert("prefix length is greater than 33");
                revert ITendermintZKLightClientErrors.ITendermintZKLightClientTendermintSpecInvalidProof();
            }
            if (path[i].suffix.length % 32 != 0) {
                // revert("suffix length is not a multiple of 32");
                revert ITendermintZKLightClientErrors.ITendermintZKLightClientTendermintSpecInvalidProof();
            }
            h = sha256(bytes.concat(p, h, path[i].suffix));
        }
        return h;
    }

    function prepareLeafData(bytes memory data) internal pure returns (bytes memory) {
        uint256 len = data.length;
        bytes memory bs = new bytes(ProtoBufRuntime._sz_varint(len));
        ProtoBufRuntime._encode_varint(len, 32, bs);
        return bytes.concat(bs, data);
    }

    function prepareLeafData(bytes32 data) internal pure returns (bytes memory) {
        // bytes memory bs = new bytes(ProtoBufRuntime._sz_varint(32));
        // ProtoBufRuntime._encode_varint(32, 32, bs);
        return bytes.concat(bytes1(0x20), data);
    }

    /**
     * @dev Verify a IAVL proof
     * var IavlSpec = &ProofSpec{
     * 	LeafSpec: &LeafOp{
     * 		Prefix:       []byte{0},
     * 		PrehashKey:   HashOp_NO_HASH,
     * 		Hash:         HashOp_SHA256,
     * 		PrehashValue: HashOp_SHA256,
     * 		Length:       LengthOp_VAR_PROTO,
     * 	},
     * 	InnerSpec: &InnerSpec{
     * 		ChildOrder:      []int32{0, 1},
     * 		MinPrefixLength: 4,
     * 		MaxPrefixLength: 12,
     * 		ChildSize:       33, // (with length byte)
     * 		EmptyChild:      nil,
     * 		Hash:            HashOp_SHA256,
     * 	},
     * }
     */
    function verifyMembershipIAVLSpec(bytes memory prefix, bytes memory key, bytes memory value, InnerOp[] memory path)
        internal
        pure
        returns (bytes32)
    {
        if (prefix[0] != 0) {
            revert ITendermintZKLightClientErrors.ITendermintZKLightClientIAVLSpecInvalidProof();
        }
        validateIAVLOps(prefix, 0);

        // 1. caclulate the hash of the leaf
        bytes32 h = sha256(bytes.concat(prefix, prepareLeafData(key), prepareLeafData(sha256(value))));
        // 2. calculate the hash of the root
        for (uint256 i = 0; i < path.length; i++) {
            bytes memory innerPrefix = path[i].prefix;
            if (innerPrefix.length < 4) {
                revert ITendermintZKLightClientErrors.ITendermintZKLightClientInvalidInnerPrefixLength();
            } else if (innerPrefix.length > 45) {
                revert ITendermintZKLightClientErrors.ITendermintZKLightClientInvalidInnerPrefixLength();
            }
            if (path[i].suffix.length % 33 != 0) {
                revert ITendermintZKLightClientErrors.ITendermintZKLightClientInvalidInnerSuffixLength();
            }
            validateIAVLOps(innerPrefix, i + 1);
            h = sha256(bytes.concat(innerPrefix, h, path[i].suffix));
        }
        return h;
    }

    /// @dev validate the IAVL Ops
    /// https://github.com/cosmos/ics23/blob/94d38b80c8ce912265fb176acba1321c5ade2083/go/ops.go#L21
    function validateIAVLOps(bytes memory prefix, uint256 b) internal pure {
        uint256 ptr = 32;
        uint256[3] memory values;
        for (uint256 i = 0; i < 3; i++) {
            (uint256 v, uint256 n) = ProtoBufRuntime._decode_varint(ptr, prefix);
            if (v < 0) {
                revert ITendermintZKLightClientErrors.ITendermintZKLightClientInvalidIAVLPrefix();
            }
            ptr += n;
            values[i] = v;
        }
        if (values[0] < b) {
            revert ITendermintZKLightClientErrors.ITendermintZKLightClientInvalidIAVLOp();
        }
        unchecked {
            uint256 r2 = prefix.length + 32 - ptr;
            if (b == 0) {
                if (r2 != 0) {
                    revert ITendermintZKLightClientErrors.ITendermintZKLightClientInvalidIAVLOp();
                }
            } else {
                // if !(r2^(0xff&0x01) == 0 || r2 == (0xde+int('v'))/10)
                if (!(r2 ^ 1 == 0 || r2 == 34)) {
                    revert ITendermintZKLightClientErrors.ITendermintZKLightClientInvalidIAVLOp();
                }
            }
        }
    }
}
