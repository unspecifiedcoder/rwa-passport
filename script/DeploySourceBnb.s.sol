// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockRWA} from "../src/mocks/MockRWA.sol";
import {CCIPSender} from "../src/ccip/CCIPSender.sol";

/// @title DeploySourceBnb
/// @notice Deploys source-chain contracts on BNB Testnet (for reverse direction: BNB → Fuji)
/// @dev Run: forge script script/DeploySourceBnb.s.sol:DeploySourceBnb --rpc-url bnb_testnet --broadcast
contract DeploySourceBnb is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address ccipRouter = vm.envAddress("CCIP_ROUTER_BNB");

        console.log("=== Xythum Source Deployment on BNB Testnet (Reverse Direction) ===");
        console.log("Deployer:", deployer);
        console.log("CCIP Router:", ccipRouter);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 1. Deploy MockRWA on BNB so users can create RWAs here too
        MockRWA mockRwa = new MockRWA();
        console.log("MockRWA (BNB):", address(mockRwa));
        console.log("  mTBILL supply:", mockRwa.totalSupply() / 1 ether, "tokens");

        // 2. Deploy CCIPSender on BNB (for sending attestations TO Fuji)
        //    NOTE: BNB already has SignerRegistry + AttestationRegistry from DeployTarget.s.sol
        //    Those are used for the existing Fuji→BNB direction (target role).
        //    The CCIPSender doesn't need them — it just relays pre-signed payloads.
        CCIPSender ccipSender = new CCIPSender(ccipRouter, deployer);
        console.log("CCIPSender (BNB):", address(ccipSender));

        vm.stopBroadcast();

        console.log("");
        console.log("=== BNB Source Deployment Complete ===");
        console.log("Set these in .env:");
        console.log("  MOCK_RWA_BNB=", address(mockRwa));
        console.log("  CCIP_SENDER_BNB=", address(ccipSender));
    }
}
