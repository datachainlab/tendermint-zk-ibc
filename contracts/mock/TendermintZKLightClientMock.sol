// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";
import {TendermintZKLightClient} from "../TendermintZKLightClient.sol";

contract TendermintZKLightClientMock is TendermintZKLightClient {
    constructor(address ibcHandler_, uint256 stepVerifierDigest_, uint256 skipVerifierDigest_, uint64 revisionNumber_)
        TendermintZKLightClient(ibcHandler_, stepVerifierDigest_, skipVerifierDigest_, revisionNumber_)
    {}

    function routeUpdateState(string calldata clientId, UpdateStateInput memory m, bytes memory proof)
        public
        pure
        virtual
        override
        returns (bytes4 selector, bytes memory args)
    {
        return (this.updateStateMock.selector, abi.encode(clientId, m, proof));
    }

    function updateStateMock(
        string calldata clientId,
        UpdateStateInput calldata message,
        bytes calldata proof
    ) public virtual returns (Height.Data[] memory heights) {
        require(keccak256(proof) == keccak256("mock"), "proof not valid");
        return updateState(clientId, message);
    }
}
