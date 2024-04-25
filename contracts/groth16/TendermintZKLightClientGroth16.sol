// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";
import {TendermintZKLightClient} from "../TendermintZKLightClient.sol";
import {Verifier} from "./Groth16Verifier.sol";

contract TendermintZKLightClientGroth16 is TendermintZKLightClient, Verifier {
    constructor(address ibcHandler_, uint256 stepVerifierDigest_, uint256 skipVerifierDigest_, uint64 revisionNumber_)
        TendermintZKLightClient(ibcHandler_, stepVerifierDigest_, skipVerifierDigest_, revisionNumber_)
    {}

    function routeUpdateState(string calldata clientId, UpdateStateInput memory m, bytes memory zkp)
        public
        pure
        virtual
        override
        returns (bytes4 selector, bytes memory args)
    {
        return (this.updateStateGroth16Commitment.selector, abi.encode(clientId, m, abi.decode(zkp, (uint256[8]))));
    }

    function updateStateGroth16Commitment(
        string calldata clientId,
        UpdateStateInput calldata message,
        uint256[8] calldata proof
    ) public virtual returns (Height.Data[] memory heights) {
        verifyProof(proof, message.input);
        return updateState(clientId, message);
    }
}
