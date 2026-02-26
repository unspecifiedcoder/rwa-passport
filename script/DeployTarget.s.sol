// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { SignerRegistry } from "../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";
import { XythumCCIPReceiver } from "../src/ccip/CCIPReceiver.sol";
import { MockGroth16Verifier } from "../src/mocks/MockGroth16Verifier.sol";
import { CollateralVerifier } from "../src/zk/CollateralVerifier.sol";
import { AaveAdapter } from "../src/adapters/AaveAdapter.sol";

/// @title DeployTarget
/// @notice Deploys target-chain contracts on BNB Chain Testnet
/// @dev Run: forge script script/DeployTarget.s.sol --rpc-url bnb_testnet --broadcast
contract DeployTarget is Script {
    // Same demo signer keys as source (must match for attestation signing) — 5 signers
    uint256 constant SIGNER_1_KEY = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_2_KEY = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_3_KEY = uint256(keccak256("xythum-demo-signer-3"));
    uint256 constant SIGNER_4_KEY = uint256(keccak256("xythum-demo-signer-4"));
    uint256 constant SIGNER_5_KEY = uint256(keccak256("xythum-demo-signer-5"));

    /// @notice Register 5 demo signers on a SignerRegistry and log their addresses
    function _registerSigners(SignerRegistry signerReg) internal {
        signerReg.registerSigner(vm.addr(SIGNER_1_KEY));
        signerReg.registerSigner(vm.addr(SIGNER_2_KEY));
        signerReg.registerSigner(vm.addr(SIGNER_3_KEY));
        signerReg.registerSigner(vm.addr(SIGNER_4_KEY));
        signerReg.registerSigner(vm.addr(SIGNER_5_KEY));
        console.log("  Signer 1:", vm.addr(SIGNER_1_KEY));
        console.log("  Signer 2:", vm.addr(SIGNER_2_KEY));
        console.log("  Signer 3:", vm.addr(SIGNER_3_KEY));
        console.log("  Signer 4:", vm.addr(SIGNER_4_KEY));
        console.log("  Signer 5:", vm.addr(SIGNER_5_KEY));
        console.log("  Threshold: 3/5");
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address ccipRouter = vm.envAddress("CCIP_ROUTER_BNB");

        console.log("=== Xythum Target Chain Deployment (BNB Testnet) ===");
        console.log("Deployer:", deployer);
        console.log("CCIP Router:", ccipRouter);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 1. Deploy SignerRegistry (threshold = 3/5)
        SignerRegistry signerReg = new SignerRegistry(deployer, 3);
        console.log("SignerRegistry:", address(signerReg));

        // 2. Register 5 demo signers
        _registerSigners(signerReg);

        // 3. Deploy AttestationRegistry
        AttestationRegistry attReg = new AttestationRegistry(
            address(signerReg),
            24 hours, // maxStaleness
            1 hours // rateLimitPeriod
        );
        console.log("AttestationRegistry:", address(attReg));

        // 4. Deploy CanonicalFactory
        CanonicalFactory factory = new CanonicalFactory(
            address(attReg),
            address(0), // no compliance contract for demo
            deployer, // treasury
            deployer // owner
        );
        console.log("CanonicalFactory:", address(factory));

        // 5. Deploy CCIPReceiver
        XythumCCIPReceiver ccipReceiver =
            new XythumCCIPReceiver(ccipRouter, address(factory), deployer);
        console.log("CCIPReceiver:", address(ccipReceiver));

        // 6. Deploy ZK stack
        _deployZKStack(deployer, address(factory));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Target Deployment Complete ===");
        console.log("Set these in .env:");
        console.log("  SIGNER_REGISTRY_BNB=", address(signerReg));
        console.log("  ATTESTATION_REGISTRY_BNB=", address(attReg));
        console.log("  CANONICAL_FACTORY_BNB=", address(factory));
        console.log("  CCIP_RECEIVER_BNB=", address(ccipReceiver));
    }

    /// @notice Deploy MockGroth16Verifier, CollateralVerifier, and AaveAdapter
    function _deployZKStack(address deployer, address factory) internal {
        MockGroth16Verifier mockVerifier = new MockGroth16Verifier();
        CollateralVerifier collVerifier = new CollateralVerifier(address(mockVerifier), deployer);
        console.log("MockGroth16Verifier:", address(mockVerifier));
        console.log("CollateralVerifier:", address(collVerifier));

        AaveAdapter aaveAdapter = new AaveAdapter(
            address(collVerifier),
            factory,
            6 hours, // maxProofAge
            deployer
        );
        console.log("AaveAdapter:", address(aaveAdapter));
    }
}
