// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { RWALockEscrow } from "../../src/escrow/RWALockEscrow.sol";

import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { ReceiptLib } from "../../src/libraries/ReceiptLib.sol";

import { MockERC3643 } from "../helpers/MockERC3643.sol";
import { ReceiptHelper } from "../helpers/ReceiptHelper.sol";

/// @notice Full round-trip integration test:
///           lock (origin) → mintFromLock (target) → use → burnForLock (target) → release (origin)
///
/// Two SignerRegistry/AttestationRegistry pairs are deployed — one per
/// "chain" — but the same signer keys + same EIP-712 domain are used on
/// both. Domain separator differs per chain (chainId + verifyingContract)
/// so signatures cannot be replayed across chains.
///
/// We simulate two chains by:
///   - originChainId = 31337 (forge default == block.chainid)
///   - targetChainId = 99999 (a fictional chain id we pin via vm.chainId)
/// Since forge runs in a single EVM, we deploy contracts for both "chains"
/// in the same process and just switch the active chain id with vm.chainId
/// when entering target-chain or origin-chain context.
contract RoundTripTest is Test {
    // Origin (chain A) — escrow lives here
    SignerRegistry public srOrigin;
    RWALockEscrow public escrow;
    MockERC3643 public rwa;

    // Target (chain B) — factory + mirror live here
    SignerRegistry public srTarget;
    AttestationRegistry public attRegTarget; // factory needs this
    CanonicalFactory public factory;

    // Single helper holds the signer keys; both chains register the same set.
    ReceiptHelper public helper;

    address public user = makeAddr("user");
    uint256 public constant ORIGIN_CHAIN = 31337; // forge default
    uint256 public constant TARGET_CHAIN = 99999;
    uint256 public constant THRESHOLD = 3;
    uint256 public constant SIGNER_COUNT = 5;
    uint256 public constant MAX_STALENESS = 1 days;
    uint256 public constant RATE_LIMIT = 1 hours;

    // ─── setUp ───────────────────────────────────────────────────────

    function setUp() public {
        helper = new ReceiptHelper();
        helper.generateSigners(SIGNER_COUNT);

        // ─── Deploy origin-chain stack (chainId == 31337) ────────────
        // (we are at the default chain id here)
        srOrigin = new SignerRegistry(address(this), THRESHOLD);
        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            srOrigin.registerSigner(helper.getSignerAddress(i));
        }
        escrow = new RWALockEscrow(address(srOrigin), MAX_STALENESS, address(this));

        rwa = new MockERC3643();
        rwa.transfer(user, 100_000 ether);
        vm.prank(user);
        rwa.approve(address(escrow), type(uint256).max);

        // ─── Deploy target-chain stack at chainId 99999 ──────────────
        vm.chainId(TARGET_CHAIN);

        srTarget = new SignerRegistry(address(this), THRESHOLD);
        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            srTarget.registerSigner(helper.getSignerAddress(i));
        }
        attRegTarget = new AttestationRegistry(address(srTarget), MAX_STALENESS, RATE_LIMIT);
        factory = new CanonicalFactory(
            address(attRegTarget),
            address(0), // no compliance for round-trip test
            address(this), // treasury
            address(this) // owner
        );

        // ─── Snap back to origin chain for the test body ─────────────
        vm.chainId(ORIGIN_CHAIN);
    }

    // ─── helpers ─────────────────────────────────────────────────────

    function _thresholdIndices() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            ids[i] = i;
        }
        return ids;
    }

    // ─── full round-trip happy path ──────────────────────────────────

    function test_fullRoundTrip_lockMintBurnUnlock() public {
        // ─── 1. Lock 50,000 mTBILL on the origin chain ────────────────
        uint256 amount = 50_000 ether;
        uint256 userOriginBefore = rwa.balanceOf(user);

        vm.prank(user);
        bytes32 lockId = escrow.lock(address(rwa), amount, TARGET_CHAIN);

        assertEq(rwa.balanceOf(user), userOriginBefore - amount);
        assertEq(rwa.balanceOf(address(escrow)), amount);
        (,, uint256 lockedAmt,, bool released) = escrow.lockState(lockId);
        assertEq(lockedAmt, amount);
        assertFalse(released);

        // ─── 2. Switch to target chain. Signers (off-chain) sign the
        //         LockReceipt with verifyingContract = factory-on-target.
        vm.chainId(TARGET_CHAIN);

        ReceiptLib.LockReceipt memory lockReceipt = ReceiptLib.LockReceipt({
            originContract: address(rwa),
            originChainId: ORIGIN_CHAIN,
            targetChainId: TARGET_CHAIN,
            locker: user,
            amount: amount,
            lockId: lockId,
            timestamp: block.timestamp
        });

        bytes32 targetDomainSep = AttestationLib.domainSeparator(TARGET_CHAIN, address(factory));
        (bytes memory lockSigs, uint256 lockBitmap) =
            helper.signLockReceipt(lockReceipt, targetDomainSep, _thresholdIndices());

        // ─── 3. mintFromLock — auto-deploys + mints into mirror ───────
        address mirror = factory.mintFromLock(lockReceipt, lockSigs, lockBitmap);

        XythumToken token = XythumToken(mirror);
        assertEq(token.balanceOf(user), amount);
        assertEq(token.mintCap(), amount);
        assertEq(token.totalMinted(), amount);
        assertTrue(factory.mintedFromLock(lockId));

        // ─── 4. User uses xRWA in DeFi (skipped — out of scope) ───────

        // ─── 5. burnForLock on the target chain ───────────────────────
        vm.prank(user);
        token.burnForLock(amount, lockId);
        assertEq(token.balanceOf(user), 0);
        assertTrue(token.burnedForLock(lockId));

        // ─── 6-7. Unlock on origin chain (scoped to reduce stack depth)
        vm.chainId(ORIGIN_CHAIN);
        {
            ReceiptLib.UnlockReceipt memory unlockReceipt = ReceiptLib.UnlockReceipt({
                originContract: address(rwa),
                originChainId: ORIGIN_CHAIN,
                targetChainId: TARGET_CHAIN,
                recipient: user,
                amount: amount,
                lockId: lockId,
                burnTxBlock: block.number,
                timestamp: block.timestamp
            });

            bytes32 originDomainSep = AttestationLib.domainSeparator(ORIGIN_CHAIN, address(escrow));
            (bytes memory unlockSigs, uint256 unlockBitmap) =
                helper.signUnlockReceipt(unlockReceipt, originDomainSep, _thresholdIndices());

            escrow.release(unlockReceipt, unlockSigs, unlockBitmap);
        }

        assertEq(rwa.balanceOf(user), userOriginBefore);
        assertEq(rwa.balanceOf(address(escrow)), 0);
        assertEq(escrow.totalLocked(address(rwa)), 0);

        (,,,, released) = escrow.lockState(lockId);
        assertTrue(released);

        // Mirror's mintCap stays as a high-water mark even after release.
        // This is the documented design — caps never decrement.
        assertEq(token.mintCap(), amount);
        assertEq(token.totalSupply(), 0);
    }

    // ─── two parallel locks: each gets its own lockId, mirror grows ──

    function test_twoParallelLocks_singleMirrorGrowingCap() public {
        // Lock #1: 30k
        vm.prank(user);
        bytes32 id1 = escrow.lock(address(rwa), 30_000 ether, TARGET_CHAIN);

        // Lock #2: 20k — same user, same token, same target chain → DIFFERENT lockId
        vm.prank(user);
        bytes32 id2 = escrow.lock(address(rwa), 20_000 ether, TARGET_CHAIN);
        assertTrue(id1 != id2);

        vm.chainId(TARGET_CHAIN);

        bytes32 dsep = AttestationLib.domainSeparator(TARGET_CHAIN, address(factory));

        ReceiptLib.LockReceipt memory r1 = ReceiptLib.LockReceipt({
            originContract: address(rwa),
            originChainId: ORIGIN_CHAIN,
            targetChainId: TARGET_CHAIN,
            locker: user,
            amount: 30_000 ether,
            lockId: id1,
            timestamp: block.timestamp
        });
        (bytes memory s1, uint256 b1) = helper.signLockReceipt(r1, dsep, _thresholdIndices());
        address mirror = factory.mintFromLock(r1, s1, b1);

        ReceiptLib.LockReceipt memory r2 = ReceiptLib.LockReceipt({
            originContract: address(rwa),
            originChainId: ORIGIN_CHAIN,
            targetChainId: TARGET_CHAIN,
            locker: user,
            amount: 20_000 ether,
            lockId: id2,
            timestamp: block.timestamp
        });
        (bytes memory s2, uint256 b2) = helper.signLockReceipt(r2, dsep, _thresholdIndices());
        address mirror2 = factory.mintFromLock(r2, s2, b2);

        assertEq(mirror, mirror2); // same canonical mirror per corridor
        XythumToken token = XythumToken(mirror);
        assertEq(token.balanceOf(user), 50_000 ether);
        assertEq(token.mintCap(), 50_000 ether);
    }

    // ─── invariant: cannot release without burning first (signers refuse,
    //     but on-chain we test that a receipt with the wrong amount fails)
    function test_release_revertsForReceiptThatDoesntMatchLock() public {
        // Lock 10
        vm.prank(user);
        bytes32 id = escrow.lock(address(rwa), 10 ether, TARGET_CHAIN);

        // Build & sign a forged unlock receipt with wrong amount
        bytes32 dsep = AttestationLib.domainSeparator(ORIGIN_CHAIN, address(escrow));
        ReceiptLib.UnlockReceipt memory r = ReceiptLib.UnlockReceipt({
            originContract: address(rwa),
            originChainId: ORIGIN_CHAIN,
            targetChainId: TARGET_CHAIN,
            recipient: user,
            amount: 999 ether, // <-- wrong
            lockId: id,
            burnTxBlock: 1,
            timestamp: block.timestamp
        });
        (bytes memory sigs, uint256 bm) = helper.signUnlockReceipt(r, dsep, _thresholdIndices());

        vm.expectRevert(
            abi.encodeWithSelector(RWALockEscrow.WrongAmount.selector, 999 ether, 10 ether)
        );
        escrow.release(r, sigs, bm);
    }
}
