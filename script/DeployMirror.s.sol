// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CanonicalFactory} from "../src/core/CanonicalFactory.sol";
import {XythumToken} from "../src/core/XythumToken.sol";
import {AttestationLib} from "../src/libraries/AttestationLib.sol";

/// @title DeployMirror
/// @notice Deploy a single canonical mirror for a specific RWA.
///         Assumes the protocol is already deployed on the target chain.
/// @dev Run: forge script script/DeployMirror.s.sol --rpc-url $RPC --broadcast
///
///      Required env vars:
///        PRIVATE_KEY         — Deployer/caller private key
///        FACTORY             — CanonicalFactory address on this chain
///        ORIGIN_CONTRACT     — RWA contract address on source chain
///        ORIGIN_CHAIN_ID     — Source chain ID
///        TARGET_CHAIN_ID     — This chain's ID
///        NAV_ROOT            — Merkle root of NAV attestation
///        COMPLIANCE_ROOT     — Merkle root of compliance data
///        LOCKED_AMOUNT       — Amount locked on source chain (wei)
///        NONCE               — Attestation nonce
///        SIGNATURES          — Packed threshold signatures (hex)
///        SIGNER_BITMAP       — Bitmap of signing signers
contract DeployMirror is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address factoryAddr = vm.envAddress("FACTORY");

        // Build attestation from environment
        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: vm.envAddress("ORIGIN_CONTRACT"),
            originChainId: vm.envUint("ORIGIN_CHAIN_ID"),
            targetChainId: vm.envUint("TARGET_CHAIN_ID"),
            navRoot: vm.envBytes32("NAV_ROOT"),
            complianceRoot: vm.envBytes32("COMPLIANCE_ROOT"),
            lockedAmount: vm.envUint("LOCKED_AMOUNT"),
            timestamp: block.timestamp,
            nonce: vm.envUint("NONCE")
        });

        bytes memory signatures = vm.envBytes("SIGNATURES");
        uint256 bitmap = vm.envUint("SIGNER_BITMAP");

        CanonicalFactory factory = CanonicalFactory(factoryAddr);

        // Predict the mirror address
        address predicted = factory.computeMirrorAddress(att);
        console.log("=== Deploy Mirror ===");
        console.log("Origin:", att.originContract);
        console.log("Origin Chain:", att.originChainId);
        console.log("Target Chain:", att.targetChainId);
        console.log("Predicted Address:", predicted);

        vm.startBroadcast(deployerKey);

        address mirror = factory.deployMirror(att, signatures, bitmap);

        vm.stopBroadcast();

        console.log("Mirror Deployed:", mirror);
        console.log("Canonical:", factory.isCanonical(mirror));

        // Verify metadata
        XythumToken token = XythumToken(mirror);
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
    }
}
