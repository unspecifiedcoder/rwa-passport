// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGroth16Verifier} from "../../src/zk/CollateralVerifier.sol";

/// @title MockGroth16Verifier
/// @notice Mock Groth16 verifier for testing when circom/snarkjs are unavailable.
///         Accepts any proof where public inputs are well-formed.
/// @dev Replace with real generated verifier when circom tooling is set up.
///      TODO(upgrade): Replace with real Groth16 verifier from snarkjs export
contract MockGroth16Verifier is IGroth16Verifier {
    /// @notice If true, all proofs pass. If false, all proofs fail.
    bool public shouldAccept;

    constructor() {
        shouldAccept = true;
    }

    /// @notice Toggle mock verification behavior
    function setShouldAccept(bool _accept) external {
        shouldAccept = _accept;
    }

    /// @inheritdoc IGroth16Verifier
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[4] calldata
    ) external view override returns (bool) {
        return shouldAccept;
    }
}
