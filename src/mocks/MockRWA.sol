// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockRWA
/// @author Xythum Protocol
/// @notice Deployable ERC-20 simulating a tokenized real-world asset (e.g. T-bill)
///         on the source chain. This is the asset that gets mirrored cross-chain.
/// @dev In production, this would be a real RWA like Ondo OUSG, BlackRock BUIDL,
///      or any ERC-3643 compliant token. For the testnet demo, we use a simple ERC-20.
contract MockRWA is ERC20 {
    /// @notice Deploy the mock RWA and mint initial supply to deployer
    /// @dev Mints 1,000,000 tokens (18 decimals) to msg.sender
    constructor() ERC20("Mock Treasury Bill", "mTBILL") {
        _mint(msg.sender, 1_000_000 ether);
    }
}
