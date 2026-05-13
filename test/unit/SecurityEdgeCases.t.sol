// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";
import { StakingModule } from "../../src/staking/StakingModule.sol";
import { FeeRouter } from "../../src/finance/FeeRouter.sol";

/// @title SecurityEdgeCases
/// @notice Arithmetic overflow, fee rounding, and vesting boundary tests
contract SecurityEdgeCasesTest is Test {
    ProtocolToken public token;
    StakingModule public staking;
    FeeRouter public feeRouter;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public insurance = makeAddr("insurance");
    address public alice = makeAddr("alice");

    uint256 public constant INITIAL_MINT = 100_000_000 ether;

    function setUp() public {
        vm.warp(100_000);
        vm.startPrank(owner);
        token = new ProtocolToken(owner, INITIAL_MINT, treasury);
        staking = new StakingModule(address(token), insurance, owner);
        token.setMinter(address(staking), true);
        token.setTransferLimitExempt(address(staking), true);

        feeRouter = new FeeRouter(
            treasury, address(staking), insurance, address(token), owner
        );
        token.setTransferLimitExempt(address(feeRouter), true);
        vm.stopPrank();

        vm.prank(treasury);
        token.transfer(alice, 1_000_000 ether);
        vm.prank(alice);
        token.approve(address(staking), type(uint256).max);
    }

    // ─── Fee split must total exactly 10000 BPS ─────────────────────

    function test_feeSplit_rejectsOver10000BPS() public {
        vm.prank(owner);
        vm.expectRevert();
        feeRouter.setFeeSplit(5000, 3000, 2000, 1001);
    }

    function test_feeSplit_rejectsUnder10000BPS() public {
        vm.prank(owner);
        vm.expectRevert();
        feeRouter.setFeeSplit(5000, 2000, 1000, 1000);
    }

    // ─── Vesting with cliff == vestingEnd (instant vest) ────────────

    function test_vesting_cliffEqualsEnd_instantVest() public {
        vm.prank(owner);
        token.createVestingSchedule(alice, 10_000 ether, 90 days, 90 days, true);

        // Before cliff: nothing releasable
        assertEq(token.getReleasableAmount(alice), 0);

        // At cliff == vestingEnd: everything releasable
        vm.warp(block.timestamp + 90 days);
        assertEq(token.getReleasableAmount(alice), 10_000 ether);
    }

    // ─── Staking reward with zero duration reverts ──────────────────

    function test_staking_notifyRewardZeroDurationReverts() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 0);

        vm.startPrank(treasury);
        token.transfer(owner, 10_000 ether);
        vm.stopPrank();

        vm.startPrank(owner);
        token.approve(address(staking), 10_000 ether);
        vm.expectRevert();
        staking.notifyRewardAmount(10_000 ether, 0);
        vm.stopPrank();
    }

    // ─── Max supply enforcement ─────────────────────────────────────

    function test_mintBeyondMaxSupplyReverts() public {
        vm.prank(owner);
        token.setMinter(owner, true);

        uint256 remaining = token.maxSupply() - token.totalSupply();

        vm.prank(owner);
        vm.expectRevert();
        token.mint(alice, remaining + 1);
    }

    // ─── Transfer limit boundary ────────────────────────────────────

    function test_transferLimit_exactBoundaryPasses() public {
        vm.prank(owner);
        token.setTransferLimit(1000 ether);

        vm.prank(alice);
        token.transfer(makeAddr("bob"), 1000 ether);
    }

    function test_transferLimit_onOverBoundaryReverts() public {
        vm.prank(owner);
        token.setTransferLimit(1000 ether);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(makeAddr("bob"), 1001 ether);
    }
}
