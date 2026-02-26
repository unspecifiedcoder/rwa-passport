// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IXythumToken
/// @author Xythum Protocol
/// @notice Interface for canonical mirror tokens deployed by CanonicalFactory
interface IXythumToken is IERC20 {
    /// @notice Mint mirror tokens (only callable by authorized minter)
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external;

    /// @notice Burn mirror tokens (only callable by authorized minter)
    /// @param from Address to burn from
    /// @param amount Amount to burn
    function burn(address from, uint256 amount) external;

    /// @notice Get the origin contract address on the source chain
    /// @return The address of the original RWA contract
    function originContract() external view returns (address);

    /// @notice Get the source chain ID
    /// @return The chain ID where the original RWA lives
    function originChainId() external view returns (uint256);

    /// @notice Check if a transfer between two addresses is compliant
    /// @param from Sender address
    /// @param to Receiver address
    /// @return True if the transfer is allowed
    function isCompliant(address from, address to) external view returns (bool);

    /// @notice Maximum total tokens that can ever be minted
    /// @return The mint cap
    function mintCap() external view returns (uint256);

    /// @notice Running total of all tokens ever minted (does not decrease on burn)
    /// @return The total minted amount
    function totalMinted() external view returns (uint256);
}
