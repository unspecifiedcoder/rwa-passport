// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISignerRegistry
/// @author Xythum Protocol
/// @notice Manages the set of authorized signers who attest to RWA state.
/// @dev MVP uses ECDSA signatures with bitmap tracking.
///      TODO(upgrade): Upgrade to BLS12-381 aggregate signatures.
interface ISignerRegistry {
    /// @notice Emitted when a new signer is registered
    /// @param signer The address of the registered signer
    /// @param index The index assigned to the signer in the signer set
    event SignerRegistered(address indexed signer, uint256 index);

    /// @notice Emitted when a signer is removed
    /// @param signer The address of the removed signer
    event SignerRemoved(address indexed signer);

    /// @notice Emitted when the signature threshold is updated
    /// @param oldThreshold The previous threshold value
    /// @param newThreshold The new threshold value
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /// @notice Register a new signer
    /// @param signer Address of the signer to register
    function registerSigner(address signer) external;

    /// @notice Remove a signer from the active set
    /// @dev First call initiates cooldown, second call (after cooldown) executes removal
    /// @param signer Address of the signer to remove
    function removeSigner(address signer) external;

    /// @notice Check if an address is an active signer
    /// @param signer Address to check
    /// @return True if the address is an active signer
    function isActiveSigner(address signer) external view returns (bool);

    /// @notice Get the full list of active signers
    /// @return Array of active signer addresses
    function getSignerSet() external view returns (address[] memory);

    /// @notice Get the current signature threshold
    /// @return Minimum number of signatures required for a valid attestation
    function getThreshold() external view returns (uint256);

    /// @notice Get the index of a signer (used for bitmap verification)
    /// @param signer Address of the signer
    /// @return Index in the signer set (0-indexed for bitmap, reverts if not a signer)
    function getSignerIndex(address signer) external view returns (uint256);

    /// @notice Update the signature threshold
    /// @param newThreshold New minimum number of required signatures
    function setThreshold(uint256 newThreshold) external;
}
