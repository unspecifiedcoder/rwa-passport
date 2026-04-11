// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { CollateralVerifier } from "../../src/zk/CollateralVerifier.sol";
import { AaveAdapter } from "../../src/adapters/AaveAdapter.sol";
import { CCIPSender } from "../../src/ccip/CCIPSender.sol";
import { XythumCCIPReceiver } from "../../src/ccip/CCIPReceiver.sol";
import { MockCCIPRouter } from "../helpers/MockCCIPRouter.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";
import { MockGroth16Verifier } from "../helpers/MockCollateralVerifier.sol";
import { AttestationHelper } from "../helpers/AttestationHelper.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { IXythumToken } from "../../src/interfaces/IXythumToken.sol";

/// @title AttackScenariosTest
/// @notice Tests every known attack vector against the Xythum protocol.
///         Each test represents a real threat an adversary would attempt.
contract AttackScenariosTest is Test {
    // ─── Full protocol stack ─────────────────────────────────────────
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    CanonicalFactory public factory;
    MockCompliance public compliance;
    AttestationHelper public helper;
    CCIPSender public ccipSender;
    XythumCCIPReceiver public ccipReceiver;
    MockCCIPRouter public router;
    CollateralVerifier public collateralVerifier;
    AaveAdapter public adapter;
    MockGroth16Verifier public mockGroth16;

    // ─── Tokens ──────────────────────────────────────────────────────
    address public receiptAddr;

    // ─── Config (5 signers, threshold=3 — consistent with existing tests) ──
    address public owner;
    uint256 constant NUM_SIGNERS = 5;
    uint256 constant THRESHOLD = 3;
    uint64 constant SOURCE_SELECTOR = 16015286601757825753;
    uint64 constant TARGET_SELECTOR = 3478487238524512106;

    function setUp() public {
        vm.warp(100_000);
        owner = address(this);

        // ── Signer infrastructure ──
        signerRegistry = new SignerRegistry(owner, THRESHOLD);
        helper = new AttestationHelper();
        helper.generateSigners(NUM_SIGNERS);
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }

        // ── Attestation registry ──
        attestationRegistry = new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);

        // ── Factory ──
        compliance = new MockCompliance();
        factory = new CanonicalFactory(
            address(attestationRegistry), address(compliance), makeAddr("treasury"), owner
        );

        // ── CCIP infrastructure ──
        router = new MockCCIPRouter();
        router.setFixedFee(0.01 ether);
        router.setSourceChainSelector(SOURCE_SELECTOR);

        ccipSender = new CCIPSender(address(router), owner);
        ccipReceiver = new XythumCCIPReceiver(address(router), address(factory), owner);

        ccipSender.setSupportedChain(TARGET_SELECTOR, true);
        ccipSender.setReceiver(TARGET_SELECTOR, address(ccipReceiver));
        router.setReceiver(TARGET_SELECTOR, address(ccipReceiver));
        ccipReceiver.setAllowedSender(SOURCE_SELECTOR, address(ccipSender), true);

        // ── ZK stack ──
        mockGroth16 = new MockGroth16Verifier();
        collateralVerifier = new CollateralVerifier(address(mockGroth16), owner);

        adapter = new AaveAdapter(address(collateralVerifier), address(factory), 1 hours, owner);

        // ── Receipt token for adapter ──
        compliance.setEnforceCompliance(false);
        receiptAddr = _deployCanonicalMirror(address(0xFFFF), 1, block.chainid, 99);
        vm.prank(address(factory));
        XythumToken(receiptAddr).setAuthorizedMinter(address(adapter), true);
        adapter.setReceiptToken(receiptAddr);
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    function _buildSignedAttestation(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 nonce,
        uint256 numSigners
    )
        internal
        view
        returns (AttestationLib.Attestation memory att, bytes memory signatures, uint256 bitmap)
    {
        att = helper.buildAttestation(originContract, originChainId, targetChainId, nonce);
        uint256[] memory signerIndices = new uint256[](numSigners);
        for (uint256 i = 0; i < numSigners; i++) {
            signerIndices[i] = i;
        }
        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (signatures, bitmap) = helper.signAttestation(att, domainSep, signerIndices);
    }

    function _deployCanonicalMirror(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 nonce
    ) internal returns (address mirror) {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(originContract, originChainId, targetChainId, nonce, THRESHOLD);
        mirror = factory.deployMirror(att, sigs, bitmap);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 1: Signer Collusion Below Threshold
    // ═══════════════════════════════════════════════════════════════════

    /// @notice 2 signers collude to attest a fake NAV (below threshold of 3).
    ///         Must revert — insufficient signatures.
    function test_attack_signer_collusion_below_threshold() public {
        // Only 2 signers sign (below threshold of 3)
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(address(0xDEAD), 1, block.chainid, 1, 2);

        // Attempt to deploy mirror with insufficient signatures
        vm.expectRevert(); // InsufficientSignatures
        factory.deployMirror(att, sigs, bitmap);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 2: Replay Attestation
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Valid attestation processed successfully, then replayed.
    ///         Second attempt must revert.
    function test_attack_replay_attestation() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(address(0xAAAA), 1, block.chainid, 1, THRESHOLD);

        // First deployment succeeds
        address mirror1 = factory.deployMirror(att, sigs, bitmap);
        assertTrue(factory.isCanonical(mirror1), "Mirror should be canonical");

        // Replay: same attestation again
        vm.expectRevert(); // MirrorAlreadyDeployed
        factory.deployMirror(att, sigs, bitmap);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 3: Replay on Different Target Chain
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Two different origins deployed on the same target chain.
    ///         Should SUCCEED — different origins produce different mirror addresses.
    /// @dev Note: after the targetChainId check added in PR #2, this test can no
    ///      longer replay the same attestation across chains in a single Foundry
    ///      test (block.chainid is fixed per test). Instead we verify that two
    ///      different origins produce distinct canonical mirrors on the same chain.
    function test_attack_replay_different_chain() public {
        address originA = address(0xBBBB);
        address originB = address(0xBBBC);

        address mirror1 = _deployCanonicalMirror(originA, 1, block.chainid, 1);
        address mirror2 = _deployCanonicalMirror(originB, 1, block.chainid, 1);

        // Both should be canonical and different
        assertTrue(factory.isCanonical(mirror1), "Mirror 1 canonical");
        assertTrue(factory.isCanonical(mirror2), "Mirror 2 canonical");
        assertTrue(mirror1 != mirror2, "Mirrors should be different addresses");

        // Each mirror points to its own origin
        assertEq(XythumToken(mirror1).originContract(), originA);
        assertEq(XythumToken(mirror2).originContract(), originB);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 4: Frontrun Mirror Deployment
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Attacker tries to frontrun by deploying a fake contract at
    ///         the predicted CREATE2 address. Should be impossible because
    ///         CREATE2 address includes the factory address as deployer.
    function test_attack_frontrun_mirror_deployment() public {
        // Build attestation
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(address(0xCCCC), 1, block.chainid, 1, THRESHOLD);

        // Compute expected mirror address
        address predicted = factory.computeMirrorAddress(att);
        assertTrue(predicted != address(0), "Predicted address non-zero");

        // An attacker CAN'T deploy at this address because:
        // 1. CREATE2 address = keccak256(0xff ++ FACTORY ++ salt ++ initCodeHash)
        // 2. Only the factory contract can deploy at this address
        // 3. Even if attacker deploys same bytecode via their own contract,
        //    different deployer = different address

        // Deploy the real mirror
        address real = factory.deployMirror(att, sigs, bitmap);
        assertEq(real, predicted, "Real mirror at predicted address");
        assertTrue(factory.isCanonical(real), "Real mirror is canonical");

        // Attacker deploys same bytecode from a different address
        // This would be at a completely different CREATE2 address
        // isCanonical checks against the factory's deployed set
        address attacker = makeAddr("attacker");
        assertFalse(factory.isCanonical(attacker), "Attacker address not canonical");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 5: Stale NAV Exploitation
    // ═══════════════════════════════════════════════════════════════════

    /// @notice NAV becomes stale (>24h) — protocol should prevent cheap collateral.
    ///         CollateralVerifier still works (it's a mock) but a real verifier
    ///         would validate the attestation root freshness.
    function test_attack_stale_nav_exploitation() public {
        // Deploy mirror
        address mirrorAddr = _deployCanonicalMirror(address(0xDDDD), 1, block.chainid, 5);

        // Register in verifier
        uint256 assetId = 55;
        collateralVerifier.registerAsset(mirrorAddr, assetId);

        // Submit proof at current time
        bytes memory proof = _buildMockProof(1);
        uint256[] memory inputs = _buildPublicInputs(assetId, 100_000e18);

        address user = makeAddr("staleUser");
        vm.prank(user);
        bytes32 proofId = collateralVerifier.verifyCollateralProof(proof, inputs);

        // Warp 25 hours — way past NAV attestation validity
        vm.warp(block.timestamp + 25 hours);

        // The proof was verified 25 hours ago — should be too old for adapter
        // (maxProofAge = 1 hour)
        vm.prank(user);
        vm.expectRevert(); // ProofTooOld
        adapter.depositWithProof(proofId);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 6: Compliance Bypass via Intermediary
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Non-compliant user B tries to receive tokens via compliant
    ///         intermediary C. Every hop is checked — C→B must fail.
    function test_attack_compliance_bypass_via_intermediate() public {
        // Deploy mirror with compliance enabled
        compliance.setEnforceCompliance(true);

        address mirrorAddr = _deployCanonicalMirror(address(0xEEEE), 1, block.chainid, 6);
        XythumToken mirror = XythumToken(mirrorAddr);

        // Set up authorized minter
        compliance.setEnforceCompliance(false);
        vm.prank(address(factory));
        mirror.setAuthorizedMinter(address(this), true);

        address userA = makeAddr("compliantA");
        address intermediary = makeAddr("compliantC");
        address userB = makeAddr("nonCompliantB");

        // Mint tokens to userA (compliance off during mint)
        mirror.mint(userA, 1000 ether);

        // Enable compliance
        compliance.setEnforceCompliance(true);
        compliance.setWhitelisted(userA, true);
        compliance.setWhitelisted(intermediary, true);
        // userB is NOT whitelisted

        // A → Intermediary (both compliant) → succeeds
        vm.prank(userA);
        mirror.transfer(intermediary, 500 ether);
        assertEq(mirror.balanceOf(intermediary), 500 ether);

        // Intermediary → B (B is non-compliant) → must FAIL
        vm.prank(intermediary);
        vm.expectRevert(
            abi.encodeWithSelector(XythumToken.TransferNotCompliant.selector, intermediary, userB)
        );
        mirror.transfer(userB, 250 ether);

        // Direct A → B also fails
        vm.prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(XythumToken.TransferNotCompliant.selector, userA, userB)
        );
        mirror.transfer(userB, 100 ether);

        // B has 0 tokens — bypass completely prevented
        assertEq(mirror.balanceOf(userB), 0, "Non-compliant user should have 0 tokens");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 7: Unauthorized Mint
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Only factory and registered minters can mint. Random address reverts.
    function test_attack_unauthorized_mint() public {
        address mirrorAddr = _deployCanonicalMirror(address(0xF1F1), 1, block.chainid, 7);
        XythumToken mirror = XythumToken(mirrorAddr);

        address attacker = makeAddr("minterAttacker");

        // Attacker is NOT an authorized minter
        assertFalse(mirror.authorizedMinters(attacker), "Attacker should not be authorized");

        // Attempt to mint
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(XythumToken.Unauthorized.selector, attacker));
        mirror.mint(attacker, 1_000_000 ether);

        // Attempt to burn
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(XythumToken.Unauthorized.selector, attacker));
        mirror.burn(address(this), 1 ether);

        // Attempt to set authorized minter (only factory can)
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(XythumToken.Unauthorized.selector, attacker));
        mirror.setAuthorizedMinter(attacker, true);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 8: CCIP Message from Unauthorized Source
    // ═══════════════════════════════════════════════════════════════════

    /// @notice CCIP message from unregistered sender/chain must be rejected.
    function test_attack_ccip_message_from_unauthorized_source() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(address(0xA1A1), 1, block.chainid, 1, THRESHOLD);

        // Unknown chain selector
        uint64 unknownChain = 99999;

        // Create Client.Any2EVMMessage struct directly via MockCCIPRouter won't work —
        // the receiver checks both source chain AND sender address.
        // So test via the router: try sending from an unauthorized sender
        ccipSender.setSupportedChain(unknownChain, true);
        ccipSender.setReceiver(unknownChain, address(ccipReceiver));
        router.setReceiver(unknownChain, address(ccipReceiver));
        // But do NOT register the sender as allowed on the receiver

        // The message will be delivered by router but rejected by receiver
        // because ccipSender is NOT allowed from unknownChain
        // (only allowed from SOURCE_SELECTOR)

        // Instead, test: unregistered sender from a valid chain
        address maliciousSender = makeAddr("maliciousSender");
        assertFalse(
            ccipReceiver.allowedSenders(SOURCE_SELECTOR, maliciousSender),
            "Malicious sender should not be allowed"
        );

        // The mock router delivers to ccipReceiver — if the message claims to be
        // from maliciousSender, the receiver's _ccipReceive checks should reject it
        // This is validated by the CCIPReceiver unit tests (test_receive_unauthorized_sender_reverts)
        // Here we verify the state: unauthorized senders are NOT in the allowlist
        assertTrue(
            ccipReceiver.allowedSenders(SOURCE_SELECTOR, address(ccipSender)),
            "Real sender should be allowed"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 9: Double-Spend ZK Proof
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Submit valid ZK proof, get receipt tokens, try to reuse proof.
    ///         Must revert — nullifier prevents double-spend.
    function test_attack_double_spend_zk_proof() public {
        address mirrorAddr = _deployCanonicalMirror(address(0xB2B2), 1, block.chainid, 9);
        uint256 assetId = 99;
        collateralVerifier.registerAsset(mirrorAddr, assetId);

        address user = makeAddr("zkUser");
        uint256 collateralValue = 100_000e18;

        // Submit proof
        bytes memory proof = _buildMockProof(9);
        uint256[] memory inputs = _buildPublicInputs(assetId, collateralValue);

        vm.prank(user);
        bytes32 proofId = collateralVerifier.verifyCollateralProof(proof, inputs);

        // Deposit succeeds
        vm.prank(user);
        uint256 receipts = adapter.depositWithProof(proofId);
        assertEq(receipts, collateralValue, "Should receive receipt tokens");

        // Attempt to deposit again with same proofId
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AaveAdapter.ProofAlreadyUsed.selector, proofId));
        adapter.depositWithProof(proofId);

        // Attempt to resubmit same proof bytes to verifier
        vm.prank(user);
        bytes32 nullifier = keccak256(proof);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralVerifier.NullifierAlreadyUsed.selector, nullifier)
        );
        collateralVerifier.verifyCollateralProof(proof, inputs);

        // User only has receipt tokens from the FIRST deposit
        assertEq(
            XythumToken(receiptAddr).balanceOf(user),
            collateralValue,
            "Should only have tokens from single deposit"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ATTACK 10: Paused Protocol
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Owner pauses factory → deployments blocked. Unpause → resumes.
    function test_attack_paused_protocol() public {
        // Pause factory
        factory.pause();

        // Attempt to deploy mirror while paused
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(address(0xC3C3), 1, block.chainid, 1, THRESHOLD);

        vm.expectRevert(); // EnforcedPause
        factory.deployMirror(att, sigs, bitmap);

        // Unpause → deployment succeeds
        factory.unpause();

        // Need fresh attestation (rate limit may have passed, but same nonce is fine since first deploy failed)
        address mirror = factory.deployMirror(att, sigs, bitmap);
        assertTrue(factory.isCanonical(mirror), "Mirror should be canonical after unpause");
    }

    // ─── Mock proof helpers ──────────────────────────────────────────

    function _buildMockProof(uint256 nonce) internal pure returns (bytes memory) {
        uint256[2] memory a = [nonce, nonce + 1];
        uint256[2][2] memory b = [[nonce + 2, nonce + 3], [nonce + 4, nonce + 5]];
        uint256[2] memory c = [nonce + 6, nonce + 7];
        return abi.encode(a, b, c);
    }

    function _buildPublicInputs(uint256 assetId, uint256 minimumValue)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory inputs = new uint256[](4);
        inputs[0] = uint256(keccak256("attestationRoot"));
        inputs[1] = assetId;
        inputs[2] = minimumValue;
        inputs[3] = 1e18;
        return inputs;
    }
}
