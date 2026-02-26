// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IZKCollateral } from "../interfaces/IZKCollateral.sol";
import { ICanonicalFactory } from "../interfaces/ICanonicalFactory.sol";
import { IXythumToken } from "../interfaces/IXythumToken.sol";

/// @title AaveAdapter
/// @author Xythum Protocol
/// @notice Bridges ZK collateral proofs into Aave's lending system.
///         A user proves they have sufficient collateral via ZK proof,
///         and the adapter mints "collateral receipt" tokens that can be
///         deposited into Aave as standard ERC-20 collateral.
/// @dev MVP wrapper pattern: Aave sees a standard ERC-20 collateral token
///      backed by ZK-verified cross-chain collateral.
///      TODO(upgrade): Deep Aave integration with custom aToken/debtToken
contract AaveAdapter is Ownable2Step {
    // ─── Custom Errors ───────────────────────────────────────────────
    error ProofAlreadyUsed(bytes32 proofId);
    error ProofTooOld(bytes32 proofId, uint256 age);
    error ProofNotOwner(bytes32 proofId, address expected, address actual);
    error AssetNotCanonical(address asset);
    error ReceiptTokenNotSet();
    error InsufficientReceiptBalance(address user, uint256 requested, uint256 available);

    // ─── Events ──────────────────────────────────────────────────────
    event CollateralDeposited(address indexed user, bytes32 indexed proofId, uint256 receiptAmount);
    event ReceiptRedeemed(address indexed user, uint256 amount);
    event MaxProofAgeUpdated(uint256 newAge);
    event ReceiptTokenUpdated(address newToken);

    // ─── Immutables ──────────────────────────────────────────────────
    /// @notice The ZK collateral verifier contract
    IZKCollateral public immutable zkVerifier;

    /// @notice The canonical factory for isCanonical checks
    ICanonicalFactory public immutable factory;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Proofs that have been used for collateral deposits
    mapping(bytes32 => bool) public usedProofs;

    /// @notice Maximum age (seconds) for a proof to be valid for deposit
    uint256 public maxProofAge;

    /// @notice The receipt token contract (ERC-20 with mint/burn by adapter)
    address public receiptToken;

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _zkVerifier Address of the CollateralVerifier
    /// @param _factory Address of the CanonicalFactory
    /// @param _maxProofAge Maximum proof age in seconds
    /// @param _owner Contract owner
    constructor(address _zkVerifier, address _factory, uint256 _maxProofAge, address _owner)
        Ownable(_owner)
    {
        zkVerifier = IZKCollateral(_zkVerifier);
        factory = ICanonicalFactory(_factory);
        maxProofAge = _maxProofAge;
    }

    // ─── External Functions ──────────────────────────────────────────

    /// @notice Deposit collateral using a verified ZK proof
    /// @param proofId The proof ID from CollateralVerifier
    /// @return receiptAmount Amount of receipt tokens minted
    function depositWithProof(bytes32 proofId) external returns (uint256 receiptAmount) {
        if (receiptToken == address(0)) revert ReceiptTokenNotSet();

        // 1. Get proof details
        (uint256 minValue, address asset, uint256 verifiedAt) =
            zkVerifier.getCollateralValue(proofId);

        // 2. Verify proof freshness
        uint256 age = block.timestamp - verifiedAt;
        if (age > maxProofAge) revert ProofTooOld(proofId, age);

        // 3. Verify proof not already used for deposit
        if (usedProofs[proofId]) revert ProofAlreadyUsed(proofId);
        usedProofs[proofId] = true;

        // 4. Verify asset is a canonical Xythum mirror
        if (!factory.isCanonical(asset)) revert AssetNotCanonical(asset);

        // 5. Mint receipt tokens equal to the proven minimum value
        receiptAmount = minValue;
        IXythumToken(receiptToken).mint(msg.sender, receiptAmount);

        emit CollateralDeposited(msg.sender, proofId, receiptAmount);
    }

    /// @notice Redeem (burn) receipt tokens after repaying Aave loan
    /// @param amount Amount of receipt tokens to burn
    function redeemReceipt(uint256 amount) external {
        if (receiptToken == address(0)) revert ReceiptTokenNotSet();
        IXythumToken(receiptToken).burn(msg.sender, amount);
        emit ReceiptRedeemed(msg.sender, amount);
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    /// @notice Set the maximum proof age
    /// @param _maxProofAge New maximum proof age in seconds
    function setMaxProofAge(uint256 _maxProofAge) external onlyOwner {
        maxProofAge = _maxProofAge;
        emit MaxProofAgeUpdated(_maxProofAge);
    }

    /// @notice Set the receipt token address
    /// @param _receiptToken Address of the receipt token contract
    function setReceiptToken(address _receiptToken) external onlyOwner {
        receiptToken = _receiptToken;
        emit ReceiptTokenUpdated(_receiptToken);
    }
}
