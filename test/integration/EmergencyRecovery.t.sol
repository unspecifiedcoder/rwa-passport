// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { EmergencyGuardian } from "../../src/security/EmergencyGuardian.sol";

/// @title EmergencyRecovery
/// @notice Circuit breaker edge cases, guardian race conditions, and recovery flows
contract EmergencyRecoveryTest is Test {
    EmergencyGuardian public guardian;

    address public governance = makeAddr("governance");
    address public guardian1 = makeAddr("guardian1");
    address public guardian2 = makeAddr("guardian2");
    address public anyone = makeAddr("anyone");

    bytes32 public constant TVL_BREAKER = keccak256("TVL_DROP");

    function setUp() public {
        vm.warp(100_000);

        address[] memory guardians = new address[](2);
        guardians[0] = guardian1;
        guardians[1] = guardian2;
        guardian = new EmergencyGuardian(governance, guardians);

        // Configure a circuit breaker
        vm.prank(governance);
        guardian.configureCircuitBreaker(TVL_BREAKER, 1_000_000 ether, false, 1 hours);
    }

    // ─── Circuit breaker reset while emergency is active ────────────

    function test_circuitBreakerReset_duringEmergency() public {
        // Trip breaker
        guardian.reportMetric(TVL_BREAKER, 500_000 ether);
        assertTrue(guardian.isCircuitBreakerTripped(TVL_BREAKER));

        // Activate emergency
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("tvl_crash"));
        assertTrue(guardian.isEmergencyActive());

        // Reset breaker while emergency active — should work independently
        vm.prank(governance);
        guardian.resetCircuitBreaker(TVL_BREAKER);
        assertFalse(guardian.isCircuitBreakerTripped(TVL_BREAKER));

        // Emergency still active (breaker reset doesn't deactivate emergency)
        assertTrue(guardian.isEmergencyActive());
    }

    // ─── Re-activation immediately after deactivation ───────────────

    function test_reactivation_immediatelyAfterDeactivation() public {
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("first"));

        vm.prank(governance);
        guardian.deactivateEmergency();
        assertFalse(guardian.isEmergencyActive());

        // Guardian can immediately re-activate (no cooldown on activation)
        vm.prank(guardian2);
        guardian.activateEmergency(keccak256("second"));
        assertTrue(guardian.isEmergencyActive());
        assertEq(guardian.emergencyReason(), keccak256("second"));
    }

    // ─── Emergency with no pausable contracts ───────────────────────

    function test_emergency_noPausableContracts_gracefulNoOp() public {
        // No pausable contracts registered — activateEmergency should not revert
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("no_contracts"));
        assertTrue(guardian.isEmergencyActive());

        vm.prank(governance);
        guardian.deactivateEmergency();
        assertFalse(guardian.isEmergencyActive());
    }

    // ─── Double activation reverts ──────────────────────────────────

    function test_doubleActivation_reverts() public {
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("first"));

        vm.prank(guardian2);
        vm.expectRevert(EmergencyGuardian.EmergencyAlreadyActive.selector);
        guardian.activateEmergency(keccak256("second"));
    }

    // ─── Circuit breaker with zero threshold reverts ────────────────

    function test_circuitBreaker_zeroThresholdReverts() public {
        vm.prank(governance);
        vm.expectRevert(EmergencyGuardian.InvalidThreshold.selector);
        guardian.configureCircuitBreaker(keccak256("BAD"), 0, false, 1 hours);
    }

    // ─── Unconfigured breaker reportMetric reverts ──────────────────

    function test_unconfiguredBreaker_reportReverts() public {
        vm.expectRevert();
        guardian.reportMetric(keccak256("UNKNOWN"), 100);
    }

    // ─── Emergency reason is cleared on deactivation ────────────────

    function test_emergencyReason_clearedOnDeactivation() public {
        vm.prank(guardian1);
        guardian.activateEmergency(keccak256("crisis"));
        assertEq(guardian.emergencyReason(), keccak256("crisis"));

        vm.prank(governance);
        guardian.deactivateEmergency();
        assertEq(guardian.emergencyReason(), bytes32(0));
    }

    // ─── Deactivation when not active reverts ───────────────────────

    function test_deactivation_whenNotActive_reverts() public {
        vm.prank(governance);
        vm.expectRevert(EmergencyGuardian.EmergencyNotActive.selector);
        guardian.deactivateEmergency();
    }

    // ─── Circuit breaker cooldown prevents re-trip ──────────────────

    function test_circuitBreakerCooldown_preventsReTrip() public {
        // Trip the breaker
        guardian.reportMetric(TVL_BREAKER, 500_000 ether);
        assertTrue(guardian.isCircuitBreakerTripped(TVL_BREAKER));

        // Reset it
        vm.prank(governance);
        guardian.resetCircuitBreaker(TVL_BREAKER);

        // Immediately report again — should NOT re-trip (cooldown active)
        guardian.reportMetric(TVL_BREAKER, 500_000 ether);
        assertFalse(guardian.isCircuitBreakerTripped(TVL_BREAKER));

        // After cooldown period: should re-trip
        vm.warp(block.timestamp + 2 hours);
        guardian.reportMetric(TVL_BREAKER, 500_000 ether);
        assertTrue(guardian.isCircuitBreakerTripped(TVL_BREAKER));
    }
}
