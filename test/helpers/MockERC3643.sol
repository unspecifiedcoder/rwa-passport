// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC3643
/// @notice Minimal ERC-3643 mock for testing the source chain RWA
/// @dev In production, this would be a full ERC-3643 compliant token with
///      identity registry, compliance module, etc.
contract MockERC3643 is ERC20 {
    constructor() ERC20("Mock Treasury Bill", "mTBILL") {
        _mint(msg.sender, 1_000_000 ether);
    }
}
