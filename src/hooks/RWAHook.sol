// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { LPFeeLibrary } from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { ICanonicalFactory } from "../interfaces/ICanonicalFactory.sol";
import { IXythumToken } from "../interfaces/IXythumToken.sol";

/// @title RWAHook
/// @author Xythum Protocol
/// @notice Uniswap V4 hook that enforces RWA-specific rules on pools containing
///         canonical Xythum mirror tokens:
///         1. Only canonical mirrors can use this hook
///         2. All swappers and LPs must be compliant
///         3. Dynamic fees based on NAV staleness
///         4. Pool-level pause capability
/// @dev Implements IHooks directly (no BaseHook — v4-periphery not installed).
///      Hook address must encode enabled flags in its lowest 14 bits.
///      TODO(upgrade): Use permit-based user identification instead of tx.origin
contract RWAHook is IHooks {
    using PoolIdLibrary for PoolKey;

    // ─── Custom Errors ───────────────────────────────────────────────
    error NotCanonicalToken(address token0, address token1);
    error SwapperNotCompliant(address swapper);
    error LPNotCompliant(address lp);
    error PoolPaused(PoolId poolId);
    error HookNotImplemented();
    error OnlyOwner();
    error HookDataRequired();
    error InvalidFeeConfig(uint24 baseFee, uint24 staleFee);

    // ─── Events ──────────────────────────────────────────────────────
    event PoolConfigured(PoolId indexed poolId, address xythumToken);
    event NAVUpdated(PoolId indexed poolId, uint256 timestamp);
    event PoolPauseChanged(PoolId indexed poolId, bool indexed active);

    // ─── Structs ─────────────────────────────────────────────────────
    /// @notice Per-pool configuration
    struct PoolConfig {
        address xythumToken; // which token in the pair is the mirror
        uint24 baseFee; // base fee in hundredths of bps (500 = 5 bps)
        uint24 staleFee; // elevated fee when NAV is stale
        uint256 lastNAVUpdate; // timestamp of last NAV attestation
        bool active;
    }

    // ─── Constants ───────────────────────────────────────────────────
    uint24 public constant DEFAULT_BASE_FEE = 500; // 5 bps
    uint24 public constant DEFAULT_STALE_FEE = 5000; // 50 bps
    uint256 public constant NAV_FRESH_WINDOW = 1 hours;
    uint256 public constant NAV_STALE_WINDOW = 6 hours;

    // ─── Immutables ──────────────────────────────────────────────────
    IPoolManager public immutable poolManager;
    ICanonicalFactory public immutable factory;
    address public immutable owner;

    // ─── Storage ─────────────────────────────────────────────────────
    mapping(PoolId => PoolConfig) public poolConfigs;

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(IPoolManager _poolManager, address _factory, address _owner) {
        poolManager = _poolManager;
        factory = ICanonicalFactory(_factory);
        owner = _owner;

        // Validate that our address encodes the correct hook permissions
        Hooks.validateHookPermissions(IHooks(this), getHookPermissions());
    }

    // ─── Permissions ─────────────────────────────────────────────────

    /// @notice Declare which hook callbacks are enabled
    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ─── Implemented Callbacks ───────────────────────────────────────

    /// @notice Verify pool contains a canonical mirror; initialize pool config
    function beforeInitialize(address, PoolKey calldata key, uint160)
        external
        override
        returns (bytes4)
    {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        bool token0Canonical = factory.isCanonical(token0);
        bool token1Canonical = factory.isCanonical(token1);

        if (!token0Canonical && !token1Canonical) {
            revert NotCanonicalToken(token0, token1);
        }

        address xToken = token0Canonical ? token0 : token1;

        PoolId poolId = key.toId();
        poolConfigs[poolId] = PoolConfig({
            xythumToken: xToken,
            baseFee: DEFAULT_BASE_FEE,
            staleFee: DEFAULT_STALE_FEE,
            lastNAVUpdate: block.timestamp,
            active: true
        });

        emit PoolConfigured(poolId, xToken);
        return IHooks.beforeInitialize.selector;
    }

    /// @notice Compliance check + dynamic fee calculation
    /// @dev The swapper address is decoded from hookData if provided (≥20 bytes).
    ///      If hookData is empty, falls back to tx.origin for backward compatibility.
    ///      The caller (e.g. a router contract) is responsible for authenticating the user
    ///      (via permit or direct call) before passing their address in hookData.
    ///      TODO(v2): Remove tx.origin fallback entirely
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];

        if (!config.active) revert PoolPaused(poolId);

        // Decode the actual user address from hookData (required)
        if (hookData.length < 20) revert HookDataRequired();
        address swapper = abi.decode(hookData, (address));

        IXythumToken xToken = IXythumToken(config.xythumToken);
        if (!xToken.isCompliant(swapper, swapper)) {
            revert SwapperNotCompliant(swapper);
        }

        // Calculate dynamic fee based on NAV staleness
        uint24 fee = _calculateFee(config);

        return (
            IHooks.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            fee | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    /// @notice After swap — protocol fee logging (MVP: no-op)
    /// @dev TODO(v2): Implement protocol fee collection via V4's native mechanism
    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, int128) {
        return (IHooks.afterSwap.selector, 0);
    }

    /// @notice Compliance check for liquidity providers
    /// @dev LP address decoded from hookData if provided, falls back to tx.origin
    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata hookData
    ) external override returns (bytes4) {
        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];

        if (!config.active) revert PoolPaused(poolId);

        // Decode LP address from hookData (required)
        if (hookData.length < 20) revert HookDataRequired();
        address lp = abi.decode(hookData, (address));

        // Compliance check for LP
        IXythumToken xToken = IXythumToken(config.xythumToken);
        if (!xToken.isCompliant(lp, lp)) {
            revert LPNotCompliant(lp);
        }

        return IHooks.beforeAddLiquidity.selector;
    }

    // ─── Non-implemented Callbacks (revert) ──────────────────────────

    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    // ─── Admin / NAV Functions ───────────────────────────────────────

    /// @notice Update NAV timestamp (resets dynamic fee to base)
    /// @dev TODO(v2): Only callable by AttestationRegistry
    function updateNAV(PoolId poolId) external {
        poolConfigs[poolId].lastNAVUpdate = block.timestamp;
        emit NAVUpdated(poolId, block.timestamp);
    }

    /// @notice Pause a pool
    function pausePool(PoolId poolId) external {
        if (msg.sender != owner) revert OnlyOwner();
        poolConfigs[poolId].active = false;
        emit PoolPauseChanged(poolId, false);
    }

    /// @notice Unpause a pool
    function unpausePool(PoolId poolId) external {
        if (msg.sender != owner) revert OnlyOwner();
        poolConfigs[poolId].active = true;
        emit PoolPauseChanged(poolId, true);
    }

    // ─── Internal ────────────────────────────────────────────────────

    /// @notice Calculate dynamic fee based on NAV staleness
    /// @dev Fresh (<=1hr): baseFee, Stale (>6hr): staleFee, between: linear interpolation
    function _calculateFee(PoolConfig storage config) internal view returns (uint24) {
        uint256 age = block.timestamp - config.lastNAVUpdate;

        if (age <= NAV_FRESH_WINDOW) {
            return config.baseFee;
        } else if (age >= NAV_STALE_WINDOW || config.staleFee <= config.baseFee) {
            return config.staleFee;
        } else {
            // Linear interpolation between baseFee and staleFee
            uint256 feeDelta = uint256(config.staleFee - config.baseFee);
            uint256 timeDelta = age - NAV_FRESH_WINDOW;
            uint256 window = NAV_STALE_WINDOW - NAV_FRESH_WINDOW;
            return config.baseFee + uint24((feeDelta * timeDelta) / window);
        }
    }
}
