// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { LPFeeLibrary } from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import { ICanonicalFactory } from "../interfaces/ICanonicalFactory.sol";

/// @title LiquidityBootstrap
/// @author Xythum Protocol
/// @notice Automates Uniswap V4 pool creation when a new canonical mirror is deployed.
///         Creates a pool with the RWAHook and a paired quote asset (e.g. USDC).
/// @dev MVP: only creates the pool. Initial liquidity provision is manual.
///      TODO(v2): Auto-seed liquidity using protocol treasury funds.
contract LiquidityBootstrap is Ownable2Step {
    using PoolIdLibrary for PoolKey;

    // ─── Custom Errors ───────────────────────────────────────────────
    error NotCanonical(address mirror);
    error PoolAlreadyExists(address mirror);

    // ─── Events ──────────────────────────────────────────────────────
    event PoolCreated(address indexed mirror, PoolId poolId, address quoteAsset);

    // ─── Immutables ──────────────────────────────────────────────────
    IPoolManager public immutable poolManager;
    ICanonicalFactory public immutable factory;
    address public immutable hook;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Default quote asset for pairing (e.g. USDC)
    address public quoteAsset;

    /// @notice Default tick spacing for RWA pools (wide ticks = low volatility)
    int24 public constant DEFAULT_TICK_SPACING = 100;

    /// @notice 1:1 sqrtPriceX96 for pool initialization
    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    /// @notice Mirror address → its pool ID
    mapping(address => PoolId) public mirrorPools;

    /// @notice Track which mirrors have pools
    mapping(address => bool) public hasPool;

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _poolManager Uniswap V4 PoolManager
    /// @param _factory CanonicalFactory for isCanonical checks
    /// @param _hook RWAHook address
    /// @param _quoteAsset Default quote asset (e.g. USDC)
    /// @param _owner Contract owner
    constructor(
        address _poolManager,
        address _factory,
        address _hook,
        address _quoteAsset,
        address _owner
    ) Ownable(_owner) {
        poolManager = IPoolManager(_poolManager);
        factory = ICanonicalFactory(_factory);
        hook = _hook;
        quoteAsset = _quoteAsset;
    }

    // ─── External Functions ──────────────────────────────────────────

    /// @notice Create a V4 pool for a canonical mirror token
    /// @param mirror The canonical mirror token address
    /// @return poolId The ID of the created pool
    function createPool(address mirror) external returns (PoolId poolId) {
        if (!factory.isCanonical(mirror)) revert NotCanonical(mirror);
        if (hasPool[mirror]) revert PoolAlreadyExists(mirror);

        // Sort currencies (V4 requires currency0 < currency1)
        (Currency c0, Currency c1) = mirror < quoteAsset
            ? (Currency.wrap(mirror), Currency.wrap(quoteAsset))
            : (Currency.wrap(quoteAsset), Currency.wrap(mirror));

        // Build PoolKey with dynamic fee flag
        PoolKey memory key = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: IHooks(hook)
        });

        // Initialize pool at 1:1 price
        // TODO(v2): Derive initial price from attested NAV
        poolManager.initialize(key, SQRT_PRICE_1_1);

        // Store pool mapping
        poolId = key.toId();
        mirrorPools[mirror] = poolId;
        hasPool[mirror] = true;

        emit PoolCreated(mirror, poolId, quoteAsset);
    }

    /// @notice Get the pool for a mirror
    function getPool(address mirror) external view returns (PoolId) {
        return mirrorPools[mirror];
    }

    /// @notice Set the default quote asset
    function setQuoteAsset(address _quoteAsset) external onlyOwner {
        quoteAsset = _quoteAsset;
    }
}
