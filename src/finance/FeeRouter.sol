// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IFeeRouter } from "../interfaces/IFeeRouter.sol";

/// @title FeeRouter
/// @author Xythum Protocol
/// @notice Dynamic fee collection and distribution engine for the Xythum protocol.
///         Collects fees from all protocol actions (mirror deployments, attestations,
///         vault yields) and distributes them across treasury, staking, insurance, and burn.
/// @dev Fee splits are configurable via governance. All values in basis points (10000 = 100%).
contract FeeRouter is IFeeRouter, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Custom Errors ───────────────────────────────────────────────
    error InvalidFeeSplit(uint256 total);
    error ZeroAmount();
    error OnlyCollector();
    error ZeroAddress();
    error ETHTransferFailed(address recipient);

    // ─── Constants ───────────────────────────────────────────────────
    uint256 public constant BPS_DENOMINATOR = 10000;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Current fee split configuration
    FeeSplit public feeSplit;

    /// @notice Treasury address
    address public treasury;

    /// @notice Staking rewards pool address
    address public stakingPool;

    /// @notice Insurance fund address
    address public insuranceFund;

    /// @notice Protocol token for burning
    address public protocolToken;

    /// @notice Accumulated fees per token
    mapping(address => uint256) public accumulatedFees;

    /// @notice Addresses authorized to collect fees (factory, vaults, hooks)
    mapping(address => bool) public feeCollectors;

    /// @notice Total fees collected per token (lifetime)
    mapping(address => uint256) public totalFeesCollected;

    /// @notice Total fees distributed per token (lifetime)
    mapping(address => uint256) public totalFeesDistributed;

    // ─── Events ──────────────────────────────────────────────────────
    event CollectorUpdated(address indexed collector, bool authorized);
    event RecipientUpdated(string recipientType, address indexed newAddress);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(
        address _treasury,
        address _stakingPool,
        address _insuranceFund,
        address _protocolToken,
        address _owner
    ) Ownable(_owner) {
        if (_treasury == address(0)) revert ZeroAddress();

        treasury = _treasury;
        stakingPool = _stakingPool;
        insuranceFund = _insuranceFund;
        protocolToken = _protocolToken;

        // Default split: 40% treasury, 30% staking, 20% insurance, 10% burn
        feeSplit =
            FeeSplit({ treasuryBps: 4000, stakingBps: 3000, insuranceBps: 2000, burnBps: 1000 });
    }

    // ─── Fee Collection ──────────────────────────────────────────────

    /// @inheritdoc IFeeRouter
    function collectFee(address token, uint256 amount, address payer) external {
        if (!feeCollectors[msg.sender]) revert OnlyCollector();
        if (amount == 0) revert ZeroAmount();

        accumulatedFees[token] += amount;
        totalFeesCollected[token] += amount;

        IERC20(token).safeTransferFrom(payer, address(this), amount);
        emit FeesCollected(token, amount, payer);
    }

    /// @notice Collect ETH fees
    function collectETHFee() external payable {
        if (!feeCollectors[msg.sender]) revert OnlyCollector();
        if (msg.value == 0) revert ZeroAmount();

        accumulatedFees[address(0)] += msg.value;
        totalFeesCollected[address(0)] += msg.value;

        emit FeesCollected(address(0), msg.value, msg.sender);
    }

    // ─── Fee Distribution ────────────────────────────────────────────

    /// @inheritdoc IFeeRouter
    function distributeFees(address token) external nonReentrant {
        uint256 amount = accumulatedFees[token];
        if (amount == 0) revert ZeroAmount();

        accumulatedFees[token] = 0;
        totalFeesDistributed[token] += amount;

        uint256 toTreasury = (amount * feeSplit.treasuryBps) / BPS_DENOMINATOR;
        uint256 toStaking = (amount * feeSplit.stakingBps) / BPS_DENOMINATOR;
        uint256 toInsurance = (amount * feeSplit.insuranceBps) / BPS_DENOMINATOR;
        uint256 toBurn = amount - toTreasury - toStaking - toInsurance;

        if (token == address(0)) {
            _distributeETH(toTreasury, toStaking, toInsurance, toBurn);
        } else {
            _distributeToken(token, toTreasury, toStaking, toInsurance, toBurn);
        }

        emit FeesDistributed(token, toTreasury, toStaking, toInsurance, toBurn);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    /// @notice Update the fee split configuration
    function setFeeSplit(
        uint256 treasuryBps,
        uint256 stakingBps,
        uint256 insuranceBps,
        uint256 burnBps
    ) external onlyOwner {
        uint256 total = treasuryBps + stakingBps + insuranceBps + burnBps;
        if (total != BPS_DENOMINATOR) revert InvalidFeeSplit(total);

        feeSplit = FeeSplit({
            treasuryBps: treasuryBps,
            stakingBps: stakingBps,
            insuranceBps: insuranceBps,
            burnBps: burnBps
        });

        emit FeeSplitUpdated(treasuryBps, stakingBps, insuranceBps, burnBps);
    }

    function setFeeCollector(address collector, bool authorized) external onlyOwner {
        feeCollectors[collector] = authorized;
        emit CollectorUpdated(collector, authorized);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit RecipientUpdated("treasury", _treasury);
    }

    function setStakingPool(address _stakingPool) external onlyOwner {
        stakingPool = _stakingPool;
        emit RecipientUpdated("staking", _stakingPool);
    }

    function setInsuranceFund(address _insuranceFund) external onlyOwner {
        insuranceFund = _insuranceFund;
        emit RecipientUpdated("insurance", _insuranceFund);
    }

    // ─── View ────────────────────────────────────────────────────────

    /// @inheritdoc IFeeRouter
    function getFeeSplit() external view returns (FeeSplit memory) {
        return feeSplit;
    }

    /// @inheritdoc IFeeRouter
    function pendingFees(address token) external view returns (uint256) {
        return accumulatedFees[token];
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _distributeToken(
        address token,
        uint256 toTreasury,
        uint256 toStaking,
        uint256 toInsurance,
        uint256 toBurn
    ) internal {
        IERC20 tok = IERC20(token);

        if (toTreasury > 0 && treasury != address(0)) {
            tok.safeTransfer(treasury, toTreasury);
        }
        if (toStaking > 0 && stakingPool != address(0)) {
            tok.safeTransfer(stakingPool, toStaking);
        }
        if (toInsurance > 0 && insuranceFund != address(0)) {
            tok.safeTransfer(insuranceFund, toInsurance);
        }
        if (toBurn > 0 && token == protocolToken) {
            // Burn XYT by sending to dead address
            tok.safeTransfer(address(0xdead), toBurn);
        } else if (toBurn > 0) {
            // Non-protocol tokens: send burn portion to treasury instead
            tok.safeTransfer(treasury, toBurn);
        }
    }

    function _distributeETH(
        uint256 toTreasury,
        uint256 toStaking,
        uint256 toInsurance,
        uint256 toBurn
    ) internal {
        if (toTreasury > 0 && treasury != address(0)) {
            (bool s,) = treasury.call{ value: toTreasury }("");
            if (!s) revert ETHTransferFailed(treasury);
        }
        if (toStaking > 0 && stakingPool != address(0)) {
            (bool s,) = stakingPool.call{ value: toStaking }("");
            if (!s) revert ETHTransferFailed(stakingPool);
        }
        if (toInsurance > 0 && insuranceFund != address(0)) {
            (bool s,) = insuranceFund.call{ value: toInsurance }("");
            if (!s) revert ETHTransferFailed(insuranceFund);
        }
        // ETH burn portion goes to treasury
        if (toBurn > 0 && treasury != address(0)) {
            (bool s,) = treasury.call{ value: toBurn }("");
            if (!s) revert ETHTransferFailed(treasury);
        }
    }
}
