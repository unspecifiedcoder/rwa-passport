// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SignerRegistry} from "../../src/core/SignerRegistry.sol";
import {AttestationRegistry} from "../../src/core/AttestationRegistry.sol";
import {CanonicalFactory} from "../../src/core/CanonicalFactory.sol";
import {XythumToken} from "../../src/core/XythumToken.sol";
import {CollateralVerifier} from "../../src/zk/CollateralVerifier.sol";
import {AaveAdapter} from "../../src/adapters/AaveAdapter.sol";
import {MockGroth16Verifier} from "../helpers/MockCollateralVerifier.sol";
import {MockCompliance} from "../helpers/MockCompliance.sol";
import {AttestationHelper} from "../helpers/AttestationHelper.sol";
import {AttestationLib} from "../../src/libraries/AttestationLib.sol";
import {IZKCollateral} from "../../src/interfaces/IZKCollateral.sol";

/// @title ZKCollateralTest
/// @notice Integration test: deploy mirror -> prove collateral -> deposit -> redeem
///         Validates the full Phase 5 ZK collateral flow end-to-end.
contract ZKCollateralTest is Test {
    // ─── Xythum stack ────────────────────────────────────────────────
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    CanonicalFactory public factory;
    MockCompliance public compliance;
    AttestationHelper public helper;

    // ─── ZK + Adapter stack ──────────────────────────────────────────
    MockGroth16Verifier public mockGroth16;
    CollateralVerifier public collateralVerifier;
    AaveAdapter public adapter;

    // ─── Tokens ──────────────────────────────────────────────────────
    XythumToken public mirrorToken;
    XythumToken public receiptToken;
    address public mirrorAddr;
    address public receiptAddr;

    // ─── Config ──────────────────────────────────────────────────────
    address public owner;
    address public user;

    uint256 constant NUM_SIGNERS = 5;
    uint256 constant THRESHOLD = 3;
    uint256 constant ASSET_ID = 42;
    uint256 constant MAX_PROOF_AGE = 1 hours;

    function setUp() public {
        vm.warp(100_000);
        owner = address(this);
        user = makeAddr("user");

        // ── Deploy full Xythum protocol stack ──
        signerRegistry = new SignerRegistry(owner, THRESHOLD);
        helper = new AttestationHelper();
        helper.generateSigners(NUM_SIGNERS);
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }
        attestationRegistry = new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);
        compliance = new MockCompliance();
        compliance.setEnforceCompliance(false);
        factory = new CanonicalFactory(
            address(attestationRegistry),
            address(compliance),
            makeAddr("treasury"),
            owner
        );

        // ── Deploy canonical mirror (the "collateral" asset) ──
        mirrorAddr = _deployCanonicalMirror(address(0xAAA), 1, 42161, 1);
        mirrorToken = XythumToken(mirrorAddr);

        // ── Deploy receipt token (another canonical mirror repurposed) ──
        receiptAddr = _deployCanonicalMirror(address(0xBBB), 1, 42161, 2);
        receiptToken = XythumToken(receiptAddr);

        // ── Deploy ZK stack ──
        mockGroth16 = new MockGroth16Verifier();
        collateralVerifier = new CollateralVerifier(address(mockGroth16), owner);
        collateralVerifier.registerAsset(mirrorAddr, ASSET_ID);

        // ── Deploy Aave adapter ──
        adapter = new AaveAdapter(
            address(collateralVerifier),
            address(factory),
            MAX_PROOF_AGE,
            owner
        );

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
        for (uint256 i = 0; i < THRESHOLD; i++) signerIndices[i] = i;
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
        inputs[3] = 1e18;
        return inputs;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  INTEGRATION: Full ZK Collateral Flow
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Full flow: deploy mirror -> register asset -> prove collateral ->
    ///         deposit via adapter -> get receipt tokens -> redeem
    function test_zk_collateral_full_flow() public {
        uint256 collateralValue = 100_000e18;

        // 1. Verify mirror is canonical
        assertTrue(factory.isCanonical(mirrorAddr), "Mirror should be canonical");

        // 2. Verify asset is registered in CollateralVerifier
        assertEq(
            collateralVerifier.assetAddresses(ASSET_ID),
            mirrorAddr,
            "Asset should be registered"
        );

        // 3. User submits ZK proof proving 100,000 USDC value of collateral
        bytes memory proof = _buildMockProof(1);
        uint256[] memory inputs = _buildPublicInputs(collateralValue);

        vm.prank(user);
        bytes32 proofId = collateralVerifier.verifyCollateralProof(proof, inputs);
        assertTrue(proofId != bytes32(0), "proofId should be non-zero");

        // 4. Verify proof data stored correctly
        (uint256 minValue, address asset, uint256 timestamp) =
            collateralVerifier.getCollateralValue(proofId);
        assertEq(minValue, collateralValue, "Stored value should match");
        assertEq(asset, mirrorAddr, "Stored asset should match mirror");
        assertEq(timestamp, block.timestamp, "Timestamp should be current");

        // 5. User deposits via AaveAdapter
        vm.prank(user);
        uint256 receiptAmount = adapter.depositWithProof(proofId);
        assertEq(receiptAmount, collateralValue, "Receipt amount should match proven value");

        // 6. Verify receipt tokens received
        assertEq(
            receiptToken.balanceOf(user),
            collateralValue,
            "User should have receipt tokens"
        );

        // 7. Verify proof cannot be reused
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(AaveAdapter.ProofAlreadyUsed.selector, proofId)
        );
        adapter.depositWithProof(proofId);

        // 8. User redeems receipt tokens (after hypothetically repaying Aave loan)
        vm.prank(user);
        adapter.redeemReceipt(collateralValue);
        assertEq(receiptToken.balanceOf(user), 0, "User should have no receipts after redeem");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  INTEGRATION: Proof Expiry Flow
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Prove collateral -> wait too long -> deposit fails
    function test_expired_proof_flow() public {
        // Submit proof
        bytes memory proof = _buildMockProof(2);
        uint256[] memory inputs = _buildPublicInputs(50_000e18);

        vm.prank(user);
        bytes32 proofId = collateralVerifier.verifyCollateralProof(proof, inputs);

        // Warp past MAX_PROOF_AGE
        vm.warp(block.timestamp + MAX_PROOF_AGE + 1);

        // Deposit should fail
        vm.prank(user);
        vm.expectRevert(); // ProofTooOld
        adapter.depositWithProof(proofId);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  INTEGRATION: Multiple Proofs, Multiple Users
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Two different users submit proofs and deposit independently
    function test_multiple_users_collateral_flow() public {
        address user2 = makeAddr("user2");

        // User 1 submits proof for 100k
        bytes memory proof1 = _buildMockProof(3);
        uint256[] memory inputs1 = _buildPublicInputs(100_000e18);
        vm.prank(user);
        bytes32 proofId1 = collateralVerifier.verifyCollateralProof(proof1, inputs1);

        // User 2 submits proof for 200k
        bytes memory proof2 = _buildMockProof(4);
        uint256[] memory inputs2 = _buildPublicInputs(200_000e18);
        vm.prank(user2);
        bytes32 proofId2 = collateralVerifier.verifyCollateralProof(proof2, inputs2);

        // Both deposit
        vm.prank(user);
        adapter.depositWithProof(proofId1);

        vm.prank(user2);
        adapter.depositWithProof(proofId2);

        // Verify balances
        assertEq(receiptToken.balanceOf(user), 100_000e18, "User 1 receipts");
        assertEq(receiptToken.balanceOf(user2), 200_000e18, "User 2 receipts");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  INTEGRATION: Emergency Proof Invalidation
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Owner invalidates a proof -> it's marked inactive
    function test_emergency_invalidation_flow() public {
        // Submit proof
        bytes memory proof = _buildMockProof(5);
        uint256[] memory inputs = _buildPublicInputs(100_000e18);
        vm.prank(user);
        bytes32 proofId = collateralVerifier.verifyCollateralProof(proof, inputs);

        // Proof is active
        assertTrue(collateralVerifier.isProofActive(proofId), "Proof should be active");

        // Owner invalidates
        collateralVerifier.invalidateProof(proofId);

        // Proof is now inactive
        assertFalse(collateralVerifier.isProofActive(proofId), "Proof should be inactive");

        // Note: AaveAdapter doesn't check isProofActive (MVP simplification)
        // In production, depositWithProof would also check proof.active
        // TODO(upgrade): Add active check to AaveAdapter.depositWithProof
    }
}
