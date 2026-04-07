// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { FeeRouter } from "../../src/finance/FeeRouter.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";

/// @title FeeRouter Unit Tests
contract FeeRouterTest is Test {
    FeeRouter public router;
    ProtocolToken public token;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public stakingPool = makeAddr("stakingPool");
    address public insurance = makeAddr("insurance");
    address public collector = makeAddr("collector");
    address public payer = makeAddr("payer");

    uint256 public constant INITIAL_MINT = 100_000_000 ether;

    function setUp() public {
        vm.startPrank(owner);

        token = new ProtocolToken(owner, INITIAL_MINT, treasury);
        router = new FeeRouter(treasury, stakingPool, insurance, address(token), owner);
        router.setFeeCollector(collector, true);

        vm.stopPrank();

        // Fund payer
        vm.prank(treasury);
        token.transfer(payer, 100_000 ether);

        vm.prank(payer);
        token.approve(address(router), type(uint256).max);
    }

    // ─── Fee Collection ──────────────────────────────────────────────

    function test_collectFee() public {
        vm.prank(collector);
        router.collectFee(address(token), 1000 ether, payer);

        assertEq(router.pendingFees(address(token)), 1000 ether);
        assertEq(router.totalFeesCollected(address(token)), 1000 ether);
    }

    function test_unauthorizedCollectorReverts() public {
        vm.prank(payer);
        vm.expectRevert(FeeRouter.OnlyCollector.selector);
        router.collectFee(address(token), 1000 ether, payer);
    }

    function test_collectZeroReverts() public {
        vm.prank(collector);
        vm.expectRevert(FeeRouter.ZeroAmount.selector);
        router.collectFee(address(token), 0, payer);
    }

    // ─── Fee Distribution ────────────────────────────────────────────

    function test_distributeFees() public {
        vm.prank(collector);
        router.collectFee(address(token), 10_000 ether, payer);

        router.distributeFees(address(token));

        // Default split: 40% treasury, 30% staking, 20% insurance, 10% burn
        assertEq(token.balanceOf(treasury), INITIAL_MINT - 100_000 ether + 4_000 ether);
        assertEq(token.balanceOf(stakingPool), 3_000 ether);
        assertEq(token.balanceOf(insurance), 2_000 ether);
        // 10% burn goes to 0xdead
        assertEq(token.balanceOf(address(0xdead)), 1_000 ether);

        assertEq(router.pendingFees(address(token)), 0);
        assertEq(router.totalFeesDistributed(address(token)), 10_000 ether);
    }

    function test_distributeZeroReverts() public {
        vm.expectRevert(FeeRouter.ZeroAmount.selector);
        router.distributeFees(address(token));
    }

    // ─── Fee Split Configuration ─────────────────────────────────────

    function test_setFeeSplit() public {
        vm.prank(owner);
        router.setFeeSplit(5000, 2000, 2000, 1000);

        FeeRouter.FeeSplit memory split = router.getFeeSplit();
        assertEq(split.treasuryBps, 5000);
        assertEq(split.stakingBps, 2000);
        assertEq(split.insuranceBps, 2000);
        assertEq(split.burnBps, 1000);
    }

    function test_invalidFeeSplitReverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(FeeRouter.InvalidFeeSplit.selector, 9000));
        router.setFeeSplit(5000, 2000, 1000, 1000);
    }

    function test_customFeeSplitDistribution() public {
        // 80% treasury, 10% staking, 5% insurance, 5% burn
        vm.prank(owner);
        router.setFeeSplit(8000, 1000, 500, 500);

        vm.prank(collector);
        router.collectFee(address(token), 10_000 ether, payer);

        router.distributeFees(address(token));

        assertEq(token.balanceOf(stakingPool), 1_000 ether);
        assertEq(token.balanceOf(insurance), 500 ether);
    }

    // ─── ETH Fees ────────────────────────────────────────────────────

    function test_collectETHFee() public {
        vm.deal(collector, 10 ether);

        vm.prank(collector);
        router.collectETHFee{ value: 1 ether }();

        assertEq(router.pendingFees(address(0)), 1 ether);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function test_setCollector() public {
        address newCollector = makeAddr("newCollector");

        vm.prank(owner);
        router.setFeeCollector(newCollector, true);

        assertTrue(router.feeCollectors(newCollector));
    }

    function test_onlyOwnerCanSetFeeSplit() public {
        vm.prank(payer);
        vm.expectRevert();
        router.setFeeSplit(5000, 2000, 2000, 1000);
    }
}
