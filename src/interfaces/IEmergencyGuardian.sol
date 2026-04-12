// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEmergencyGuardian
/// @author Xythum Protocol
/// @notice Interface for the emergency guardian with circuit breakers
interface IEmergencyGuardian {
    /// @notice Emitted when global emergency is activated
    event EmergencyActivated(address indexed activator, bytes32 reason);

    /// @notice Emitted when emergency is deactivated
    event EmergencyDeactivated(address indexed deactivator);

    /// @notice Emitted when a circuit breaker trips
    event CircuitBreakerTripped(bytes32 indexed breakerId, uint256 value, uint256 threshold);

    /// @notice Emitted when a guardian is added or removed
    event GuardianUpdated(address indexed guardian, bool active);

    /// @notice Activate global emergency pause
    function activateEmergency(bytes32 reason) external;

    /// @notice Deactivate emergency (requires higher threshold)
    function deactivateEmergency() external;

    /// @notice Check if emergency is active
    function isEmergencyActive() external view returns (bool);

    /// @notice Report a metric value for circuit breaker evaluation
    function reportMetric(bytes32 breakerId, uint256 value) external;

    /// @notice Check if a circuit breaker is tripped
    function isCircuitBreakerTripped(bytes32 breakerId) external view returns (bool);

    /// @notice Add or remove a guardian
    function setGuardian(address guardian, bool active) external;
}
