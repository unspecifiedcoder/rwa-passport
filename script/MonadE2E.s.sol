// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";
import { AttestationRegistry } from "../src/core/AttestationRegistry.sol";
import { AttestationLib } from "../src/libraries/AttestationLib.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { XythumToken } from "../src/core/XythumToken.sol";

/// @title MonadE2E
/// @notice Cross-chain E2E test: deploy a mirror of Fuji MockRWA on Monad Testnet
/// @dev Run: forge script script/MonadE2E.s.sol:MonadE2E --rpc-url monad_testnet --broadcast -vv
contract MonadE2E is Script {
    // Demo signer keys (same as all chains)
    uint256 constant SIGNER_1_KEY = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_2_KEY = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_3_KEY = uint256(keccak256("xythum-demo-signer-3"));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Monad deployed addresses
        address factoryAddr = vm.envAddress("CANONICAL_FACTORY_MONAD");
        address attRegAddr = vm.envAddress("ATTESTATION_REGISTRY_MONAD");

        // Fuji origin token
        address mockRwaFuji = vm.envAddress("MOCK_RWA_FUJI");

        console.log("=== Cross-Chain E2E: Fuji MockRWA -> Monad Mirror ===");
        console.log("Factory (Monad):", factoryAddr);
        console.log("AttestationRegistry (Monad):", attRegAddr);
        console.log("Origin RWA (Fuji):", mockRwaFuji);
        console.log("");

        // 1. Read the on-chain domain separator
        AttestationRegistry attReg = AttestationRegistry(attRegAddr);
        bytes32 domainSep = attReg.DOMAIN_SEPARATOR();
        console.log("On-chain DOMAIN_SEPARATOR:");
        console.logBytes32(domainSep);

        // Verify locally
        bytes32 localDomainSep = AttestationLib.domainSeparator(10143, attRegAddr);
        console.log("Local computed domainSep:");
        console.logBytes32(localDomainSep);
        require(domainSep == localDomainSep, "Domain separator mismatch!");
        console.log("Domain separators MATCH");
        console.log("");

        // 2. Build attestation: Fuji (43113) -> Monad (10143)
        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: mockRwaFuji,
            originChainId: 43113,
            targetChainId: 10143,
            navRoot: keccak256("demo-nav-data-monad"),
            complianceRoot: keccak256("demo-compliance-monad"),
            lockedAmount: 500_000 ether,
            timestamp: block.timestamp,
            nonce: 1
        });

        console.log("Attestation: Fuji(43113) -> Monad(10143)");
        console.log("  Origin:", att.originContract);
        console.log("  Locked:", att.lockedAmount);
        console.log("  Timestamp:", att.timestamp);
        console.log("  Nonce:", att.nonce);

        // 3. Compute EIP-712 digest
        bytes32 digest = AttestationLib.toTypedDataHash(att, domainSep);
        console.log("EIP-712 digest:");
        console.logBytes32(digest);

        // 4. Sign with 3 signers (indices 0, 1, 2)
        bytes memory signatures;
        uint256 signerBitmap;

        uint256[3] memory keys;
        keys[0] = SIGNER_1_KEY;
        keys[1] = SIGNER_2_KEY;
        keys[2] = SIGNER_3_KEY;

        console.log("");
        console.log("Signing with 3/5 signers:");
        for (uint256 i = 0; i < 3; i++) {
            address signerAddr = vm.addr(keys[i]);
            console.log("  Signer", i, ":", signerAddr);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            signatures = abi.encodePacked(signatures, r, s, v);
            signerBitmap |= (1 << i);
        }
        console.log("Bitmap:", signerBitmap);

        // 5. Compute expected mirror address
        CanonicalFactory factory = CanonicalFactory(factoryAddr);
        address expectedMirror = factory.computeMirrorAddress(att);
        console.log("");
        console.log("Expected mirror address:", expectedMirror);

        // 6. Deploy via deployMirrorDirect (direct attestation path)
        vm.startBroadcast(deployerKey);
        address mirror = factory.deployMirrorDirect(att, signatures, signerBitmap);
        vm.stopBroadcast();

        // 7. Verify results
        console.log("");
        console.log("=== MIRROR DEPLOYED ON MONAD! ===");
        console.log("Mirror address:", mirror);
        console.log("Matches expected:", mirror == expectedMirror);

        bool canonical = factory.isCanonical(mirror);
        console.log("isCanonical:", canonical);

        IERC20Metadata token = IERC20Metadata(mirror);
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());

        XythumToken xToken = XythumToken(mirror);
        console.log("Origin Contract:", xToken.originContract());
        console.log("Origin Chain ID:", xToken.originChainId());

        uint256 mirrorCount = factory.getMirrorCount();
        console.log("Total mirrors on Monad:", mirrorCount);

        console.log("");
        console.log("=== E2E TEST PASSED ===");
    }
}
