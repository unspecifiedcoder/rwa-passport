// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { CollateralVerifier } from "../../src/zk/CollateralVerifier.sol";
import { IZKCollateral } from "../../src/interfaces/IZKCollateral.sol";
import { MockGroth16Verifier } from "../helpers/MockCollateralVerifier.sol";

/// @title CollateralVerifierTest
/// @notice Unit tests for CollateralVerifier — ZK proof verification and storage
contract CollateralVerifierTest is Test {
    CollateralVerifier public verifier;
    MockGroth16Verifier public mockGroth16;

    address public owner;
    address public prover;
    address public attacker;

    // Test asset
    address public testAsset;
    uint256 public constant ASSET_ID = 42;

    function setUp() public {
        vm.warp(100_000);

        owner = address(this);
        prover = makeAddr("prover");
        attacker = makeAddr("attacker");
        testAsset = makeAddr("testAsset");

        // Deploy mock Groth16 verifier
        mockGroth16 = new MockGroth16Verifier();

        // Deploy CollateralVerifier
        verifier = new CollateralVerifier(address(mockGroth16), owner);

        // Register test asset
        verifier.registerAsset(testAsset, ASSET_ID);
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    /// @notice Build a mock proof (abi-encoded a, b, c points)
    function _buildMockProof(uint256 nonce) internal pure returns (bytes memory) {
        uint256[2] memory a = [nonce, nonce + 1];
        uint256[2][2] memory b = [[nonce + 2, nonce + 3], [nonce + 4, nonce + 5]];
        uint256[2] memory c = [nonce + 6, nonce + 7];
        return abi.encode(a, b, c);
    }

    /// @notice Build public inputs: [attestationRoot, assetId, minimumValue, navPrice]
    function _buildPublicInputs(
        uint256 attestationRoot,
        uint256 assetId,
        uint256 minimumValue,
        uint256 navPrice
    ) internal pure returns (uint256[] memory) {
        uint256[] memory inputs = new uint256[](4);
        inputs[0] = attestationRoot;
        inputs[1] = assetId;
        inputs[2] = minimumValue;
        inputs[3] = navPrice;
        return inputs;
    }

    // ─── verifyCollateralProof Tests ─────────────────────────────────

    function test_verifyCollateralProof_valid() public {
        bytes memory proof = _buildMockProof(1);
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("root")), ASSET_ID, 100_000e18, 1e18);

        vm.prank(prover);
        bytes32 proofId = verifier.verifyCollateralProof(proof, inputs);

        // Verify proofId is non-zero
        assertTrue(proofId != bytes32(0), "proofId should be non-zero");

        // Verify stored data
        (uint256 minValue, address asset, uint256 timestamp) = verifier.getCollateralValue(proofId);
        assertEq(minValue, 100_000e18, "minimumValue should match");
        assertEq(asset, testAsset, "asset should match");
        assertEq(timestamp, block.timestamp, "timestamp should match");

        // Verify proof is active
        assertTrue(verifier.isProofActive(proofId), "proof should be active");
    }

    function test_verifyCollateralProof_emits_event() public {
        bytes memory proof = _buildMockProof(10);
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("root")), ASSET_ID, 50_000e18, 2e18);

        vm.prank(prover);
        vm.expectEmit(false, true, false, true);
        emit IZKCollateral.CollateralProofVerified(
            bytes32(0), // proofId unknown ahead of time
            testAsset,
            50_000e18,
            block.timestamp
        );
        verifier.verifyCollateralProof(proof, inputs);
    }

    function test_verifyCollateralProof_replay_reverts() public {
        bytes memory proof = _buildMockProof(2);
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("root2")), ASSET_ID, 100_000e18, 1e18);

        vm.prank(prover);
        verifier.verifyCollateralProof(proof, inputs);

        // Same proof again should revert
        bytes32 nullifier = keccak256(proof);
        vm.prank(prover);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralVerifier.NullifierAlreadyUsed.selector, nullifier)
        );
        verifier.verifyCollateralProof(proof, inputs);
    }

    function test_verifyCollateralProof_unknown_asset_reverts() public {
        bytes memory proof = _buildMockProof(3);
        uint256 unknownAssetId = 999;
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("root3")), unknownAssetId, 100_000e18, 1e18);

        vm.prank(prover);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralVerifier.UnknownAsset.selector, unknownAssetId)
        );
        verifier.verifyCollateralProof(proof, inputs);
    }

    function test_verifyCollateralProof_invalid_proof_reverts() public {
        // Make the mock verifier reject proofs
        mockGroth16.setShouldAccept(false);

        bytes memory proof = _buildMockProof(4);
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("root4")), ASSET_ID, 100_000e18, 1e18);

        vm.prank(prover);
        vm.expectRevert(CollateralVerifier.InvalidProof.selector);
        verifier.verifyCollateralProof(proof, inputs);
    }

    function test_verifyCollateralProof_wrong_input_length_reverts() public {
        bytes memory proof = _buildMockProof(5);
        uint256[] memory inputs = new uint256[](3); // Wrong length
        inputs[0] = 1;
        inputs[1] = 2;
        inputs[2] = 3;

        vm.prank(prover);
        vm.expectRevert(CollateralVerifier.InvalidProof.selector);
        verifier.verifyCollateralProof(proof, inputs);
    }

    function test_verifyCollateralProof_multiple_proofs_unique_ids() public {
        bytes memory proof1 = _buildMockProof(6);
        bytes memory proof2 = _buildMockProof(7);
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("root6")), ASSET_ID, 100_000e18, 1e18);

        vm.prank(prover);
        bytes32 id1 = verifier.verifyCollateralProof(proof1, inputs);

        vm.prank(prover);
        bytes32 id2 = verifier.verifyCollateralProof(proof2, inputs);

        assertTrue(id1 != id2, "Proof IDs should be unique");
    }

    // ─── getCollateralValue Tests ────────────────────────────────────

    function test_getCollateralValue_returns_stored() public {
        bytes memory proof = _buildMockProof(20);
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("rootX")), ASSET_ID, 250_000e18, 3e18);

        vm.prank(prover);
        bytes32 proofId = verifier.verifyCollateralProof(proof, inputs);

        (uint256 minValue, address asset, uint256 ts) = verifier.getCollateralValue(proofId);
        assertEq(minValue, 250_000e18);
        assertEq(asset, testAsset);
        assertEq(ts, block.timestamp);
    }

    function test_getCollateralValue_nonexistent_reverts() public {
        bytes32 fakeId = keccak256("nonexistent");
        // After the security fix in PR #2, getCollateralValue reverts with
        // ProofNotFound for unknown proofs (previously returned zeros, which
        // could silently mislead consumers).
        vm.expectRevert();
        verifier.getCollateralValue(fakeId);
    }

    // ─── registerAsset Tests ─────────────────────────────────────────

    function test_registerAsset_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        verifier.registerAsset(makeAddr("newAsset"), 100);
    }

    function test_registerAsset_stores_mapping() public {
        address newAsset = makeAddr("newAsset");
        uint256 newId = 777;

        verifier.registerAsset(newAsset, newId);

        assertEq(verifier.assetIds(newAsset), newId);
        assertEq(verifier.assetAddresses(newId), newAsset);
    }

    // ─── invalidateProof Tests ───────────────────────────────────────

    function test_invalidateProof_deactivates() public {
        bytes memory proof = _buildMockProof(30);
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("root30")), ASSET_ID, 100_000e18, 1e18);

        vm.prank(prover);
        bytes32 proofId = verifier.verifyCollateralProof(proof, inputs);
        assertTrue(verifier.isProofActive(proofId), "proof should be active before invalidation");

        // Owner invalidates
        verifier.invalidateProof(proofId);
        assertFalse(verifier.isProofActive(proofId), "proof should be inactive after invalidation");
    }

    function test_invalidateProof_onlyOwner() public {
        bytes memory proof = _buildMockProof(31);
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("root31")), ASSET_ID, 100_000e18, 1e18);

        vm.prank(prover);
        bytes32 proofId = verifier.verifyCollateralProof(proof, inputs);

        vm.prank(attacker);
        vm.expectRevert();
        verifier.invalidateProof(proofId);
    }

    function test_invalidateProof_already_inactive_reverts() public {
        bytes memory proof = _buildMockProof(32);
        uint256[] memory inputs =
            _buildPublicInputs(uint256(keccak256("root32")), ASSET_ID, 100_000e18, 1e18);

        vm.prank(prover);
        bytes32 proofId = verifier.verifyCollateralProof(proof, inputs);

        verifier.invalidateProof(proofId);

        // Second invalidation should revert
        vm.expectRevert(abi.encodeWithSelector(CollateralVerifier.ProofNotActive.selector, proofId));
        verifier.invalidateProof(proofId);
    }
}
