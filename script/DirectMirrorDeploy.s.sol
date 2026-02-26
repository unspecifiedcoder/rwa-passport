// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {AttestationLib} from "../src/libraries/AttestationLib.sol";
import {CanonicalFactory} from "../src/core/CanonicalFactory.sol";

/// @title DirectMirrorDeploy
/// @notice Deploy a mirror via the direct path (no CCIP, instant).
///         Builds attestation, collects threshold signatures, calls deployMirrorDirect.
///
/// Usage:
///   # Set env vars for target chain
///   export FACTORY=0x...        # CanonicalFactory on target chain
///   export ORIGIN_RWA=0x...     # RWA contract on source chain
///   export ORIGIN_CHAIN_ID=43113  # Source chain ID (e.g. Fuji)
///   export LOCKED_AMOUNT=1000000000000000000000000  # 1M tokens (in wei)
///   export NONCE=1
///
///   # Run against target chain RPC
///   forge script script/DirectMirrorDeploy.s.sol \
///       --rpc-url $RPC_BNB_TESTNET --broadcast
contract DirectMirrorDeploy is Script {
    // Demo signer keys (TESTNET ONLY — deterministic keys from known seeds)
    uint256 constant SIGNER_KEY_1 = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_KEY_2 = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_KEY_3 = uint256(keccak256("xythum-demo-signer-3"));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        CanonicalFactory factory = CanonicalFactory(vm.envAddress("FACTORY"));

        // 1. Build attestation
        AttestationLib.Attestation memory att = _buildAttestation();

        // 2. Collect threshold signatures
        bytes memory signatures = _signAttestation(att, address(factory));
        uint256 signerBitmap = 7; // bits 0,1,2 set

        // 3. Log expected address
        console.log("Expected mirror:", factory.computeMirrorAddress(att));

        // 4. Deploy directly (instant!)
        vm.startBroadcast(deployerKey);
        address mirror = factory.deployMirrorDirect(att, signatures, signerBitmap);
        vm.stopBroadcast();

        // 5. Verify
        console.log("Mirror deployed:", mirror);
        console.log("Is canonical:", factory.isCanonical(mirror));
    }

    function _buildAttestation() internal view returns (AttestationLib.Attestation memory) {
        return AttestationLib.Attestation({
            originContract: vm.envAddress("ORIGIN_RWA"),
            originChainId: vm.envUint("ORIGIN_CHAIN_ID"),
            targetChainId: block.chainid,
            navRoot: keccak256("nav-placeholder"),
            complianceRoot: keccak256("compliance-placeholder"),
            lockedAmount: vm.envUint("LOCKED_AMOUNT"),
            timestamp: block.timestamp,
            nonce: vm.envUint("NONCE")
        });
    }

    function _signAttestation(
        AttestationLib.Attestation memory att,
        address factory
    ) internal view returns (bytes memory) {
        address attRegistry = address(CanonicalFactory(factory).attestationRegistry());
        bytes32 domainSep = AttestationLib.domainSeparator(block.chainid, attRegistry);
        bytes32 digest = AttestationLib.toTypedDataHash(att, domainSep);

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(SIGNER_KEY_1, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(SIGNER_KEY_2, digest);
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(SIGNER_KEY_3, digest);

        return abi.encodePacked(r1, s1, v1, r2, s2, v2, r3, s3, v3);
    }
}
