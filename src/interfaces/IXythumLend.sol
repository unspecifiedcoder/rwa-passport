// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IXythumLend
/// @author Xythum Protocol
/// @notice Public surface of the XythumLend single-pair demo lending market.
/// @dev    Exposes user-facing actions plus position views so that tests, scripts,
///         and the frontend can hold a typed reference to the market.
interface IXythumLend {
    // ─── Events ──────────────────────────────────────────────────────
    event Supplied(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event ReservesSeeded(uint256 amount);

    // ─── User Actions ────────────────────────────────────────────────
    /// @notice Supply xRWA collateral.
    function supply(uint256 amount) external;

    /// @notice Withdraw xRWA collateral. Reverts if it would breach LTV.
    function withdraw(uint256 amount) external;

    /// @notice Borrow USDC against supplied collateral.
    function borrow(uint256 amount) external;

    /// @notice Repay outstanding debt. Pass `type(uint256).max` to repay everything.
    function repay(uint256 amount) external;

    // ─── Views ───────────────────────────────────────────────────────
    /// @notice Read a user's position and a derived health score.
    /// @return collateral User's xRWA collateral (18 decimals).
    /// @return debt       User's USDC debt (6 decimals).
    /// @return healthBps  Higher = healthier; `type(uint256).max` if no debt.
    function positionOf(address user)
        external
        view
        returns (uint256 collateral, uint256 debt, uint256 healthBps);

    /// @notice Maximum additional USDC the user can borrow, capped by reserves.
    function maxBorrow(address user) external view returns (uint256);

    /// @notice Maximum collateral the user can withdraw while remaining within LTV.
    function maxWithdraw(address user) external view returns (uint256);
}
