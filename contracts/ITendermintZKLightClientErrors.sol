// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface ITendermintZKLightClientErrors {
    error ITendermintZKLightClientOnlyIBC();
    error ITendermintZKLightClientInvalidStepVerifierDigest();
    error ITendermintZKLightClientInvalidSkipVerifierDigest();
    error ITendermintZKLightClientInvalidTrustingPeriod();
    error ITendermintZKLightClientClientStateFrozen();
    error ITendermintZKLightClientClientInvalidRevisionHeight();
    error ITendermintZKLightClientClientInvalidRevisionNumber();
    error ITendermintZKLightClientClientInvalidBlockHash();
    error ITendermintZKLightClientClientInvalidAppHash();
    error ITendermintZKLightClientClientInvalidTimestamp();

    error ITendermintZKLightClientInvalidUpdateStateMessageInvalidHeight();
    error ITendermintZKLightClientConsensusStateNotFound();
    error ITendermintZKLightClientOldConsensusExpired();

    error ITendermintZKLightClientZKProofUnexpectedStepVerifierDigest();
    error ITendermintZKLightClientZKProofUnexpectedSkipVerifierDigest();
    error ITendermintZKLightClientZKProofUnexpectedStepInput();
    error ITendermintZKLightClientZKProofUnexpectedSkipInput();
    error ITendermintZKLightClientZKProofUnexpectedOutput();

    error ITendermintZKLightClientInvalidSimpleTreeProof();

    error ITendermintZKLightClientUnsupportedProtoMessageType();

    error ITendermintZKLightClientUnsupportedProofSpec();
    error ITendermintZKLightClientTendermintSpecInvalidProof();
    error ITendermintZKLightClientIAVLSpecInvalidProof();

    error ITendermintZKLightClientInvalidInnerPrefixLength();
    error ITendermintZKLightClientInvalidInnerSuffixLength();

    error ITendermintZKLightClientInvalidIAVLOp();
    error ITendermintZKLightClientInvalidIAVLPrefix();
}
