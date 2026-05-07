// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IEmergencyGuardian } from "../interfaces/IEmergencyGuardian.sol";

/// @title EmergencyGuardian
/// @author Xythum Protocol
/// @notice Emergency response system with circuit breakers for the Xythum protocol.
///         - Multi-guardian emergency activation (any guardian can trigger)
///         - Governance-only deactivation (prevents guardian abuse)
///         - Automatic circuit breakers for TVL drops, volume spikes, oracle failures
///         - Cooldown periods to prevent oscillation
/// @dev Designed for billion-dollar protocol safety. Circuit breakers automatically
///      halt operations when anomalous conditions are detected.
contract EmergencyGuardian is IEmergencyGuardian {
    // ─── Custom Errors ───────────────────────────────────────────────
    error OnlyGuardian();
    error OnlyGovernance();
    error EmergencyAlreadyActive();
    error EmergencyNotActive();
    error CircuitBreakerNotConfigured(bytes32 breakerId);
    error CooldownNotElapsed(bytes32 breakerId, uint256 availableAt);
    error InvalidThreshold();

    // ─── Structs ─────────────────────────────────────────────────────
    /// @notice Circuit breaker configuration
    struct CircuitBreaker {
        uint256 threshold; // Value that triggers the breaker
        uint256 cooldownPeriod; // Minimum time between trips
        uint256 lastTripped; // Timestamp of last trip
        bool isUpperBound; // true = trip if value > threshold, false = trip if value < threshold
        bool active; // Whether this breaker is configured
        bool tripped; // Current trip state
    }

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Governance address (timelock) - can deactivate emergency
    address public immutable governance;

    /// @notice Whether a global emergency is active
    bool public emergencyActive;

    /// @notice Timestamp when emergency was activated
    uint256 public emergencyActivatedAt;

    /// @notice Reason for the current emergency
    bytes32 public emergencyReason;

    /// @notice Authorized guardian addresses
    mapping(address => bool) public guardians;

    /// @notice Number of active guardians
    uint256 public guardianCount;

    /// @notice Circuit breaker configurations
    mapping(bytes32 => CircuitBreaker) public circuitBreakers;

    /// @notice All circuit breaker IDs (for enumeration)
    bytes32[] public breakerIds;

    /// @notice Contracts that should be paused during emergency
    address[] public pausableContracts;

    // ─── Constants ────────────────────────────────────────────────────
    /// @notice Maximum emergency duration before auto-deactivation (7 days)
    uint256 public constant MAX_EMERGENCY_DURATION = 7 days;

    // ─── Events ──────────────────────────────────────────────────────
    event PausableContractRegistered(address indexed contractAddr);
    event PauseFailed(address indexed contractAddr);
    event CircuitBreakerConfigured(
        bytes32 indexed breakerId, uint256 threshold, bool isUpperBound, uint256 cooldownPeriod
    );
    event CircuitBreakerReset(bytes32 indexed breakerId);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(address _governance, address[] memory _initialGuardians) {
        governance = _governance;

        for (uint256 i = 0; i < _initialGuardians.length; i++) {
            guardians[_initialGuardians[i]] = true;
        }
        guardianCount = _initialGuardians.length;
    }

    // ─── Modifiers ───────────────────────────────────────────────────
    modifier onlyGuardian() {
        if (!guardians[msg.sender]) revert OnlyGuardian();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    // ─── Emergency Control ───────────────────────────────────────────

    /// @inheritdoc IEmergencyGuardian
    function activateEmergency(bytes32 reason) external onlyGuardian {
        if (emergencyActive) revert EmergencyAlreadyActive();

        emergencyActive = true;
        emergencyActivatedAt = block.timestamp;
        emergencyReason = reason;

        // Attempt to pause all registered contracts
        for (uint256 i = 0; i < pausableContracts.length; i++) {
            (bool success,) = pausableContracts[i].call(abi.encodeWithSignature("pause()"));
            if (!success) emit PauseFailed(pausableContracts[i]);
        }

        emit EmergencyActivated(msg.sender, reason);
    }

    /// @inheritdoc IEmergencyGuardian
    function deactivateEmergency() external {
        // Governance can always deactivate
        // Anyone can deactivate if MAX_EMERGENCY_DURATION has passed (auto-timeout)
        if (msg.sender != governance) {
            if (!emergencyActive || block.timestamp < emergencyActivatedAt + MAX_EMERGENCY_DURATION)
            {
                revert OnlyGovernance();
            }
        }
        if (!emergencyActive) revert EmergencyNotActive();

        emergencyActive = false;
        emergencyReason = bytes32(0);

        // Attempt to unpause all registered contracts
        for (uint256 i = 0; i < pausableContracts.length; i++) {
            (bool success,) = pausableContracts[i].call(abi.encodeWithSignature("unpause()"));
            if (!success) emit PauseFailed(pausableContracts[i]);
        }

        emit EmergencyDeactivated(msg.sender);
    }

    /// @inheritdoc IEmergencyGuardian
    function isEmergencyActive() external view returns (bool) {
        return emergencyActive;
    }

    // ─── Circuit Breakers ────────────────────────────────────────────

    /// @notice Configure a circuit breaker
    function configureCircuitBreaker(
        bytes32 breakerId,
        uint256 threshold,
        bool isUpperBound,
        uint256 cooldownPeriod
    ) external onlyGovernance {
        if (threshold == 0) revert InvalidThreshold();

        if (!circuitBreakers[breakerId].active) {
            breakerIds.push(breakerId);
        }

        circuitBreakers[breakerId] = CircuitBreaker({
            threshold: threshold,
            cooldownPeriod: cooldownPeriod,
            lastTripped: 0,
            isUpperBound: isUpperBound,
            active: true,
            tripped: false
        });

        emit CircuitBreakerConfigured(breakerId, threshold, isUpperBound, cooldownPeriod);
    }

    /// @inheritdoc IEmergencyGuardian
    function reportMetric(bytes32 breakerId, uint256 value) external {
        CircuitBreaker storage breaker = circuitBreakers[breakerId];
        if (!breaker.active) revert CircuitBreakerNotConfigured(breakerId);

        // Check cooldown
        if (
            breaker.lastTripped != 0
                && block.timestamp < breaker.lastTripped + breaker.cooldownPeriod
        ) {
            return; // Still in cooldown, skip
        }

        // Evaluate condition
        bool shouldTrip;
        if (breaker.isUpperBound) {
            shouldTrip = value > breaker.threshold;
        } else {
            shouldTrip = value < breaker.threshold;
        }

        if (shouldTrip && !breaker.tripped) {
            breaker.tripped = true;
            breaker.lastTripped = block.timestamp;
            emit CircuitBreakerTripped(breakerId, value, breaker.threshold);
        }
    }

    /// @notice Reset a tripped circuit breaker
    function resetCircuitBreaker(bytes32 breakerId) external onlyGovernance {
        CircuitBreaker storage breaker = circuitBreakers[breakerId];
        if (!breaker.active) revert CircuitBreakerNotConfigured(breakerId);
        breaker.tripped = false;
        emit CircuitBreakerReset(breakerId);
    }

    /// @inheritdoc IEmergencyGuardian
    function isCircuitBreakerTripped(bytes32 breakerId) external view returns (bool) {
        return circuitBreakers[breakerId].tripped;
    }

    // ─── Guardian Management ─────────────────────────────────────────

    /// @inheritdoc IEmergencyGuardian
    function setGuardian(address guardian, bool active) external onlyGovernance {
        if (guardians[guardian] != active) {
            guardians[guardian] = active;
            if (active) {
                guardianCount++;
            } else {
                guardianCount--;
            }
            emit GuardianUpdated(guardian, active);
        }
    }

    /// @notice Register a contract for automatic pause/unpause during emergencies
    function registerPausableContract(address contractAddr) external onlyGovernance {
        pausableContracts.push(contractAddr);
        emit PausableContractRegistered(contractAddr);
    }

    // ─── View ────────────────────────────────────────────────────────

    /// @notice Get all circuit breaker IDs
    function getAllBreakerIds() external view returns (bytes32[] memory) {
        return breakerIds;
    }

    /// @notice Get count of registered pausable contracts
    function pausableContractCount() external view returns (uint256) {
        return pausableContracts.length;
    }
}
