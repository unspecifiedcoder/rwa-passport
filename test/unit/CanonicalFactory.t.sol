// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";
import { AttestationHelper } from "../helpers/AttestationHelper.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { ICanonicalFactory } from "../../src/interfaces/ICanonicalFactory.sol";
import { TestConstants } from "../helpers/TestConstants.sol";

/// @title CanonicalFactoryTest
/// @notice Unit tests for CanonicalFactory — deterministic CREATE2 mirror deployment
contract CanonicalFactoryTest is Test {
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
    uint256 public constant ORIGIN_CHAIN = 1;
    uint256 public constant TARGET_CHAIN = 42161;
    uint256 public constant TARGET_CHAIN_2 = 10; // Optimism

    function setUp() public {
        // Warp to avoid underflow in timestamp arithmetic
        vm.warp(100_000);

        owner = address(this);
        treasury = makeAddr("treasury");

        // 1. Deploy signer registry
        signerRegistry = new SignerRegistry(owner, THRESHOLD);

        // 2. Generate signers via helper
        helper = new AttestationHelper();
        helper.generateSigners(NUM_SIGNERS);

        // 3. Register signers (must be done by owner, not helper)
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }

        // 4. Deploy attestation registry
        attestationRegistry =
            new AttestationRegistry(address(signerRegistry), MAX_STALENESS, RATE_LIMIT);

        // 5. Deploy compliance
        compliance = new MockCompliance();

        // 6. Deploy factory
        factory =
            new CanonicalFactory(address(attestationRegistry), address(compliance), treasury, owner);
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    /// @notice Build and sign an attestation ready for deployMirror
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

        // Sign with first THRESHOLD signers (indices 0,1,2)
        uint256[] memory signerIndices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            signerIndices[i] = i;
        }

        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (signatures, bitmap) = helper.signAttestation(att, domainSep, signerIndices);
    }

    /// @notice Deploy a mirror and return its address
    function _deployTestMirror(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 nonce
    ) internal returns (address mirror) {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(originContract, originChainId, targetChainId, nonce);

        mirror = factory.deployMirror(att, sigs, bitmap);
    }

    // ─── Deployment Tests ────────────────────────────────────────────

    function test_deployMirror_creates_at_deterministic_address() public {
        // Compute expected address BEFORE deployment
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        address predicted = factory.computeMirrorAddress(att);

        // Deploy
        address mirror = factory.deployMirror(att, sigs, bitmap);

        // Must match
        assertEq(mirror, predicted, "CREATE2 address mismatch");
    }

    function test_deployMirror_returns_correct_address() public {
        address mirror = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);
        assertTrue(mirror != address(0), "Mirror should not be zero address");
        assertTrue(mirror.code.length > 0, "Mirror should have code");
    }

    function test_deployMirror_registers_as_canonical() public {
        address mirror = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);
        assertTrue(factory.isCanonical(mirror));
    }

    function test_deployMirror_stores_mirrorInfo() public {
        address mirror = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        (
            address originContract,
            uint256 originChainId,
            uint256 targetChainId,
            bytes32 attestationId,
            uint256 deployedAt,
            bool active
        ) = factory.mirrorInfoMap(mirror);

        assertEq(originContract, ORIGIN_CONTRACT);
        assertEq(originChainId, ORIGIN_CHAIN);
        assertEq(targetChainId, TARGET_CHAIN);
        assertTrue(attestationId != bytes32(0));
        assertEq(deployedAt, block.timestamp);
        assertTrue(active);
    }

    function test_deployMirror_getMirrorInfo() public {
        address mirror = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        CanonicalFactory.MirrorInfo memory info = factory.getMirrorInfo(mirror);
        assertEq(info.originContract, ORIGIN_CONTRACT);
        assertEq(info.originChainId, ORIGIN_CHAIN);
        assertEq(info.targetChainId, TARGET_CHAIN);
        assertTrue(info.active);
    }

    function test_deployMirror_emits_event() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        bytes32 salt = AttestationLib.canonicalSalt(att);
        address predicted = factory.computeMirrorAddress(att);

        vm.expectEmit(true, true, true, true);
        emit ICanonicalFactory.MirrorDeployed(
            predicted, ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, salt
        );
        factory.deployMirror(att, sigs, bitmap);
    }

    function test_deployMirror_reverts_if_already_deployed() public {
        _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        // Try to deploy again with same origin/chain pair (different nonce but same salt)
        // Need to warp past rate limit
        vm.warp(block.timestamp + RATE_LIMIT + 1);

        (AttestationLib.Attestation memory att2, bytes memory sigs2, uint256 bitmap2) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 2);

        vm.expectRevert(); // MirrorAlreadyDeployed
        factory.deployMirror(att2, sigs2, bitmap2);
    }

    function test_deployMirror_reverts_if_attestation_invalid() public {
        (AttestationLib.Attestation memory att,,) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        // Submit with only 1 signature (below threshold of 3)
        uint256[] memory oneIndex = new uint256[](1);
        oneIndex[0] = 0;
        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (bytes memory sigs, uint256 bitmap) = helper.signAttestation(att, domainSep, oneIndex);

        vm.expectRevert(); // InsufficientSignatures
        factory.deployMirror(att, sigs, bitmap);
    }

    // ─── computeMirrorAddress Tests ──────────────────────────────────

    function test_computeMirrorAddress_is_deterministic() public {
        (AttestationLib.Attestation memory att,,) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        address addr1 = factory.computeMirrorAddress(att);
        address addr2 = factory.computeMirrorAddress(att);
        assertEq(addr1, addr2, "Same input must produce same address");
    }

    function test_computeMirrorAddress_same_before_and_after_deploy() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        address beforeDeploy = factory.computeMirrorAddress(att);
        address mirror = factory.deployMirror(att, sigs, bitmap);
        address afterDeploy = factory.computeMirrorAddress(att);

        assertEq(beforeDeploy, mirror);
        assertEq(afterDeploy, mirror);
    }

    function test_computeMirrorAddress_different_for_different_origins() public {
        (AttestationLib.Attestation memory att1,,) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        address originB = address(0xBBB);
        (AttestationLib.Attestation memory att2,,) =
            _buildSignedAttestation(originB, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        address addr1 = factory.computeMirrorAddress(att1);
        address addr2 = factory.computeMirrorAddress(att2);
        assertTrue(addr1 != addr2, "Different origins must produce different addresses");
    }

    function test_computeMirrorAddress_different_for_different_chains() public {
        (AttestationLib.Attestation memory att1,,) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        (AttestationLib.Attestation memory att2,,) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN_2, 1);

        address addr1 = factory.computeMirrorAddress(att1);
        address addr2 = factory.computeMirrorAddress(att2);
        assertTrue(addr1 != addr2, "Different target chains must produce different addresses");
    }

    // ─── isCanonical Tests ───────────────────────────────────────────

    function test_isCanonical_false_for_random_address() public view {
        assertFalse(factory.isCanonical(address(0x999)));
    }

    function test_isCanonical_false_for_same_bytecode_elsewhere() public {
        // Deploy XythumToken directly (NOT via factory) with same params
        XythumToken directToken = new XythumToken(
            "Xythum Mirror",
            "xRWA",
            ORIGIN_CONTRACT,
            ORIGIN_CHAIN,
            address(compliance),
            1_000_000 ether
        );

        // This is the FORK RESISTANCE test: same bytecode, but not deployed by factory
        assertFalse(factory.isCanonical(address(directToken)));
    }

    // ─── Fee Tests ───────────────────────────────────────────────────

    function test_deploymentFee_collected() public {
        // Set fee
        factory.setDeploymentFee(0.01 ether);

        // Fund caller
        vm.deal(address(this), 1 ether);

        uint256 treasuryBefore = treasury.balance;

        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        factory.deployMirror{ value: 0.01 ether }(att, sigs, bitmap);

        assertEq(treasury.balance - treasuryBefore, 0.01 ether, "Treasury should receive fee");
    }

    function test_deploymentFee_insufficient_reverts() public {
        factory.setDeploymentFee(0.01 ether);
        vm.deal(address(this), 1 ether);

        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                CanonicalFactory.InsufficientFee.selector, 0.005 ether, 0.01 ether
            )
        );
        factory.deployMirror{ value: 0.005 ether }(att, sigs, bitmap);
    }

    function test_deploymentFee_zero_by_default() public view {
        assertEq(factory.deploymentFee(), 0);
    }

    // ─── Pause Tests ─────────────────────────────────────────────────

    function test_pause_blocks_deployment() public {
        factory.pause();

        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        vm.expectRevert(); // EnforcedPause
        factory.deployMirror(att, sigs, bitmap);
    }

    function test_unpause_allows_deployment() public {
        factory.pause();
        factory.unpause();

        address mirror = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);
        assertTrue(factory.isCanonical(mirror));
    }

    // ─── Multiple Mirrors Tests ──────────────────────────────────────

    function test_multiple_mirrors_different_targets() public {
        // Deploy mirror to TARGET_CHAIN
        address mirror1 = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        // Deploy mirror to TARGET_CHAIN_2 (different target, no rate limit conflict since different pair)
        address mirror2 = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN_2, 1);

        // Both canonical
        assertTrue(factory.isCanonical(mirror1));
        assertTrue(factory.isCanonical(mirror2));

        // Different addresses
        assertTrue(mirror1 != mirror2, "Different target chains = different mirrors");
    }

    // ─── Admin Tests ─────────────────────────────────────────────────

    function test_setDeploymentFee() public {
        factory.setDeploymentFee(0.05 ether);
        assertEq(factory.deploymentFee(), 0.05 ether);
    }

    function test_setTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        factory.setTreasury(newTreasury);
        assertEq(factory.treasury(), newTreasury);
    }

    function test_pauseMirror() public {
        address mirror = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);
        factory.pauseMirror(mirror);

        CanonicalFactory.MirrorInfo memory info = factory.getMirrorInfo(mirror);
        assertFalse(info.active, "Mirror should be paused");
    }

    function test_pauseMirror_nonexistent_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(CanonicalFactory.MirrorNotFound.selector, address(0x999))
        );
        factory.pauseMirror(address(0x999));
    }

    function test_getMirrorInfo_nonexistent_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(CanonicalFactory.MirrorNotFound.selector, address(0x999))
        );
        factory.getMirrorInfo(address(0x999));
    }

    function test_admin_functions_onlyOwner() public {
        address attacker = makeAddr("attacker");

        vm.startPrank(attacker);
        vm.expectRevert();
        factory.setDeploymentFee(1 ether);

        vm.expectRevert();
        factory.setTreasury(attacker);

        vm.expectRevert();
        factory.pause();

        vm.expectRevert();
        factory.unpause();
        vm.stopPrank();
    }

    // ─── Mirror Token Verification ───────────────────────────────────

    function test_deployed_mirror_has_correct_metadata() public {
        address mirror = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        XythumToken mirrorToken = XythumToken(mirror);
        assertEq(mirrorToken.name(), "Xythum Mirror");
        assertEq(mirrorToken.symbol(), "xRWA");
        assertEq(mirrorToken.originContract(), ORIGIN_CONTRACT);
        assertEq(mirrorToken.originChainId(), ORIGIN_CHAIN);
        assertEq(mirrorToken.factory(), address(factory));
        assertEq(mirrorToken.compliance(), address(compliance));
    }

    function test_factory_is_authorized_minter_on_mirror() public {
        address mirror = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);
        XythumToken mirrorToken = XythumToken(mirror);
        assertTrue(mirrorToken.authorizedMinters(address(factory)));
    }

    // ─── Edge Cases ──────────────────────────────────────────────────

    function test_mirrors_mapping_stores_salt() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);

        bytes32 salt = AttestationLib.canonicalSalt(att);
        address mirror = factory.deployMirror(att, sigs, bitmap);

        assertEq(factory.mirrors(salt), mirror, "Salt mapping should point to mirror");
    }

    // ─── Direct Path Tests ───────────────────────────────────────────

    /// @notice Build and sign an attestation targeting block.chainid (for direct path)
    function _buildDirectAttestation(address originContract, uint256 originChainId, uint256 nonce)
        internal
        view
        returns (AttestationLib.Attestation memory att, bytes memory signatures, uint256 bitmap)
    {
        // Direct path uses block.chainid as targetChainId
        att = helper.buildAttestation(originContract, originChainId, block.chainid, nonce);

        uint256[] memory signerIndices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            signerIndices[i] = i;
        }

        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (signatures, bitmap) = helper.signAttestation(att, domainSep, signerIndices);
    }

    function test_deployMirrorDirect_succeeds() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildDirectAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, 1);

        address predicted = factory.computeMirrorAddress(att);
        address mirror = factory.deployMirrorDirect(att, sigs, bitmap);

        assertTrue(mirror != address(0), "Mirror should not be zero address");
        assertTrue(mirror.code.length > 0, "Mirror should have code");
        assertTrue(factory.isCanonical(mirror));
        assertEq(mirror, predicted, "Direct deploy address should match prediction");
    }

    function test_deployMirrorDirect_wrong_chain_reverts() public {
        // Build attestation with a non-matching targetChainId
        AttestationLib.Attestation memory att =
            helper.buildAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, 999, 1);

        uint256[] memory signerIndices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            signerIndices[i] = i;
        }
        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (bytes memory sigs, uint256 bitmap) = helper.signAttestation(att, domainSep, signerIndices);

        vm.expectRevert(
            abi.encodeWithSelector(CanonicalFactory.WrongTargetChain.selector, 999, block.chainid)
        );
        factory.deployMirrorDirect(att, sigs, bitmap);
    }

    function test_deployMirrorDirect_same_result_as_ccip_path() public {
        // Compute the expected address
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildDirectAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, 1);

        address expected = factory.computeMirrorAddress(att);
        address mirror = factory.deployMirrorDirect(att, sigs, bitmap);

        assertEq(mirror, expected, "Direct path must produce same address as computeMirrorAddress");
    }

    function test_deployMirrorDirect_duplicate_reverts() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildDirectAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, 1);

        factory.deployMirrorDirect(att, sigs, bitmap);

        // Warp past rate limit, build new attestation with different nonce (same origin/target pair)
        vm.warp(block.timestamp + RATE_LIMIT + 1);

        (AttestationLib.Attestation memory att2, bytes memory sigs2, uint256 bitmap2) =
            _buildDirectAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, 2);

        vm.expectRevert(); // MirrorAlreadyDeployed
        factory.deployMirrorDirect(att2, sigs2, bitmap2);
    }

    function test_deployMirrorDirect_insufficient_sigs_reverts() public {
        AttestationLib.Attestation memory att =
            helper.buildAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, block.chainid, 1);

        // Sign with only 2 signers (below threshold of 3)
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (bytes memory sigs, uint256 bitmap) = helper.signAttestation(att, domainSep, indices);

        vm.expectRevert(); // InsufficientSignatures
        factory.deployMirrorDirect(att, sigs, bitmap);
    }

    function test_deployMirrorDirect_permissionless() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildDirectAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, 1);

        // Call from a random address (not owner, not signer)
        address randomCaller = makeAddr("randomCaller");
        vm.prank(randomCaller);
        address mirror = factory.deployMirrorDirect(att, sigs, bitmap);

        assertTrue(factory.isCanonical(mirror), "Anyone should be able to deploy with valid sigs");
    }

    function test_ccip_and_direct_share_state() public {
        // Deploy via direct path first
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildDirectAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, 1);

        factory.deployMirrorDirect(att, sigs, bitmap);

        // Warp past rate limit, try deploying same origin/target via CCIP path (deployMirror)
        vm.warp(block.timestamp + RATE_LIMIT + 1);

        (AttestationLib.Attestation memory att2, bytes memory sigs2, uint256 bitmap2) =
            _buildDirectAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, 2);

        vm.expectRevert(); // MirrorAlreadyDeployed — same salt
        factory.deployMirror(att2, sigs2, bitmap2);
    }

    function test_direct_and_ccip_different_origins_coexist() public {
        // Deploy origin A via direct path
        (AttestationLib.Attestation memory attA, bytes memory sigsA, uint256 bitmapA) =
            _buildDirectAttestation(ORIGIN_CONTRACT, ORIGIN_CHAIN, 1);

        address mirrorA = factory.deployMirrorDirect(attA, sigsA, bitmapA);

        // Deploy origin B via CCIP path (deployMirror)
        address originB = address(0xBBB);
        (AttestationLib.Attestation memory attB, bytes memory sigsB, uint256 bitmapB) =
            _buildDirectAttestation(originB, ORIGIN_CHAIN, 1);

        address mirrorB = factory.deployMirror(attB, sigsB, bitmapB);

        assertTrue(factory.isCanonical(mirrorA), "Mirror A should be canonical");
        assertTrue(factory.isCanonical(mirrorB), "Mirror B should be canonical");
        assertTrue(mirrorA != mirrorB, "Different origins must produce different mirrors");
    }

    // ─── Enumeration Tests ───────────────────────────────────────────

    function test_getMirrorCount_increments() public {
        assertEq(factory.getMirrorCount(), 0, "Should start at 0");

        _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);
        assertEq(factory.getMirrorCount(), 1, "Should be 1 after first deploy");

        _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN_2, 1);
        assertEq(factory.getMirrorCount(), 2, "Should be 2 after second deploy");
    }

    function test_getAllMirrors_returns_all() public {
        address mirror1 = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);
        address mirror2 = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN_2, 1);

        address[] memory all = factory.getAllMirrors();
        assertEq(all.length, 2);
        assertEq(all[0], mirror1);
        assertEq(all[1], mirror2);
    }

    function test_getMirrors_pagination() public {
        address mirror1 = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN, 1);
        address mirror2 = _deployTestMirror(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN_2, 1);

        // Get first page (offset 0, limit 1)
        address[] memory page1 = factory.getMirrors(0, 1);
        assertEq(page1.length, 1);
        assertEq(page1[0], mirror1);

        // Get second page (offset 1, limit 1)
        address[] memory page2 = factory.getMirrors(1, 1);
        assertEq(page2.length, 1);
        assertEq(page2[0], mirror2);

        // Get all (offset 0, limit 10)
        address[] memory pageAll = factory.getMirrors(0, 10);
        assertEq(pageAll.length, 2);
    }

    function test_getMirrors_out_of_bounds_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(CanonicalFactory.OutOfBounds.selector, 0, 0));
        factory.getMirrors(0, 10);
    }
}
