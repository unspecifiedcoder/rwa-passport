// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title LiquidityMining
/// @author Xythum Protocol
/// @notice Synthetix-style liquidity mining contract that distributes XYT rewards
///         to users who stake LP tokens (Uniswap V4 positions, mirror tokens,
///         or any ERC-20 representing liquidity on Xythum markets).
/// @dev Supports multiple pools, each with its own reward rate. Each pool can track
///      a different LP token or directly track mirror tokens to incentivize holders.
///
///      Reward math uses the reward-per-token pattern:
///          accRewardPerToken += (rewardRate * timeElapsed * PRECISION) / totalStaked
///          pendingReward(user) = stakedAmount(user) * (accRewardPerToken - userRewardDebt) / PRECISION
///
///      Governance (the owner) controls pool creation and reward rates. Reward emissions
///      must be funded by transferring XYT to this contract before scheduling a period.
contract LiquidityMining is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ─── Custom Errors ───────────────────────────────────────────────
    error ZeroAmount();
    error ZeroAddress();
    error InvalidPool(uint256 poolId);
    error InsufficientStake(address user, uint256 requested, uint256 available);
    error PoolAlreadyExists(address lpToken);
    error InvalidDuration();
    error InsufficientRewardBalance(uint256 required, uint256 available);

    // ─── Constants ───────────────────────────────────────────────────
    uint256 public constant PRECISION = 1e18;

    // ─── Structs ─────────────────────────────────────────────────────
    struct PoolInfo {
        IERC20 lpToken; // The staked LP/mirror token
        uint256 rewardRate; // Reward tokens per second
        uint256 periodFinish; // Timestamp when current reward period ends
        uint256 lastUpdateTime; // Last time rewards were accumulated
        uint256 rewardPerTokenStored; // Accumulated reward per staked token
        uint256 totalStaked; // Total LP tokens staked in this pool
        bool active; // Whether this pool accepts new deposits
    }

    struct UserInfo {
        uint256 stakedAmount; // User's staked LP tokens
        uint256 rewardDebt; // Reward per token at last update (for this user)
        uint256 pendingReward; // Accumulated but unclaimed rewards
    }

    // ─── Immutables ──────────────────────────────────────────────────
    /// @notice The reward token (XYT)
    IERC20 public immutable rewardToken;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice All pools
    PoolInfo[] public pools;

    /// @notice User info per pool per user
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @notice LP token → pool ID (for uniqueness check)
    mapping(address => uint256) public poolIdByToken;

    /// @notice Whether a token is registered (0 index would be ambiguous otherwise)
    mapping(address => bool) public tokenRegistered;

    /// @notice Total rewards reserved across all active periods (for balance checks)
    uint256 public totalRewardsReserved;

    // ─── Events ──────────────────────────────────────────────────────
    event PoolAdded(uint256 indexed poolId, address indexed lpToken);
    event PoolDeactivated(uint256 indexed poolId);
    event PoolReactivated(uint256 indexed poolId);
    event Staked(uint256 indexed poolId, address indexed user, uint256 amount);
    event Unstaked(uint256 indexed poolId, address indexed user, uint256 amount);
    event RewardsClaimed(uint256 indexed poolId, address indexed user, uint256 amount);
    event RewardPeriodStarted(uint256 indexed poolId, uint256 rewardAmount, uint256 duration);
    event EmergencyWithdrawal(uint256 indexed poolId, address indexed user, uint256 amount);

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _rewardToken The reward token (XYT)
    /// @param _owner Contract owner (should be governance timelock)
    constructor(address _rewardToken, address _owner) Ownable(_owner) {
        if (_rewardToken == address(0)) revert ZeroAddress();
        rewardToken = IERC20(_rewardToken);
    }

    // ─── Pool Management ─────────────────────────────────────────────

    /// @notice Add a new liquidity mining pool
    /// @param lpToken The LP token to be staked
    /// @return poolId The ID of the new pool
    function addPool(address lpToken) external onlyOwner returns (uint256 poolId) {
        if (lpToken == address(0)) revert ZeroAddress();
        if (tokenRegistered[lpToken]) revert PoolAlreadyExists(lpToken);

        poolId = pools.length;
        pools.push(
            PoolInfo({
                lpToken: IERC20(lpToken),
                rewardRate: 0,
                periodFinish: 0,
                lastUpdateTime: block.timestamp,
                rewardPerTokenStored: 0,
                totalStaked: 0,
                active: true
            })
        );
        poolIdByToken[lpToken] = poolId;
        tokenRegistered[lpToken] = true;

        emit PoolAdded(poolId, lpToken);
    }

    /// @notice Deactivate a pool (stops new deposits, withdrawals still work)
    function deactivatePool(uint256 poolId) external onlyOwner {
        if (poolId >= pools.length) revert InvalidPool(poolId);
        pools[poolId].active = false;
        emit PoolDeactivated(poolId);
    }

    /// @notice Reactivate a deactivated pool
    function reactivatePool(uint256 poolId) external onlyOwner {
        if (poolId >= pools.length) revert InvalidPool(poolId);
        pools[poolId].active = true;
        emit PoolReactivated(poolId);
    }

    /// @notice Start a new reward period for a pool
    /// @dev The reward tokens must already be in this contract. If the previous period
    ///      is still active, the remaining rewards are rolled over into the new period.
    /// @param poolId The pool to reward
    /// @param rewardAmount Total rewards to distribute over the period
    /// @param duration Duration of the period in seconds
    function notifyRewardAmount(uint256 poolId, uint256 rewardAmount, uint256 duration)
        external
        onlyOwner
    {
        if (poolId >= pools.length) revert InvalidPool(poolId);
        if (duration == 0) revert InvalidDuration();
        if (rewardAmount == 0) revert ZeroAmount();

        PoolInfo storage pool = pools[poolId];
        _updatePoolReward(pool);

        uint256 newRewardRate;
        if (block.timestamp >= pool.periodFinish) {
            newRewardRate = rewardAmount / duration;
        } else {
            uint256 remaining = pool.periodFinish - block.timestamp;
            uint256 leftover = remaining * pool.rewardRate;
            newRewardRate = (rewardAmount + leftover) / duration;
        }

        // Verify we have enough reward tokens to cover the new period
        uint256 required = newRewardRate * duration;
        uint256 balance = rewardToken.balanceOf(address(this));
        if (
            balance
                < totalRewardsReserved + required - _reservedForPool(pool, newRewardRate, duration)
        ) {
            revert InsufficientRewardBalance(required, balance);
        }

        // Update reserved amount (release old period's reservation, add new one)
        if (pool.periodFinish > block.timestamp) {
            uint256 oldRemaining = (pool.periodFinish - block.timestamp) * pool.rewardRate;
            if (totalRewardsReserved >= oldRemaining) {
                totalRewardsReserved -= oldRemaining;
            } else {
                totalRewardsReserved = 0;
            }
        }
        totalRewardsReserved += newRewardRate * duration;

        pool.rewardRate = newRewardRate;
        pool.lastUpdateTime = block.timestamp;
        pool.periodFinish = block.timestamp + duration;

        emit RewardPeriodStarted(poolId, rewardAmount, duration);
    }

    // ─── Staking ─────────────────────────────────────────────────────

    /// @notice Stake LP tokens in a pool
    function stake(uint256 poolId, uint256 amount) external nonReentrant whenNotPaused {
        if (poolId >= pools.length) revert InvalidPool(poolId);
        if (amount == 0) revert ZeroAmount();

        PoolInfo storage pool = pools[poolId];
        if (!pool.active) revert InvalidPool(poolId);

        _updateUserReward(poolId, msg.sender);

        pool.lpToken.safeTransferFrom(msg.sender, address(this), amount);
        userInfo[poolId][msg.sender].stakedAmount += amount;
        pool.totalStaked += amount;

        emit Staked(poolId, msg.sender, amount);
    }

    /// @notice Unstake LP tokens from a pool
    function unstake(uint256 poolId, uint256 amount) external nonReentrant {
        if (poolId >= pools.length) revert InvalidPool(poolId);
        if (amount == 0) revert ZeroAmount();

        PoolInfo storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];

        if (amount > user.stakedAmount) {
            revert InsufficientStake(msg.sender, amount, user.stakedAmount);
        }

        _updateUserReward(poolId, msg.sender);

        user.stakedAmount -= amount;
        pool.totalStaked -= amount;

        pool.lpToken.safeTransfer(msg.sender, amount);

        emit Unstaked(poolId, msg.sender, amount);
    }

    /// @notice Claim pending rewards from a pool
    function claim(uint256 poolId) external nonReentrant returns (uint256 reward) {
        if (poolId >= pools.length) revert InvalidPool(poolId);

        _updateUserReward(poolId, msg.sender);

        UserInfo storage user = userInfo[poolId][msg.sender];
        reward = user.pendingReward;

        if (reward == 0) return 0;

        user.pendingReward = 0;
        if (totalRewardsReserved >= reward) {
            totalRewardsReserved -= reward;
        } else {
            totalRewardsReserved = 0;
        }

        rewardToken.safeTransfer(msg.sender, reward);

        emit RewardsClaimed(poolId, msg.sender, reward);
    }

    /// @notice Emergency withdraw LP tokens without claiming rewards (forfeits pending rewards)
    /// @dev Use this if rewards are somehow stuck — you get your principal back but lose rewards
    function emergencyWithdraw(uint256 poolId) external nonReentrant {
        if (poolId >= pools.length) revert InvalidPool(poolId);

        PoolInfo storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];

        uint256 amount = user.stakedAmount;
        if (amount == 0) revert ZeroAmount();

        user.stakedAmount = 0;
        user.pendingReward = 0;
        user.rewardDebt = pool.rewardPerTokenStored;
        pool.totalStaked -= amount;

        pool.lpToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdrawal(poolId, msg.sender, amount);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get the number of pools
    function poolCount() external view returns (uint256) {
        return pools.length;
    }

    /// @notice Get pending rewards for a user in a pool
    function pendingRewards(uint256 poolId, address user) external view returns (uint256) {
        if (poolId >= pools.length) return 0;
        PoolInfo storage pool = pools[poolId];
        UserInfo storage userData = userInfo[poolId][user];

        uint256 currentRewardPerToken = _rewardPerToken(pool);
        uint256 earned =
            (userData.stakedAmount * (currentRewardPerToken - userData.rewardDebt)) / PRECISION;

        return userData.pendingReward + earned;
    }

    /// @notice Get pool info (convenience wrapper)
    function getPoolInfo(uint256 poolId)
        external
        view
        returns (
            address lpToken,
            uint256 rewardRate,
            uint256 periodFinish,
            uint256 totalStaked,
            bool active
        )
    {
        if (poolId >= pools.length) revert InvalidPool(poolId);
        PoolInfo storage pool = pools[poolId];
        return (
            address(pool.lpToken), pool.rewardRate, pool.periodFinish, pool.totalStaked, pool.active
        );
    }

    /// @notice Get user staked amount in a pool
    function stakedBalance(uint256 poolId, address user) external view returns (uint256) {
        return userInfo[poolId][user].stakedAmount;
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Recover tokens accidentally sent to the contract (not LP tokens or unclaimed rewards)
    /// @dev Cannot sweep LP tokens from registered pools, cannot sweep beyond unreserved reward balance
    function recoverERC20(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();

        if (tokenRegistered[token]) revert PoolAlreadyExists(token); // reuse error
        if (token == address(rewardToken)) {
            uint256 balance = rewardToken.balanceOf(address(this));
            if (amount > balance - totalRewardsReserved) {
                revert InsufficientRewardBalance(amount, balance - totalRewardsReserved);
            }
        }

        IERC20(token).safeTransfer(to, amount);
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _updatePoolReward(PoolInfo storage pool) internal {
        pool.rewardPerTokenStored = _rewardPerToken(pool);
        pool.lastUpdateTime = _lastTimeRewardApplicable(pool);
    }

    function _updateUserReward(uint256 poolId, address user) internal {
        PoolInfo storage pool = pools[poolId];
        _updatePoolReward(pool);

        UserInfo storage userData = userInfo[poolId][user];
        uint256 earned =
            (userData.stakedAmount * (pool.rewardPerTokenStored - userData.rewardDebt)) / PRECISION;
        userData.pendingReward += earned;
        userData.rewardDebt = pool.rewardPerTokenStored;
    }

    function _rewardPerToken(PoolInfo storage pool) internal view returns (uint256) {
        if (pool.totalStaked == 0) return pool.rewardPerTokenStored;

        uint256 timeElapsed = _lastTimeRewardApplicable(pool) - pool.lastUpdateTime;
        return
            pool.rewardPerTokenStored + (timeElapsed * pool.rewardRate * PRECISION)
                / pool.totalStaked;
    }

    function _lastTimeRewardApplicable(PoolInfo storage pool) internal view returns (uint256) {
        return block.timestamp < pool.periodFinish ? block.timestamp : pool.periodFinish;
    }

    /// @notice Helper to compute how much of the current balance is reserved for a specific pool
    /// @dev Used to avoid double-counting when replacing the reward rate on an active period
    function _reservedForPool(PoolInfo storage pool, uint256, uint256)
        internal
        view
        returns (uint256)
    {
        if (pool.periodFinish <= block.timestamp) return 0;
        return (pool.periodFinish - block.timestamp) * pool.rewardRate;
    }
}
