// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICompliance
/// @notice Interface for transfer compliance checks
interface ICompliance {
    /// @notice Check if a transfer is compliant
    /// @param from Sender address
    /// @param to Receiver address
    /// @param amount Transfer amount
    /// @return True if the transfer is allowed
    function isTransferCompliant(address from, address to, uint256 amount)
        external
        view
        returns (bool);
}

/// @title MockCompliance
/// @notice Simple allowlist-based compliance contract for testing
/// @dev In production, this would be a full ERC-3643 identity registry
contract MockCompliance is ICompliance {
    mapping(address => bool) public isWhitelisted;
    bool public enforceCompliance;

    constructor() {
        enforceCompliance = true;
    }

    /// @notice Set whitelist status for an address
    function setWhitelisted(address user, bool status) external {
        isWhitelisted[user] = status;
    }

    /// @notice Toggle compliance enforcement (for testing)
    function setEnforceCompliance(bool enforce) external {
        enforceCompliance = enforce;
    }

    /// @inheritdoc ICompliance
    function isTransferCompliant(address from, address to, uint256) external view returns (bool) {
        if (!enforceCompliance) return true;
        // address(0) is allowed for mint/burn operations
        bool fromOk = from == address(0) || isWhitelisted[from];
        bool toOk = to == address(0) || isWhitelisted[to];
        return fromOk && toOk;
    }
}
