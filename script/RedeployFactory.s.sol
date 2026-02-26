// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";
import { XythumCCIPReceiver } from "../src/ccip/CCIPReceiver.sol";
import { CCIPSender } from "../src/ccip/CCIPSender.sol";

/// @title RedeployFactoryBnb
/// @notice Redeploys CanonicalFactory + CCIPReceiver on BNB Testnet with new code
///         (adds deployMirrorDirect, allMirrors enumeration).
///         Also re-wires the new CCIPReceiver to trust the existing Fuji CCIPSender.
///
/// Run: forge script script/RedeployFactory.s.sol:RedeployFactoryBnb --rpc-url bnb_testnet --broadcast
contract RedeployFactoryBnb is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address attRegBnb = vm.envAddress("ATTESTATION_REGISTRY_BNB");
        address ccipRouterBnb = vm.envAddress("CCIP_ROUTER_BNB");
        address ccipSenderFuji = vm.envAddress("CCIP_SENDER_FUJI");
        uint64 fujiSelector = uint64(vm.envUint("CCIP_SELECTOR_FUJI"));

        console.log("=== Redeploy Factory on BNB Testnet ===");
        console.log("Deployer:", deployer);
        console.log("AttestationRegistry (reused):", attRegBnb);

        vm.startBroadcast(deployerKey);

        // 1. Deploy NEW CanonicalFactory (with deployMirrorDirect + enumeration)
        CanonicalFactory factory = new CanonicalFactory(
            attRegBnb,
            address(0), // no compliance for demo
            deployer, // treasury
            deployer // owner
        );
        console.log("NEW CanonicalFactory:", address(factory));

        // 2. Deploy NEW CCIPReceiver (points to new factory)
        XythumCCIPReceiver receiver =
            new XythumCCIPReceiver(ccipRouterBnb, address(factory), deployer);
        console.log("NEW CCIPReceiver:", address(receiver));

        // 3. Wire: allow Fuji CCIPSender as trusted source on new receiver
        receiver.setAllowedSender(fujiSelector, ccipSenderFuji, true);
        console.log("  Allowed Fuji sender on new BNB receiver");

        vm.stopBroadcast();

        console.log("");
        console.log("=== BNB Redeploy Complete ===");
        console.log("Update .env:");
        console.log("  CANONICAL_FACTORY_BNB=", address(factory));
        console.log("  CCIP_RECEIVER_BNB=", address(receiver));
        console.log("");
        console.log("NEXT: Update Fuji CCIPSender to point to new BNB receiver:");
        console.log("  Run RedeployFactory.s.sol:RewireFujiSender on Fuji");
    }
}

/// @title RewireFujiSender
/// @notice Updates the Fuji CCIPSender to point to the NEW BNB CCIPReceiver
///
/// Run: forge script script/RedeployFactory.s.sol:RewireFujiSender --rpc-url fuji --broadcast
contract RewireFujiSender is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ccipSenderFuji = vm.envAddress("CCIP_SENDER_FUJI");
        address newBnbReceiver = vm.envAddress("CCIP_RECEIVER_BNB");
        uint64 bnbSelector = uint64(vm.envUint("CCIP_SELECTOR_BNB"));

        console.log("=== Rewire Fuji CCIPSender ===");
        console.log("CCIPSender (Fuji):", ccipSenderFuji);
        console.log("New BNB Receiver:", newBnbReceiver);

        vm.startBroadcast(deployerKey);

        CCIPSender sender = CCIPSender(ccipSenderFuji);
        sender.setReceiver(bnbSelector, newBnbReceiver);
        console.log("  Updated BNB receiver on Fuji sender");

        vm.stopBroadcast();

        console.log("=== Fuji Sender Rewired ===");
    }
}

/// @title RedeployFactoryFuji
/// @notice Redeploys CanonicalFactory + CCIPReceiver on Fuji with new code.
///         Also re-wires to trust the existing BNB CCIPSender.
///
/// Run: forge script script/RedeployFactory.s.sol:RedeployFactoryFuji --rpc-url fuji --broadcast
contract RedeployFactoryFuji is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address attRegFuji = vm.envAddress("ATTESTATION_REGISTRY_FUJI");
        address ccipRouterFuji = vm.envAddress("CCIP_ROUTER_FUJI");
        address ccipSenderBnb = vm.envAddress("CCIP_SENDER_BNB");
        uint64 bnbSelector = uint64(vm.envUint("CCIP_SELECTOR_BNB"));

        console.log("=== Redeploy Factory on Fuji ===");
        console.log("Deployer:", deployer);
        console.log("AttestationRegistry (reused):", attRegFuji);

        vm.startBroadcast(deployerKey);

        // 1. Deploy NEW CanonicalFactory
        CanonicalFactory factory = new CanonicalFactory(attRegFuji, address(0), deployer, deployer);
        console.log("NEW CanonicalFactory:", address(factory));

        // 2. Deploy NEW CCIPReceiver
        XythumCCIPReceiver receiver =
            new XythumCCIPReceiver(ccipRouterFuji, address(factory), deployer);
        console.log("NEW CCIPReceiver:", address(receiver));

        // 3. Wire: allow BNB CCIPSender on new Fuji receiver
        receiver.setAllowedSender(bnbSelector, ccipSenderBnb, true);
        console.log("  Allowed BNB sender on new Fuji receiver");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Fuji Redeploy Complete ===");
        console.log("Update .env:");
        console.log("  CANONICAL_FACTORY_FUJI=", address(factory));
        console.log("  CCIP_RECEIVER_FUJI=", address(receiver));
    }
}

/// @title RewireBnbSender
/// @notice Updates BNB CCIPSender to point to the NEW Fuji CCIPReceiver
///
/// Run: forge script script/RedeployFactory.s.sol:RewireBnbSender --rpc-url bnb_testnet --broadcast
contract RewireBnbSender is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ccipSenderBnb = vm.envAddress("CCIP_SENDER_BNB");
        address newFujiReceiver = vm.envAddress("CCIP_RECEIVER_FUJI");
        uint64 fujiSelector = uint64(vm.envUint("CCIP_SELECTOR_FUJI"));

        console.log("=== Rewire BNB CCIPSender ===");
        console.log("CCIPSender (BNB):", ccipSenderBnb);
        console.log("New Fuji Receiver:", newFujiReceiver);

        vm.startBroadcast(deployerKey);

        CCIPSender sender = CCIPSender(ccipSenderBnb);
        sender.setReceiver(fujiSelector, newFujiReceiver);
        console.log("  Updated Fuji receiver on BNB sender");

        vm.stopBroadcast();

        console.log("=== BNB Sender Rewired ===");
    }
}
