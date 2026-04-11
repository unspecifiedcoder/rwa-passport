// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { CCIPSender } from "../../src/ccip/CCIPSender.sol";
import { XythumCCIPReceiver } from "../../src/ccip/CCIPReceiver.sol";
import { MockCCIPRouter } from "../helpers/MockCCIPRouter.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";
import { MockERC3643 } from "../helpers/MockERC3643.sol";
import { AttestationHelper } from "../helpers/AttestationHelper.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { TestConstants } from "../helpers/TestConstants.sol";

/// @title FullFlowTest
/// @notice End-to-end integration test: request → sign → CCIP send → deploy mirror
///         Validates the ENTIRE attestation → deployment pipeline in a single test.
contract FullFlowTest is Test {
    // ─── Contracts ───────────────────────────────────────────────────
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    CanonicalFactory public factory;
    CCIPSender public ccipSender;
    XythumCCIPReceiver public ccipReceiver;
    MockCCIPRouter public router;
    MockCompliance public compliance;
    MockERC3643 public sourceRWA;
    AttestationHelper public helper;

    // ─── Config ──────────────────────────────────────────────────────
    address public owner;
    address public user;

    uint256 public constant NUM_SIGNERS = 5;
    uint256 public constant THRESHOLD = 3;
    uint64 public constant SOURCE_SELECTOR = 16015286601757825753; // ETH Sepolia
    uint64 public constant TARGET_SELECTOR_ARB = 3478487238524512106; // Arb Sepolia
    uint64 public constant TARGET_SELECTOR_BASE = 10344971235874465080; // Base Sepolia
    uint64 public constant TARGET_SELECTOR_OP = 2664363617261496610; // OP Sepolia

    function setUp() public {
        vm.warp(100_000);

        owner = address(this);
        user = makeAddr("user");
        vm.deal(user, 100 ether);

        // ── Deploy source chain RWA mock ──
        sourceRWA = new MockERC3643();

        // ── Deploy signer infrastructure ──
        signerRegistry = new SignerRegistry(owner, THRESHOLD);
        helper = new AttestationHelper();
        helper.generateSigners(NUM_SIGNERS);
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }

        // ── Deploy attestation registry ──
        attestationRegistry = new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);

        // ── Deploy factory ──
        compliance = new MockCompliance();
        factory = new CanonicalFactory(
            address(attestationRegistry), address(compliance), makeAddr("treasury"), owner
        );

        // ── Deploy CCIP infrastructure ──
        router = new MockCCIPRouter();
        router.setFixedFee(0.01 ether);
        router.setSourceChainSelector(SOURCE_SELECTOR);

        ccipSender = new CCIPSender(address(router), owner);
        ccipReceiver = new XythumCCIPReceiver(address(router), address(factory), owner);

        // ── Wire everything together ──
        // Sender config: support target chains, set receivers
        ccipSender.setSupportedChain(TARGET_SELECTOR_ARB, true);
        ccipSender.setReceiver(TARGET_SELECTOR_ARB, address(ccipReceiver));

        ccipSender.setSupportedChain(TARGET_SELECTOR_BASE, true);
        ccipSender.setReceiver(TARGET_SELECTOR_BASE, address(ccipReceiver));

        ccipSender.setSupportedChain(TARGET_SELECTOR_OP, true);
        ccipSender.setReceiver(TARGET_SELECTOR_OP, address(ccipReceiver));

        // Router config: deliver to receiver
        router.setReceiver(TARGET_SELECTOR_ARB, address(ccipReceiver));
        router.setReceiver(TARGET_SELECTOR_BASE, address(ccipReceiver));
        router.setReceiver(TARGET_SELECTOR_OP, address(ccipReceiver));

        // Receiver config: allow sender from source chain
        ccipReceiver.setAllowedSender(SOURCE_SELECTOR, address(ccipSender), true);
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    /// @notice Build and sign an attestation
    function _buildSignedAttestation(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 nonce
    )
        internal
        view
        returns (AttestationLib.Attestation memory att, bytes memory signatures, uint256 bitmap)
    {
        att = helper.buildAttestation(originContract, originChainId, targetChainId, nonce);

        uint256[] memory signerIndices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            signerIndices[i] = i;
        }

        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (signatures, bitmap) = helper.signAttestation(att, domainSep, signerIndices);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  INTEGRATION TEST: FULL LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Full pipeline: create attestation → collect sigs → CCIP send → deploy mirror
    function test_full_lifecycle() public {
        address origin = address(sourceRWA);
        uint256 originChainId = 11155111; // ETH Sepolia
        uint256 targetChainId = block.chainid;

        // 1. Create attestation
        // 2. Collect 3 threshold signatures
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(origin, originChainId, targetChainId, 1);

        // 3. Compute expected mirror address BEFORE deployment
        address predicted = factory.computeMirrorAddress(att);
        assertTrue(predicted != address(0), "Predicted address should be non-zero");

        // 4. User sends attestation via CCIP
        vm.prank(user);
        bytes32 messageId =
            ccipSender.sendAttestation{ value: 1 ether }(TARGET_SELECTOR_ARB, att, sigs, bitmap);

        // 5-6. MockCCIPRouter delivers to CCIPReceiver → calls factory.deployMirror()
        // (happens atomically in the mock)

        // 7. Verify: mirror deployed at expected address
        assertTrue(predicted.code.length > 0, "Mirror should have code");

        // 8. Verify: factory.isCanonical(mirror) == true
        assertTrue(factory.isCanonical(predicted), "Mirror should be canonical");

        // 9. Verify: XythumToken metadata matches origin
        XythumToken mirror = XythumToken(predicted);
        assertEq(mirror.originContract(), origin, "Origin contract mismatch");
        assertEq(mirror.originChainId(), originChainId, "Origin chain mismatch");
        assertEq(mirror.name(), "Xythum Mirror");
        assertEq(mirror.symbol(), "xRWA");

        // 10. Verify: CCIP message was processed
        assertTrue(ccipReceiver.processedMessages(messageId), "Message should be processed");

        // 11. Verify: user got refund (sent 1 ETH, fee was 0.01 ETH)
        assertGe(user.balance, 99 ether, "User should get refund");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  INTEGRATION TEST: MULTIPLE TARGETS FROM SAME ORIGIN
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Deploy mirrors for 3 different origins on the same target chain
    function test_multiple_origins_to_same_target() public {
        uint256 originChainId = 11155111;
        address origin1 = address(sourceRWA);
        address origin2 = address(0xBEEF);
        address origin3 = address(0xCAFE);

        address mirror1 = _bridgeAndComputeMirror(origin1, originChainId, TARGET_SELECTOR_ARB);
        address mirror2 = _bridgeAndComputeMirror(origin2, originChainId, TARGET_SELECTOR_BASE);
        address mirror3 = _bridgeAndComputeMirror(origin3, originChainId, TARGET_SELECTOR_OP);

        // All 3 are canonical
        assertTrue(factory.isCanonical(mirror1), "Mirror 1 should be canonical");
        assertTrue(factory.isCanonical(mirror2), "Mirror 2 should be canonical");
        assertTrue(factory.isCanonical(mirror3), "Mirror 3 should be canonical");

        // All 3 have different addresses
        assertTrue(mirror1 != mirror2, "Mirrors 1 and 2 should differ");
        assertTrue(mirror2 != mirror3, "Mirrors 2 and 3 should differ");
        assertTrue(mirror1 != mirror3, "Mirrors 1 and 3 should differ");

        // Each points to its own origin
        assertEq(XythumToken(mirror1).originContract(), origin1);
        assertEq(XythumToken(mirror2).originContract(), origin2);
        assertEq(XythumToken(mirror3).originContract(), origin3);
        assertEq(XythumToken(mirror1).originChainId(), originChainId);
        assertEq(XythumToken(mirror2).originChainId(), originChainId);
        assertEq(XythumToken(mirror3).originChainId(), originChainId);
    }

    /// @dev Helper to build attestation, send via CCIP, and return the mirror address
    function _bridgeAndComputeMirror(address origin, uint256 originChainId, uint64 targetSelector)
        internal
        returns (address mirror)
    {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(origin, originChainId, block.chainid, 1);

        vm.prank(user);
        ccipSender.sendAttestation{ value: 1 ether }(targetSelector, att, sigs, bitmap);
        return factory.computeMirrorAddress(att);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  INTEGRATION TEST: SECOND ATTESTATION FOR SAME PAIR
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Second attestation for same origin/target should not revert CCIP message
    function test_second_attestation_for_same_pair() public {
        address origin = address(sourceRWA);
        uint256 originChainId = 11155111;
        uint256 targetChainId = block.chainid;

        // First deployment succeeds
        (AttestationLib.Attestation memory att1, bytes memory sigs1, uint256 bitmap1) =
            _buildSignedAttestation(origin, originChainId, targetChainId, 1);

        vm.prank(user);
        bytes32 msg1 =
            ccipSender.sendAttestation{ value: 1 ether }(TARGET_SELECTOR_ARB, att1, sigs1, bitmap1);
        assertTrue(ccipReceiver.processedMessages(msg1), "First message processed");

        address mirror = factory.computeMirrorAddress(att1);
        assertTrue(factory.isCanonical(mirror), "Mirror should be canonical");

        // Warp past rate limit
        vm.warp(block.timestamp + 1 hours + 1);

        // Second attestation for same pair (nonce=2) — factory will reject (MirrorAlreadyDeployed)
        // But CCIP message should still process (try/catch in receiver)
        (AttestationLib.Attestation memory att2, bytes memory sigs2, uint256 bitmap2) =
            _buildSignedAttestation(origin, originChainId, targetChainId, 2);

        vm.prank(user);
        bytes32 msg2 =
            ccipSender.sendAttestation{ value: 1 ether }(TARGET_SELECTOR_ARB, att2, sigs2, bitmap2);

        // Message was processed (not reverted) even though deploy failed
        assertTrue(ccipReceiver.processedMessages(msg2), "Second message should be processed");

        // Original mirror is still the canonical one
        assertTrue(factory.isCanonical(mirror), "Original mirror still canonical");
    }
}
