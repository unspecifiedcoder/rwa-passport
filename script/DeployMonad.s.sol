// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { SignerRegistry } from "../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";
import { MockRWA } from "../src/mocks/MockRWA.sol";

/// @title DeployMonad
/// @notice Deploys Xythum RWA Passport contracts on Monad Testnet (chain 10143)
/// @dev No CCIP on Monad — direct deploy path only.
///      Run: forge script script/DeployMonad.s.sol:DeployMonad --rpc-url monad_testnet --broadcast -vv
contract DeployMonad is Script {
    // Same 5 demo signer keys as all other chains (must match for cross-chain attestations)
    uint256 constant SIGNER_1_KEY = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_2_KEY = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_3_KEY = uint256(keccak256("xythum-demo-signer-3"));
    uint256 constant SIGNER_4_KEY = uint256(keccak256("xythum-demo-signer-4"));
    uint256 constant SIGNER_5_KEY = uint256(keccak256("xythum-demo-signer-5"));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== Xythum RWA Passport Deployment (Monad Testnet) ===");
        console.log("Chain ID: 10143");
        console.log("Deployer:", deployer);
        console.log("NOTE: No CCIP on Monad - direct deploy path only");
        console.log("");

        vm.startBroadcast(deployerKey);

        // 1. Deploy MockRWA (origin token for Monad-originating RWAs)
        MockRWA mockRwa = new MockRWA();
        console.log("1. MockRWA (mTBILL):", address(mockRwa));

        // 2. Deploy SignerRegistry (threshold = 3/5)
        SignerRegistry signerReg = new SignerRegistry(deployer, 3);
        console.log("2. SignerRegistry:", address(signerReg));

        // 3. Register 5 demo signers
        signerReg.registerSigner(vm.addr(SIGNER_1_KEY));
        signerReg.registerSigner(vm.addr(SIGNER_2_KEY));
        signerReg.registerSigner(vm.addr(SIGNER_3_KEY));
        signerReg.registerSigner(vm.addr(SIGNER_4_KEY));
        signerReg.registerSigner(vm.addr(SIGNER_5_KEY));
        console.log("   Signer 1:", vm.addr(SIGNER_1_KEY));
        console.log("   Signer 2:", vm.addr(SIGNER_2_KEY));
        console.log("   Signer 3:", vm.addr(SIGNER_3_KEY));
        console.log("   Signer 4:", vm.addr(SIGNER_4_KEY));
        console.log("   Signer 5:", vm.addr(SIGNER_5_KEY));
        console.log("   Threshold: 3/5");

        // 4. Deploy AttestationRegistry
        AttestationRegistry attReg = new AttestationRegistry(
            address(signerReg),
            24 hours, // maxStaleness
            1 hours // rateLimitPeriod
        );
        console.log("3. AttestationRegistry:", address(attReg));

        // 5. Deploy CanonicalFactory
        CanonicalFactory factory = new CanonicalFactory(
            address(attReg),
            address(0), // no compliance contract for demo
            deployer, // treasury
            deployer // owner
        );
        console.log("4. CanonicalFactory:", address(factory));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Monad Testnet Deployment Complete ===");
        console.log("Set these in .env:");
        console.log("  MOCK_RWA_MONAD=", address(mockRwa));
        console.log("  SIGNER_REGISTRY_MONAD=", address(signerReg));
        console.log("  ATTESTATION_REGISTRY_MONAD=", address(attReg));
        console.log("  CANONICAL_FACTORY_MONAD=", address(factory));
        console.log("");
        console.log("No CCIP contracts deployed (Chainlink CCIP not supported on Monad).");
        console.log("Use deployMirrorDirect() for cross-chain mirror deployment.");
    }
}
