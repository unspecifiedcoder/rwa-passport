// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { LiquidityMining } from "../../src/staking/LiquidityMining.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockLPToken
/// @notice Simple ERC-20 mock representing an LP token for testing
contract MockLPToken is ERC20 {
    constructor() ERC20("Mock LP", "MLP") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title LiquidityMining Unit Tests
/// @notice Tests for the Synthetix-style liquidity mining contract
contract LiquidityMiningTest is Test {
    LiquidityMining public mining;
    ProtocolToken public xyt;
    MockLPToken public lpToken;

    address public owner;
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_MINT = 100_000_000 ether;
    uint256 public constant REWARD_AMOUNT = 100_000 ether;
    uint256 public constant REWARD_DURATION = 30 days;

    function setUp() public {
        owner = address(this);

        // Deploy XYT token
        xyt = new ProtocolToken(owner, INITIAL_MINT, treasury);

        // Deploy liquidity mining
        mining = new LiquidityMining(address(xyt), owner);
        xyt.setTransferLimitExempt(address(mining), true);

        // Deploy a mock LP token
        lpToken = new MockLPToken();

        // Mint LP tokens to alice and bob
        lpToken.mint(alice, 1_000_000 ether);
        lpToken.mint(bob, 1_000_000 ether);

        // Approve mining contract
        vm.prank(alice);
        lpToken.approve(address(mining), type(uint256).max);
        vm.prank(bob);
        lpToken.approve(address(mining), type(uint256).max);
    }

    // ─── Pool Management ─────────────────────────────────────────────

    function test_addPool_assignsId() public {
        uint256 poolId = mining.addPool(address(lpToken));
        assertEq(poolId, 0);
        assertEq(mining.poolCount(), 1);

        (address token,,,, bool active) = mining.getPoolInfo(0);
        assertEq(token, address(lpToken));
        assertTrue(active);
    }

    function test_addPool_duplicateReverts() public {
        mining.addPool(address(lpToken));
        vm.expectRevert();
        mining.addPool(address(lpToken));
    }

    function test_addPool_zeroAddressReverts() public {
        vm.expectRevert(LiquidityMining.ZeroAddress.selector);
        mining.addPool(address(0));
    }

    function test_addPool_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        mining.addPool(address(lpToken));
    }

    function test_deactivatePool_blocksStaking() public {
        uint256 poolId = mining.addPool(address(lpToken));
        mining.deactivatePool(poolId);

        vm.prank(alice);
        vm.expectRevert();
        mining.stake(poolId, 1000 ether);
    }

    function test_reactivatePool_allowsStakingAgain() public {
        uint256 poolId = mining.addPool(address(lpToken));
        mining.deactivatePool(poolId);
        mining.reactivatePool(poolId);

        vm.prank(alice);
        mining.stake(poolId, 1000 ether);
        assertEq(mining.stakedBalance(poolId, alice), 1000 ether);
    }

    // ─── Staking ─────────────────────────────────────────────────────

    function test_stake_updatesBalance() public {
        uint256 poolId = mining.addPool(address(lpToken));

        vm.prank(alice);
        mining.stake(poolId, 10_000 ether);

        assertEq(mining.stakedBalance(poolId, alice), 10_000 ether);
        assertEq(lpToken.balanceOf(address(mining)), 10_000 ether);
    }

    function test_stake_zeroAmountReverts() public {
        uint256 poolId = mining.addPool(address(lpToken));
        vm.prank(alice);
        vm.expectRevert(LiquidityMining.ZeroAmount.selector);
        mining.stake(poolId, 0);
    }

    function test_stake_invalidPoolReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        mining.stake(99, 1000 ether);
    }

    // ─── Unstaking ───────────────────────────────────────────────────

    function test_unstake_returnsLP() public {
        uint256 poolId = mining.addPool(address(lpToken));
        vm.prank(alice);
        mining.stake(poolId, 10_000 ether);

        uint256 balBefore = lpToken.balanceOf(alice);
        vm.prank(alice);
        mining.unstake(poolId, 5_000 ether);

        assertEq(lpToken.balanceOf(alice), balBefore + 5_000 ether);
        assertEq(mining.stakedBalance(poolId, alice), 5_000 ether);
    }

    function test_unstake_moreThanStakedReverts() public {
        uint256 poolId = mining.addPool(address(lpToken));
        vm.prank(alice);
        mining.stake(poolId, 10_000 ether);

        vm.prank(alice);
        vm.expectRevert();
        mining.unstake(poolId, 20_000 ether);
    }

    // ─── Rewards ─────────────────────────────────────────────────────

    function _fundAndStartPeriod(uint256 poolId, uint256 amount, uint256 duration) internal {
        vm.prank(treasury);
        xyt.transfer(address(mining), amount);
        mining.notifyRewardAmount(poolId, amount, duration);
    }

    function test_rewards_singleStaker() public {
        uint256 poolId = mining.addPool(address(lpToken));

        // Alice stakes
        vm.prank(alice);
        mining.stake(poolId, 10_000 ether);

        // Start reward period
        _fundAndStartPeriod(poolId, REWARD_AMOUNT, REWARD_DURATION);

        // Advance to end of period
        vm.warp(block.timestamp + REWARD_DURATION);

        uint256 pending = mining.pendingRewards(poolId, alice);
        // Alice should get ~all rewards (single staker). Allow 0.1% tolerance for
        // integer division rounding over 30 days.
        assertApproxEqRel(pending, REWARD_AMOUNT, 0.001e18);
    }

    function test_rewards_proportional() public {
        uint256 poolId = mining.addPool(address(lpToken));

        // Alice stakes 25k, Bob stakes 75k
        vm.prank(alice);
        mining.stake(poolId, 25_000 ether);
        vm.prank(bob);
        mining.stake(poolId, 75_000 ether);

        _fundAndStartPeriod(poolId, REWARD_AMOUNT, REWARD_DURATION);

        vm.warp(block.timestamp + REWARD_DURATION);

        uint256 alicePending = mining.pendingRewards(poolId, alice);
        uint256 bobPending = mining.pendingRewards(poolId, bob);

        // Bob should get ~3x Alice's rewards (75/25 ratio)
        assertApproxEqRel(bobPending, alicePending * 3, 0.01e18);
    }

    function test_claim_transfersRewards() public {
        uint256 poolId = mining.addPool(address(lpToken));
        vm.prank(alice);
        mining.stake(poolId, 10_000 ether);

        _fundAndStartPeriod(poolId, REWARD_AMOUNT, REWARD_DURATION);
        vm.warp(block.timestamp + REWARD_DURATION);

        uint256 balBefore = xyt.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = mining.claim(poolId);

        assertGt(claimed, 0);
        assertEq(xyt.balanceOf(alice), balBefore + claimed);
        // After claim, pending should be zero
        assertEq(mining.pendingRewards(poolId, alice), 0);
    }

    function test_claim_noRewardsReturnsZero() public {
        uint256 poolId = mining.addPool(address(lpToken));
        vm.prank(alice);
        uint256 claimed = mining.claim(poolId);
        assertEq(claimed, 0);
    }

    // ─── Emergency Withdrawal ────────────────────────────────────────

    function test_emergencyWithdraw_returnsLPForfeitsRewards() public {
        uint256 poolId = mining.addPool(address(lpToken));
        vm.prank(alice);
        mining.stake(poolId, 10_000 ether);

        _fundAndStartPeriod(poolId, REWARD_AMOUNT, REWARD_DURATION);
        vm.warp(block.timestamp + REWARD_DURATION / 2);

        uint256 lpBefore = lpToken.balanceOf(alice);
        vm.prank(alice);
        mining.emergencyWithdraw(poolId);

        // LP tokens returned
        assertEq(lpToken.balanceOf(alice), lpBefore + 10_000 ether);
        // Stake cleared
        assertEq(mining.stakedBalance(poolId, alice), 0);
        // Pending rewards forfeited (0 even though we had earned some)
        assertEq(mining.pendingRewards(poolId, alice), 0);
    }

    // ─── Reward Period Management ────────────────────────────────────

    function test_notifyRewardAmount_zeroDurationReverts() public {
        uint256 poolId = mining.addPool(address(lpToken));
        vm.prank(treasury);
        xyt.transfer(address(mining), REWARD_AMOUNT);

        vm.expectRevert(LiquidityMining.InvalidDuration.selector);
        mining.notifyRewardAmount(poolId, REWARD_AMOUNT, 0);
    }

    function test_notifyRewardAmount_insufficientBalanceReverts() public {
        uint256 poolId = mining.addPool(address(lpToken));
        // Don't fund the contract
        vm.expectRevert();
        mining.notifyRewardAmount(poolId, REWARD_AMOUNT, REWARD_DURATION);
    }

    // ─── Pause ───────────────────────────────────────────────────────

    function test_pause_blocksStaking() public {
        uint256 poolId = mining.addPool(address(lpToken));
        mining.pause();

        vm.prank(alice);
        vm.expectRevert();
        mining.stake(poolId, 1000 ether);
    }

    function test_pause_allowsUnstaking() public {
        uint256 poolId = mining.addPool(address(lpToken));
        vm.prank(alice);
        mining.stake(poolId, 10_000 ether);

        mining.pause();

        // Unstake should still work (user funds must always be retrievable)
        vm.prank(alice);
        mining.unstake(poolId, 10_000 ether);
        assertEq(mining.stakedBalance(poolId, alice), 0);
    }
}
