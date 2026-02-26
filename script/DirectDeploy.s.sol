// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";
import { AttestationRegistry } from "../src/core/AttestationRegistry.sol";
import { AttestationLib } from "../src/libraries/AttestationLib.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { XythumToken } from "../src/core/XythumToken.sol";

/// @title DirectDeploy
/// @notice Calls deployMirror() directly on BNB Testnet, bypassing CCIP.
///         This proves the attestation signing + verification + CREATE2 deployment
///         works end-to-end on the live target chain.
/// @dev Run: forge script script/DirectDeploy.s.sol --rpc-url bnb_testnet --broadcast
contract DirectDeploy is Script {
    // Demo signer keys (must match what's registered in SignerRegistry on BNB Testnet)
    uint256 constant SIGNER_1_KEY = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_2_KEY = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_3_KEY = uint256(keccak256("xythum-demo-signer-3"));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address factoryAddr = vm.envAddress("CANONICAL_FACTORY_BNB");
        address attRegAddr = vm.envAddress("ATTESTATION_REGISTRY_BNB");
        address mockRwaFuji = vm.envAddress("MOCK_RWA_FUJI");

        console.log("=== Direct Mirror Deployment on BNB Testnet ===");
        console.log("Factory:", factoryAddr);
        console.log("AttestationRegistry:", attRegAddr);
        console.log("MockRWA (Fuji origin):", mockRwaFuji);

        // 1. Read the on-chain domain separator from the deployed AttestationRegistry
        AttestationRegistry attReg = AttestationRegistry(attRegAddr);
        bytes32 domainSep = attReg.DOMAIN_SEPARATOR();
        console.log("On-chain DOMAIN_SEPARATOR:");
        console.log(vm.toString(domainSep));

        // Also compute locally to compare
        bytes32 localDomainSep = AttestationLib.domainSeparator(97, attRegAddr);
        console.log("Local computed domainSep:");
        console.log(vm.toString(localDomainSep));

        if (domainSep != localDomainSep) {
            console.log("WARNING: Domain separator MISMATCH! Using on-chain value.");
        } else {
            console.log("Domain separators MATCH");
        }

        // 2. Build attestation (nonce=3 to avoid collision with prior attempts)
        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: mockRwaFuji,
            originChainId: 43113, // Avalanche Fuji
            targetChainId: 97, // BNB Chain Testnet
            navRoot: keccak256("demo-nav-data"),
            complianceRoot: keccak256("demo-compliance"),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp,
            nonce: 3 // nonce 3 to avoid collision
         });

        console.log("Attestation timestamp:", att.timestamp);

        // 3. Compute the EIP-712 digest using the ON-CHAIN domain separator
        bytes32 digest = AttestationLib.toTypedDataHash(att, domainSep);
        console.log("EIP-712 digest:");
        console.log(vm.toString(digest));

        // 4. Sign in registration order (index 0, 1, 2)
        bytes memory signatures;
        uint256 signerBitmap;

        uint256[3] memory keys;
        keys[0] = SIGNER_1_KEY;
        keys[1] = SIGNER_2_KEY;
        keys[2] = SIGNER_3_KEY;

        console.log("");
        console.log("Signer addresses (registration order):");
        for (uint256 i = 0; i < 3; i++) {
            address signerAddr = vm.addr(keys[i]);
            console.log("  Index", i, ":", signerAddr);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            signatures = abi.encodePacked(signatures, r, s, v);
            signerBitmap |= (1 << i);
        }
        console.log("Bitmap:", signerBitmap);
        console.log("Signatures length:", signatures.length);

        // 5. Compute expected mirror address before deployment
        CanonicalFactory factory = CanonicalFactory(factoryAddr);
        address expectedMirror = factory.computeMirrorAddress(att);
        console.log("");
        console.log("Expected mirror address:", expectedMirror);

        // 6. Deploy mirror
        vm.startBroadcast(deployerKey);

        address mirror = factory.deployMirror(att, signatures, signerBitmap);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Mirror Deployed! ===");
        console.log("Mirror address:", mirror);
        console.log("Matches expected:", mirror == expectedMirror);

        // 7. Verify
        bool canonical = factory.isCanonical(mirror);
        console.log("isCanonical:", canonical);

        IERC20Metadata token = IERC20Metadata(mirror);
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());

        XythumToken xToken = XythumToken(mirror);
        console.log("Origin Contract:", xToken.originContract());
        console.log("Origin Chain ID:", xToken.originChainId());
    }
}
