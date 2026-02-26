// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CCIPSender } from "../src/ccip/CCIPSender.sol";
import { XythumCCIPReceiver } from "../src/ccip/CCIPReceiver.sol";

/// @title WireReverse
/// @notice Wires the reverse direction: BNB CCIPSender → Fuji CCIPReceiver
/// @dev Run TWICE:
///   1. On BNB Testnet: forge script script/WireReverse.s.sol:WireBnbSource --rpc-url bnb_testnet --broadcast
///   2. On Fuji:        forge script script/WireReverse.s.sol:WireFujiTarget --rpc-url fuji --broadcast

/// @notice Wire BNB Testnet as source: configure CCIPSender to know about Fuji receiver
contract WireBnbSource is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ccipSender = vm.envAddress("CCIP_SENDER_BNB");
        address ccipReceiverFuji = vm.envAddress("CCIP_RECEIVER_FUJI");
        uint64 fujiSelector = uint64(vm.envUint("CCIP_SELECTOR_FUJI"));

        console.log("=== Wiring BNB Source (Reverse Direction) ===");
        console.log("CCIPSender (BNB):", ccipSender);
        console.log("Fuji Receiver:", ccipReceiverFuji);
        console.log("Fuji Selector:", fujiSelector);

        vm.startBroadcast(deployerKey);

        CCIPSender sender = CCIPSender(ccipSender);

        // Enable Avalanche Fuji as a supported destination
        sender.setSupportedChain(fujiSelector, true);
        console.log("  Set Fuji as supported chain");

        // Set the receiver address on Fuji
        sender.setReceiver(fujiSelector, ccipReceiverFuji);
        console.log("  Set receiver on Fuji");

        vm.stopBroadcast();

        console.log("=== BNB Source Wiring Complete ===");
    }
}

/// @notice Wire Fuji as target: allow BNB CCIPSender as trusted source
contract WireFujiTarget is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ccipReceiver = vm.envAddress("CCIP_RECEIVER_FUJI");
        address ccipSenderBnb = vm.envAddress("CCIP_SENDER_BNB");
        uint64 bnbSelector = uint64(vm.envUint("CCIP_SELECTOR_BNB"));

        console.log("=== Wiring Fuji Target (Reverse Direction) ===");
        console.log("CCIPReceiver (Fuji):", ccipReceiver);
        console.log("BNB Sender:", ccipSenderBnb);
        console.log("BNB Selector:", bnbSelector);

        vm.startBroadcast(deployerKey);

        XythumCCIPReceiver receiver = XythumCCIPReceiver(ccipReceiver);

        // Allow the BNB CCIPSender as a trusted source
        receiver.setAllowedSender(bnbSelector, ccipSenderBnb, true);
        console.log("  Allowed BNB sender on Fuji receiver");

        vm.stopBroadcast();

        console.log("=== Fuji Target Wiring Complete ===");
    }
}
