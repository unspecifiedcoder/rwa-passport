// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IComplianceEngine } from "../interfaces/IComplianceEngine.sol";

/// @title ComplianceEngine
/// @author Xythum Protocol
/// @notice On-chain KYC/AML/accredited investor compliance registry.
///         Implements the ICompliance interface for XythumToken transfer hooks.
///         Supports tiered investor credentials with expiry and blacklisting.
/// @dev Designed for institutional-grade compliance:
///      - Multiple credential tiers (retail -> institutional)
///      - Time-bound credentials with automatic expiry
///      - Per-asset minimum tier requirements
///      - Authorized compliance providers (Chainalysis, Elliptic integrations)
///      - Batch operations for onboarding campaigns
contract ComplianceEngine is IComplianceEngine, Ownable2Step {
    // ─── Custom Errors ───────────────────────────────────────────────
    error OnlyProvider();
    error InvalidTier();
    error ArrayLengthMismatch();
    error AlreadyBlacklisted(address investor);
    error NotBlacklisted(address investor);
    error ZeroAddress();

    // ─── Structs ─────────────────────────────────────────────────────
    struct Credential {
        InvestorTier tier;
        uint256 expiry; // Unix timestamp when credential expires
        uint256 issuedAt; // When the credential was issued
        address issuedBy; // Which provider issued it
    }

    /// @notice Per-asset compliance rules
    struct AssetRule {
        InvestorTier minimumTier; // Minimum tier required to hold this asset
        uint256 maxTransferAmount; // Maximum single transfer amount (0 = unlimited)
        bool requireBothParties; // Both sender and receiver must be compliant
    }

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Investor credentials
    mapping(address => Credential) public credentials;

    /// @notice Blacklisted addresses
    mapping(address => bool) public blacklisted;

    /// @notice Blacklist reasons
    mapping(address => bytes32) public blacklistReasons;

    /// @notice Authorized compliance providers
    mapping(address => bool) public providers;

    /// @notice Per-asset compliance rules
    mapping(address => AssetRule) public assetRules;

    /// @notice Default minimum tier for assets without specific rules
    InvestorTier public defaultMinimumTier;

    /// @notice Total credentialed investors
    uint256 public totalCredentialed;

    /// @notice Total blacklisted addresses
    uint256 public totalBlacklisted;

    // ─── Events ──────────────────────────────────────────────────────
    event AssetRuleUpdated(
        address indexed asset, InvestorTier minimumTier, uint256 maxTransferAmount
    );
    event DefaultTierUpdated(InvestorTier tier);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(address _owner) Ownable(_owner) {
        defaultMinimumTier = InvestorTier.RETAIL;
        providers[_owner] = true;
    }

    // ─── Modifiers ───────────────────────────────────────────────────
    modifier onlyProvider() {
        if (!providers[msg.sender] && msg.sender != owner()) revert OnlyProvider();
        _;
    }

    // ─── Credential Management ───────────────────────────────────────

    /// @inheritdoc IComplianceEngine
    function setCredential(address investor, InvestorTier tier, uint256 expiry)
        external
        onlyProvider
    {
        if (investor == address(0)) revert ZeroAddress();
        if (tier == InvestorTier.NONE) revert InvalidTier();

        bool isNew = credentials[investor].tier == InvestorTier.NONE;

        credentials[investor] = Credential({
            tier: tier, expiry: expiry, issuedAt: block.timestamp, issuedBy: msg.sender
        });

        if (isNew) totalCredentialed++;

        emit CredentialUpdated(investor, tier, expiry);
    }

    /// @inheritdoc IComplianceEngine
    function batchSetCredentials(
        address[] calldata investors,
        InvestorTier[] calldata tiers,
        uint256[] calldata expiries
    ) external onlyProvider {
        if (investors.length != tiers.length || investors.length != expiries.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < investors.length; i++) {
            if (investors[i] == address(0)) revert ZeroAddress();
            if (tiers[i] == InvestorTier.NONE) revert InvalidTier();

            bool isNew = credentials[investors[i]].tier == InvestorTier.NONE;

            credentials[investors[i]] = Credential({
                tier: tiers[i], expiry: expiries[i], issuedAt: block.timestamp, issuedBy: msg.sender
            });

            if (isNew) totalCredentialed++;

            emit CredentialUpdated(investors[i], tiers[i], expiries[i]);
        }
    }

    // ─── Blacklist Management ────────────────────────────────────────

    /// @inheritdoc IComplianceEngine
    function blacklist(address investor, bytes32 reason) external onlyProvider {
        if (investor == address(0)) revert ZeroAddress();
        if (blacklisted[investor]) revert AlreadyBlacklisted(investor);

        blacklisted[investor] = true;
        blacklistReasons[investor] = reason;
        totalBlacklisted++;

        emit InvestorBlacklisted(investor, reason);
    }

    /// @inheritdoc IComplianceEngine
    function removeBlacklist(address investor) external onlyOwner {
        if (!blacklisted[investor]) revert NotBlacklisted(investor);

        blacklisted[investor] = false;
        delete blacklistReasons[investor];
        totalBlacklisted--;

        emit InvestorWhitelisted(investor);
    }

    // ─── Compliance Checks ───────────────────────────────────────────

    /// @inheritdoc IComplianceEngine
    /// @dev This implements the ICompliance interface used by XythumToken
    function isTransferCompliant(address from, address to, uint256 amount)
        external
        view
        returns (bool)
    {
        // Mint and burn bypass compliance
        if (from == address(0) || to == address(0)) return true;

        // Blacklist check
        if (blacklisted[from] || blacklisted[to]) return false;

        // Credential check for sender
        if (!_hasValidCredential(from)) return false;

        // Credential check for receiver
        if (!_hasValidCredential(to)) return false;

        // Amount is available for per-asset checks but not enforced at this level
        // (asset-specific rules are checked via getAssetCompliance)
        amount; // silence unused warning

        return true;
    }

    /// @notice Check if a transfer is compliant for a specific asset
    function isAssetTransferCompliant(address asset, address from, address to, uint256 amount)
        external
        view
        returns (bool)
    {
        if (from == address(0) || to == address(0)) return true;
        if (blacklisted[from] || blacklisted[to]) return false;

        AssetRule storage rule = assetRules[asset];
        InvestorTier minTier =
            rule.minimumTier != InvestorTier.NONE ? rule.minimumTier : defaultMinimumTier;

        // Check sender tier
        Credential storage fromCred = credentials[from];
        if (fromCred.tier < minTier || fromCred.expiry < block.timestamp) return false;

        // Check receiver tier
        if (rule.requireBothParties) {
            Credential storage toCred = credentials[to];
            if (toCred.tier < minTier || toCred.expiry < block.timestamp) return false;
        }

        // Check transfer amount limit
        if (rule.maxTransferAmount > 0 && amount > rule.maxTransferAmount) return false;

        return true;
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @inheritdoc IComplianceEngine
    function getInvestorTier(address investor) external view returns (InvestorTier) {
        return credentials[investor].tier;
    }

    /// @inheritdoc IComplianceEngine
    function isCredentialValid(address investor) external view returns (bool) {
        return _hasValidCredential(investor);
    }

    /// @inheritdoc IComplianceEngine
    function isBlacklisted(address investor) external view returns (bool) {
        return blacklisted[investor];
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function setProvider(address provider, bool active) external onlyOwner {
        providers[provider] = active;
        emit ProviderUpdated(provider, active);
    }

    function setAssetRule(
        address asset,
        InvestorTier minimumTier,
        uint256 maxTransferAmount,
        bool requireBothParties
    ) external onlyOwner {
        assetRules[asset] = AssetRule({
            minimumTier: minimumTier,
            maxTransferAmount: maxTransferAmount,
            requireBothParties: requireBothParties
        });
        emit AssetRuleUpdated(asset, minimumTier, maxTransferAmount);
    }

    function setDefaultMinimumTier(InvestorTier tier) external onlyOwner {
        defaultMinimumTier = tier;
        emit DefaultTierUpdated(tier);
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _hasValidCredential(address investor) internal view returns (bool) {
        Credential storage cred = credentials[investor];
        return cred.tier >= defaultMinimumTier && cred.expiry > block.timestamp;
    }
}
