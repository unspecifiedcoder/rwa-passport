// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {SignerRegistry} from "../../src/core/SignerRegistry.sol";
import {AttestationRegistry} from "../../src/core/AttestationRegistry.sol";
import {AttestationLib} from "../../src/libraries/AttestationLib.sol";
import {IAttestationVerifier} from "../../src/interfaces/IAttestationVerifier.sol";
import {AttestationHelper} from "../helpers/AttestationHelper.sol";
import {TestConstants} from "../helpers/TestConstants.sol";

/// @title AttestationRegistryTest
/// @notice Unit tests for the AttestationRegistry contract
contract AttestationRegistryTest is Test {
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    AttestationHelper public helper;

    // Default attestation params
    address public constant ORIGIN_CONTRACT = address(0xAAAA);
    uint256 public constant ORIGIN_CHAIN = 1;
    uint256 public constant TARGET_CHAIN = 42161;

    uint256 public constant MAX_STALENESS = 24 hours;
    uint256 public constant RATE_LIMIT = 1 hours;
    uint256 public constant THRESHOLD = 3;
    uint256 public constant SIGNER_COUNT = 5;

    function setUp() public {
        // Deploy signer registry (this contract is the owner)
        signerRegistry = new SignerRegistry(address(this), THRESHOLD);

        // Create helper and generate signer keys
        helper = new AttestationHelper();
        helper.generateSigners(SIGNER_COUNT);

        // Register signers from the owner (this contract)
        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }

        // Deploy attestation registry
        attestationRegistry = new AttestationRegistry(
            address(signerRegistry),
            MAX_STALENESS,
            RATE_LIMIT
        );
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    function _buildDefaultAttestation(uint256 nonce)
        internal view returns (AttestationLib.Attestation memory)
    {
        return helper.buildAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, nonce);
    }

    function _signWithSigners(
        AttestationLib.Attestation memory att,
        uint256[] memory indices
    ) internal view returns (bytes memory signatures, uint256 bitmap) {
        return helper.signAttestation(att, attestationRegistry.DOMAIN_SEPARATOR(), indices);
    }

    function _thresholdIndices() internal pure returns (uint256[] memory) {
        uint256[] memory indices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            indices[i] = i;
        }
        return indices;
    }

    function _allIndices() internal pure returns (uint256[] memory) {
        uint256[] memory indices = new uint256[](SIGNER_COUNT);
        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            indices[i] = i;
        }
        return indices;
    }

    // ─── verifyAttestation ───────────────────────────────────────────

    function test_verifyAttestation_valid_threshold_signatures() public {
        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _thresholdIndices());

        bytes32 attId = attestationRegistry.verifyAttestation(att, sigs, bitmap);

        // Verify stored correctly
        AttestationLib.Attestation memory stored = attestationRegistry.getAttestation(attId);
        assertEq(stored.originContract, att.originContract);
        assertEq(stored.originChainId, att.originChainId);
        assertEq(stored.targetChainId, att.targetChainId);
        assertEq(stored.nonce, att.nonce);
        assertEq(stored.timestamp, att.timestamp);
        assertEq(stored.lockedAmount, att.lockedAmount);
    }

    function test_verifyAttestation_all_signers_sign() public {
        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _allIndices());

        bytes32 attId = attestationRegistry.verifyAttestation(att, sigs, bitmap);
        assertTrue(attId != bytes32(0));
    }

    function test_verifyAttestation_insufficient_signatures_reverts() public {
        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);

        // Sign with only 2 (below threshold of 3)
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, indices);

        vm.expectRevert(
            abi.encodeWithSelector(
                AttestationRegistry.InsufficientSignatures.selector, 2, THRESHOLD
            )
        );
        attestationRegistry.verifyAttestation(att, sigs, bitmap);
    }

    function test_verifyAttestation_invalid_signature_reverts() public {
        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);

        // Sign with threshold signers but tamper with one signature
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _thresholdIndices());

        // Corrupt the first signature's last byte (v value)
        bytes memory corruptedSigs = sigs;
        corruptedSigs[64] = corruptedSigs[64] == bytes1(0x1b) ? bytes1(0x1c) : bytes1(0x1b);

        vm.expectRevert(); // Will revert with InvalidSignature or ECDSA error
        attestationRegistry.verifyAttestation(att, corruptedSigs, bitmap);
    }

    function test_verifyAttestation_expired_timestamp_reverts() public {
        // Warp to a reasonable timestamp first to avoid underflow
        vm.warp(100_000);

        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);
        att.timestamp = block.timestamp - 25 hours; // Older than MAX_STALENESS

        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _thresholdIndices());

        vm.expectRevert(
            abi.encodeWithSelector(
                AttestationRegistry.AttestationExpired.selector, att.timestamp, MAX_STALENESS
            )
        );
        attestationRegistry.verifyAttestation(att, sigs, bitmap);
    }

    function test_verifyAttestation_rate_limited_reverts() public {
        // Submit first attestation
        AttestationLib.Attestation memory att1 = _buildDefaultAttestation(1);
        (bytes memory sigs1, uint256 bitmap1) = _signWithSigners(att1, _thresholdIndices());
        attestationRegistry.verifyAttestation(att1, sigs1, bitmap1);

        // Try to submit another for the same pair immediately
        AttestationLib.Attestation memory att2 = _buildDefaultAttestation(2);
        (bytes memory sigs2, uint256 bitmap2) = _signWithSigners(att2, _thresholdIndices());

        bytes32 _pairKey = AttestationLib.pairKey(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttestationRegistry.RateLimited.selector,
                _pairKey,
                block.timestamp + RATE_LIMIT
            )
        );
        attestationRegistry.verifyAttestation(att2, sigs2, bitmap2);
    }

    function test_verifyAttestation_rate_limit_expires() public {
        // Submit first attestation
        AttestationLib.Attestation memory att1 = _buildDefaultAttestation(1);
        (bytes memory sigs1, uint256 bitmap1) = _signWithSigners(att1, _thresholdIndices());
        attestationRegistry.verifyAttestation(att1, sigs1, bitmap1);

        // Warp past rate limit
        vm.warp(block.timestamp + RATE_LIMIT + 1);

        // Submit second — should succeed
        AttestationLib.Attestation memory att2 = _buildDefaultAttestation(2);
        (bytes memory sigs2, uint256 bitmap2) = _signWithSigners(att2, _thresholdIndices());

        bytes32 attId2 = attestationRegistry.verifyAttestation(att2, sigs2, bitmap2);
        assertTrue(attId2 != bytes32(0));
    }

    function test_verifyAttestation_duplicate_reverts() public {
        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _thresholdIndices());

        attestationRegistry.verifyAttestation(att, sigs, bitmap);

        // Warp past rate limit but same nonce
        vm.warp(block.timestamp + RATE_LIMIT + 1);

        bytes32 attId = AttestationLib.attestationId(att);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttestationRegistry.AttestationAlreadyExists.selector, attId
            )
        );
        attestationRegistry.verifyAttestation(att, sigs, bitmap);
    }

    function test_verifyAttestation_different_nonce_succeeds() public {
        // Submit nonce=1
        AttestationLib.Attestation memory att1 = _buildDefaultAttestation(1);
        (bytes memory sigs1, uint256 bitmap1) = _signWithSigners(att1, _thresholdIndices());
        attestationRegistry.verifyAttestation(att1, sigs1, bitmap1);

        // Warp past rate limit
        vm.warp(block.timestamp + RATE_LIMIT + 1);

        // Submit nonce=2 — should succeed
        AttestationLib.Attestation memory att2 = _buildDefaultAttestation(2);
        (bytes memory sigs2, uint256 bitmap2) = _signWithSigners(att2, _thresholdIndices());

        bytes32 attId2 = attestationRegistry.verifyAttestation(att2, sigs2, bitmap2);
        assertTrue(attId2 != bytes32(0));
    }

    // ─── getAttestation ──────────────────────────────────────────────

    function test_getAttestation_returns_stored_data() public {
        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _thresholdIndices());

        bytes32 attId = attestationRegistry.verifyAttestation(att, sigs, bitmap);

        AttestationLib.Attestation memory stored = attestationRegistry.getAttestation(attId);
        assertEq(stored.originContract, ORIGIN_CONTRACT);
        assertEq(stored.originChainId, ORIGIN_CHAIN);
        assertEq(stored.targetChainId, TARGET_CHAIN);
        assertEq(stored.nonce, 1);
        assertEq(stored.navRoot, att.navRoot);
        assertEq(stored.complianceRoot, att.complianceRoot);
        assertEq(stored.lockedAmount, att.lockedAmount);
    }

    function test_getAttestation_not_found_reverts() public {
        bytes32 fakeId = keccak256("nonexistent");
        vm.expectRevert(
            abi.encodeWithSelector(
                AttestationRegistry.AttestationNotFound.selector, fakeId
            )
        );
        attestationRegistry.getAttestation(fakeId);
    }

    // ─── isAttested ──────────────────────────────────────────────────

    function test_isAttested_true_after_verification() public {
        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _thresholdIndices());
        attestationRegistry.verifyAttestation(att, sigs, bitmap);

        assertTrue(attestationRegistry.isAttested(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN));
    }

    function test_isAttested_false_before_verification() public view {
        assertFalse(attestationRegistry.isAttested(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN));
    }

    // ─── getLatestAttestation ────────────────────────────────────────

    function test_getLatestAttestation_updates_on_new() public {
        // Submit nonce=1
        AttestationLib.Attestation memory att1 = _buildDefaultAttestation(1);
        (bytes memory sigs1, uint256 bitmap1) = _signWithSigners(att1, _thresholdIndices());
        bytes32 attId1 = attestationRegistry.verifyAttestation(att1, sigs1, bitmap1);

        assertEq(
            attestationRegistry.getLatestAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN),
            attId1
        );

        // Warp past rate limit, submit nonce=2
        vm.warp(block.timestamp + RATE_LIMIT + 1);

        AttestationLib.Attestation memory att2 = _buildDefaultAttestation(2);
        (bytes memory sigs2, uint256 bitmap2) = _signWithSigners(att2, _thresholdIndices());
        bytes32 attId2 = attestationRegistry.verifyAttestation(att2, sigs2, bitmap2);

        assertEq(
            attestationRegistry.getLatestAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN),
            attId2
        );
    }

    // ─── EIP-712 Digest ──────────────────────────────────────────────

    function test_eip712_digest_matches_manual_computation() public view {
        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);

        // Compute digest manually
        bytes32 structHash = AttestationLib.hash(att);
        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        bytes32 expectedDigest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));

        // Compute via library
        bytes32 libraryDigest = AttestationLib.toTypedDataHash(att, domainSep);

        assertEq(libraryDigest, expectedDigest);
    }

    // ─── Event Emission ──────────────────────────────────────────────

    function test_verifyAttestation_emits_event() public {
        AttestationLib.Attestation memory att = _buildDefaultAttestation(1);
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _thresholdIndices());

        bytes32 expectedId = AttestationLib.attestationId(att);

        vm.expectEmit(true, true, false, true);
        emit IAttestationVerifier.AttestationVerified(
            expectedId,
            ORIGIN_CONTRACT,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            att.timestamp
        );

        attestationRegistry.verifyAttestation(att, sigs, bitmap);
    }

    // ─── submitAttestation Tests ─────────────────────────────────────

    function test_submitAttestation_succeeds() public {
        // Build attestation with targetChainId = block.chainid
        AttestationLib.Attestation memory att = helper.buildAttestation(
            ORIGIN_CONTRACT, ORIGIN_CHAIN, block.chainid, 1
        );
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _thresholdIndices());

        bytes32 attId = attestationRegistry.submitAttestation(att, sigs, bitmap);

        assertTrue(attId != bytes32(0), "Should return valid attestation ID");

        // Verify stored correctly
        AttestationLib.Attestation memory stored = attestationRegistry.getAttestation(attId);
        assertEq(stored.originContract, ORIGIN_CONTRACT);
        assertEq(stored.targetChainId, block.chainid);
    }

    function test_submitAttestation_wrong_chain_reverts() public {
        // Build attestation with wrong targetChainId
        AttestationLib.Attestation memory att = helper.buildAttestation(
            ORIGIN_CONTRACT, ORIGIN_CHAIN, 999, 1
        );
        (bytes memory sigs, uint256 bitmap) = _signWithSigners(att, _thresholdIndices());

        vm.expectRevert(
            abi.encodeWithSelector(
                AttestationRegistry.WrongTargetChain.selector, 999, block.chainid
            )
        );
        attestationRegistry.submitAttestation(att, sigs, bitmap);
    }

    function test_submitAttestation_same_verification_as_verifyAttestation() public {
        // Build two identical attestations targeting this chain
        AttestationLib.Attestation memory att1 = helper.buildAttestation(
            ORIGIN_CONTRACT, ORIGIN_CHAIN, block.chainid, 1
        );
        (bytes memory sigs1, uint256 bitmap1) = _signWithSigners(att1, _thresholdIndices());

        // Pre-compute the expected attestation ID (both paths should produce the same one)
        bytes32 expectedId = AttestationLib.attestationId(att1);

        // Submit via submitAttestation
        bytes32 attId = attestationRegistry.submitAttestation(att1, sigs1, bitmap1);

        assertEq(attId, expectedId, "submitAttestation should produce same ID as attestationId()");

        // Verify it's stored — trying again should revert with AttestationAlreadyExists
        vm.warp(block.timestamp + RATE_LIMIT + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttestationRegistry.AttestationAlreadyExists.selector, expectedId
            )
        );
        attestationRegistry.submitAttestation(att1, sigs1, bitmap1);
    }
}
