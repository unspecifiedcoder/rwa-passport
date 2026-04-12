// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IStakingModule
/// @author Xythum Protocol
/// @notice Interface for the XYT staking module with rewards and slashing
interface IStakingModule {
    /// @notice Emitted when a user stakes XYT
    event Staked(address indexed user, uint256 amount, uint256 lockDuration);

    /// @notice Emitted when a user unstakes XYT
    event Unstaked(address indexed user, uint256 amount);

    /// @notice Emitted when rewards are claimed
    event RewardsClaimed(address indexed user, uint256 amount);

    /// @notice Emitted when a staker is slashed
    event Slashed(address indexed staker, uint256 amount, bytes32 reason);

    /// @notice Emitted when the reward rate is updated
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    /// @notice Stake XYT tokens with a lock duration for boosted rewards
    function stake(uint256 amount, uint256 lockDuration) external;

    /// @notice Unstake XYT tokens after lock period
    function unstake(uint256 amount) external;

    /// @notice Claim accumulated rewards
    function claimRewards() external returns (uint256);

    /// @notice Get pending rewards for a user
    function pendingRewards(address user) external view returns (uint256);

    /// @notice Get staked balance for a user
    function stakedBalance(address user) external view returns (uint256);

    /// @notice Get total staked across all users
    function totalStaked() external view returns (uint256);

    /// @notice Slash a staker for misbehavior (governance only)
    function slash(address staker, uint256 amount, bytes32 reason) external;
}
