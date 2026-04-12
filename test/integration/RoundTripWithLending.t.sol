// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { RWALockEscrow } from "../../src/escrow/RWALockEscrow.sol";

import { XythumLend } from "../../src/lend/XythumLend.sol";
import { MockUSDC } from "../../src/lend/MockUSDC.sol";

import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { ReceiptLib } from "../../src/libraries/ReceiptLib.sol";

import { MockERC3643 } from "../helpers/MockERC3643.sol";
import { ReceiptHelper } from "../helpers/ReceiptHelper.sol";

/// @notice End-to-end round-trip with the XythumLend market sandwiched in the middle.
///
///   lock (origin / Monad)
///     → mintFromLock (target / Fuji)
///     → supply + borrow on XythumLend (Fuji)
///     → repay + withdraw on XythumLend (Fuji)
///     → burnForLock (Fuji)
///     → release (Monad)
///
/// The pattern mirrors `test/integration/RoundTrip.t.sol` — both "chains"
/// are deployed in a single forge process and we toggle `block.chainid`
/// with `vm.chainId` to keep EIP-712 domain separators distinct.
contract RoundTripWithLendingTest is Test {
    // Origin (chain A — simulated Monad testnet)
    SignerRegistry public srOrigin;
    RWALockEscrow public escrow;
    MockERC3643 public rwa;

    // Target (chain B — simulated Avalanche Fuji)
    SignerRegistry public srTarget;
    AttestationRegistry public attRegTarget;
    CanonicalFactory public factory;
    MockUSDC public usdc;
    XythumLend public lend; // deployed lazily after mintFromLock so collateralToken = mirror

    ReceiptHelper public helper;

    address public alice = makeAddr("alice");
    uint256 public constant ORIGIN_CHAIN = 10143; // Monad testnet
    uint256 public constant TARGET_CHAIN = 43113; // Fuji
    uint256 public constant THRESHOLD = 3;
    uint256 public constant SIGNER_COUNT = 5;
    uint256 public constant MAX_STALENESS = 1 days;
    uint256 public constant RATE_LIMIT = 1 hours;

    uint256 public constant SUPPLY_AMOUNT = 100_000 ether; // 100k xRWA (18-dec)
    uint256 public constant BORROW_AMOUNT = 70_000 * 1e6; // 70k USDC (6-dec)
    uint256 public constant RESERVES_AMOUNT = 1_000_000 * 1e6; // 1M USDC reserves
    uint256 public constant ALICE_USDC_FAUCET = 100_000 * 1e6; // pre-loaded for repay

    function setUp() public {
        helper = new ReceiptHelper();
        helper.generateSigners(SIGNER_COUNT);

        // ─── Deploy origin-chain stack at chainId ORIGIN_CHAIN (Monad) ───
        vm.chainId(ORIGIN_CHAIN);
        srOrigin = new SignerRegistry(address(this), THRESHOLD);
        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            srOrigin.registerSigner(helper.getSignerAddress(i));
        }
        escrow = new RWALockEscrow(address(srOrigin), MAX_STALENESS, address(this));

        rwa = new MockERC3643();
        rwa.transfer(alice, 100_000 ether);
        vm.prank(alice);
        rwa.approve(address(escrow), type(uint256).max);

        // ─── Deploy target-chain stack at chainId TARGET_CHAIN (Fuji) ────
        vm.chainId(TARGET_CHAIN);
        srTarget = new SignerRegistry(address(this), THRESHOLD);
        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            srTarget.registerSigner(helper.getSignerAddress(i));
        }
        attRegTarget =
            new AttestationRegistry(address(srTarget), MAX_STALENESS, RATE_LIMIT);
        factory = new CanonicalFactory(
            address(attRegTarget),
            address(0), // no compliance for round-trip
            address(this), // treasury
            address(this) // owner
        );

        // MockUSDC lives on Fuji; XythumLend is deployed AFTER mintFromLock.
        usdc = new MockUSDC(address(this));

        // ─── Snap back to origin for the test body ───────────────────────
        vm.chainId(ORIGIN_CHAIN);
    }

    function _thresholdIndices() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) ids[i] = i;
        return ids;
    }

    // ─── round-trip with lending ─────────────────────────────────────

    function test_roundTrip_withLendingStep() public {
        uint256 startingRwa = rwa.balanceOf(alice);
        assertEq(startingRwa, 100_000 ether);

        // ─── 1. Lock 100k mTBILL on origin ────────────────────────────
        vm.prank(alice);
        bytes32 lockId = escrow.lock(address(rwa), 100_000 ether, TARGET_CHAIN);

        assertEq(rwa.balanceOf(alice), 0);
        assertEq(rwa.balanceOf(address(escrow)), 100_000 ether);

        // ─── 2. Cross to target chain. Sign LockReceipt with 3 keys ───
        vm.chainId(TARGET_CHAIN);

        ReceiptLib.LockReceipt memory lockReceipt = ReceiptLib.LockReceipt({
            originContract: address(rwa),
            originChainId: ORIGIN_CHAIN,
            targetChainId: TARGET_CHAIN,
            locker: alice,
            amount: 100_000 ether,
            lockId: lockId,
            timestamp: block.timestamp
        });
        bytes32 targetDsep = AttestationLib.domainSeparator(TARGET_CHAIN, address(factory));
        (bytes memory lockSigs, uint256 lockBitmap) =
            helper.signLockReceipt(lockReceipt, targetDsep, _thresholdIndices());

        // ─── 3. mintFromLock — auto-deploys mirror, mints to alice ────
        address mirror = factory.mintFromLock(lockReceipt, lockSigs, lockBitmap);
        XythumToken xrwa = XythumToken(mirror);
        assertEq(xrwa.balanceOf(alice), 100_000 ether);

        // ─── 4. Now that the mirror exists, deploy XythumLend pointing at it.
        //         Owner seeds 1M USDC; alice gets 100k from faucet equivalent (mint).
        lend = new XythumLend(address(xrwa), address(usdc), address(this));
        usdc.mint(address(this), RESERVES_AMOUNT);
        usdc.approve(address(lend), RESERVES_AMOUNT);
        lend.seedReserves(RESERVES_AMOUNT);

        usdc.mint(alice, ALICE_USDC_FAUCET);
        uint256 aliceUsdcStart = usdc.balanceOf(alice);
        assertEq(aliceUsdcStart, ALICE_USDC_FAUCET);

        // ─── 5. Alice supplies 100k xRWA, borrows 70k USDC ────────────
        vm.startPrank(alice);
        xrwa.approve(address(lend), type(uint256).max);
        usdc.approve(address(lend), type(uint256).max);

        lend.supply(SUPPLY_AMOUNT);
        lend.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        {
            (uint256 c, uint256 d) = lend.positions(alice);
            assertEq(c, SUPPLY_AMOUNT);
            assertEq(d, BORROW_AMOUNT);
        }
        assertEq(xrwa.balanceOf(alice), 0); // collateral all in market
        assertEq(usdc.balanceOf(alice), aliceUsdcStart + BORROW_AMOUNT);
        assertEq(lend.reservesBalance(), RESERVES_AMOUNT - BORROW_AMOUNT);

        // ─── 6. Alice repays 70k USDC, withdraws 100k xRWA ────────────
        vm.startPrank(alice);
        lend.repay(BORROW_AMOUNT);
        lend.withdraw(SUPPLY_AMOUNT);
        vm.stopPrank();

        {
            (uint256 c, uint256 d) = lend.positions(alice);
            assertEq(c, 0);
            assertEq(d, 0);
        }
        assertEq(xrwa.balanceOf(alice), 100_000 ether);
        assertEq(usdc.balanceOf(alice), aliceUsdcStart); // borrow flow nets to zero
        assertEq(lend.reservesBalance(), RESERVES_AMOUNT); // fully restored

        // ─── 7. burnForLock ───────────────────────────────────────────
        vm.prank(alice);
        xrwa.burnForLock(100_000 ether, lockId);
        assertEq(xrwa.balanceOf(alice), 0);
        assertTrue(xrwa.burnedForLock(lockId));

        // ─── 8. Cross back to origin. Sign UnlockReceipt ──────────────
        vm.chainId(ORIGIN_CHAIN);

        ReceiptLib.UnlockReceipt memory unlockReceipt = ReceiptLib.UnlockReceipt({
            originContract: address(rwa),
            originChainId: ORIGIN_CHAIN,
            targetChainId: TARGET_CHAIN,
            recipient: alice,
            amount: 100_000 ether,
            lockId: lockId,
            burnTxBlock: block.number,
            timestamp: block.timestamp
        });
        bytes32 originDsep = AttestationLib.domainSeparator(ORIGIN_CHAIN, address(escrow));
        (bytes memory unlockSigs, uint256 unlockBitmap) = helper.signUnlockReceipt(
            unlockReceipt, originDsep, _thresholdIndices()
        );

        // ─── 9. release — alice gets her 100k mTBILL back ─────────────
        escrow.release(unlockReceipt, unlockSigs, unlockBitmap);

        // ─── 10. Final invariants ─────────────────────────────────────
        assertEq(rwa.balanceOf(alice), startingRwa, "mTBILL fully returned");
        assertEq(rwa.balanceOf(address(escrow)), 0);
        assertEq(escrow.totalLocked(address(rwa)), 0);
        assertEq(xrwa.balanceOf(alice), 0, "xRWA fully burned");
        assertEq(xrwa.totalSupply(), 0);

        // Lending invariants
        assertEq(usdc.balanceOf(alice), aliceUsdcStart, "USDC nets to faucet baseline");
        assertEq(lend.reservesBalance(), RESERVES_AMOUNT, "reserves restored to 1M");
        assertEq(lend.totalCollateral(), 0);
        assertEq(lend.totalDebt(), 0);
    }
}
