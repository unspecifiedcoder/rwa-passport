// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { EmergencyGuardian } from "../../src/security/EmergencyGuardian.sol";

/// @title EmergencyGuardian Unit Tests
contract EmergencyGuardianTest is Test {
    EmergencyGuardian public guardian;

    address public governance = makeAddr("governance");
    address public guardian1 = makeAddr("guardian1");
    address public guardian2 = makeAddr("guardian2");
    address public nonGuardian = makeAddr("nonGuardian");

    bytes32 public constant TVL_BREAKER = keccak256("TVL_DROP");
    bytes32 public constant VOLUME_BREAKER = keccak256("VOLUME_SPIKE");

    function setUp() public {
        address[] memory guardians = new address[](2);
        guardians[0] = guardian1;
        guardians[1] = guardian2;

        guardian = new EmergencyGuardian(governance, guardians);
    }

    // ─── Emergency Control ───────────────────────────────────────────

    function test_guardianCanActivateEmergency() public {
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("exploit_detected"));

        assertTrue(guardian.isEmergencyActive());
        assertEq(guardian.emergencyReason(), keccak256("exploit_detected"));
    }

    function test_nonGuardianCannotActivateEmergency() public {
        vm.prank(nonGuardian);
        vm.expectRevert(EmergencyGuardian.OnlyGuardian.selector);
        guardian.activateEmergency(keccak256("fake"));
    }

    function test_doubleActivationReverts() public {
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("first"));

        vm.prank(guardian2);
        vm.expectRevert(EmergencyGuardian.EmergencyAlreadyActive.selector);
        guardian.activateEmergency(keccak256("second"));
    }

    function test_governanceCanDeactivate() public {
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("exploit"));

        vm.prank(governance);
        guardian.deactivateEmergency();

        assertFalse(guardian.isEmergencyActive());
    }

    function test_guardianCannotDeactivate() public {
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("exploit"));

        vm.prank(guardian1);
        vm.expectRevert(EmergencyGuardian.OnlyGovernance.selector);
        guardian.deactivateEmergency();
    }

    function test_deactivateWhenNotActiveReverts() public {
        vm.prank(governance);
        vm.expectRevert(EmergencyGuardian.EmergencyNotActive.selector);
        guardian.deactivateEmergency();
    }

    // ─── Circuit Breakers ────────────────────────────────────────────

    function test_configureCircuitBreaker() public {
        vm.prank(governance);
        guardian.configureCircuitBreaker(TVL_BREAKER, 1_000_000 ether, false, 1 hours);

        (uint256 threshold,,, bool isUpperBound, bool active,) =
            guardian.circuitBreakers(TVL_BREAKER);
        assertEq(threshold, 1_000_000 ether);
        assertFalse(isUpperBound);
        assertTrue(active);
    }

    function test_circuitBreakerTripsOnLowerBound() public {
        vm.prank(governance);
        guardian.configureCircuitBreaker(TVL_BREAKER, 1_000_000 ether, false, 1 hours);

        // Report value below threshold
        guardian.reportMetric(TVL_BREAKER, 500_000 ether);

        assertTrue(guardian.isCircuitBreakerTripped(TVL_BREAKER));
    }

    function test_circuitBreakerTripsOnUpperBound() public {
        vm.prank(governance);
        guardian.configureCircuitBreaker(VOLUME_BREAKER, 10_000_000 ether, true, 1 hours);

        // Report value above threshold
        guardian.reportMetric(VOLUME_BREAKER, 20_000_000 ether);

        assertTrue(guardian.isCircuitBreakerTripped(VOLUME_BREAKER));
    }

    function test_circuitBreakerDoesNotTripWithinBounds() public {
        vm.prank(governance);
        guardian.configureCircuitBreaker(TVL_BREAKER, 1_000_000 ether, false, 1 hours);

        // Report value above threshold (lower bound - trip if below)
        guardian.reportMetric(TVL_BREAKER, 2_000_000 ether);

        assertFalse(guardian.isCircuitBreakerTripped(TVL_BREAKER));
    }

    function test_circuitBreakerCooldown() public {
        vm.prank(governance);
        guardian.configureCircuitBreaker(TVL_BREAKER, 1_000_000 ether, false, 1 hours);

        guardian.reportMetric(TVL_BREAKER, 500_000 ether);
        assertTrue(guardian.isCircuitBreakerTripped(TVL_BREAKER));

        // Reset
        vm.prank(governance);
        guardian.resetCircuitBreaker(TVL_BREAKER);
        assertFalse(guardian.isCircuitBreakerTripped(TVL_BREAKER));

        // Try to trip again during cooldown - should not trip
        guardian.reportMetric(TVL_BREAKER, 500_000 ether);
        assertFalse(guardian.isCircuitBreakerTripped(TVL_BREAKER));

        // After cooldown
        vm.warp(block.timestamp + 2 hours);
        guardian.reportMetric(TVL_BREAKER, 500_000 ether);
        assertTrue(guardian.isCircuitBreakerTripped(TVL_BREAKER));
    }

    function test_unconfiguredBreakerReverts() public {
        vm.expectRevert();
        guardian.reportMetric(keccak256("UNKNOWN"), 100);
    }

    // ─── Guardian Management ─────────────────────────────────────────

    function test_addGuardian() public {
        vm.prank(governance);
        guardian.setGuardian(nonGuardian, true);

        assertTrue(guardian.guardians(nonGuardian));
        assertEq(guardian.guardianCount(), 3);
    }

    function test_removeGuardian() public {
        vm.prank(governance);
        guardian.setGuardian(guardian1, false);

        assertFalse(guardian.guardians(guardian1));
        assertEq(guardian.guardianCount(), 1);
    }

    function test_onlyGovernanceCanManageGuardians() public {
        vm.prank(guardian1);
        vm.expectRevert(EmergencyGuardian.OnlyGovernance.selector);
        guardian.setGuardian(nonGuardian, true);
    }

    // ─── Pausable Contracts ──────────────────────────────────────────

    function test_registerPausableContract() public {
        address mockContract = makeAddr("pausable");

        vm.prank(governance);
        guardian.registerPausableContract(mockContract);

        assertEq(guardian.pausableContractCount(), 1);
    }
}
