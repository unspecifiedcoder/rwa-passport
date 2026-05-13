// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";
import { StakingModule } from "../../src/staking/StakingModule.sol";
import { EmergencyGuardian } from "../../src/security/EmergencyGuardian.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";

/// @title AccessControlEdgeCases
/// @notice Privilege escalation, ownership, and guardian abuse tests
contract AccessControlEdgeCasesTest is Test {
    EmergencyGuardian public guardian;
    SignerRegistry public signerRegistry;
    CanonicalFactory public factory;
    AttestationRegistry public attestationRegistry;
    MockCompliance public compliance;

    address public governance = makeAddr("governance");
    address public guardian1 = makeAddr("guardian1");
    address public attacker = makeAddr("attacker");
    address public owner;

    function setUp() public {
        vm.warp(100_000);
        owner = address(this);

        address[] memory guardians = new address[](1);
        guardians[0] = guardian1;
        guardian = new EmergencyGuardian(governance, guardians);

        signerRegistry = new SignerRegistry(owner, 3);
        attestationRegistry =
            new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);
        compliance = new MockCompliance();
        factory = new CanonicalFactory(
            address(attestationRegistry), address(compliance), makeAddr("treasury"), owner
        );
    }

    // ─── Guardian cannot deactivate emergency (only governance) ─────

    function test_guardianCannotDeactivateEmergency() public {
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("test"));

        vm.prank(guardian1);
        vm.expectRevert(EmergencyGuardian.OnlyGovernance.selector);
        guardian.deactivateEmergency();
    }

    // ─── Emergency auto-deactivation after MAX_EMERGENCY_DURATION ───

    function test_emergencyAutoDeactivationAfter7Days() public {
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("test"));

        // Before 7 days: random user cannot deactivate
        vm.warp(block.timestamp + 6 days);
        vm.prank(attacker);
        vm.expectRevert(EmergencyGuardian.OnlyGovernance.selector);
        guardian.deactivateEmergency();

        // After 7 days: anyone can deactivate (auto-timeout)
        vm.warp(block.timestamp + 2 days); // now 8 days total
        vm.prank(attacker);
        guardian.deactivateEmergency();
        assertFalse(guardian.isEmergencyActive());
    }

    // ─── Signer removal cooldown enforcement ────────────────────────

    function test_signerRemovalCooldownEnforced() public {
        address signer = makeAddr("signer");
        signerRegistry.registerSigner(signer);
        signerRegistry.registerSigner(makeAddr("signer2"));
        signerRegistry.registerSigner(makeAddr("signer3"));
        signerRegistry.registerSigner(makeAddr("signer4"));

        // First call initiates cooldown
        signerRegistry.removeSigner(signer);

        // Second call before cooldown reverts
        vm.expectRevert();
        signerRegistry.removeSigner(signer);

        // After cooldown: succeeds
        vm.warp(block.timestamp + 7 days + 1);
        signerRegistry.removeSigner(signer);
        assertFalse(signerRegistry.isSigner(signer));
    }

    // ─── Paused factory blocks deployMirrorDirect ───────────────────

    function test_pausedFactoryBlocksDeployMirrorDirect() public {
        factory.pause();

        vm.expectRevert();
        factory.deployMirrorDirect(
            _dummyAttestation(), bytes(""), 0
        );
    }

    // ─── Non-owner cannot set authorized minter ─────────────────────

    function test_nonOwnerCannotPauseFactory() public {
        vm.prank(attacker);
        vm.expectRevert();
        factory.pause();
    }

    // ─── Guardian management only by governance ─────────────────────

    function test_onlyGovernanceCanAddGuardian() public {
        vm.prank(attacker);
        vm.expectRevert(EmergencyGuardian.OnlyGovernance.selector);
        guardian.setGuardian(attacker, true);
    }

    function test_governanceCanAddAndRemoveGuardian() public {
        vm.startPrank(governance);
        guardian.setGuardian(attacker, true);
        assertTrue(guardian.guardians(attacker));

        guardian.setGuardian(attacker, false);
        assertFalse(guardian.guardians(attacker));
        vm.stopPrank();
    }

    // ─── Helper ─────────────────────────────────────────────────────

    function _dummyAttestation()
        internal
        view
        returns (AttestationLib.Attestation memory)
    {
        return AttestationLib.Attestation({
            originContract: address(0xAAA),
            originChainId: 1,
            targetChainId: block.chainid,
            navRoot: bytes32(0),
            complianceRoot: bytes32(0),
            lockedAmount: 1000 ether,
            timestamp: block.timestamp,
            nonce: 1
        });
    }
}
