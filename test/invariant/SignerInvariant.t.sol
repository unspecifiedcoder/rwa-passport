// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";

/// @title SignerRegistryHandler
/// @notice Fuzzing handler that wraps SignerRegistry for invariant testing
contract SignerRegistryHandler is Test {
    SignerRegistry public registry;

    // Track all addresses we've tried to register for assertions
    address[] public allRegistered;
    mapping(address => bool) public wasEverRegistered;

    // Counter for generating unique addresses
    uint256 public nextAddr = 0x1000;

    /// @notice Get total count of all registered addresses
    function allRegisteredCount() external view returns (uint256) {
        return allRegistered.length;
    }

    constructor(SignerRegistry _registry) {
        registry = _registry;
    }

    /// @notice Register a new signer (generates a unique address)
    function registerSigner(uint256 seed) external {
        address signer = address(uint160(bound(seed, 1, type(uint160).max)));

        // Skip if already registered or zero address
        if (registry.isSigner(signer) || signer == address(0)) return;

        registry.registerSigner(signer);
        allRegistered.push(signer);
        wasEverRegistered[signer] = true;
    }

    /// @notice Initiate signer removal
    function initiateRemoval(uint256 signerIdx) external {
        address[] memory signers = registry.getSignerSet();
        if (signers.length == 0) return;

        signerIdx = bound(signerIdx, 0, signers.length - 1);
        address signer = signers[signerIdx];

        // Only initiate if not already initiated
        if (registry.removalTimestamp(signer) != 0) return;

        registry.removeSigner(signer);
    }

    /// @notice Complete signer removal (after cooldown)
    function completeRemoval(uint256 signerIdx) external {
        address[] memory signers = registry.getSignerSet();
        if (signers.length == 0) return;

        signerIdx = bound(signerIdx, 0, signers.length - 1);
        address signer = signers[signerIdx];

        uint256 removalTime = registry.removalTimestamp(signer);
        if (removalTime == 0) return;

        // Warp past cooldown
        vm.warp(removalTime + registry.REMOVAL_COOLDOWN() + 1);

        // Only complete if it won't violate threshold
        if (signers.length - 1 < registry.threshold()) return;

        registry.removeSigner(signer);
    }

    /// @notice Update threshold
    function setThreshold(uint256 newThreshold) external {
        address[] memory signers = registry.getSignerSet();
        if (signers.length == 0) return;

        newThreshold = bound(newThreshold, 1, signers.length);
        registry.setThreshold(newThreshold);
    }
}

/// @title SignerInvariantTest
/// @notice Invariant tests for SignerRegistry
contract SignerInvariantTest is Test {
    SignerRegistry public registry;
    SignerRegistryHandler public handler;

    function setUp() public {
        registry = new SignerRegistry(address(this), 1);
        handler = new SignerRegistryHandler(registry);

        // Transfer ownership to handler so it can call onlyOwner functions
        registry.transferOwnership(address(handler));
        vm.prank(address(handler));
        registry.acceptOwnership();

        // Target only the handler for fuzzing
        targetContract(address(handler));
    }

    /// @notice Threshold must always be <= signer count
    function invariant_threshold_lte_signerCount() public view {
        assertLe(
            registry.threshold(),
            registry.getSignerSet().length > 0
                ? registry.getSignerSet().length
                : registry.threshold(),
            "Threshold exceeds signer count"
        );
    }

    /// @notice No duplicate signers in the signer list
    function invariant_no_duplicate_signers() public view {
        address[] memory signers = registry.getSignerSet();
        for (uint256 i = 0; i < signers.length; i++) {
            for (uint256 j = i + 1; j < signers.length; j++) {
                assertTrue(signers[i] != signers[j], "Duplicate signer found");
            }
        }
    }

    /// @notice signerIndex must be consistent with actual position in array
    function invariant_signerIndex_consistent() public view {
        address[] memory signers = registry.getSignerSet();
        for (uint256 i = 0; i < signers.length; i++) {
            // isSigner must be true
            assertTrue(registry.isSigner(signers[i]), "Active signer not marked");

            // signerIndex must match (getSignerIndex returns 0-indexed)
            assertEq(registry.getSignerIndex(signers[i]), i, "Signer index mismatch");
        }
    }

    /// @notice After removal, signer is fully cleaned up
    function invariant_removed_signer_fully_cleaned() public view {
        address[] memory currentSigners = registry.getSignerSet();

        // Check all registered addresses to find removed ones
        uint256 allCount = handler.allRegisteredCount();
        for (uint256 i = 0; i < allCount; i++) {
            address addr = handler.allRegistered(i);
            bool isCurrentSigner = false;
            for (uint256 j = 0; j < currentSigners.length; j++) {
                if (currentSigners[j] == addr) {
                    isCurrentSigner = true;
                    break;
                }
            }

            if (!isCurrentSigner && handler.wasEverRegistered(addr)) {
                // This signer was removed — verify full cleanup
                assertFalse(registry.isSigner(addr), "Removed signer still marked active");
            }
        }
    }
}
