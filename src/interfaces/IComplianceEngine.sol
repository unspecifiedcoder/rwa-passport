// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IComplianceEngine
/// @author Xythum Protocol
/// @notice Interface for on-chain KYC/AML/accredited investor compliance
interface IComplianceEngine {
    /// @notice Investor credential tiers
    enum InvestorTier {
        NONE,
        RETAIL, // Basic KYC verified
        QUALIFIED, // Qualified purchaser
        ACCREDITED, // Accredited investor
        INSTITUTIONAL // Institutional-grade verification
    }

    /// @notice Emitted when an investor's credentials are updated
    event CredentialUpdated(address indexed investor, InvestorTier tier, uint256 expiry);

    /// @notice Emitted when an investor is blacklisted
    event InvestorBlacklisted(address indexed investor, bytes32 reason);

    /// @notice Emitted when an investor is removed from blacklist
    event InvestorWhitelisted(address indexed investor);

    /// @notice Emitted when a compliance provider is updated
    event ProviderUpdated(address indexed provider, bool active);

    /// @notice Set investor credential tier
    function setCredential(address investor, InvestorTier tier, uint256 expiry) external;

    /// @notice Batch set credentials for multiple investors
    function batchSetCredentials(
        address[] calldata investors,
        InvestorTier[] calldata tiers,
        uint256[] calldata expiries
    ) external;

    /// @notice Blacklist an investor
    function blacklist(address investor, bytes32 reason) external;

    /// @notice Remove investor from blacklist
    function removeBlacklist(address investor) external;

    /// @notice Check if a transfer is compliant (ICompliance compatible)
    function isTransferCompliant(address from, address to, uint256 amount)
        external
        view
        returns (bool);

    /// @notice Get investor tier
    function getInvestorTier(address investor) external view returns (InvestorTier);

    /// @notice Check if investor credentials are valid (not expired)
    function isCredentialValid(address investor) external view returns (bool);

    /// @notice Check if an investor is blacklisted
    function isBlacklisted(address investor) external view returns (bool);
}
