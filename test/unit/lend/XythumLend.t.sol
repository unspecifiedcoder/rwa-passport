// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { XythumLend } from "../../../src/lend/XythumLend.sol";
import { MockUSDC } from "../../../src/lend/MockUSDC.sol";

/// @notice 18-decimal mock ERC-20 used as the xRWA collateral stand-in.
contract MockERC20Collat is ERC20 {
    constructor() ERC20("Mock Collateral", "mCOL") {
        _mint(msg.sender, 100_000_000 ether);
    }
}

/// @notice 18-decimal "unrelated" ERC-20 used to test rescueStuckTokens success path.
contract MockERC20Unrelated is ERC20 {
    constructor() ERC20("Unrelated", "UNR") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

/// @title XythumLendTest
/// @notice Unit tests for XythumLend — single-pair, fixed-LTV, no-interest demo market.
contract XythumLendTest is Test {
    XythumLend public lend;
    MockERC20Collat public collat;
    MockUSDC public usdc;

    address public owner;
    address public alice = makeAddr("alice");

    uint256 public constant SEED = 1_000_000 * 1e6; // 1M USDC reserves
    uint256 public constant LTV_BPS = 7000;
    uint256 public constant BPS_DENOM = 10_000;

    function setUp() public {
        owner = address(this);

        collat = new MockERC20Collat();
        usdc = new MockUSDC(owner);

        lend = new XythumLend(address(collat), address(usdc), owner);

        // Owner mints + seeds 1M USDC reserves
        usdc.mint(owner, SEED);
        usdc.approve(address(lend), SEED);
        lend.seedReserves(SEED);

        // Stage alice with collateral and USDC for repay tests
        collat.transfer(alice, 10_000 ether);
        usdc.mint(alice, 10_000 * 1e6);

        vm.startPrank(alice);
        collat.approve(address(lend), type(uint256).max);
        usdc.approve(address(lend), type(uint256).max);
        vm.stopPrank();
    }

    // ─── supply ──────────────────────────────────────────────────────

    function test_supply_increases_collateral() public {
        uint256 aliceCollatBefore = collat.balanceOf(alice);
        uint256 lendCollatBefore = collat.balanceOf(address(lend));

        vm.prank(alice);
        lend.supply(1000 ether);

        (uint256 c, uint256 d) = lend.positions(alice);
        assertEq(c, 1000 ether);
        assertEq(d, 0);
        assertEq(lend.totalCollateral(), 1000 ether);
        assertEq(collat.balanceOf(alice), aliceCollatBefore - 1000 ether);
        assertEq(collat.balanceOf(address(lend)), lendCollatBefore + 1000 ether);
    }

    function test_supply_zero_reverts() public {
        vm.prank(alice);
        vm.expectRevert(XythumLend.AmountZero.selector);
        lend.supply(0);
    }

    // ─── borrow ──────────────────────────────────────────────────────

    function test_borrow_within_ltv_succeeds() public {
        vm.startPrank(alice);
        lend.supply(1000 ether);

        uint256 reservesBefore = lend.reservesBalance();
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        lend.borrow(700 * 1e6);
        vm.stopPrank();

        (uint256 c, uint256 d) = lend.positions(alice);
        assertEq(c, 1000 ether);
        assertEq(d, 700 * 1e6);
        assertEq(lend.totalDebt(), 700 * 1e6);
        assertEq(lend.reservesBalance(), reservesBefore - 700 * 1e6);
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + 700 * 1e6);
    }

    function test_borrow_above_ltv_reverts() public {
        vm.startPrank(alice);
        lend.supply(1000 ether);
        // Borrowing 701 USDC against 1000e18 collateral.
        // collateralValueUsd6 = 1_000_000_000.
        // debtBps = 701_000_000 * 10_000 / 1_000_000_000 = 7010 > 7000 → breach.
        // (Adding +1 wei to a 700 USDC borrow does NOT breach because BPS math
        //  truncates: 700_000_001 * 10000 / 1e9 = 7000.)
        vm.expectRevert(
            abi.encodeWithSelector(XythumLend.LtvBreached.selector, 7010, LTV_BPS)
        );
        lend.borrow(701 * 1e6);
        vm.stopPrank();
    }

    function test_borrow_insufficient_reserves_reverts() public {
        // Fresh deployment with zero reserves
        XythumLend freshLend = new XythumLend(address(collat), address(usdc), owner);

        // Stage alice with collateral on the fresh market
        collat.transfer(alice, 1000 ether);
        vm.startPrank(alice);
        collat.approve(address(freshLend), type(uint256).max);
        freshLend.supply(1000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(XythumLend.InsufficientReserves.selector, 1, 0)
        );
        freshLend.borrow(1);
        vm.stopPrank();
    }

    // ─── repay ───────────────────────────────────────────────────────

    function test_repay_reduces_debt() public {
        vm.startPrank(alice);
        lend.supply(1000 ether);
        lend.borrow(700 * 1e6);

        uint256 reservesBefore = lend.reservesBalance();

        lend.repay(300 * 1e6);
        vm.stopPrank();

        (, uint256 d) = lend.positions(alice);
        assertEq(d, 400 * 1e6);
        assertEq(lend.totalDebt(), 400 * 1e6);
        assertEq(lend.reservesBalance(), reservesBefore + 300 * 1e6);
    }

    function test_repay_max_caps_at_debt() public {
        vm.startPrank(alice);
        lend.supply(1000 ether);
        lend.borrow(700 * 1e6);

        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 reservesBefore = lend.reservesBalance();

        lend.repay(type(uint256).max);
        vm.stopPrank();

        (, uint256 d) = lend.positions(alice);
        assertEq(d, 0);
        assertEq(lend.totalDebt(), 0);
        // Only 700 USDC actually transferred — alice still has rest of her balance.
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore - 700 * 1e6);
        assertEq(lend.reservesBalance(), reservesBefore + 700 * 1e6);
    }

    // ─── withdraw ────────────────────────────────────────────────────

    function test_withdraw_within_health_succeeds() public {
        // Supply 2000, borrow 700 (35% LTV), withdraw 1000 — leaves 1000 collateral
        // backing 700 debt = 70% LTV, exactly at the limit.
        vm.startPrank(alice);
        lend.supply(2000 ether);
        lend.borrow(700 * 1e6);

        lend.withdraw(1000 ether);
        vm.stopPrank();

        (uint256 c, uint256 d) = lend.positions(alice);
        assertEq(c, 1000 ether);
        assertEq(d, 700 * 1e6);
    }

    function test_withdraw_breaches_ltv_reverts() public {
        vm.startPrank(alice);
        lend.supply(1000 ether);
        lend.borrow(700 * 1e6);

        // At 70% LTV exactly, ANY material withdrawal breaks health.
        // Withdrawing 1 ether (1e18 wei) drops collateralValueUsd6 by 1e6 (1 USDC),
        // from 1_000_000_000 to 999_000_000, pushing debtBps to 7007 > 7000.
        vm.expectRevert(); // LtvBreached
        lend.withdraw(1 ether);
        vm.stopPrank();
    }

    // ─── pause ───────────────────────────────────────────────────────

    function test_pause_blocks_user_actions() public {
        // Pre-stage a position so repay/withdraw have something to act on
        vm.prank(alice);
        lend.supply(1000 ether);

        lend.pause();

        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        lend.supply(1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        lend.withdraw(1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        lend.borrow(1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        lend.repay(1);
        vm.stopPrank();
    }

    // ─── access control ──────────────────────────────────────────────

    function test_only_owner_seedReserves() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice)
        );
        lend.seedReserves(100);
    }

    // ─── rescueStuckTokens ───────────────────────────────────────────

    function test_rescue_blocks_collateral_and_debt_tokens() public {
        // Sending the protected tokens directly should NOT make them rescuable
        vm.expectRevert(XythumLend.CannotRescueMarketToken.selector);
        lend.rescueStuckTokens(IERC20(address(collat)), alice);

        vm.expectRevert(XythumLend.CannotRescueMarketToken.selector);
        lend.rescueStuckTokens(IERC20(address(usdc)), alice);

        // An unrelated token sent to the contract is rescuable.
        MockERC20Unrelated other = new MockERC20Unrelated();
        other.transfer(address(lend), 123 ether);

        uint256 aliceBefore = other.balanceOf(alice);
        lend.rescueStuckTokens(IERC20(address(other)), alice);
        assertEq(other.balanceOf(alice), aliceBefore + 123 ether);
        assertEq(other.balanceOf(address(lend)), 0);
    }

    // ─── views ───────────────────────────────────────────────────────

    function test_positionOf_returns_correct_health() public {
        // Zero-debt path → max sentinel
        vm.prank(alice);
        lend.supply(1000 ether);
        (uint256 c0, uint256 d0, uint256 h0) = lend.positionOf(alice);
        assertEq(c0, 1000 ether);
        assertEq(d0, 0);
        assertEq(h0, type(uint256).max);

        // Borrow 350 USDC (50% LTV)
        // collateralValueUsd6 = 1000e18 * 1e6 / 1e18 = 1_000_000_000 (1000e6)
        // healthBps = 1_000_000_000 * 10_000 / 350_000_000 = 28_571
        vm.prank(alice);
        lend.borrow(350 * 1e6);

        (uint256 c1, uint256 d1, uint256 h1) = lend.positionOf(alice);
        assertEq(c1, 1000 ether);
        assertEq(d1, 350 * 1e6);
        assertEq(h1, uint256(1_000_000_000) * 10_000 / uint256(350_000_000));
        assertEq(h1, 28_571);
    }

    function test_maxBorrow_after_partial_borrow() public {
        vm.startPrank(alice);
        lend.supply(1000 ether);
        // Headroom from scratch: collateralValueUsd6=1000e6, maxDebt=700e6 → maxBorrow=700e6
        assertEq(lend.maxBorrow(alice), 700 * 1e6);

        lend.borrow(200 * 1e6);
        assertEq(lend.maxBorrow(alice), 500 * 1e6);
        vm.stopPrank();
    }

    function test_maxWithdraw_with_debt() public {
        vm.startPrank(alice);
        lend.supply(1000 ether);
        // No debt → can pull everything
        assertEq(lend.maxWithdraw(alice), 1000 ether);

        lend.borrow(700 * 1e6);
        // At 70% LTV the position is exactly at the line — maxWithdraw should be 0.
        assertEq(lend.maxWithdraw(alice), 0);
        vm.stopPrank();
    }
}
