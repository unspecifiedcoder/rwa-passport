// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SignerRegistry} from "../../src/core/SignerRegistry.sol";
import {AttestationRegistry} from "../../src/core/AttestationRegistry.sol";
import {CanonicalFactory} from "../../src/core/CanonicalFactory.sol";
import {XythumToken} from "../../src/core/XythumToken.sol";
import {MockCompliance} from "../helpers/MockCompliance.sol";
import {AttestationHelper} from "../helpers/AttestationHelper.sol";
import {AttestationLib} from "../../src/libraries/AttestationLib.sol";

/// @title DualPathTest
/// @notice Integration tests for the dual-path (Direct + CCIP) mirror deployment system.
///         Verifies that both paths produce identical results and interoperate correctly.
contract DualPathTest is Test {
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    CanonicalFactory public factory;
    MockCompliance public compliance;
    AttestationHelper public helper;

    address public owner;
    address public treasury;

    uint256 public constant NUM_SIGNERS = 5;
    uint256 public constant THRESHOLD = 3;
    uint256 public constant MAX_STALENESS = 24 hours;
    uint256 public constant RATE_LIMIT = 1 hours;

    address public constant ORIGIN_CONTRACT = address(0xAAA);
    uint256 public constant ORIGIN_CHAIN = 43113; // Fuji

    function setUp() public {
        vm.warp(100_000);

        owner = address(this);
        treasury = makeAddr("treasury");

        // 1. Deploy signer registry
        signerRegistry = new SignerRegistry(owner, THRESHOLD);

        // 2. Generate signers via helper
        helper = new AttestationHelper();
        helper.generateSigners(NUM_SIGNERS);

        // 3. Register signers
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }

        // 4. Deploy attestation registry
        attestationRegistry = new AttestationRegistry(
            address(signerRegistry),
            MAX_STALENESS,
            RATE_LIMIT
        );

        // 5. Deploy compliance
        compliance = new MockCompliance();

        // 6. Deploy factory
        factory = new CanonicalFactory(
            address(attestationRegistry),
            address(compliance),
            treasury,
            owner
        );
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    function _buildAndSignDirect(
        address originContract,
        uint256 originChainId,
        uint256 nonce
    ) internal view returns (
        AttestationLib.Attestation memory att,
        bytes memory signatures,
        uint256 bitmap
    ) {
        att = helper.buildAttestation(originContract, originChainId, block.chainid, nonce);

        uint256[] memory signerIndices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            signerIndices[i] = i;
        }

        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (signatures, bitmap) = helper.signAttestation(att, domainSep, signerIndices);
    }

    // ─── Integration Tests ───────────────────────────────────────────

    /// @notice Full lifecycle test: deploy mirror via direct path, verify everything
    function test_full_flow_direct_path() public {
        // 1. Build attestation off-chain
        (
            AttestationLib.Attestation memory att,
            bytes memory sigs,
            uint256 bitmap
        ) = _buildAndSignDirect(ORIGIN_CONTRACT, ORIGIN_CHAIN, 1);

        // 2. Predict the mirror address
        address predicted = factory.computeMirrorAddress(att);

        // 3. Deploy via direct path (instant!)
        address mirror = factory.deployMirrorDirect(att, sigs, bitmap);

        // 4. Verify mirror is canonical
        assertTrue(factory.isCanonical(mirror), "Mirror must be canonical");
        assertEq(mirror, predicted, "Address must match prediction");

        // 5. Verify mirror metadata
        CanonicalFactory.MirrorInfo memory info = factory.getMirrorInfo(mirror);
        assertEq(info.originContract, ORIGIN_CONTRACT);
        assertEq(info.originChainId, ORIGIN_CHAIN);
        assertEq(info.targetChainId, block.chainid);
        assertTrue(info.active);
        assertEq(info.deployedAt, block.timestamp);

        // 6. Verify enumeration
        assertEq(factory.getMirrorCount(), 1);
        address[] memory allMirrors = factory.getAllMirrors();
        assertEq(allMirrors[0], mirror);

        // 7. Verify the mirror token has correct properties
        XythumToken mirrorToken = XythumToken(mirror);
        assertEq(mirrorToken.name(), "Xythum Mirror");
        assertEq(mirrorToken.symbol(), "xRWA");
        assertEq(mirrorToken.originContract(), ORIGIN_CONTRACT);
        assertEq(mirrorToken.originChainId(), ORIGIN_CHAIN);
        assertEq(mirrorToken.factory(), address(factory));

        // 8. Mint tokens via factory (factory is authorized minter)
        assertTrue(mirrorToken.authorizedMinters(address(factory)));

        // 9. Verify attestation is stored in registry
        assertTrue(
            attestationRegistry.isAttested(ORIGIN_CONTRACT, ORIGIN_CHAIN, block.chainid),
            "Attestation must be stored in registry"
        );
    }

    /// @notice Mixed path usage: direct deploy first, then a different origin via the
    ///         CCIP path (deployMirror), verifying both interoperate on the same state.
    function test_direct_deploy_then_ccip_path_coexist() public {
        // 1. Deploy mirror for origin A via direct path
        (
            AttestationLib.Attestation memory attA,
            bytes memory sigsA,
            uint256 bitmapA
        ) = _buildAndSignDirect(ORIGIN_CONTRACT, ORIGIN_CHAIN, 1);

        address mirrorA = factory.deployMirrorDirect(attA, sigsA, bitmapA);

        // 2. Deploy mirror for origin B via CCIP-style path (deployMirror)
        address originB = address(0xBBB);
        (
            AttestationLib.Attestation memory attB,
            bytes memory sigsB,
            uint256 bitmapB
        ) = _buildAndSignDirect(originB, ORIGIN_CHAIN, 1);

        address mirrorB = factory.deployMirror(attB, sigsB, bitmapB);

        // 3. Both mirrors exist and are canonical
        assertTrue(factory.isCanonical(mirrorA), "Mirror A canonical");
        assertTrue(factory.isCanonical(mirrorB), "Mirror B canonical");
        assertTrue(mirrorA != mirrorB, "Different origins produce different mirrors");

        // 4. Enumeration shows both
        assertEq(factory.getMirrorCount(), 2);
        address[] memory all = factory.getAllMirrors();
        assertEq(all[0], mirrorA);
        assertEq(all[1], mirrorB);

        // 5. Both attestations stored in registry
        assertTrue(
            attestationRegistry.isAttested(ORIGIN_CONTRACT, ORIGIN_CHAIN, block.chainid)
        );
        assertTrue(
            attestationRegistry.isAttested(originB, ORIGIN_CHAIN, block.chainid)
        );

        // 6. Trying to redeploy origin A via CCIP path should fail (shared state)
        vm.warp(block.timestamp + RATE_LIMIT + 1);
        (
            AttestationLib.Attestation memory attA2,
            bytes memory sigsA2,
            uint256 bitmapA2
        ) = _buildAndSignDirect(ORIGIN_CONTRACT, ORIGIN_CHAIN, 2);

        vm.expectRevert(); // MirrorAlreadyDeployed
        factory.deployMirror(attA2, sigsA2, bitmapA2);
    }
}
