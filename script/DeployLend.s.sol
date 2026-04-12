// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { MockUSDC } from "../src/lend/MockUSDC.sol";
import { XythumLend } from "../src/lend/XythumLend.sol";

/// @title DeployLendScript
/// @author Xythum Protocol
/// @notice Deploys MockUSDC + XythumLend and (when possible) seeds reserves in one shot.
/// @dev    Run: forge script script/DeployLend.s.sol:DeployLendScript \
///              --sig "run(address,address)" <mirror> <owner> --rpc-url fuji --broadcast
contract DeployLendScript is Script {
    /// @notice Default reserves seeded by the deployer (1M USDC, 6-decimal).
    uint256 public constant DEFAULT_RESERVES = 1_000_000 * 1e6;

    /// @param mirrorToken  The xRWA mirror to use as collateral on this chain.
    ///                     Pass address(0) only if you intend to swap it in later.
    /// @param initialOwner Address that owns MockUSDC + XythumLend.
    function run(address mirrorToken, address initialOwner) external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== Xythum -- Deploy Lend Market ===");
        console.log("ChainId:        ", block.chainid);
        console.log("Deployer:       ", deployer);
        console.log("MirrorToken:    ", mirrorToken);
        console.log("InitialOwner:   ", initialOwner);

        vm.startBroadcast(deployerKey);

        MockUSDC usdc = new MockUSDC(initialOwner);
        XythumLend lend = new XythumLend(mirrorToken, address(usdc), initialOwner);

        // Owner mints reserves and seeds them in the same broadcast.
        // NOTE: deployer must equal initialOwner for this leg to succeed, since
        //       MockUSDC.mint and XythumLend.seedReserves are both onlyOwner.
        if (initialOwner == deployer) {
            usdc.mint(deployer, DEFAULT_RESERVES);
            usdc.approve(address(lend), DEFAULT_RESERVES);
            lend.seedReserves(DEFAULT_RESERVES);
        }

        vm.stopBroadcast();

        console.log(">>> MockUSDC:    ", address(usdc));
        console.log(">>> XythumLend:  ", address(lend));
        console.log(">>> Reserves:    ", DEFAULT_RESERVES);
        console.log("Update frontend/src/lib/contracts.ts:");
        console.log("  <chain>.mockUsdc   =", address(usdc));
        console.log("  <chain>.xythumLend =", address(lend));
    }
}
