// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ISignerRegistry } from "../interfaces/ISignerRegistry.sol";

/// @title SignerRegistry
/// @author Xythum Protocol
/// @notice Manages the set of authorized signers who attest to RWA state.
///         Owner-managed initially (Phase 1-4), permissionless via restaking in Phase 5.
/// @dev Uses ECDSA multi-sig with bitmap tracking for MVP.
///      TODO(upgrade): Replace ECDSA multi-sig with BLS12-381 aggregation
contract SignerRegistry is ISignerRegistry, Ownable2Step {
    // ─── Custom Errors ───────────────────────────────────────────────
    error SignerAlreadyRegistered(address signer);
    error SignerNotRegistered(address signer);
    error InvalidThreshold(uint256 threshold, uint256 signerCount);
    error RemovalCooldownNotElapsed(address signer, uint256 availableAt);
    error ZeroAddress();

    // ─── Constants ───────────────────────────────────────────────────
    /// @notice Cooldown period before a signer can actually be removed (prevents flash attacks)
    uint256 public constant REMOVAL_COOLDOWN = 7 days;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Whether an address is an active signer
    mapping(address => bool) public isSigner;

    /// @notice 1-indexed position of a signer in signerList (0 = not a signer)
    mapping(address => uint256) public signerIndex;

    /// @notice Enumerable set of active signers
    address[] public signerList;

    /// @notice Minimum number of signatures required for valid attestation
    uint256 public threshold;

    /// @notice Timestamp when removal was initiated for a signer (0 = not initiated)
    mapping(address => uint256) public removalTimestamp;

    // ─── Constructor ─────────────────────────────────────────────────
    /// @notice Initialize the signer registry
    /// @param _owner Address that will own this contract
    /// @param _threshold Initial signature threshold
    constructor(address _owner, uint256 _threshold) Ownable(_owner) {
        if (_threshold == 0) revert InvalidThreshold(_threshold, 0);
        threshold = _threshold;
    }

    // ─── External Functions ──────────────────────────────────────────

    /// @inheritdoc ISignerRegistry
    function registerSigner(address signer) external onlyOwner {
        if (signer == address(0)) revert ZeroAddress();
        if (isSigner[signer]) revert SignerAlreadyRegistered(signer);

        signerList.push(signer);
        signerIndex[signer] = signerList.length; // 1-indexed
        isSigner[signer] = true;

        emit SignerRegistered(signer, signerList.length - 1);
    }

    /// @inheritdoc ISignerRegistry
    function removeSigner(address signer) external onlyOwner {
        if (!isSigner[signer]) revert SignerNotRegistered(signer);

        // First call: initiate cooldown
        if (removalTimestamp[signer] == 0) {
            removalTimestamp[signer] = block.timestamp;
            return;
        }

        // Second call: check cooldown elapsed
        uint256 availableAt = removalTimestamp[signer] + REMOVAL_COOLDOWN;
        if (block.timestamp < availableAt) {
            revert RemovalCooldownNotElapsed(signer, availableAt);
        }

        // Validate that removing won't break threshold
        uint256 newCount = signerList.length - 1;
        if (newCount < threshold) {
            revert InvalidThreshold(threshold, newCount);
        }

        // Swap-and-pop removal
        uint256 indexToRemove = signerIndex[signer] - 1; // Convert to 0-indexed
        uint256 lastIndex = signerList.length - 1;

        if (indexToRemove != lastIndex) {
            address lastSigner = signerList[lastIndex];
            signerList[indexToRemove] = lastSigner;
            signerIndex[lastSigner] = indexToRemove + 1; // Back to 1-indexed
        }

        signerList.pop();
        delete isSigner[signer];
        delete signerIndex[signer];
        delete removalTimestamp[signer];

        emit SignerRemoved(signer);
    }

    /// @inheritdoc ISignerRegistry
    function setThreshold(uint256 _threshold) external onlyOwner {
        if (_threshold == 0 || _threshold > signerList.length) {
            revert InvalidThreshold(_threshold, signerList.length);
        }

        uint256 oldThreshold = threshold;
        threshold = _threshold;

        emit ThresholdUpdated(oldThreshold, _threshold);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @inheritdoc ISignerRegistry
    function isActiveSigner(address signer) external view returns (bool) {
        return isSigner[signer];
    }

    /// @inheritdoc ISignerRegistry
    function getSignerSet() external view returns (address[] memory) {
        return signerList;
    }

    /// @inheritdoc ISignerRegistry
    function getThreshold() external view returns (uint256) {
        return threshold;
    }

    /// @inheritdoc ISignerRegistry
    function getSignerIndex(address signer) external view returns (uint256) {
        if (signerIndex[signer] == 0) revert SignerNotRegistered(signer);
        return signerIndex[signer] - 1; // Convert to 0-indexed for bitmap use
    }

    /// @notice Get the number of active signers
    /// @return The count of active signers
    function getSignerCount() external view returns (uint256) {
        return signerList.length;
    }
}
