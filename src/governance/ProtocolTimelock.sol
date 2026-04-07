// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title ProtocolTimelock
/// @author Xythum Protocol
/// @notice Timelock controller for delayed execution of governance proposals.
///         All critical protocol actions (fee changes, upgrades, treasury) must
///         pass through this timelock with a minimum 2-day delay.
/// @dev Roles:
///      - Proposer: XythumGovernor contract
///      - Executor: XythumGovernor contract (or open to anyone after delay)
///      - Admin: Initially deployer, then renounced to make governance fully decentralized
contract ProtocolTimelock is TimelockController {
    /// @notice Deploy the timelock
    /// @param minDelay Minimum delay in seconds (e.g., 2 days = 172800)
    /// @param proposers Array of proposer addresses (Governor contract)
    /// @param executors Array of executor addresses (Governor or address(0) for open execution)
    /// @param admin Admin address (set to address(0) to renounce admin immediately)
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) { }
}
