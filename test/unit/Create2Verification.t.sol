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

/// @title Create2VerificationTest
/// @notice Verify that CanonicalFactory's CREATE2 deployment matches Ethereum's spec.
///         Tests deterministic addressing and proves addresses cannot be spoofed.
contract Create2VerificationTest is Test {
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    CanonicalFactory public factory;
    MockCompliance public compliance;
    AttestationHelper public helper;

    uint256 constant NUM_SIGNERS = 5;
    uint256 constant THRESHOLD = 3;

    function setUp() public {
        vm.warp(100_000);

        signerRegistry = new SignerRegistry(address(this), THRESHOLD);
        helper = new AttestationHelper();
        helper.generateSigners(NUM_SIGNERS);
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }
        attestationRegistry = new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);
        compliance = new MockCompliance();
        compliance.setEnforceCompliance(false);
        factory = new CanonicalFactory(
            address(attestationRegistry), address(compliance), makeAddr("treasury"), address(this)
        );
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    function _buildSignedAttestation(
        address origin,
        uint256 originChain,
        uint256 targetChain,
        uint256 nonce
    )
        internal
        view
        returns (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap)
    {
        att = helper.buildAttestation(origin, originChain, targetChain, nonce);
        uint256[] memory idx = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            idx[i] = i;
        }
        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (sigs, bitmap) = helper.signAttestation(att, domainSep, idx);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  CREATE2 matches Ethereum spec
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Manually compute CREATE2 address and verify it matches both
    ///         factory.computeMirrorAddress() and the actual deployed address.
    function test_create2_matches_ethereum_spec() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(address(0xAAAA), 1, block.chainid, 1);

        // 1. Get predicted address from factory
        address predicted = factory.computeMirrorAddress(att);

        // 2. Manually compute CREATE2 address
        // CREATE2: address = keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))[12:]
        bytes32 salt =
            keccak256(abi.encode(att.originContract, att.originChainId, att.targetChainId));

        // initCode = creation code + constructor args
        bytes memory constructorArgs = abi.encode(
            "Xythum Mirror", // name
            "xRWA", // symbol
            att.originContract, // _originContract
            att.originChainId, // _originChainId
            address(compliance), // _compliance
            att.lockedAmount // _mintCap
        );
        bytes memory initCode = abi.encodePacked(type(XythumToken).creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(initCode);

        address manual = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initCodeHash))
                )
            )
        );

        // 3. Verify manual matches factory prediction
        assertEq(manual, predicted, "Manual CREATE2 should match factory.computeMirrorAddress");

        // 4. Deploy and verify actual address matches
        address actual = factory.deployMirror(att, sigs, bitmap);
        assertEq(actual, predicted, "Deployed address should match prediction");
        assertEq(actual, manual, "Deployed address should match manual CREATE2");
    }

    /// @notice CREATE2 address is deterministic — same inputs always give same address
    function test_create2_deterministic_across_calls() public view {
        AttestationLib.Attestation memory att =
            helper.buildAttestation(address(0xBBBB), 1, block.chainid, 1);

        address addr1 = factory.computeMirrorAddress(att);
        address addr2 = factory.computeMirrorAddress(att);
        address addr3 = factory.computeMirrorAddress(att);

        assertEq(addr1, addr2, "Identical calls should return identical addresses");
        assertEq(addr2, addr3, "Multiple calls should be consistent");
    }

    /// @notice Different factory addresses produce different CREATE2 results
    function test_create2_different_deployer_different_address() public {
        CanonicalFactory factory2 = new CanonicalFactory(
            address(attestationRegistry), address(compliance), makeAddr("treasury2"), address(this)
        );

        AttestationLib.Attestation memory att =
            helper.buildAttestation(address(0xCCCC), 1, block.chainid, 1);

        address addr1 = factory.computeMirrorAddress(att);
        address addr2 = factory2.computeMirrorAddress(att);

        assertTrue(addr1 != addr2, "Different factories must produce different addresses");
    }

    /// @notice Verify code at deployed address matches XythumToken
    function test_create2_deployed_code_matches() public {
        (AttestationLib.Attestation memory att, bytes memory sigs, uint256 bitmap) =
            _buildSignedAttestation(address(0xDDDD), 1, block.chainid, 2);

        address mirror = factory.deployMirror(att, sigs, bitmap);

        // Deployed code should be non-empty
        assertTrue(mirror.code.length > 0, "Mirror should have code");

        // Should be a valid XythumToken
        XythumToken token = XythumToken(mirror);
        assertEq(token.name(), "Xythum Mirror");
        assertEq(token.symbol(), "xRWA");
        assertEq(token.originContract(), address(0xDDDD));
        assertEq(token.originChainId(), 1);
        assertEq(token.factory(), address(factory));
    }
}
