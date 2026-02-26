// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";
import { XythumCCIPReceiver } from "../src/ccip/CCIPReceiver.sol";

/// @title DeployTargetFuji
/// @notice Deploys target-chain contracts on Avalanche Fuji (for reverse direction: BNB → Fuji)
/// @dev Fuji already has SignerRegistry + AttestationRegistry from DeploySource.s.sol.
///      We reuse the existing AttestationRegistry for the CanonicalFactory.
/// @dev Run: forge script script/DeployTargetFuji.s.sol:DeployTargetFuji --rpc-url fuji --broadcast
contract DeployTargetFuji is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address ccipRouter = vm.envAddress("CCIP_ROUTER_FUJI");
        address attRegFuji = vm.envAddress("ATTESTATION_REGISTRY_FUJI");

        console.log("=== Xythum Target Deployment on Fuji (Reverse Direction) ===");
        console.log("Deployer:", deployer);
        console.log("CCIP Router:", ccipRouter);
        console.log("AttestationRegistry (existing):", attRegFuji);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 1. Deploy CanonicalFactory
        //    Uses the EXISTING AttestationRegistry on Fuji (deployed by DeploySource.s.sol)
        //    compliance = address(0) for demo, treasury = deployer
        CanonicalFactory factory = new CanonicalFactory(
            attRegFuji,
            address(0), // no compliance contract for demo
            deployer, // treasury
            deployer // owner
        );
        console.log("CanonicalFactory (Fuji):", address(factory));

        // 2. Deploy CCIPReceiver
        XythumCCIPReceiver ccipReceiver =
            new XythumCCIPReceiver(ccipRouter, address(factory), deployer);
        console.log("CCIPReceiver (Fuji):", address(ccipReceiver));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Fuji Target Deployment Complete ===");
        console.log("Set these in .env:");
        console.log("  CANONICAL_FACTORY_FUJI=", address(factory));
        console.log("  CCIP_RECEIVER_FUJI=", address(ccipReceiver));
    }
}
