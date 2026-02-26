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

/// @title CanonicalFactoryHandler
/// @notice Handler for invariant testing — calls deployMirror with varied inputs
contract CanonicalFactoryHandler is Test {
    CanonicalFactory public factory;
    AttestationRegistry public attestationRegistry;
    AttestationHelper public helper;

    /// @notice All deployed mirrors, for invariant checks
    address[] public deployedMirrors;
    /// @notice Corresponding attestations for each deployed mirror
    AttestationLib.Attestation[] public deployedAtts;
    /// @notice Track salts → mirrors to check uniqueness
    mapping(bytes32 => address) public saltToMirror;
    /// @notice Track mirror → salt for reverse lookup
    mapping(address => bytes32) public mirrorToSalt;

    uint256 public nextNonce;
    uint256 public constant THRESHOLD = 3;
    uint256 public constant RATE_LIMIT = 1 hours;

    constructor(
        CanonicalFactory _factory,
        AttestationRegistry _attestationRegistry,
        AttestationHelper _helper
    ) {
        factory = _factory;
        attestationRegistry = _attestationRegistry;
        helper = _helper;
        nextNonce = 1;
    }

    /// @notice Deploy a mirror with fuzzed origin/target parameters
    /// @dev Constrains inputs to valid ranges to avoid uninteresting reverts
    function deployMirror(uint160 originSeed, uint32 targetSeed) external {
        // Derive unique origin and target from seeds
        address originContract = address(uint160(uint256(originSeed) % type(uint160).max + 1));
        uint256 originChainId = 1;
        uint256 targetChainId = uint256(targetSeed) % 1000 + 2; // 2..1001

        // Compute salt to check if already deployed
        bytes32 salt = keccak256(abi.encode(originContract, originChainId, targetChainId));
        if (saltToMirror[salt] != address(0)) {
            // Already deployed, skip
            return;
        }

        // Warp time so rate limit and staleness are satisfied
        vm.warp(block.timestamp + RATE_LIMIT + 1);

        uint256 nonce = nextNonce++;

        AttestationLib.Attestation memory att = helper.buildAttestation(
            originContract, originChainId, targetChainId, nonce
        );

        uint256[] memory signerIndices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            signerIndices[i] = i;
        }

        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (bytes memory sigs, uint256 bitmap) = helper.signAttestation(att, domainSep, signerIndices);

        address mirror = factory.deployMirror(att, sigs, bitmap);

        deployedMirrors.push(mirror);
        deployedAtts.push(att);
        saltToMirror[salt] = mirror;
        mirrorToSalt[mirror] = salt;
    }

    /// @notice Number of deployed mirrors
    function mirrorCount() external view returns (uint256) {
        return deployedMirrors.length;
    }
}

/// @title CanonicalInvariantTest
/// @notice Invariant tests for the CanonicalFactory
/// @dev Verifies: address determinism, no duplicates, isCanonical correctness, origin metadata
contract CanonicalInvariantTest is Test {
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    CanonicalFactory public factory;
    MockCompliance public compliance;
    AttestationHelper public helper;
    CanonicalFactoryHandler public handler;

    function setUp() public {
        vm.warp(100_000);

        address owner = address(this);

        // Full stack
        signerRegistry = new SignerRegistry(owner, 3);
        helper = new AttestationHelper();
        helper.generateSigners(5);
        for (uint256 i = 0; i < 5; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }
        attestationRegistry = new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);
        compliance = new MockCompliance();
        factory = new CanonicalFactory(
            address(attestationRegistry),
            address(compliance),
            makeAddr("treasury"),
            owner
        );

        handler = new CanonicalFactoryHandler(factory, attestationRegistry, helper);

        // Target only the handler
        targetContract(address(handler));
    }

    /// @notice computeMirrorAddress must match actual deployed address for every mirror
    function invariant_computeAddress_matches_deployed() public view {
        uint256 count = handler.mirrorCount();
        for (uint256 i = 0; i < count; i++) {
            address mirror = handler.deployedMirrors(i);
            (
                address originContract,
                uint256 originChainId,
                uint256 targetChainId,
                , // attestationId
                , // deployedAt
                  // active
            ) = factory.mirrorInfoMap(mirror);

            // Rebuild a minimal attestation for computeMirrorAddress
            // The salt only depends on originContract, originChainId, targetChainId
            // But computeMirrorAddress needs a full Attestation struct (those 3 fields for salt + lockedAmount for creation code)
            // lockedAmount must match the original attestation (1_000_000 ether from AttestationHelper)
            AttestationLib.Attestation memory att = AttestationLib.Attestation({
                originContract: originContract,
                originChainId: originChainId,
                targetChainId: targetChainId,
                navRoot: bytes32(0),
                complianceRoot: bytes32(0),
                lockedAmount: 1_000_000 ether,
                timestamp: 0,
                nonce: 0
            });

            address predicted = factory.computeMirrorAddress(att);
            assertEq(predicted, mirror, "computeMirrorAddress must match deployed");
        }
    }

    /// @notice No two different salts map to the same mirror address
    function invariant_no_duplicate_mirrors() public view {
        uint256 count = handler.mirrorCount();
        for (uint256 i = 0; i < count; i++) {
            for (uint256 j = i + 1; j < count; j++) {
                assertTrue(
                    handler.deployedMirrors(i) != handler.deployedMirrors(j),
                    "Duplicate mirror address detected"
                );
            }
        }
    }

    /// @notice isCanonical(addr) == true for every deployed mirror
    function invariant_isCanonical_iff_deployed() public view {
        uint256 count = handler.mirrorCount();
        for (uint256 i = 0; i < count; i++) {
            address mirror = handler.deployedMirrors(i);
            assertTrue(factory.isCanonical(mirror), "Deployed mirror must be canonical");
        }
    }

    /// @notice Every canonical mirror has correct origin metadata
    function invariant_mirror_has_correct_origin() public view {
        uint256 count = handler.mirrorCount();
        for (uint256 i = 0; i < count; i++) {
            address mirror = handler.deployedMirrors(i);

            (
                address originContract,
                uint256 originChainId,
                ,,,
            ) = factory.mirrorInfoMap(mirror);

            XythumToken mirrorToken = XythumToken(mirror);
            assertEq(
                mirrorToken.originContract(),
                originContract,
                "Mirror originContract must match mirrorInfo"
            );
            assertEq(
                mirrorToken.originChainId(),
                originChainId,
                "Mirror originChainId must match mirrorInfo"
            );
        }
    }
}
