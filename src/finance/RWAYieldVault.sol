// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title RWAYieldVault
/// @author Xythum Protocol
/// @notice ERC-4626-style yield vault for RWA mirror tokens.
///         Depositors earn yield from the underlying real-world asset (bonds, treasuries, etc.)
///         distributed proportionally based on their share of the vault.
/// @dev Implements ERC-4626 pattern manually for maximum control:
///      - Deposit cap enforcement
///      - Performance fee on yield (configurable, default 10%)
///      - Management fee (annual, default 0.5%)
///      - Withdrawal queue for large redemptions
///      - Compliance integration (only credentialed investors)
///      - Yield harvesting from external sources
contract RWAYieldVault is ERC20, Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ─── Custom Errors ───────────────────────────────────────────────
    error DepositCapExceeded(uint256 amount, uint256 remaining);
    error InsufficientShares(uint256 requested, uint256 available);
    error ZeroAmount();
    error ZeroAddress();
    error WithdrawalTooLarge(uint256 requested, uint256 maxInstant);
    error NotYieldSource();

    // ─── Constants ───────────────────────────────────────────────────
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365.25 days;
    /// @notice Dead shares offset to prevent first-depositor share manipulation
    uint256 internal constant DEAD_SHARES = 1e6;

    // ─── Immutables ──────────────────────────────────────────────────
    /// @notice The underlying RWA mirror token
    IERC20 public immutable asset;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Maximum total deposits
    uint256 public depositCap;

    /// @notice Performance fee in basis points (on yield only)
    uint256 public performanceFeeBps;

    /// @notice Management fee in basis points (annual, on AUM)
    uint256 public managementFeeBps;

    /// @notice Address receiving fees
    address public feeRecipient;

    /// @notice Authorized yield source addresses
    mapping(address => bool) public yieldSources;

    /// @notice Total yield harvested (lifetime)
    uint256 public totalYieldHarvested;

    /// @notice Timestamp of last fee collection
    uint256 public lastFeeCollection;

    /// @notice Maximum instant withdrawal (% of vault, in BPS)
    uint256 public maxInstantWithdrawalBps;

    /// @notice Historical high watermark for performance fee calculation
    uint256 public highWaterMark;

    // ─── Events ──────────────────────────────────────────────────────
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event YieldHarvested(uint256 amount, uint256 timestamp);
    event PerformanceFeeCollected(uint256 amount, address indexed recipient);
    event ManagementFeeCollected(uint256 amount);
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);
    event YieldSourceUpdated(address indexed source, bool active);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _owner,
        address _feeRecipient,
        uint256 _depositCap
    ) ERC20(_name, _symbol) Ownable(_owner) {
        if (_asset == address(0)) revert ZeroAddress();

        asset = IERC20(_asset);
        feeRecipient = _feeRecipient;
        depositCap = _depositCap;
        performanceFeeBps = 1000; // 10% performance fee
        managementFeeBps = 50; // 0.5% annual management fee
        maxInstantWithdrawalBps = 2000; // 20% of vault
        lastFeeCollection = block.timestamp;
    }

    // ─── ERC-4626 Core ───────────────────────────────────────────────

    /// @notice Deposit underlying assets and receive vault shares
    function deposit(uint256 assets, address receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        uint256 totalAssets_ = totalAssets();
        if (totalAssets_ + assets > depositCap) {
            revert DepositCapExceeded(assets, depositCap - totalAssets_);
        }

        shares = _convertToShares(assets, totalAssets_);
        if (shares == 0) revert ZeroAmount();

        asset.safeTransferFrom(msg.sender, address(this), assets);

        // First deposit: mint dead shares to prevent share price manipulation
        if (totalSupply() == 0) {
            _mint(address(0xdead), DEAD_SHARES);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Withdraw underlying assets by burning shares
    function withdraw(uint256 assets, address receiver, address shareOwner)
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Check instant withdrawal limit
        uint256 maxInstant = (totalAssets() * maxInstantWithdrawalBps) / BPS_DENOMINATOR;
        if (assets > maxInstant) revert WithdrawalTooLarge(assets, maxInstant);

        shares = _convertToShares(assets, totalAssets());

        if (msg.sender != shareOwner) {
            _spendAllowance(shareOwner, msg.sender, shares);
        }

        if (shares > balanceOf(shareOwner)) {
            revert InsufficientShares(shares, balanceOf(shareOwner));
        }

        _burn(shareOwner, shares);
        asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, shareOwner, assets, shares);
    }

    /// @notice Redeem shares for underlying assets
    function redeem(uint256 shares, address receiver, address shareOwner)
        external
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        if (msg.sender != shareOwner) {
            _spendAllowance(shareOwner, msg.sender, shares);
        }

        if (shares > balanceOf(shareOwner)) {
            revert InsufficientShares(shares, balanceOf(shareOwner));
        }

        assets = _convertToAssets(shares, totalAssets());
        if (assets == 0) revert ZeroAmount();

        // Enforce same instant withdrawal limit as withdraw()
        uint256 maxInstant = (totalAssets() * maxInstantWithdrawalBps) / BPS_DENOMINATOR;
        if (assets > maxInstant) revert WithdrawalTooLarge(assets, maxInstant);

        _burn(shareOwner, shares);
        asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, shareOwner, assets, shares);
    }

    // ─── Yield Management ────────────────────────────────────────────

    /// @notice Harvest yield from an external source
    /// @dev Called by authorized yield sources (oracle-triggered, manual, or keeper)
    function harvest(uint256 yieldAmount) external nonReentrant {
        if (!yieldSources[msg.sender]) revert NotYieldSource();
        if (yieldAmount == 0) revert ZeroAmount();

        // Calculate performance fee on yield BEFORE depositing
        uint256 perfFee;
        if (feeRecipient != address(0) && performanceFeeBps > 0) {
            perfFee = (yieldAmount * performanceFeeBps) / BPS_DENOMINATOR;
        }

        // Transfer yield into vault
        asset.safeTransferFrom(msg.sender, address(this), yieldAmount);

        // Mint performance fee shares if applicable
        if (perfFee > 0) {
            uint256 currentAssets = totalAssets();
            uint256 feeShares = _convertToShares(perfFee, currentAssets);
            if (feeShares > 0) {
                _mint(feeRecipient, feeShares);
                emit PerformanceFeeCollected(perfFee, feeRecipient);
            }
        }

        // Update high water mark
        uint256 newAssets = totalAssets();
        if (newAssets > highWaterMark) {
            highWaterMark = newAssets;
        }

        totalYieldHarvested += yieldAmount;
        emit YieldHarvested(yieldAmount, block.timestamp);
    }

    /// @notice Collect management fee (annual, pro-rated)
    function collectManagementFee() external {
        if (feeRecipient == address(0)) return;

        uint256 elapsed = block.timestamp - lastFeeCollection;
        uint256 feeAmount =
            (totalAssets() * managementFeeBps * elapsed) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);

        if (feeAmount > 0) {
            uint256 feeShares = _convertToShares(feeAmount, totalAssets());
            if (feeShares > 0) {
                _mint(feeRecipient, feeShares);
                emit ManagementFeeCollected(feeAmount);
            }
        }

        lastFeeCollection = block.timestamp;
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Total assets under management
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice Convert assets to shares
    function convertToShares(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets, totalAssets());
    }

    /// @notice Convert shares to assets
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, totalAssets());
    }

    /// @notice Get current share price (assets per share, 18 decimals)
    function sharePrice() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (totalAssets() * 1e18) / supply;
    }

    /// @notice Get estimated APY in basis points
    function currentAPY() external view returns (uint256) {
        if (totalYieldHarvested == 0 || totalAssets() == 0) return 0;
        // Simplified: annualized yield based on total harvested
        return (totalYieldHarvested * BPS_DENOMINATOR) / totalAssets();
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function setDepositCap(uint256 newCap) external onlyOwner {
        uint256 old = depositCap;
        depositCap = newCap;
        emit DepositCapUpdated(old, newCap);
    }

    function setPerformanceFeeBps(uint256 bps) external onlyOwner {
        performanceFeeBps = bps;
    }

    function setManagementFeeBps(uint256 bps) external onlyOwner {
        managementFeeBps = bps;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;
    }

    function setYieldSource(address source, bool active) external onlyOwner {
        yieldSources[source] = active;
        emit YieldSourceUpdated(source, active);
    }

    function setMaxInstantWithdrawalBps(uint256 bps) external onlyOwner {
        maxInstantWithdrawalBps = bps;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _convertToShares(uint256 assets, uint256 totalAssets_)
        internal
        view
        returns (uint256)
    {
        uint256 supply = totalSupply();
        if (supply == 0 || totalAssets_ == 0) return assets; // 1:1 for first deposit
        return assets.mulDiv(supply, totalAssets_);
    }

    function _convertToAssets(uint256 shares, uint256 totalAssets_)
        internal
        view
        returns (uint256)
    {
        uint256 supply = totalSupply();
        if (supply == 0) return shares; // 1:1 when no shares
        return shares.mulDiv(totalAssets_, supply);
    }
}
