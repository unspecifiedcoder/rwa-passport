// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IProtocolToken
/// @author Xythum Protocol
/// @notice Interface for the XYT governance token with vote delegation and vesting
interface IProtocolToken is IERC20 {
    /// @notice Emitted when tokens are vested to a beneficiary
    event TokensVested(address indexed beneficiary, uint256 amount, uint256 cliff, uint256 duration);

    /// @notice Emitted when vested tokens are released
    event TokensReleased(address indexed beneficiary, uint256 amount);

    /// @notice Emitted when anti-whale limit is updated
    event TransferLimitUpdated(uint256 oldLimit, uint256 newLimit);

    /// @notice Mint tokens (only callable by authorized minters - staking, governance)
    function mint(address to, uint256 amount) external;

    /// @notice Burn tokens
    function burn(uint256 amount) external;

    /// @notice Create a vesting schedule for a beneficiary
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 vestingDuration
    ) external;

    /// @notice Release vested tokens for a beneficiary
    function releaseVestedTokens(address beneficiary) external;

    /// @notice Get the releasable amount for a beneficiary
    function getReleasableAmount(address beneficiary) external view returns (uint256);

    /// @notice Get the total supply cap
    function maxSupply() external view returns (uint256);
}
