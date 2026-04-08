// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { StakingModule } from "../../src/staking/StakingModule.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";

/// @title StakingModule Unit Tests
/// @notice Tests covering staking, unstaking, rewards, slashing, and emergency withdrawal
contract StakingModuleTest is Test {
    StakingModule public staking;
    ProtocolToken public token;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public insurance = makeAddr("insurance");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public slasher = makeAddr("slasher");

    uint256 public constant INITIAL_MINT = 100_000_000 ether;

    function setUp() public {
        vm.startPrank(owner);

        token = new ProtocolToken(owner, INITIAL_MINT, treasury);
        staking = new StakingModule(address(token), insurance, owner);

        token.setMinter(address(staking), true);
        staking.setSlasher(slasher, true);

        vm.stopPrank();

        // Fund alice and bob
        vm.startPrank(treasury);
        token.transfer(alice, 100_000 ether);
        token.transfer(bob, 100_000 ether);
        vm.stopPrank();

        // Approve staking contract
        vm.prank(alice);
        token.approve(address(staking), type(uint256).max);

        vm.prank(bob);
        token.approve(address(staking), type(uint256).max);
    }

    // ─── Staking ─────────────────────────────────────────────────────

    function test_stakeFlexible() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 0); // No lock

        assertEq(staking.stakedBalance(alice), 10_000 ether);
    }

    function test_stakeWithLock30Days() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 30 days);

        (uint256 amount, uint256 weighted,,,,) = staking.stakes(alice);
        assertEq(amount, 10_000 ether);
        // 1.5x multiplier for 30 days
        assertEq(weighted, 15_000 ether);
    }

    function test_stakeWithLock365Days() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 365 days);

        (, uint256 weighted,,,,) = staking.stakes(alice);
        // 3x multiplier for 365 days
        assertEq(weighted, 30_000 ether);
    }

    function test_stakeZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(StakingModule.ZeroAmount.selector);
        staking.stake(0, 0);
    }

    function test_stakeInvalidLockDurationReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.stake(10_000 ether, 400 days);
    }

    // ─── Unstaking ───────────────────────────────────────────────────

    function test_unstakeFlexible() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 0);

        vm.prank(alice);
        staking.unstake(5_000 ether);

        assertEq(staking.stakedBalance(alice), 5_000 ether);
        assertEq(token.balanceOf(alice), 95_000 ether);
    }

    function test_unstakeBeforeLockReverts() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 30 days);

        vm.prank(alice);
        vm.expectRevert();
        staking.unstake(5_000 ether);
    }

    function test_unstakeAfterLock() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 30 days);

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        staking.unstake(10_000 ether);

        assertEq(staking.stakedBalance(alice), 0);
        assertEq(token.balanceOf(alice), 100_000 ether);
    }

    function test_unstakeMoreThanStakedReverts() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 0);

        vm.prank(alice);
        vm.expectRevert();
        staking.unstake(20_000 ether);
    }

    // ─── Emergency Withdrawal ────────────────────────────────────────

    function test_emergencyUnstake() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 365 days);

        vm.prank(alice);
        staking.emergencyUnstake();

        // 10% penalty = 1000 ether
        assertEq(token.balanceOf(alice), 99_000 ether); // 90000 + 9000
        assertEq(token.balanceOf(insurance), 1_000 ether);
        assertEq(staking.stakedBalance(alice), 0);
    }

    // ─── Rewards ─────────────────────────────────────────────────────

    function test_rewardDistribution() public {
        // Alice stakes
        vm.prank(alice);
        staking.stake(10_000 ether, 0);

        // Owner funds rewards
        vm.startPrank(treasury);
        token.transfer(owner, 10_000 ether);
        vm.stopPrank();

        vm.startPrank(owner);
        token.approve(address(staking), 10_000 ether);
        staking.notifyRewardAmount(10_000 ether, 100 days);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + 50 days);

        // Alice should have ~50% of rewards
        uint256 pending = staking.pendingRewards(alice);
        assertGt(pending, 0);
    }

    function test_rewardProportional() public {
        // Alice stakes 10k, Bob stakes 30k
        vm.prank(alice);
        staking.stake(10_000 ether, 0);

        vm.prank(bob);
        staking.stake(30_000 ether, 0);

        // Fund rewards
        vm.startPrank(treasury);
        token.transfer(owner, 10_000 ether);
        vm.stopPrank();

        vm.startPrank(owner);
        token.approve(address(staking), 10_000 ether);
        staking.notifyRewardAmount(10_000 ether, 100 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 100 days);

        uint256 alicePending = staking.pendingRewards(alice);
        uint256 bobPending = staking.pendingRewards(bob);

        // Bob should have ~3x Alice's rewards
        assertApproxEqRel(bobPending, alicePending * 3, 0.01e18);
    }

    function test_claimRewards() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 0);

        vm.startPrank(treasury);
        token.transfer(owner, 10_000 ether);
        vm.stopPrank();

        vm.startPrank(owner);
        token.approve(address(staking), 10_000 ether);
        staking.notifyRewardAmount(10_000 ether, 100 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 100 days);

        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        staking.claimRewards();

        assertGt(token.balanceOf(alice), balanceBefore);
    }

    // ─── Slashing ────────────────────────────────────────────────────

    function test_slash() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 0);

        vm.prank(slasher);
        staking.slash(alice, 2_000 ether, keccak256("misconduct"));

        assertEq(staking.stakedBalance(alice), 8_000 ether);
        assertEq(token.balanceOf(insurance), 2_000 ether);
        assertEq(staking.totalSlashed(), 2_000 ether);
    }

    function test_slashUnauthorizedReverts() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 0);

        vm.prank(bob);
        vm.expectRevert(StakingModule.OnlySlasher.selector);
        staking.slash(alice, 2_000 ether, keccak256("misconduct"));
    }

    function test_slashExceedsStakeReverts() public {
        vm.prank(alice);
        staking.stake(10_000 ether, 0);

        vm.prank(slasher);
        vm.expectRevert();
        staking.slash(alice, 20_000 ether, keccak256("misconduct"));
    }

    // ─── Multiplier ──────────────────────────────────────────────────

    function test_multiplierValues() public view {
        assertEq(staking.getMultiplier(0), 10000); // 1x
        assertEq(staking.getMultiplier(30 days), 15000); // 1.5x
        assertEq(staking.getMultiplier(90 days), 20000); // 2x
        assertEq(staking.getMultiplier(180 days), 25000); // 2.5x
        assertEq(staking.getMultiplier(365 days), 30000); // 3x
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function test_pause() public {
        vm.prank(owner);
        staking.pause();

        vm.prank(alice);
        vm.expectRevert();
        staking.stake(10_000 ether, 0);
    }
}
