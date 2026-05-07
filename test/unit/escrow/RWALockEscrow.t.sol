// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { RWALockEscrow } from "../../../src/escrow/RWALockEscrow.sol";
import { SignerRegistry } from "../../../src/core/SignerRegistry.sol";
import { ReceiptLib } from "../../../src/libraries/ReceiptLib.sol";
import { SignatureLib } from "../../../src/libraries/SignatureLib.sol";
import { MockERC3643 } from "../../helpers/MockERC3643.sol";
import { ReceiptHelper } from "../../helpers/ReceiptHelper.sol";

/// @notice Unit tests for RWALockEscrow.lock + release
contract RWALockEscrowTest is Test {
    SignerRegistry public signerRegistry;
    RWALockEscrow public escrow;
    MockERC3643 public rwa;
    ReceiptHelper public helper;

    address public user = address(0xBEEF);
    uint256 public constant TARGET_CHAIN = 97;
    uint256 public constant ORIGIN_CHAIN = 31337; // forge default
    uint256 public constant MAX_STALENESS = 1 days;
    uint256 public constant THRESHOLD = 3;
    uint256 public constant SIGNER_COUNT = 5;

    function setUp() public {
        // 1. Spin up signer registry
        signerRegistry = new SignerRegistry(address(this), THRESHOLD);

        // 2. Generate 5 deterministic signers and register them
        helper = new ReceiptHelper();
        helper.generateSigners(SIGNER_COUNT);
        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }

        // 3. Deploy escrow with this contract as owner
        escrow = new RWALockEscrow(address(signerRegistry), MAX_STALENESS, address(this));

        // 4. Mint RWA to the user and approve the escrow
        rwa = new MockERC3643();
        rwa.transfer(user, 100_000 ether);
        vm.prank(user);
        rwa.approve(address(escrow), type(uint256).max);
    }

    function _thresholdIndices() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            ids[i] = i;
        }
        return ids;
    }

    // ─── lock ────────────────────────────────────────────────────────

    function test_lock_transfersFundsAndEmits() public {
        uint256 amt = 10_000 ether;
        uint256 escrowBefore = rwa.balanceOf(address(escrow));
        uint256 userBefore = rwa.balanceOf(user);

        vm.prank(user);
        bytes32 lockId = escrow.lock(address(rwa), amt, TARGET_CHAIN);

        assertEq(rwa.balanceOf(address(escrow)), escrowBefore + amt);
        assertEq(rwa.balanceOf(user), userBefore - amt);
        assertEq(escrow.totalLocked(address(rwa)), amt);

        (address token, address locker, uint256 amount, uint256 lockedAt, bool released) =
            escrow.lockState(lockId);
        assertEq(token, address(rwa));
        assertEq(locker, user);
        assertEq(amount, amt);
        assertEq(lockedAt, block.timestamp);
        assertFalse(released);
    }

    function test_lock_revertsOnZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(RWALockEscrow.ZeroAmount.selector);
        escrow.lock(address(rwa), 0, TARGET_CHAIN);
    }

    function test_lock_revertsOnZeroAddressToken() public {
        vm.prank(user);
        vm.expectRevert(RWALockEscrow.ZeroAddress.selector);
        escrow.lock(address(0), 1, TARGET_CHAIN);
    }

    function test_lock_revertsWhenTargetIsCurrentChain() public {
        vm.prank(user);
        vm.expectRevert(RWALockEscrow.TargetIsThisChain.selector);
        escrow.lock(address(rwa), 1, block.chainid);
    }

    function test_lock_revertsWhenPaused() public {
        escrow.pause();
        vm.prank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.lock(address(rwa), 1, TARGET_CHAIN);
    }

    function test_lock_uniqueLockIdsForRepeatedLocks() public {
        vm.startPrank(user);
        bytes32 a = escrow.lock(address(rwa), 1 ether, TARGET_CHAIN);
        bytes32 b = escrow.lock(address(rwa), 1 ether, TARGET_CHAIN);
        vm.stopPrank();
        assertTrue(a != b);
    }

    // ─── release ─────────────────────────────────────────────────────

    function _doLock(uint256 amount) internal returns (bytes32 lockId) {
        vm.prank(user);
        lockId = escrow.lock(address(rwa), amount, TARGET_CHAIN);
    }

    function _buildUnlockReceipt(bytes32 lockId, uint256 amount, address recipient)
        internal
        view
        returns (ReceiptLib.UnlockReceipt memory)
    {
        return ReceiptLib.UnlockReceipt({
            originContract: address(rwa),
            originChainId: block.chainid,
            targetChainId: TARGET_CHAIN,
            recipient: recipient,
            amount: amount,
            lockId: lockId,
            burnTxBlock: 1234,
            timestamp: block.timestamp
        });
    }

    function test_release_happyPath() public {
        uint256 amt = 5_000 ether;
        bytes32 lockId = _doLock(amt);
        uint256 userBefore = rwa.balanceOf(user);

        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(lockId, amt, user);
        (bytes memory sigs, uint256 bitmap) =
            helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), _thresholdIndices());

        escrow.release(r, sigs, bitmap);

        assertEq(rwa.balanceOf(user), userBefore + amt);
        assertEq(escrow.totalLocked(address(rwa)), 0);
        (,,,, bool released) = escrow.lockState(lockId);
        assertTrue(released);
    }

    function test_release_revertsOnDoubleRelease() public {
        bytes32 lockId = _doLock(1 ether);
        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(lockId, 1 ether, user);
        (bytes memory sigs, uint256 bitmap) =
            helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), _thresholdIndices());

        escrow.release(r, sigs, bitmap);

        // Re-sign with a fresh timestamp to dodge staleness; the LockAlreadyReleased
        // check should still fire first.
        r.timestamp = block.timestamp;
        (sigs, bitmap) = helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), _thresholdIndices());

        vm.expectRevert(abi.encodeWithSelector(RWALockEscrow.LockAlreadyReleased.selector, lockId));
        escrow.release(r, sigs, bitmap);
    }

    function test_release_revertsOnUnknownLock() public {
        bytes32 fakeLockId = keccak256("nope");
        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(fakeLockId, 1 ether, user);
        (bytes memory sigs, uint256 bitmap) =
            helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), _thresholdIndices());

        vm.expectRevert(abi.encodeWithSelector(RWALockEscrow.LockNotFound.selector, fakeLockId));
        escrow.release(r, sigs, bitmap);
    }

    function test_release_revertsOnAmountMismatch() public {
        bytes32 lockId = _doLock(10 ether);
        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(lockId, 5 ether, user); // wrong
        (bytes memory sigs, uint256 bitmap) =
            helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), _thresholdIndices());

        vm.expectRevert(
            abi.encodeWithSelector(RWALockEscrow.WrongAmount.selector, 5 ether, 10 ether)
        );
        escrow.release(r, sigs, bitmap);
    }

    function test_release_revertsOnWrongOriginChain() public {
        bytes32 lockId = _doLock(1 ether);
        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(lockId, 1 ether, user);
        r.originChainId = 999; // wrong
        (bytes memory sigs, uint256 bitmap) =
            helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), _thresholdIndices());

        vm.expectRevert(
            abi.encodeWithSelector(RWALockEscrow.WrongOriginChain.selector, 999, block.chainid)
        );
        escrow.release(r, sigs, bitmap);
    }

    function test_release_revertsOnStaleReceipt() public {
        bytes32 lockId = _doLock(1 ether);
        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(lockId, 1 ether, user);
        (bytes memory sigs, uint256 bitmap) =
            helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), _thresholdIndices());

        // Jump well past staleness
        vm.warp(r.timestamp + MAX_STALENESS + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                RWALockEscrow.UnlockReceiptStale.selector, r.timestamp, MAX_STALENESS
            )
        );
        escrow.release(r, sigs, bitmap);
    }

    function test_release_revertsOnFutureReceipt() public {
        bytes32 lockId = _doLock(1 ether);
        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(lockId, 1 ether, user);
        r.timestamp = block.timestamp + 1 hours;
        (bytes memory sigs, uint256 bitmap) =
            helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), _thresholdIndices());

        vm.expectRevert(
            abi.encodeWithSelector(RWALockEscrow.UnlockReceiptInFuture.selector, r.timestamp)
        );
        escrow.release(r, sigs, bitmap);
    }

    function test_release_revertsOnInsufficientSignatures() public {
        bytes32 lockId = _doLock(1 ether);
        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(lockId, 1 ether, user);

        // Sign with only 2 signers; threshold is 3.
        uint256[] memory only2 = new uint256[](2);
        only2[0] = 0;
        only2[1] = 1;
        (bytes memory sigs, uint256 bitmap) =
            helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), only2);

        vm.expectRevert(abi.encodeWithSelector(SignatureLib.InsufficientSignatures.selector, 2, 3));
        escrow.release(r, sigs, bitmap);
    }

    function test_release_revertsOnTamperedReceipt() public {
        bytes32 lockId = _doLock(1 ether);
        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(lockId, 1 ether, user);
        (bytes memory sigs, uint256 bitmap) =
            helper.signUnlockReceipt(r, escrow.DOMAIN_SEPARATOR(), _thresholdIndices());

        // Mutate the recipient AFTER signing — sigs no longer recover signers[0].
        r.recipient = address(0xDEAD);

        vm.expectRevert();
        escrow.release(r, sigs, bitmap);
    }

    // ─── owner controls ──────────────────────────────────────────────

    function test_pause_blocksLockAndRelease() public {
        escrow.pause();

        vm.prank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.lock(address(rwa), 1, TARGET_CHAIN);

        ReceiptLib.UnlockReceipt memory r = _buildUnlockReceipt(bytes32(0), 1, user);
        bytes memory sigs = new bytes(0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.release(r, sigs, 0);
    }

    function test_unpause_restoresLock() public {
        escrow.pause();
        escrow.unpause();
        vm.prank(user);
        bytes32 id = escrow.lock(address(rwa), 1 ether, TARGET_CHAIN);
        assertTrue(id != bytes32(0));
    }

    function test_rescueStuckTokens_cannotPullEscrowedFunds() public {
        // Lock 100 — escrow custody
        _doLock(100 ether);

        // Now also send 50 directly (e.g., a fat-fingered user) — that 50 IS rescuable.
        rwa.transfer(address(escrow), 50 ether);

        uint256 ownerBefore = rwa.balanceOf(address(this));
        escrow.rescueStuckTokens(address(rwa), address(this));

        // Owner got 50, NOT the locked 100.
        assertEq(rwa.balanceOf(address(this)), ownerBefore + 50 ether);
        assertEq(rwa.balanceOf(address(escrow)), 100 ether);
    }

    function test_rescueStuckTokens_onlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        escrow.rescueStuckTokens(address(rwa), user);
    }
}
