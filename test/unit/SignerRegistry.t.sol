// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { ISignerRegistry } from "../../src/interfaces/ISignerRegistry.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title SignerRegistryTest
/// @notice Unit tests for the SignerRegistry contract
contract SignerRegistryTest is Test {
    SignerRegistry public registry;

    address public owner = address(this);
    address public signer1 = address(0x10);
    address public signer2 = address(0x11);
    address public signer3 = address(0x12);
    address public signer4 = address(0x13);
    address public signer5 = address(0x14);
    address public nonOwner = address(0xBEEF);

    function setUp() public {
        registry = new SignerRegistry(owner, 3);

        // Register 5 signers
        registry.registerSigner(signer1);
        registry.registerSigner(signer2);
        registry.registerSigner(signer3);
        registry.registerSigner(signer4);
        registry.registerSigner(signer5);
    }

    // ─── registerSigner ──────────────────────────────────────────────

    function test_registerSigner_success() public {
        address newSigner = address(0x20);

        vm.expectEmit(true, false, false, true);
        emit ISignerRegistry.SignerRegistered(newSigner, 5);

        registry.registerSigner(newSigner);

        assertTrue(registry.isActiveSigner(newSigner));
        assertEq(registry.getSignerSet().length, 6);
        assertEq(registry.getSignerIndex(newSigner), 5); // 0-indexed
    }

    function test_registerSigner_duplicate_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(SignerRegistry.SignerAlreadyRegistered.selector, signer1)
        );
        registry.registerSigner(signer1);
    }

    function test_registerSigner_zero_address_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(SignerRegistry.ZeroAddress.selector));
        registry.registerSigner(address(0));
    }

    function test_registerSigner_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        registry.registerSigner(address(0x20));
    }

    // ─── removeSigner ────────────────────────────────────────────────

    function test_removeSigner_initiates_cooldown() public {
        registry.removeSigner(signer5);

        // Signer should still be active (cooldown just started)
        assertTrue(registry.isActiveSigner(signer5));
        assertEq(registry.removalTimestamp(signer5), block.timestamp);
    }

    function test_removeSigner_before_cooldown_reverts() public {
        // Initiate cooldown
        registry.removeSigner(signer5);

        // Try again immediately — should revert
        uint256 availableAt = block.timestamp + registry.REMOVAL_COOLDOWN();
        vm.expectRevert(
            abi.encodeWithSelector(
                SignerRegistry.RemovalCooldownNotElapsed.selector, signer5, availableAt
            )
        );
        registry.removeSigner(signer5);
    }

    function test_removeSigner_after_cooldown_succeeds() public {
        // Initiate cooldown
        registry.removeSigner(signer5);

        // Warp past cooldown
        vm.warp(block.timestamp + 7 days + 1);

        vm.expectEmit(true, false, false, false);
        emit ISignerRegistry.SignerRemoved(signer5);

        registry.removeSigner(signer5);

        assertFalse(registry.isActiveSigner(signer5));
        assertEq(registry.getSignerSet().length, 4);
    }

    function test_removeSigner_not_registered_reverts() public {
        address unknown = address(0x99);
        vm.expectRevert(
            abi.encodeWithSelector(SignerRegistry.SignerNotRegistered.selector, unknown)
        );
        registry.removeSigner(unknown);
    }

    function test_removeSigner_would_violate_threshold_reverts() public {
        // Set threshold to 5 (equal to signer count)
        registry.setThreshold(5);

        // Initiate cooldown
        registry.removeSigner(signer5);

        // Warp past cooldown
        vm.warp(block.timestamp + 7 days + 1);

        // Try to remove — would leave 4 signers with threshold 5
        vm.expectRevert(abi.encodeWithSelector(SignerRegistry.InvalidThreshold.selector, 5, 4));
        registry.removeSigner(signer5);
    }

    function test_removeSigner_swapAndPop_updates_index() public {
        // Remove signer1 (index 0 in the array)
        // After swap-and-pop, signer5 should take signer1's position
        registry.removeSigner(signer1);
        vm.warp(block.timestamp + 7 days + 1);
        registry.removeSigner(signer1);

        assertFalse(registry.isActiveSigner(signer1));

        // signer5 should now be at index 0
        assertEq(registry.getSignerIndex(signer5), 0);
        assertEq(registry.getSignerSet().length, 4);
    }

    // ─── setThreshold ────────────────────────────────────────────────

    function test_setThreshold_success() public {
        vm.expectEmit(false, false, false, true);
        emit ISignerRegistry.ThresholdUpdated(3, 4);

        registry.setThreshold(4);

        assertEq(registry.getThreshold(), 4);
    }

    function test_setThreshold_zero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(SignerRegistry.InvalidThreshold.selector, 0, 5));
        registry.setThreshold(0);
    }

    function test_setThreshold_exceeds_signer_count_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(SignerRegistry.InvalidThreshold.selector, 6, 5));
        registry.setThreshold(6);
    }

    function test_setThreshold_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        registry.setThreshold(4);
    }

    // ─── View Functions ──────────────────────────────────────────────

    function test_getSignerSet_returns_all_active() public {
        address[] memory signers = registry.getSignerSet();
        assertEq(signers.length, 5);
        assertEq(signers[0], signer1);
        assertEq(signers[1], signer2);
        assertEq(signers[2], signer3);
        assertEq(signers[3], signer4);
        assertEq(signers[4], signer5);
    }

    function test_getSignerSet_after_removal() public {
        // Remove signer3 (index 2)
        registry.removeSigner(signer3);
        vm.warp(block.timestamp + 7 days + 1);
        registry.removeSigner(signer3);

        address[] memory signers = registry.getSignerSet();
        assertEq(signers.length, 4);
        // signer5 should have been swapped into signer3's spot
        assertEq(signers[0], signer1);
        assertEq(signers[1], signer2);
        assertEq(signers[2], signer5); // swapped
        assertEq(signers[3], signer4);
    }

    function test_getSignerIndex_returns_correct_index() public {
        assertEq(registry.getSignerIndex(signer1), 0);
        assertEq(registry.getSignerIndex(signer2), 1);
        assertEq(registry.getSignerIndex(signer3), 2);
        assertEq(registry.getSignerIndex(signer4), 3);
        assertEq(registry.getSignerIndex(signer5), 4);
    }

    function test_getSignerIndex_not_registered_reverts() public {
        address unknown = address(0x99);
        vm.expectRevert(
            abi.encodeWithSelector(SignerRegistry.SignerNotRegistered.selector, unknown)
        );
        registry.getSignerIndex(unknown);
    }

    function test_getSignerIndex_after_swapAndPop() public {
        // Remove signer1, signer5 takes its place
        registry.removeSigner(signer1);
        vm.warp(block.timestamp + 7 days + 1);
        registry.removeSigner(signer1);

        assertEq(registry.getSignerIndex(signer5), 0);
        assertEq(registry.getSignerIndex(signer2), 1);
        assertEq(registry.getSignerIndex(signer3), 2);
        assertEq(registry.getSignerIndex(signer4), 3);
    }

    function test_getSignerCount() public view {
        assertEq(registry.getSignerCount(), 5);
    }

    function test_isActiveSigner() public view {
        assertTrue(registry.isActiveSigner(signer1));
        assertFalse(registry.isActiveSigner(address(0x99)));
    }
}
