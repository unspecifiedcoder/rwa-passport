// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { SignerSlashingCourt } from "../../src/security/SignerSlashingCourt.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { StakingModule } from "../../src/staking/StakingModule.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { AttestationHelper } from "../helpers/AttestationHelper.sol";

/// @title SignerSlashingCourt Unit Tests
/// @notice Tests for cryptographic evidence of signer misbehavior → automated slashing
contract SignerSlashingCourtTest is Test {
    SignerSlashingCourt public court;
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    StakingModule public staking;
    ProtocolToken public token;
    AttestationHelper public helper;

    address public owner;
    address public insuranceFund = makeAddr("insuranceFund");
    address public reporter = makeAddr("reporter");
    address public treasury = makeAddr("treasury");

    uint256 public constant NUM_SIGNERS = 5;
    uint256 public constant THRESHOLD = 3;
    uint256 public constant INITIAL_MINT = 100_000_000 ether;
    uint256 public constant STAKE_AMOUNT = 50_000 ether;

    function setUp() public {
        owner = address(this);
        vm.warp(100_000);

        // 1. Deploy XYT + staking
        token = new ProtocolToken(owner, INITIAL_MINT, treasury);
        staking = new StakingModule(address(token), insuranceFund, owner);
        token.setMinter(address(staking), true);
        token.setTransferLimitExempt(address(staking), true);

        // 2. Deploy signer + attestation registries
        signerRegistry = new SignerRegistry(owner, THRESHOLD);
        attestationRegistry = new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);

        // 3. Generate signer keypairs via helper
        helper = new AttestationHelper();
        helper.generateSigners(NUM_SIGNERS);

        // 4. Fund signers with XYT and stake on their behalf (test shortcut)
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            address signer = helper.getSignerAddress(i);
            vm.prank(treasury);
            token.transfer(signer, STAKE_AMOUNT);
            vm.prank(signer);
            token.approve(address(staking), type(uint256).max);
            vm.prank(signer);
            staking.stake(STAKE_AMOUNT, 0);
        }

        // 5. Register signers
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }

        // 6. Deploy slashing court + authorize it as slasher
        court = new SignerSlashingCourt(
            address(signerRegistry), address(staking), attestationRegistry.DOMAIN_SEPARATOR(), owner
        );
        staking.setSlasher(address(court), true);
    }

    // ─── Helper Functions ────────────────────────────────────────────

    function _buildAndSign(
        address origin,
        uint256 originChain,
        uint256 targetChain,
        uint256 nonce,
        uint256 signerIdx,
        bytes32 navRoot
    ) internal view returns (AttestationLib.Attestation memory att, bytes memory sig) {
        att = AttestationLib.Attestation({
            originContract: origin,
            originChainId: originChain,
            targetChainId: targetChain,
            navRoot: navRoot,
            complianceRoot: keccak256(abi.encodePacked("compliance", nonce)),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp,
            nonce: nonce
        });

        bytes32 digest = AttestationLib.toTypedDataHash(att, attestationRegistry.DOMAIN_SEPARATOR());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(helper.signerKeys(signerIdx), digest);
        sig = abi.encodePacked(r, s, v);
    }

    // ─── Double-Signing Tests ────────────────────────────────────────

    function test_doubleSigning_slashes_signer() public {
        // Signer 0 signs two attestations with same nonce but different navRoot
        address signer = helper.getSignerAddress(0);
        address origin = address(0xAAA);

        (AttestationLib.Attestation memory att1, bytes memory sig1) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x111)));
        (AttestationLib.Attestation memory att2, bytes memory sig2) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x222)));

        uint256 stakeBefore = staking.stakedBalance(signer);
        uint256 insuranceBefore = token.balanceOf(insuranceFund);

        vm.prank(reporter);
        court.submitDoubleSigningEvidence(att1, sig1, att2, sig2, signer);

        // Verify slashing occurred
        assertEq(staking.stakedBalance(signer), stakeBefore - court.doubleSignSlashAmount());
        assertEq(token.balanceOf(insuranceFund), insuranceBefore + court.doubleSignSlashAmount());
        assertEq(court.slashingCount(signer), 1);
        assertTrue(court.hasBeenSlashed(signer));
    }

    function test_doubleSigning_identicalAttestationsRevert() public {
        address signer = helper.getSignerAddress(0);
        address origin = address(0xAAA);

        (AttestationLib.Attestation memory att1, bytes memory sig1) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x111)));

        // Submit the same attestation twice — not double-signing
        vm.prank(reporter);
        vm.expectRevert(SignerSlashingCourt.AttestationsIdentical.selector);
        court.submitDoubleSigningEvidence(att1, sig1, att1, sig1, signer);
    }

    function test_doubleSigning_differentNonceReverts() public {
        // Different nonces = not the same attestationId = invalid evidence type
        address signer = helper.getSignerAddress(0);
        address origin = address(0xAAA);

        (AttestationLib.Attestation memory att1, bytes memory sig1) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x111)));
        (AttestationLib.Attestation memory att2, bytes memory sig2) =
            _buildAndSign(origin, 1, block.chainid, 2, 0, bytes32(uint256(0x222)));

        vm.prank(reporter);
        vm.expectRevert(SignerSlashingCourt.InvalidEvidenceType.selector);
        court.submitDoubleSigningEvidence(att1, sig1, att2, sig2, signer);
    }

    function test_doubleSigning_wrongSignerReverts() public {
        address signer0 = helper.getSignerAddress(0);
        address signer1 = helper.getSignerAddress(1);
        address origin = address(0xAAA);

        (AttestationLib.Attestation memory att1, bytes memory sig1) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x111)));
        (AttestationLib.Attestation memory att2, bytes memory sig2) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x222)));

        // Claim signer1 signed it, but actually signer0 did
        vm.prank(reporter);
        vm.expectRevert();
        court.submitDoubleSigningEvidence(att1, sig1, att2, sig2, signer1);
    }

    function test_doubleSigning_unregisteredSignerReverts() public {
        address unregistered = makeAddr("unregistered");
        address origin = address(0xAAA);

        (AttestationLib.Attestation memory att1, bytes memory sig1) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x111)));
        (AttestationLib.Attestation memory att2, bytes memory sig2) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x222)));

        vm.prank(reporter);
        vm.expectRevert(
            abi.encodeWithSelector(SignerSlashingCourt.SignerNotRegistered.selector, unregistered)
        );
        court.submitDoubleSigningEvidence(att1, sig1, att2, sig2, unregistered);
    }

    function test_doubleSigning_duplicateEvidenceReverts() public {
        address signer = helper.getSignerAddress(0);
        address origin = address(0xAAA);

        (AttestationLib.Attestation memory att1, bytes memory sig1) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x111)));
        (AttestationLib.Attestation memory att2, bytes memory sig2) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x222)));

        vm.prank(reporter);
        court.submitDoubleSigningEvidence(att1, sig1, att2, sig2, signer);

        // Second submission of same evidence should fail
        vm.prank(reporter);
        vm.expectRevert();
        court.submitDoubleSigningEvidence(att1, sig1, att2, sig2, signer);
    }

    // ─── Conflicting NAV Tests ───────────────────────────────────────

    function test_conflictingNAV_slashes_signer() public {
        address signer = helper.getSignerAddress(0);
        address origin = address(0xBBB);

        // Same pairKey, different nonces, different navRoots
        (AttestationLib.Attestation memory att1, bytes memory sig1) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x111)));
        (AttestationLib.Attestation memory att2, bytes memory sig2) =
            _buildAndSign(origin, 1, block.chainid, 2, 0, bytes32(uint256(0x222)));

        uint256 stakeBefore = staking.stakedBalance(signer);

        vm.prank(reporter);
        court.submitConflictingNAVEvidence(att1, sig1, att2, sig2, signer);

        assertEq(staking.stakedBalance(signer), stakeBefore - court.conflictingNAVSlashAmount());
        assertEq(court.slashingCount(signer), 1);
    }

    function test_conflictingNAV_samePairKeyDifferentContentNoNavChangeReverts() public {
        address signer = helper.getSignerAddress(0);
        address origin = address(0xBBB);

        // Same pairKey + same navRoot = not a conflict
        (AttestationLib.Attestation memory att1, bytes memory sig1) =
            _buildAndSign(origin, 1, block.chainid, 1, 0, bytes32(uint256(0x333)));
        (AttestationLib.Attestation memory att2, bytes memory sig2) =
            _buildAndSign(origin, 1, block.chainid, 2, 0, bytes32(uint256(0x333)));

        vm.prank(reporter);
        vm.expectRevert(SignerSlashingCourt.AttestationsIdentical.selector);
        court.submitConflictingNAVEvidence(att1, sig1, att2, sig2, signer);
    }

    function test_conflictingNAV_differentPairKeyReverts() public {
        address signer = helper.getSignerAddress(0);

        // Different origins = different pairKeys
        (AttestationLib.Attestation memory att1, bytes memory sig1) =
            _buildAndSign(address(0xAAA), 1, block.chainid, 1, 0, bytes32(uint256(0x111)));
        (AttestationLib.Attestation memory att2, bytes memory sig2) =
            _buildAndSign(address(0xBBB), 1, block.chainid, 2, 0, bytes32(uint256(0x222)));

        vm.prank(reporter);
        vm.expectRevert(SignerSlashingCourt.InvalidEvidenceType.selector);
        court.submitConflictingNAVEvidence(att1, sig1, att2, sig2, signer);
    }

    // ─── Admin Tests ─────────────────────────────────────────────────

    function test_setSlashingParameters_updatesValues() public {
        court.setSlashingParameters(20_000 ether, 10_000 ether, 1000);

        assertEq(court.doubleSignSlashAmount(), 20_000 ether);
        assertEq(court.conflictingNAVSlashAmount(), 10_000 ether);
        assertEq(court.reporterBountyBps(), 1000);
    }

    function test_setSlashingParameters_onlyOwner() public {
        vm.prank(reporter);
        vm.expectRevert();
        court.setSlashingParameters(20_000 ether, 10_000 ether, 1000);
    }

    function test_setSlashingParameters_rejectsZero() public {
        vm.expectRevert(SignerSlashingCourt.InvalidSlashAmount.selector);
        court.setSlashingParameters(0, 10_000 ether, 500);
    }
}
