// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRWAYieldVault
/// @author Xythum Protocol
/// @notice Interface for ERC-4626 yield vault for RWA yield distribution
interface IRWAYieldVault {
    /// @notice Emitted when yield is harvested from the underlying RWA
    event YieldHarvested(uint256 amount, uint256 timestamp);

    /// @notice Emitted when performance fee is collected
    event PerformanceFeeCollected(uint256 amount, address indexed recipient);

    /// @notice Emitted when vault strategy is updated
    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);

    /// @notice Emitted when deposit cap is updated
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);

    /// @notice Harvest yield from the underlying RWA source
    function harvest() external returns (uint256 yieldAmount);

    /// @notice Get the current APY in basis points
    function currentAPY() external view returns (uint256);

    /// @notice Get the total assets under management
    function totalAssetsManaged() external view returns (uint256);

    /// @notice Get the deposit cap
    function depositCap() external view returns (uint256);

    /// @notice Get the performance fee in basis points
    function performanceFeeBps() external view returns (uint256);
}
