// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CCIPSender } from "../src/ccip/CCIPSender.sol";
import { XythumCCIPReceiver } from "../src/ccip/CCIPReceiver.sol";

/// @title WireChains
/// @notice Wires cross-chain connections between Fuji CCIPSender and BNB CCIPReceiver
/// @dev Run TWICE:
///   1. On Fuji:       forge script script/WireChains.s.sol:WireSourceChain --rpc-url fuji --broadcast
///   2. On BNB Testnet: forge script script/WireChains.s.sol:WireTargetChain --rpc-url bnb_testnet --broadcast

/// @notice Wire the source chain (Fuji): configure CCIPSender to know about BNB receiver
contract WireSourceChain is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ccipSender = vm.envAddress("CCIP_SENDER_FUJI");
        address ccipReceiverBnb = vm.envAddress("CCIP_RECEIVER_BNB");
        uint64 bnbSelector = uint64(vm.envUint("CCIP_SELECTOR_BNB"));

        console.log("=== Wiring Source Chain (Fuji) ===");
        console.log("CCIPSender:", ccipSender);
        console.log("BNB Receiver:", ccipReceiverBnb);
        console.log("BNB Selector:", bnbSelector);

        vm.startBroadcast(deployerKey);

        CCIPSender sender = CCIPSender(ccipSender);

        // Enable BNB Testnet as a supported destination
        sender.setSupportedChain(bnbSelector, true);
        console.log("  Set BNB Testnet as supported chain");

        // Set the receiver address on BNB Testnet
        sender.setReceiver(bnbSelector, ccipReceiverBnb);
        console.log("  Set receiver on BNB Testnet");

        vm.stopBroadcast();

        console.log("=== Source Chain Wiring Complete ===");
    }
}

/// @notice Wire the target chain (BNB Testnet): allow Fuji CCIPSender as trusted source
contract WireTargetChain is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ccipReceiver = vm.envAddress("CCIP_RECEIVER_BNB");
        address ccipSenderFuji = vm.envAddress("CCIP_SENDER_FUJI");
        uint64 fujiSelector = uint64(vm.envUint("CCIP_SELECTOR_FUJI"));

        console.log("=== Wiring Target Chain (BNB Testnet) ===");
        console.log("CCIPReceiver:", ccipReceiver);
        console.log("Fuji Sender:", ccipSenderFuji);
        console.log("Fuji Selector:", fujiSelector);

        vm.startBroadcast(deployerKey);

        XythumCCIPReceiver receiver = XythumCCIPReceiver(ccipReceiver);

        // Allow the Fuji CCIPSender as a trusted source
        receiver.setAllowedSender(fujiSelector, ccipSenderFuji, true);
        console.log("  Allowed Fuji sender on BNB receiver");

        vm.stopBroadcast();

        console.log("=== Target Chain Wiring Complete ===");
    }
}
