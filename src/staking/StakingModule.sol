// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IStakingModule } from "../interfaces/IStakingModule.sol";

/// @title StakingModule
/// @author Xythum Protocol
/// @notice Stake XYT tokens to earn protocol rewards and secure the network.
///         - Time-weighted staking with lock multipliers (1x-3x)
///         - Continuous reward accrual via reward-per-token mechanism
///         - Slashing for misbehaving signers/validators
///         - Emergency withdrawal with penalty
/// @dev Uses the Synthetix-style reward distribution pattern for gas efficiency.
///      Lock durations: 0 (flexible), 30d (1.5x), 90d (2x), 180d (2.5x), 365d (3x)
contract StakingModule is IStakingModule, Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ─── Custom Errors ───────────────────────────────────────────────
    error ZeroAmount();
    error LockNotExpired(address user, uint256 unlockTime);
    error InvalidLockDuration(uint256 duration);
    error InsufficientStake(address user, uint256 requested, uint256 available);
    error SlashExceedsStake(address staker, uint256 slashAmount, uint256 staked);
    error EmergencyPenaltyTooHigh();
    error OnlySlasher();
    error InvalidDuration();

    // ─── Constants ───────────────────────────────────────────────────
    uint256 public constant PRECISION = 1e18;
    uint256 public constant EMERGENCY_PENALTY_BPS = 1000; // 10% penalty for emergency withdrawal
    uint256 public constant MAX_LOCK_DURATION = 365 days;

    // ─── Structs ─────────────────────────────────────────────────────
    struct StakeInfo {
        uint256 amount; // Staked amount
        uint256 weightedAmount; // Amount * multiplier (for reward calculation)
        uint256 lockEnd; // Lock expiry timestamp
        uint256 multiplierBps; // Lock multiplier in basis points (10000 = 1x)
        uint256 rewardDebt; // Accumulated reward debt for Synthetix math
        uint256 pendingReward; // Unclaimed rewards
    }

    // ─── Immutables ──────────────────────────────────────────────────
    IERC20 public immutable stakingToken; // XYT
    IERC20 public immutable rewardToken; // XYT (same token, minted as rewards)

    // ─── Storage ─────────────────────────────────────────────────────
    mapping(address => StakeInfo) public stakes;

    /// @notice Total weighted stake across all users
    uint256 public totalWeightedStake;

    /// @notice Global accumulated reward per weighted token
    uint256 public rewardPerTokenStored;

    /// @notice Reward emission rate (tokens per second)
    uint256 public rewardRate;

    /// @notice Last time rewards were updated
    uint256 public lastUpdateTime;

    /// @notice End time for current reward period
    uint256 public periodEnd;

    /// @notice Addresses authorized to slash (governance, emergency guardian)
    mapping(address => bool) public slashers;

    /// @notice Total slashed amount (sent to insurance fund)
    uint256 public totalSlashed;

    /// @notice Insurance fund recipient for slashed tokens
    address public insuranceFund;

    // ─── Events ──────────────────────────────────────────────────────
    event EmergencyWithdrawal(address indexed user, uint256 amount, uint256 penalty);
    event RewardPeriodStarted(uint256 reward, uint256 duration);
    event InsuranceFundUpdated(address indexed fund);
    event SlasherUpdated(address indexed slasher, bool active);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(address _stakingToken, address _insuranceFund, address _owner) Ownable(_owner) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_stakingToken); // XYT rewards XYT
        insuranceFund = _insuranceFund;
    }

    // ─── Staking ─────────────────────────────────────────────────────

    /// @inheritdoc IStakingModule
    function stake(uint256 amount, uint256 lockDuration) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (lockDuration > MAX_LOCK_DURATION) revert InvalidLockDuration(lockDuration);

        _updateReward(msg.sender);

        uint256 multiplierBps = _getMultiplier(lockDuration);
        uint256 weighted = (amount * multiplierBps) / 10000;

        StakeInfo storage info = stakes[msg.sender];

        // If adding to existing position, recalculate effective multiplier
        if (info.amount > 0) {
            // Weighted average of old and new multiplier
            uint256 totalAmount = info.amount + amount;
            uint256 totalWeighted = info.weightedAmount + weighted;
            multiplierBps = (totalWeighted * 10000) / totalAmount;
            info.multiplierBps = multiplierBps;
        } else {
            info.multiplierBps = multiplierBps;
        }

        info.amount += amount;
        info.weightedAmount += weighted;

        // Update lock: take the later of existing lock or new lock
        uint256 newLockEnd = block.timestamp + lockDuration;
        if (newLockEnd > info.lockEnd) {
            info.lockEnd = newLockEnd;
        }

        totalWeightedStake += weighted;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount, lockDuration);
    }

    /// @inheritdoc IStakingModule
    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage info = stakes[msg.sender];
        if (amount == 0) revert ZeroAmount();
        if (amount > info.amount) revert InsufficientStake(msg.sender, amount, info.amount);
        if (block.timestamp < info.lockEnd) revert LockNotExpired(msg.sender, info.lockEnd);

        _updateReward(msg.sender);

        uint256 weightedToRemove = (amount * info.multiplierBps) / 10000;
        info.amount -= amount;
        info.weightedAmount -= weightedToRemove;
        totalWeightedStake -= weightedToRemove;

        if (info.amount == 0) {
            delete stakes[msg.sender];
        }

        stakingToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /// @notice Emergency unstake before lock expiry (incurs penalty)
    function emergencyUnstake() external nonReentrant {
        StakeInfo storage info = stakes[msg.sender];
        if (info.amount == 0) revert ZeroAmount();

        _updateReward(msg.sender);

        uint256 amount = info.amount;
        uint256 penalty = (amount * EMERGENCY_PENALTY_BPS) / 10000;
        uint256 payout = amount - penalty;

        totalWeightedStake -= info.weightedAmount;
        delete stakes[msg.sender];

        // Penalty goes to insurance fund
        if (penalty > 0 && insuranceFund != address(0)) {
            stakingToken.safeTransfer(insuranceFund, penalty);
        }

        stakingToken.safeTransfer(msg.sender, payout);
        emit EmergencyWithdrawal(msg.sender, amount, penalty);
    }

    // ─── Rewards ─────────────────────────────────────────────────────

    /// @inheritdoc IStakingModule
    function claimRewards() external nonReentrant returns (uint256) {
        _updateReward(msg.sender);

        uint256 reward = stakes[msg.sender].pendingReward;
        if (reward == 0) revert ZeroAmount();

        stakes[msg.sender].pendingReward = 0;
        rewardToken.safeTransfer(msg.sender, reward);

        emit RewardsClaimed(msg.sender, reward);
        return reward;
    }

    /// @notice Start a new reward distribution period
    /// @param rewardAmount Total rewards to distribute over the period
    /// @param duration Duration of the reward period in seconds
    function notifyRewardAmount(uint256 rewardAmount, uint256 duration) external onlyOwner {
        if (duration == 0) revert InvalidDuration();
        _updateReward(address(0));

        if (block.timestamp >= periodEnd) {
            rewardRate = rewardAmount / duration;
        } else {
            uint256 remaining = periodEnd - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (rewardAmount + leftover) / duration;
        }

        lastUpdateTime = block.timestamp;
        periodEnd = block.timestamp + duration;

        // Transfer rewards into the contract
        rewardToken.safeTransferFrom(msg.sender, address(this), rewardAmount);
        emit RewardPeriodStarted(rewardAmount, duration);
    }

    // ─── Slashing ────────────────────────────────────────────────────

    /// @inheritdoc IStakingModule
    function slash(address staker, uint256 amount, bytes32 reason) external {
        if (!slashers[msg.sender]) revert OnlySlasher();

        StakeInfo storage info = stakes[staker];
        if (amount > info.amount) revert SlashExceedsStake(staker, amount, info.amount);

        _updateReward(staker);

        uint256 weightedToRemove = (amount * info.multiplierBps) / 10000;
        info.amount -= amount;
        info.weightedAmount -= weightedToRemove;
        totalWeightedStake -= weightedToRemove;
        totalSlashed += amount;

        if (info.amount == 0) {
            delete stakes[staker];
        }

        // Slashed tokens go to insurance fund
        if (insuranceFund != address(0)) {
            stakingToken.safeTransfer(insuranceFund, amount);
        }

        emit Slashed(staker, amount, reason);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @inheritdoc IStakingModule
    function pendingRewards(address user) external view returns (uint256) {
        StakeInfo storage info = stakes[user];
        uint256 rpt = _rewardPerToken();
        uint256 earned = (info.weightedAmount * (rpt - info.rewardDebt)) / PRECISION;
        return info.pendingReward + earned;
    }

    /// @inheritdoc IStakingModule
    function stakedBalance(address user) external view returns (uint256) {
        return stakes[user].amount;
    }

    /// @inheritdoc IStakingModule
    function totalStaked() external view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }

    /// @notice Get the lock multiplier for a duration
    function getMultiplier(uint256 lockDuration) external pure returns (uint256) {
        return _getMultiplier(lockDuration);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function setSlasher(address slasher, bool active) external onlyOwner {
        slashers[slasher] = active;
        emit SlasherUpdated(slasher, active);
    }

    function setInsuranceFund(address fund) external onlyOwner {
        insuranceFund = fund;
        emit InsuranceFundUpdated(fund);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _updateReward(address user) internal {
        rewardPerTokenStored = _rewardPerToken();
        lastUpdateTime = _lastTimeRewardApplicable();

        if (user != address(0)) {
            StakeInfo storage info = stakes[user];
            info.pendingReward +=
                (info.weightedAmount * (rewardPerTokenStored - info.rewardDebt)) / PRECISION;
            info.rewardDebt = rewardPerTokenStored;
        }
    }

    function _rewardPerToken() internal view returns (uint256) {
        if (totalWeightedStake == 0) return rewardPerTokenStored;

        uint256 timeElapsed = _lastTimeRewardApplicable() - lastUpdateTime;
        return rewardPerTokenStored + (timeElapsed * rewardRate * PRECISION) / totalWeightedStake;
    }

    function _lastTimeRewardApplicable() internal view returns (uint256) {
        return block.timestamp < periodEnd ? block.timestamp : periodEnd;
    }

    /// @notice Get multiplier in basis points based on lock duration
    /// @dev 0 = 10000 (1x), 30d = 15000 (1.5x), 90d = 20000 (2x),
    ///      180d = 25000 (2.5x), 365d = 30000 (3x)
    function _getMultiplier(uint256 lockDuration) internal pure returns (uint256) {
        if (lockDuration >= 365 days) return 30000;
        if (lockDuration >= 180 days) return 25000;
        if (lockDuration >= 90 days) return 20000;
        if (lockDuration >= 30 days) return 15000;
        return 10000;
    }
}
