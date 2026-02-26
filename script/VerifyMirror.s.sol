// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";
import { XythumToken } from "../src/core/XythumToken.sol";
import { AttestationLib } from "../src/libraries/AttestationLib.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title VerifyMirror
/// @notice Verifies that the mirror token was deployed correctly on BNB Testnet
///         after CCIP delivered the attestation.
/// @dev Run: forge script script/VerifyMirror.s.sol --rpc-url bnb_testnet
///      Run this AFTER the CCIP message has been delivered (~5-15 min after sending)
contract VerifyMirror is Script {
    function run() external view {
        address factoryAddr = vm.envAddress("CANONICAL_FACTORY_BNB");
        address mockRwaFuji = vm.envAddress("MOCK_RWA_FUJI");

        console.log("=== Verifying Mirror on BNB Testnet ===");
        console.log("CanonicalFactory:", factoryAddr);
        console.log("Origin RWA (Fuji):", mockRwaFuji);
        console.log("");

        CanonicalFactory factory = CanonicalFactory(factoryAddr);

        // Reconstruct the attestation (must match what was sent)
        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: mockRwaFuji,
            originChainId: 43113, // Avalanche Fuji
            targetChainId: 97, // BNB Chain Testnet
            navRoot: keccak256("demo-nav-data"),
            complianceRoot: keccak256("demo-compliance"),
            lockedAmount: 1_000_000 ether,
            timestamp: 0, // not used for address computation
            nonce: 2
        });

        // Compute expected mirror address
        address expectedMirror = factory.computeMirrorAddress(att);
        console.log("Expected mirror address:", expectedMirror);

        // Check if canonical
        bool isCanonical = factory.isCanonical(expectedMirror);
        console.log("isCanonical:", isCanonical);

        if (isCanonical) {
            // Read mirror metadata
            IERC20Metadata mirror = IERC20Metadata(expectedMirror);
            console.log("");
            console.log("=== Mirror Token Details ===");
            console.log("Name:", mirror.name());
            console.log("Symbol:", mirror.symbol());
            console.log("Decimals:", mirror.decimals());

            XythumToken xToken = XythumToken(expectedMirror);
            console.log("Origin Contract:", xToken.originContract());
            console.log("Origin Chain ID:", xToken.originChainId());
            console.log("");
            console.log("SUCCESS: Mirror is canonical and deployed correctly!");
        } else {
            console.log("");
            console.log("Mirror NOT YET deployed. Possible reasons:");
            console.log("  1. CCIP message still in transit (wait 5-15 min)");
            console.log("  2. CCIP message failed (check ccip.chain.link)");
            console.log("  3. Attestation verification failed on target chain");
            console.log("");
            console.log("Check CCIP message status at: https://ccip.chain.link");
        }
    }
}
