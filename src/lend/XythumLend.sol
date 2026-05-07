// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title XythumLend
/// @author Xythum Protocol
/// @notice Single-pair, no-interest, no-liquidation demo lending market. Users supply
///         an xRWA mirror as collateral (18 decimals) and borrow mock USDC (6 decimals)
///         against it at a fixed 70% LTV with a hardcoded $1 oracle price.
/// @dev    Demo-only. No interest accrual, no liquidation engine, no dynamic oracle.
///         Reserves are seeded once by the owner and recycled through repays.
contract XythumLend is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Custom Errors ───────────────────────────────────────────────
    error AmountZero();
    error NoActivePosition();
    error InsufficientCollateral(uint256 requested, uint256 available);
    error InsufficientReserves(uint256 requested, uint256 available);
    error LtvBreached(uint256 debtBps, uint256 maxBps);
    error CannotRescueMarketToken();

    // ─── Constants ───────────────────────────────────────────────────
    /// @notice Maximum loan-to-value, in basis points (70%).
    uint256 public constant LTV_BPS = 7000;
    /// @notice Basis-point denominator.
    uint256 public constant BPS_DENOM = 10_000;
    /// @notice Hardcoded $1 oracle price in 6-decimal precision (matches USDC).
    uint256 public constant ORACLE_PRICE_E6 = 1e6;

    // ─── Immutables ──────────────────────────────────────────────────
    /// @notice The xRWA mirror token accepted as collateral (18 decimals).
    IERC20 public immutable collateralToken;
    /// @notice The debt asset lent out (mock USDC, 6 decimals).
    IERC20 public immutable debtToken;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Per-user position.
    /// @param collateral xRWA collateral supplied (18 decimals).
    /// @param debt       USDC borrowed (6 decimals).
    struct Position {
        uint256 collateral;
        uint256 debt;
    }

    /// @notice user => Position.
    mapping(address => Position) public positions;

    /// @notice Sum of all users' collateral.
    uint256 public totalCollateral;
    /// @notice Sum of all users' outstanding debt.
    uint256 public totalDebt;
    /// @notice USDC seeded by the owner and currently available to lend out.
    uint256 public reservesBalance;

    // ─── Events ──────────────────────────────────────────────────────
    event Supplied(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event ReservesSeeded(uint256 amount);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(address _collateralToken, address _debtToken, address initialOwner)
        Ownable(initialOwner)
    {
        collateralToken = IERC20(_collateralToken);
        debtToken = IERC20(_debtToken);
    }

    // ─── User Functions ──────────────────────────────────────────────

    /// @notice Supply xRWA collateral.
    function supply(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert AmountZero();
        positions[msg.sender].collateral += amount;
        totalCollateral += amount;
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Supplied(msg.sender, amount);
    }

    /// @notice Withdraw xRWA collateral. Reverts if it would push the position above LTV.
    function withdraw(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert AmountZero();
        Position storage p = positions[msg.sender];
        if (p.collateral < amount) revert InsufficientCollateral(amount, p.collateral);

        p.collateral -= amount;
        totalCollateral -= amount;
        collateralToken.safeTransfer(msg.sender, amount);

        // Health check is post-state-mutation: must reflect the new collateral level.
        _requireHealthy(msg.sender);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Borrow USDC against supplied collateral.
    function borrow(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert AmountZero();
        if (reservesBalance < amount) revert InsufficientReserves(amount, reservesBalance);

        positions[msg.sender].debt += amount;
        totalDebt += amount;
        reservesBalance -= amount;
        debtToken.safeTransfer(msg.sender, amount);

        _requireHealthy(msg.sender);

        emit Borrowed(msg.sender, amount);
    }

    /// @notice Repay outstanding debt. Pass `type(uint256).max` to repay everything.
    function repay(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert AmountZero();
        Position storage p = positions[msg.sender];
        if (p.debt == 0) revert NoActivePosition();

        // Cap at outstanding debt so callers can pass max-uint to clear the position.
        if (amount > p.debt) amount = p.debt;

        p.debt -= amount;
        totalDebt -= amount;
        reservesBalance += amount;
        debtToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Repaid(msg.sender, amount);
    }

    // ─── Owner Functions ─────────────────────────────────────────────

    /// @notice Seed lendable reserves. Owner pulls USDC from themselves into the market.
    function seedReserves(uint256 amount) external onlyOwner {
        if (amount == 0) revert AmountZero();
        reservesBalance += amount;
        debtToken.safeTransferFrom(msg.sender, address(this), amount);
        emit ReservesSeeded(amount);
    }

    /// @notice Pause user-facing entrypoints (supply / withdraw / borrow / repay).
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume after a pause.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Recover unrelated tokens accidentally sent to this contract.
    /// @dev    Reverts for `collateralToken` and `debtToken` to protect user deposits
    ///         and seeded reserves.
    function rescueStuckTokens(IERC20 token, address to) external onlyOwner {
        if (token == collateralToken || token == debtToken) revert CannotRescueMarketToken();
        token.safeTransfer(to, token.balanceOf(address(this)));
    }

    // ─── Views ───────────────────────────────────────────────────────

    /// @notice Read a user's position alongside a derived health score.
    /// @return collateral User's xRWA collateral (18 decimals).
    /// @return debt       User's USDC debt (6 decimals).
    /// @return healthBps  collateralValue / debt in bps. `type(uint256).max` if no debt.
    ///                    Higher is healthier — 100% LTV = 10000, 70% LTV = 14285.
    function positionOf(address user)
        external
        view
        returns (uint256 collateral, uint256 debt, uint256 healthBps)
    {
        Position memory p = positions[user];
        collateral = p.collateral;
        debt = p.debt;
        if (debt == 0) {
            healthBps = type(uint256).max;
        } else {
            uint256 collateralValueUsd6 = (collateral * ORACLE_PRICE_E6) / 1e18;
            healthBps = (collateralValueUsd6 * BPS_DENOM) / debt;
        }
    }

    /// @notice Maximum additional USDC the user can borrow without breaching LTV,
    ///         capped by available reserves.
    function maxBorrow(address user) external view returns (uint256) {
        Position memory p = positions[user];
        uint256 collateralValueUsd6 = (p.collateral * ORACLE_PRICE_E6) / 1e18;
        uint256 maxDebt = (collateralValueUsd6 * LTV_BPS) / BPS_DENOM;
        if (maxDebt <= p.debt) return 0;
        uint256 headroom = maxDebt - p.debt;
        return headroom > reservesBalance ? reservesBalance : headroom;
    }

    /// @notice Maximum collateral the user can withdraw while remaining within LTV.
    function maxWithdraw(address user) external view returns (uint256) {
        Position memory p = positions[user];
        if (p.debt == 0) return p.collateral;

        // minRequiredCollateral18 = debt6 * 1e18 * BPS_DENOM / (LTV_BPS * ORACLE_PRICE_E6)
        uint256 minRequiredCollateral18 =
            (p.debt * 1e18 * BPS_DENOM) / (LTV_BPS * ORACLE_PRICE_E6);
        if (minRequiredCollateral18 >= p.collateral) return 0;
        return p.collateral - minRequiredCollateral18;
    }

    // ─── Internal ────────────────────────────────────────────────────

    /// @notice Revert if `user`'s position is above the configured LTV.
    /// @dev    Called at the END of `borrow` and `withdraw`, after state mutations,
    ///         so the check reflects post-action solvency.
    function _requireHealthy(address user) internal view {
        Position memory p = positions[user];
        if (p.debt == 0) return; // no debt → trivially healthy.

        uint256 collateralValueUsd6 = (p.collateral * ORACLE_PRICE_E6) / 1e18;
        if (collateralValueUsd6 == 0) {
            // Has debt but no collateral value: treat as max-breached.
            revert LtvBreached(type(uint256).max, LTV_BPS);
        }
        uint256 debtBps = (p.debt * BPS_DENOM) / collateralValueUsd6;
        if (debtBps > LTV_BPS) revert LtvBreached(debtBps, LTV_BPS);
    }
}
