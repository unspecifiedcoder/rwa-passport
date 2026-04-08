// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFeeRouter
/// @author Xythum Protocol
/// @notice Interface for dynamic fee collection and distribution
interface IFeeRouter {
    /// @notice Fee distribution split configuration
    struct FeeSplit {
        uint256 treasuryBps; // Basis points to protocol treasury
        uint256 stakingBps; // Basis points to staking rewards
        uint256 insuranceBps; // Basis points to insurance fund
        uint256 burnBps; // Basis points to burn (deflationary)
    }

    /// @notice Emitted when fees are collected
    event FeesCollected(address indexed token, uint256 amount, address indexed payer);

    /// @notice Emitted when fees are distributed
    event FeesDistributed(
        address indexed token,
        uint256 toTreasury,
        uint256 toStaking,
        uint256 toInsurance,
        uint256 burned
    );

    /// @notice Emitted when fee split is updated
    event FeeSplitUpdated(
        uint256 treasuryBps, uint256 stakingBps, uint256 insuranceBps, uint256 burnBps
    );

    /// @notice Collect fees from a protocol action
    function collectFee(address token, uint256 amount, address payer) external;

    /// @notice Distribute accumulated fees
    function distributeFees(address token) external;

    /// @notice Get the current fee split configuration
    function getFeeSplit() external view returns (FeeSplit memory);

    /// @notice Get accumulated undistributed fees for a token
    function pendingFees(address token) external view returns (uint256);
}
