// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { SignerRegistry } from "../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";
import { CollateralVerifier } from "../src/zk/CollateralVerifier.sol";
import { AaveAdapter } from "../src/adapters/AaveAdapter.sol";
import { LiquidityBootstrap } from "../src/hooks/LiquidityBootstrap.sol";
import { RWAHook } from "../src/hooks/RWAHook.sol";
import { XythumCCIPReceiver } from "../src/ccip/CCIPReceiver.sol";
import { CCIPSender } from "../src/ccip/CCIPSender.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title DeployXythum
/// @notice Full protocol deployment script for one chain
/// @dev Run: forge script script/Deploy.s.sol --rpc-url $RPC --broadcast --verify
///      Deployment order follows the dependency graph:
///      1. SignerRegistry → 2. AttestationRegistry → 3. CanonicalFactory →
///      4. CollateralVerifier → 5. AaveAdapter →
///      6. CCIPSender (source) / CCIPReceiver (target) →
///      7. Transfer ownership to multisig
///
///      RWAHook and LiquidityBootstrap require a V4 PoolManager address and
///      hook address mining — deployed separately via DeployHook.s.sol
contract DeployXythum is Script {
    function run() external {
        // ── Read environment ──
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address governance = vm.envOr("GOVERNANCE_MULTISIG", address(0));
        address treasury = vm.envOr("TREASURY", msg.sender);
        address compliance = vm.envOr("COMPLIANCE_CONTRACT", address(0));
        uint256 threshold = vm.envOr("SIGNER_THRESHOLD", uint256(3));

        console.log("=== Xythum RWA Passport - Full Deployment ===");
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("Treasury:", treasury);
        console.log("Threshold:", threshold);

        vm.startBroadcast(deployerKey);

        // ── 1. SignerRegistry ──
        SignerRegistry signerReg = new SignerRegistry(
            vm.addr(deployerKey), // temporary owner (transfer later)
            threshold
        );
        console.log("SignerRegistry:", address(signerReg));

        // ── 2. AttestationRegistry ──
        AttestationRegistry attReg = new AttestationRegistry(
            address(signerReg),
            24 hours, // maxStaleness
            1 hours // rateLimitPeriod
        );
        console.log("AttestationRegistry:", address(attReg));

        // ── 3. CanonicalFactory ──
        CanonicalFactory factory = new CanonicalFactory(
            address(attReg),
            compliance, // address(0) disables compliance for MVP
            treasury,
            vm.addr(deployerKey)
        );
        console.log("CanonicalFactory:", address(factory));

        // ── 4. CollateralVerifier ──
        // For MVP: deploy a mock verifier stub
        // TODO(upgrade): Replace with real Groth16Verifier from snarkjs export
        // The MockGroth16Verifier is in test/ — for production, deploy the real one
        // For now, deploy CollateralVerifier with address(0) as verifier
        // (will be configured post-deployment when verifier is ready)
        console.log("CollateralVerifier: SKIPPED (requires Groth16Verifier address)");

        // ── 5. CCIPSender (source chain only) ──
        address ccipRouter = vm.envOr("CCIP_ROUTER", address(0));
        if (ccipRouter != address(0)) {
            CCIPSender ccipSender = new CCIPSender(ccipRouter, vm.addr(deployerKey));
            console.log("CCIPSender:", address(ccipSender));
        } else {
            console.log("CCIPSender: SKIPPED (no CCIP_ROUTER set)");
        }

        // ── 6. CCIPReceiver (target chain only) ──
        if (ccipRouter != address(0)) {
            XythumCCIPReceiver ccipReceiver =
                new XythumCCIPReceiver(ccipRouter, address(factory), vm.addr(deployerKey));
            console.log("CCIPReceiver:", address(ccipReceiver));
        } else {
            console.log("CCIPReceiver: SKIPPED (no CCIP_ROUTER set)");
        }

        // ── 7. Transfer ownership to governance multisig ──
        if (governance != address(0)) {
            signerReg.transferOwnership(governance);
            factory.transferOwnership(governance);
            console.log("Ownership transferred to:", governance);
        } else {
            console.log("WARNING: No GOVERNANCE_MULTISIG set. Owner remains deployer.");
        }

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
    }
}
