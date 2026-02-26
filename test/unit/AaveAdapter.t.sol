// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { AaveAdapter } from "../../src/adapters/AaveAdapter.sol";
import { CollateralVerifier } from "../../src/zk/CollateralVerifier.sol";
import { MockGroth16Verifier } from "../helpers/MockCollateralVerifier.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";
import { AttestationHelper } from "../helpers/AttestationHelper.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";

/// @title AaveAdapterTest
/// @notice Unit tests for AaveAdapter — ZK proof-backed collateral deposits
contract AaveAdapterTest is Test {
    // ─── Xythum stack ────────────────────────────────────────────────
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    CanonicalFactory public factory;
    MockCompliance public compliance;
    AttestationHelper public helper;

    // ─── ZK stack ────────────────────────────────────────────────────
    MockGroth16Verifier public mockGroth16;
    CollateralVerifier public collateralVerifier;
    AaveAdapter public adapter;

    // ─── Receipt token (a canonical mirror repurposed as receipt) ────
    XythumToken public receiptToken;
    address public mirrorAddr;

    // ─── Config ──────────────────────────────────────────────────────
    address public owner;
    address public user;
    address public attacker;

    uint256 constant NUM_SIGNERS = 5;
    uint256 constant THRESHOLD = 3;
    uint256 constant ASSET_ID = 42;
    uint256 constant MAX_PROOF_AGE = 1 hours;

    function setUp() public {
        vm.warp(100_000);

        owner = address(this);
        user = makeAddr("user");
        attacker = makeAddr("attacker");

        // 1. Deploy Xythum stack
        signerRegistry = new SignerRegistry(owner, THRESHOLD);
        helper = new AttestationHelper();
        helper.generateSigners(NUM_SIGNERS);
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }
        attestationRegistry = new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);
        compliance = new MockCompliance();
        compliance.setEnforceCompliance(false); // Disable for testing
        factory = new CanonicalFactory(
            address(attestationRegistry), address(compliance), makeAddr("treasury"), owner
        );

        // 2. Deploy canonical mirror (used as the collateral asset)
        mirrorAddr = _deployCanonicalMirror(address(0xAAA), 1, 42161, 1);

        // 3. Deploy ZK stack
        mockGroth16 = new MockGroth16Verifier();
        collateralVerifier = new CollateralVerifier(address(mockGroth16), owner);
        collateralVerifier.registerAsset(mirrorAddr, ASSET_ID);

        // 4. Deploy adapter
        adapter =
            new AaveAdapter(address(collateralVerifier), address(factory), MAX_PROOF_AGE, owner);

        // 5. Deploy receipt token (a separate canonical mirror repurposed)
        // For testing: create a simple XythumToken that adapter can mint/burn
        // We deploy another mirror and make the adapter an authorized minter
        address receiptAddr = _deployCanonicalMirror(address(0xBBB), 1, 42161, 2);
        receiptToken = XythumToken(receiptAddr);

        // Make adapter an authorized minter on the receipt token
        vm.prank(address(factory));
        receiptToken.setAuthorizedMinter(address(adapter), true);

        adapter.setReceiptToken(receiptAddr);
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    function _deployCanonicalMirror(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 nonce
    ) internal returns (address mirror) {
        AttestationLib.Attestation memory att = helper.buildAttestation(
            originContract, originChainId, targetChainId, nonce
        );
        uint256[] memory signerIndices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            signerIndices[i] = i;
        }
        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (bytes memory sigs, uint256 bitmap) = helper.signAttestation(att, domainSep, signerIndices);
        mirror = factory.deployMirror(att, sigs, bitmap);
    }

    function _buildMockProof(uint256 nonce) internal pure returns (bytes memory) {
        uint256[2] memory a = [nonce, nonce + 1];
        uint256[2][2] memory b = [[nonce + 2, nonce + 3], [nonce + 4, nonce + 5]];
        uint256[2] memory c = [nonce + 6, nonce + 7];
        return abi.encode(a, b, c);
    }

    function _buildPublicInputs(uint256 minimumValue) internal pure returns (uint256[] memory) {
        uint256[] memory inputs = new uint256[](4);
        inputs[0] = uint256(keccak256("attestationRoot"));
        inputs[1] = ASSET_ID;
        inputs[2] = minimumValue;
        inputs[3] = 1e18; // navPrice
        return inputs;
    }

    /// @notice Submit a proof and return the proofId
    function _submitProof(uint256 nonce, uint256 minimumValue) internal returns (bytes32) {
        bytes memory proof = _buildMockProof(nonce);
        uint256[] memory inputs = _buildPublicInputs(minimumValue);
        vm.prank(user);
        return collateralVerifier.verifyCollateralProof(proof, inputs);
    }

    // ─── depositWithProof Tests ──────────────────────────────────────

    function test_depositWithProof_success() public {
        uint256 minValue = 100_000e18;
        bytes32 proofId = _submitProof(1, minValue);

        // User deposits
        vm.prank(user);
        uint256 receiptAmount = adapter.depositWithProof(proofId);

        assertEq(receiptAmount, minValue, "Receipt amount should match minimum value");
        assertEq(receiptToken.balanceOf(user), minValue, "User should have receipt tokens");
        assertTrue(adapter.usedProofs(proofId), "Proof should be marked as used");
    }

    function test_depositWithProof_emits_event() public {
        uint256 minValue = 50_000e18;
        bytes32 proofId = _submitProof(2, minValue);

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit AaveAdapter.CollateralDeposited(user, proofId, minValue);
        adapter.depositWithProof(proofId);
    }

    function test_depositWithProof_replay_reverts() public {
        bytes32 proofId = _submitProof(3, 100_000e18);

        vm.prank(user);
        adapter.depositWithProof(proofId);

        // Second deposit with same proofId
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AaveAdapter.ProofAlreadyUsed.selector, proofId));
        adapter.depositWithProof(proofId);
    }

    function test_depositWithProof_expired_proof_reverts() public {
        bytes32 proofId = _submitProof(4, 100_000e18);

        // Warp past maxProofAge
        vm.warp(block.timestamp + MAX_PROOF_AGE + 1);

        vm.prank(user);
        vm.expectRevert(); // ProofTooOld
        adapter.depositWithProof(proofId);
    }

    function test_depositWithProof_non_canonical_asset_reverts() public {
        // Register a non-canonical asset in the verifier
        address fakeAsset = makeAddr("fakeAsset");
        uint256 fakeAssetId = 999;
        collateralVerifier.registerAsset(fakeAsset, fakeAssetId);

        // Submit proof for the non-canonical asset
        bytes memory proof = _buildMockProof(5);
        uint256[] memory inputs = new uint256[](4);
        inputs[0] = uint256(keccak256("root"));
        inputs[1] = fakeAssetId;
        inputs[2] = 100_000e18;
        inputs[3] = 1e18;

        vm.prank(user);
        bytes32 proofId = collateralVerifier.verifyCollateralProof(proof, inputs);

        // Deposit should fail — asset not canonical
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AaveAdapter.AssetNotCanonical.selector, fakeAsset));
        adapter.depositWithProof(proofId);
    }

    function test_depositWithProof_no_receipt_token_reverts() public {
        // Deploy adapter without receipt token
        AaveAdapter bareAdapter =
            new AaveAdapter(address(collateralVerifier), address(factory), MAX_PROOF_AGE, owner);
        // receiptToken not set

        bytes32 proofId = _submitProof(6, 100_000e18);

        vm.prank(user);
        vm.expectRevert(AaveAdapter.ReceiptTokenNotSet.selector);
        bareAdapter.depositWithProof(proofId);
    }

    // ─── redeemReceipt Tests ─────────────────────────────────────────

    function test_redeemReceipt() public {
        uint256 minValue = 100_000e18;
        bytes32 proofId = _submitProof(10, minValue);

        // Deposit
        vm.prank(user);
        adapter.depositWithProof(proofId);
        assertEq(receiptToken.balanceOf(user), minValue, "User should have receipts");

        // Redeem
        vm.prank(user);
        adapter.redeemReceipt(minValue);
        assertEq(receiptToken.balanceOf(user), 0, "User should have 0 receipts after redeem");
    }

    function test_redeemReceipt_partial() public {
        uint256 minValue = 100_000e18;
        bytes32 proofId = _submitProof(11, minValue);

        vm.prank(user);
        adapter.depositWithProof(proofId);

        // Partial redeem
        vm.prank(user);
        adapter.redeemReceipt(40_000e18);
        assertEq(receiptToken.balanceOf(user), 60_000e18, "Partial redeem should work");
    }

    // ─── Admin Tests ─────────────────────────────────────────────────

    function test_setMaxProofAge_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        adapter.setMaxProofAge(2 hours);
    }

    function test_setMaxProofAge_updates() public {
        adapter.setMaxProofAge(2 hours);
        assertEq(adapter.maxProofAge(), 2 hours, "maxProofAge should be updated");
    }

    function test_setReceiptToken_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        adapter.setReceiptToken(makeAddr("newToken"));
    }
}
