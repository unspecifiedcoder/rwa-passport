// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { SignerRegistry } from "../src/core/SignerRegistry.sol";

/// @title RegisterMissingSigners
/// @notice Registers signer 4 & 5 on a SignerRegistry that only has 3 signers
contract RegisterMissingSignersBnb is Script {
    uint256 constant SIGNER_4_KEY = uint256(keccak256("xythum-demo-signer-4"));
    uint256 constant SIGNER_5_KEY = uint256(keccak256("xythum-demo-signer-5"));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        SignerRegistry reg = SignerRegistry(0xFA6aFAcfAA866Cf54aCCa0E23883a1597574206c);

        address signer4 = vm.addr(SIGNER_4_KEY);
        address signer5 = vm.addr(SIGNER_5_KEY);
        console.log("Signer 4:", signer4);
        console.log("Signer 5:", signer5);
        console.log("Current count:", reg.getSignerCount());

        vm.startBroadcast(deployerKey);
        reg.registerSigner(signer4);
        reg.registerSigner(signer5);
        vm.stopBroadcast();

        console.log("New count:", reg.getSignerCount());
        console.log("Done! BNB SignerRegistry now has 5 signers.");
    }
}

contract RegisterMissingSignersFuji is Script {
    uint256 constant SIGNER_4_KEY = uint256(keccak256("xythum-demo-signer-4"));
    uint256 constant SIGNER_5_KEY = uint256(keccak256("xythum-demo-signer-5"));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        SignerRegistry reg = SignerRegistry(0xF17BBD22D1d3De885d02E01805C01C0e43E64A2F);

        address signer4 = vm.addr(SIGNER_4_KEY);
        address signer5 = vm.addr(SIGNER_5_KEY);
        console.log("Signer 4:", signer4);
        console.log("Signer 5:", signer5);
        console.log("Current count:", reg.getSignerCount());

        vm.startBroadcast(deployerKey);
        reg.registerSigner(signer4);
        reg.registerSigner(signer5);
        vm.stopBroadcast();

        console.log("New count:", reg.getSignerCount());
        console.log("Done! Fuji SignerRegistry now has 5 signers.");
    }
}
