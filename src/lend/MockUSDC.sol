// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title MockUSDC
/// @author Xythum Protocol
/// @notice Demo-only stand-in for USDC. 6-decimals, public faucet, owner-mintable.
/// @dev    NOT for production use. Exists solely to fund the XythumLend demo market
///         on Avalanche Fuji testnet.
contract MockUSDC is ERC20, Ownable2Step {
    /// @notice Amount minted per `faucet()` call (10k USDC, 6-decimal precision).
    uint256 public constant FAUCET_AMOUNT = 10_000 * 1e6;

    constructor(address initialOwner) ERC20("Mock USDC", "USDC") Ownable(initialOwner) { }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint `FAUCET_AMOUNT` to the caller. Open to anyone — testnet only.
    function faucet() external {
        _mint(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Owner-only mint, used to seed reserves on the lending market.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
