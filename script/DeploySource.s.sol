// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { MockRWA } from "../src/mocks/MockRWA.sol";
import { SignerRegistry } from "../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../src/core/AttestationRegistry.sol";
import { CCIPSender } from "../src/ccip/CCIPSender.sol";

/// @title DeploySource
/// @notice Deploys source-chain contracts on Avalanche Fuji
/// @dev Run: forge script script/DeploySource.s.sol --rpc-url fuji --broadcast
contract DeploySource is Script {
    // Demo signer keys (deterministic, testnet only) — 5 signers, threshold 3
    uint256 constant SIGNER_1_KEY = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_2_KEY = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_3_KEY = uint256(keccak256("xythum-demo-signer-3"));
    uint256 constant SIGNER_4_KEY = uint256(keccak256("xythum-demo-signer-4"));
    uint256 constant SIGNER_5_KEY = uint256(keccak256("xythum-demo-signer-5"));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address ccipRouter = vm.envAddress("CCIP_ROUTER_FUJI");

        console.log("=== Xythum Source Chain Deployment (Fuji) ===");
        console.log("Deployer:", deployer);
        console.log("CCIP Router:", ccipRouter);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 1. Deploy MockRWA token
        MockRWA mockRwa = new MockRWA();
        console.log("MockRWA:", address(mockRwa));
        console.log("  mTBILL supply:", mockRwa.totalSupply() / 1 ether, "tokens");

        // 2. Deploy SignerRegistry (threshold = 3)
        SignerRegistry signerReg = new SignerRegistry(deployer, 3);
        console.log("SignerRegistry:", address(signerReg));

        // 3. Register 5 demo signers (threshold 3/5)
        address signer1 = vm.addr(SIGNER_1_KEY);
        address signer2 = vm.addr(SIGNER_2_KEY);
        address signer3 = vm.addr(SIGNER_3_KEY);
        address signer4 = vm.addr(SIGNER_4_KEY);
        address signer5 = vm.addr(SIGNER_5_KEY);

        signerReg.registerSigner(signer1);
        signerReg.registerSigner(signer2);
        signerReg.registerSigner(signer3);
        signerReg.registerSigner(signer4);
        signerReg.registerSigner(signer5);
        console.log("  Signer 1:", signer1);
        console.log("  Signer 2:", signer2);
        console.log("  Signer 3:", signer3);
        console.log("  Signer 4:", signer4);
        console.log("  Signer 5:", signer5);
        console.log("  Threshold: 3/5");

        // 4. Deploy AttestationRegistry
        AttestationRegistry attReg = new AttestationRegistry(
            address(signerReg),
            24 hours, // maxStaleness
            1 hours // rateLimitPeriod
        );
        console.log("AttestationRegistry:", address(attReg));

        // 5. Deploy CCIPSender
        CCIPSender ccipSender = new CCIPSender(ccipRouter, deployer);
        console.log("CCIPSender:", address(ccipSender));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Source Deployment Complete ===");
        console.log("Set these in .env:");
        console.log("  MOCK_RWA_FUJI=", address(mockRwa));
        console.log("  SIGNER_REGISTRY_FUJI=", address(signerReg));
        console.log("  ATTESTATION_REGISTRY_FUJI=", address(attReg));
        console.log("  CCIP_SENDER_FUJI=", address(ccipSender));
    }
}
