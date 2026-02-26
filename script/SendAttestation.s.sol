// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CCIPSender } from "../src/ccip/CCIPSender.sol";
import { AttestationLib } from "../src/libraries/AttestationLib.sol";

/// @title SendAttestation
/// @notice Creates an attestation for MockRWA, signs it with 3 demo signers,
///         and sends it via CCIP from Fuji to BNB Chain Testnet.
/// @dev Run: forge script script/SendAttestation.s.sol --rpc-url fuji --broadcast
contract SendAttestation is Script {
    // Same demo signer keys (must match what's registered in SignerRegistry)
    uint256 constant SIGNER_1_KEY = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_2_KEY = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_3_KEY = uint256(keccak256("xythum-demo-signer-3"));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ccipSenderAddr = vm.envAddress("CCIP_SENDER_FUJI");
        address mockRwaAddr = vm.envAddress("MOCK_RWA_FUJI");
        address attRegBnb = vm.envAddress("ATTESTATION_REGISTRY_BNB");
        uint64 bnbSelector = uint64(vm.envUint("CCIP_SELECTOR_BNB"));

        console.log("=== Sending Cross-Chain Attestation (Fuji -> BNB Testnet) ===");
        console.log("CCIPSender:", ccipSenderAddr);
        console.log("MockRWA:", mockRwaAddr);

        // 1. Build attestation
        AttestationLib.Attestation memory att = _buildAttestation(mockRwaAddr);

        // 2. Sign with all 3 demo signers
        (bytes memory signatures, uint256 signerBitmap) = _signAttestation(att, attRegBnb);

        // 3. Estimate fee
        uint256 fee = _estimateFee(ccipSenderAddr, bnbSelector, att, signatures, signerBitmap);

        // 4. Send via CCIP
        vm.startBroadcast(deployerKey);

        bytes32 messageId = CCIPSender(ccipSenderAddr).sendAttestation{ value: (fee * 120) / 100 }(
            bnbSelector, att, signatures, signerBitmap
        );

        vm.stopBroadcast();

        console.log("=== CCIP Message Sent! ===");
        console.log("Message ID:", vm.toString(messageId));
        console.log("Track at: https://ccip.chain.link");
        console.log("Wait 5-15 min, then run:");
        console.log("  forge script script/VerifyMirror.s.sol --rpc-url bnb_testnet");
    }

    function _buildAttestation(address mockRwa)
        internal
        view
        returns (AttestationLib.Attestation memory)
    {
        return AttestationLib.Attestation({
            originContract: mockRwa,
            originChainId: 43113, // Avalanche Fuji
            targetChainId: 97, // BNB Chain Testnet
            navRoot: keccak256("demo-nav-data"),
            complianceRoot: keccak256("demo-compliance"),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp,
            nonce: 2
        });
    }

    function _signAttestation(AttestationLib.Attestation memory att, address attRegBnb)
        internal
        returns (bytes memory signatures, uint256 signerBitmap)
    {
        // Compute EIP-712 digest for the TARGET chain (BNB Testnet, chainId=97)
        bytes32 domainSep = AttestationLib.domainSeparator(97, attRegBnb);
        bytes32 digest = AttestationLib.toTypedDataHash(att, domainSep);

        // Sign in REGISTRATION ORDER (must match SignerRegistry indices)
        // Index 0 = SIGNER_1_KEY, Index 1 = SIGNER_2_KEY, Index 2 = SIGNER_3_KEY
        uint256[3] memory keys;
        keys[0] = SIGNER_1_KEY;
        keys[1] = SIGNER_2_KEY;
        keys[2] = SIGNER_3_KEY;

        for (uint256 i = 0; i < 3; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            signatures = abi.encodePacked(signatures, r, s, v);
            signerBitmap |= (1 << i);
            console.log("  Signed by:", vm.addr(keys[i]));
        }

        console.log("Bitmap:", signerBitmap);
    }

    function _estimateFee(
        address ccipSenderAddr,
        uint64 bnbSelector,
        AttestationLib.Attestation memory att,
        bytes memory signatures,
        uint256 signerBitmap
    ) internal view returns (uint256 fee) {
        bytes memory payload = abi.encode(
            uint8(1), // MESSAGE_TYPE_DEPLOY
            abi.encode(att),
            signatures,
            signerBitmap
        );
        fee = CCIPSender(ccipSenderAddr).estimateFee(bnbSelector, payload);
        console.log("CCIP fee:", fee, "wei");
    }
}
