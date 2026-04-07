// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ProtocolTreasury
/// @author Xythum Protocol
/// @notice Multi-asset treasury controlled exclusively by governance (via Timelock).
///         Manages protocol revenue, grants, ecosystem incentives, and insurance reserves.
/// @dev Only the timelock (governance) can authorize disbursements.
///      Supports ETH and any ERC-20 token. Tracks all disbursements on-chain.
contract ProtocolTreasury is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Custom Errors ───────────────────────────────────────────────
    error OnlyGovernance();
    error InsufficientBalance(address token, uint256 requested, uint256 available);
    error TransferFailed();
    error ZeroAddress();
    error ZeroAmount();
    error SpendingLimitExceeded(address token, uint256 amount, uint256 remaining);

    // ─── Structs ─────────────────────────────────────────────────────
    /// @notice Record of a treasury disbursement
    struct Disbursement {
        address token; // address(0) for ETH
        address recipient;
        uint256 amount;
        bytes32 proposalId;
        uint256 timestamp;
    }

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice The governance timelock that controls this treasury
    address public immutable governance;

    /// @notice Per-epoch spending limits per token (0 = unlimited)
    mapping(address => uint256) public epochSpendingLimit;

    /// @notice Spent amount per token in current epoch
    mapping(address => uint256) public epochSpent;

    /// @notice Current epoch start timestamp
    uint256 public epochStart;

    /// @notice Epoch duration (default 30 days)
    uint256 public epochDuration;

    /// @notice All disbursement records
    Disbursement[] public disbursements;

    // ─── Events ──────────────────────────────────────────────────────
    event ETHReceived(address indexed sender, uint256 amount);
    event TokenDisbursed(
        address indexed token, address indexed recipient, uint256 amount, bytes32 proposalId
    );
    event ETHDisbursed(address indexed recipient, uint256 amount, bytes32 proposalId);
    event SpendingLimitUpdated(address indexed token, uint256 limit);
    event EpochReset(uint256 newEpochStart);

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _governance Address of the timelock controller
    /// @param _epochDuration Duration of each spending epoch in seconds
    constructor(address _governance, uint256 _epochDuration) {
        if (_governance == address(0)) revert ZeroAddress();
        governance = _governance;
        epochDuration = _epochDuration;
        epochStart = block.timestamp;
    }

    // ─── Modifiers ───────────────────────────────────────────────────
    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    // ─── Receive ─────────────────────────────────────────────────────
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    // ─── Disbursement Functions ──────────────────────────────────────

    /// @notice Disburse ERC-20 tokens from treasury
    /// @param token The ERC-20 token to disburse
    /// @param recipient The recipient address
    /// @param amount Amount to disburse
    /// @param proposalId The governance proposal that authorized this
    function disburseToken(address token, address recipient, uint256 amount, bytes32 proposalId)
        external
        onlyGovernance
        nonReentrant
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _checkAndUpdateEpoch();
        _checkSpendingLimit(token, amount);

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance(token, amount, balance);

        disbursements.push(
            Disbursement({
                token: token,
                recipient: recipient,
                amount: amount,
                proposalId: proposalId,
                timestamp: block.timestamp
            })
        );

        IERC20(token).safeTransfer(recipient, amount);
        emit TokenDisbursed(token, recipient, amount, proposalId);
    }

    /// @notice Disburse ETH from treasury
    /// @param recipient The recipient address
    /// @param amount Amount of ETH to disburse
    /// @param proposalId The governance proposal that authorized this
    function disburseETH(address recipient, uint256 amount, bytes32 proposalId)
        external
        onlyGovernance
        nonReentrant
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _checkAndUpdateEpoch();
        _checkSpendingLimit(address(0), amount);

        if (address(this).balance < amount) {
            revert InsufficientBalance(address(0), amount, address(this).balance);
        }

        disbursements.push(
            Disbursement({
                token: address(0),
                recipient: recipient,
                amount: amount,
                proposalId: proposalId,
                timestamp: block.timestamp
            })
        );

        (bool sent,) = recipient.call{ value: amount }("");
        if (!sent) revert TransferFailed();

        emit ETHDisbursed(recipient, amount, proposalId);
    }

    // ─── Admin (Governance Only) ─────────────────────────────────────

    /// @notice Set per-epoch spending limit for a token
    function setSpendingLimit(address token, uint256 limit) external onlyGovernance {
        epochSpendingLimit[token] = limit;
        emit SpendingLimitUpdated(token, limit);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get ETH balance of the treasury
    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Get ERC-20 token balance
    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Get total disbursement count
    function disbursementCount() external view returns (uint256) {
        return disbursements.length;
    }

    /// @notice Get remaining spending limit for a token in current epoch
    function remainingSpendingLimit(address token) external view returns (uint256) {
        uint256 limit = epochSpendingLimit[token];
        if (limit == 0) return type(uint256).max;
        uint256 spent = epochSpent[token];
        if (spent >= limit) return 0;
        return limit - spent;
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _checkAndUpdateEpoch() internal {
        if (block.timestamp >= epochStart + epochDuration) {
            epochStart = block.timestamp;
            emit EpochReset(epochStart);
        }
    }

    function _checkSpendingLimit(address token, uint256 amount) internal {
        uint256 limit = epochSpendingLimit[token];
        if (limit == 0) return; // No limit set

        epochSpent[token] += amount;
        if (epochSpent[token] > limit) {
            revert SpendingLimitExceeded(token, amount, limit - (epochSpent[token] - amount));
        }
    }
}
