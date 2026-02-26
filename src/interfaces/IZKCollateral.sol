// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IZKCollateral
/// @author Xythum Protocol
/// @notice Interface for zero-knowledge collateral proof verification
/// @dev Implemented in Phase 5. Defined here so adapters can reference it.
interface IZKCollateral {
    /// @notice Emitted when a valid collateral proof is verified
    /// @param proofId Unique identifier for the verified proof
    /// @param asset The collateral asset address
    /// @param minimumValue The minimum value proven
    /// @param timestamp When the proof was verified
    event CollateralProofVerified(
        bytes32 indexed proofId,
        address indexed asset,
        uint256 minimumValue,
        uint256 timestamp
    );

    /// @notice Verify a zero-knowledge collateral proof
    /// @param proof The ZK proof bytes
    /// @param publicInputs Public inputs to the circuit
    /// @return proofId Unique identifier for the verified proof
    function verifyCollateralProof(
        bytes calldata proof,
        uint256[] calldata publicInputs
    ) external returns (bytes32 proofId);

    /// @notice Get the verified minimum collateral value for a proof
    /// @param proofId The proof identifier
    /// @return minValue The minimum proven collateral value
    /// @return asset The collateral asset address
    /// @return timestamp When the proof was verified
    function getCollateralValue(bytes32 proofId)
        external view returns (uint256 minValue, address asset, uint256 timestamp);
}
