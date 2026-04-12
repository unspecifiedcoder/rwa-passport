// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";

/// @title RedeployFactoryV2
/// @notice Redeploys CanonicalFactory with the new mintFromLock function on any chain.
///         Pass attestationRegistry + initialOwner explicitly so this works on
///         Fuji, BNB, and Monad without per-chain branches.
///
/// Run: forge script script/RedeployFactoryV2.s.sol \
///        --rpc-url $RPC_<CHAIN> --broadcast \
///        --sig "run(address,address)" $ATT_REGISTRY_<CHAIN> $DEPLOYER
contract RedeployFactoryV2 is Script {
    function run(address attestationRegistry, address initialOwner) external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== Redeploy CanonicalFactory v2 (with mintFromLock) ===");
        console.log("ChainId:             ", block.chainid);
        console.log("Deployer:            ", deployer);
        console.log("AttestationRegistry: ", attestationRegistry);
        console.log("InitialOwner:        ", initialOwner);

        vm.startBroadcast(deployerKey);
        CanonicalFactory factory = new CanonicalFactory(
            attestationRegistry,
            address(0), // no compliance for demo
            initialOwner, // treasury
            initialOwner // owner
        );
        vm.stopBroadcast();

        console.log("");
        console.log(">>> NEW CanonicalFactory:", address(factory));
        console.log("");
        console.log("Update frontend/src/lib/contracts.ts:");
        console.log("  <chain>.canonicalFactory = ", address(factory));
        console.log("");
        console.log("NOTE: Existing mirror tokens deployed by the OLD factory are");
        console.log("      orphans. Re-attest on the new factory to redeploy them");
        console.log("      at NEW CREATE2 addresses (different deployer = different");
        console.log("      mirror addresses).");
    }
}
