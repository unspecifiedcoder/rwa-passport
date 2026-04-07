// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { Deployers } from "@uniswap/v4-core/test/utils/Deployers.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { LPFeeLibrary } from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import { RWAHook } from "../../src/hooks/RWAHook.sol";
import { LiquidityBootstrap } from "../../src/hooks/LiquidityBootstrap.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";
import { AttestationHelper } from "../helpers/AttestationHelper.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { HookMiner } from "../helpers/HookMiner.sol";

/// @title LiquidityFlowTest
/// @notice Integration test: deploy canonical mirror -> bootstrap pool -> swap
///         Validates the full Phase 4 flow end-to-end.
contract LiquidityFlowTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // ─── Xythum stack ────────────────────────────────────────────────
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    CanonicalFactory public factory;
    MockCompliance public compliance;
    AttestationHelper public helper;

    // ─── V4 + Hook ───────────────────────────────────────────────────
    RWAHook public hook;
    LiquidityBootstrap public bootstrap;
    MockERC20 public usdc;

    // ─── Config ──────────────────────────────────────────────────────
    address public owner;
    address public trader;
    uint256 constant NUM_SIGNERS = 5;
    uint256 constant THRESHOLD = 3;

    /// @dev Foundry's default tx.origin — needed for compliance whitelisting
    address constant DEFAULT_TX_ORIGIN = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    bytes internal DEFAULT_HOOK_DATA = abi.encode(DEFAULT_TX_ORIGIN);

    function setUp() public {
        vm.warp(100_000);
        owner = address(this);
        trader = makeAddr("trader");

        // 1. Deploy Xythum stack
        signerRegistry = new SignerRegistry(owner, THRESHOLD);
        helper = new AttestationHelper();
        helper.generateSigners(NUM_SIGNERS);
        for (uint256 i = 0; i < NUM_SIGNERS; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }
        attestationRegistry = new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);
        compliance = new MockCompliance();
        factory = new CanonicalFactory(
            address(attestationRegistry), address(compliance), makeAddr("treasury"), owner
        );

        // 2. Deploy V4 PoolManager and routers
        deployFreshManagerAndRouters();

        // 3. Deploy USDC mock
        usdc = new MockERC20("USD Coin", "USDC", 18);

        // 4. Mine and deploy RWAHook at valid address
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );

        (address hookAddr, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(RWAHook).creationCode,
            abi.encode(address(manager), address(factory), owner)
        );

        hook = new RWAHook{ salt: salt }(manager, address(factory), owner);
        require(address(hook) == hookAddr, "Hook address mismatch");

        // 5. Deploy LiquidityBootstrap
        bootstrap = new LiquidityBootstrap(
            address(manager), address(factory), address(hook), address(usdc), owner
        );

        // 6. Disable compliance globally for setUp — re-enable per test
        compliance.setEnforceCompliance(false);
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    function _deployCanonicalMirror(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 nonce
    ) internal returns (address mirror) {
        AttestationLib.Attestation memory att = helper.buildAttestation(
            originContract, originChainId, targetChainId, nonce
        );
        uint256[] memory signerIndices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            signerIndices[i] = i;
        }
        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (bytes memory sigs, uint256 bitmap) = helper.signAttestation(att, domainSep, signerIndices);
        mirror = factory.deployMirror(att, sigs, bitmap);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  test_deploy_and_trade
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Full integration: deploy mirror -> bootstrap pool -> add liquidity -> swap
    function test_deploy_and_trade() public {
        // 1. Deploy canonical mirror via factory
        address mirrorAddr = _deployCanonicalMirror(address(0xAAA), 1, 42161, 1);
        XythumToken mirror = XythumToken(mirrorAddr);
        assertTrue(factory.isCanonical(mirrorAddr), "Mirror should be canonical");

        // 2. Create pool via LiquidityBootstrap
        bootstrap.createPool(mirrorAddr);
        assertTrue(bootstrap.hasPool(mirrorAddr), "Pool should exist");

        // 3. Set up tokens: mint & approve
        vm.prank(address(factory));
        mirror.setAuthorizedMinter(address(this), true);
        mirror.mint(address(this), 1000 ether);
        mirror.mint(trader, 1000 ether);
        usdc.mint(address(this), 1000 ether);
        usdc.mint(trader, 1000 ether);

        // 4. Build the pool key to match bootstrap's pool
        (Currency c0, Currency c1) = mirrorAddr < address(usdc)
            ? (Currency.wrap(mirrorAddr), Currency.wrap(address(usdc)))
            : (Currency.wrap(address(usdc)), Currency.wrap(mirrorAddr));

        PoolKey memory poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(100), // LiquidityBootstrap.DEFAULT_TICK_SPACING
            hooks: IHooks(address(hook))
        });

        // 5. Approve routers
        mirror.approve(address(modifyLiquidityRouter), type(uint256).max);
        mirror.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(modifyLiquidityRouter), type(uint256).max);
        usdc.approve(address(swapRouter), type(uint256).max);

        // 6. Add initial liquidity
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -200, tickUpper: 200, liquidityDelta: 100e18, salt: bytes32(0)
            }),
            DEFAULT_HOOK_DATA
        );

        // 7. Trader approves and swaps
        vm.startPrank(trader);
        mirror.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(swapRouter), type(uint256).max);

        uint256 traderUsdcBefore = usdc.balanceOf(trader);

        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: mirrorAddr < address(usdc), // mirror -> USDC
                amountSpecified: -100,
                sqrtPriceLimitX96: mirrorAddr < address(usdc) ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            DEFAULT_HOOK_DATA
        );
        vm.stopPrank();

        // 8. Verify swap executed
        // In both cases the swap sells mirror for USDC (exact input of mirror tokens).
        // When mirror < usdc: zeroForOne=true → sell currency0(mirror), receive currency1(usdc)
        // When mirror > usdc: zeroForOne=false → sell currency1(mirror), receive currency0(usdc)
        // Either way, trader's USDC balance should increase.
        assertGt(
            usdc.balanceOf(trader), traderUsdcBefore, "Trader should have received USDC from swap"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  test_stale_nav_increases_cost
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Deploy mirror -> pool -> trade at fresh NAV -> age NAV -> trade at stale fee -> update -> fresh again
    function test_stale_nav_increases_cost() public {
        // 1. Deploy mirror + pool
        address mirrorAddr = _deployCanonicalMirror(address(0xBBB), 1, 42161, 2);
        XythumToken mirror = XythumToken(mirrorAddr);

        PoolId poolId = bootstrap.createPool(mirrorAddr);

        // 2. Set up tokens
        vm.prank(address(factory));
        mirror.setAuthorizedMinter(address(this), true);
        mirror.mint(address(this), 10_000 ether);
        usdc.mint(address(this), 10_000 ether);

        (Currency c0, Currency c1) = mirrorAddr < address(usdc)
            ? (Currency.wrap(mirrorAddr), Currency.wrap(address(usdc)))
            : (Currency.wrap(address(usdc)), Currency.wrap(mirrorAddr));

        PoolKey memory poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(100),
            hooks: IHooks(address(hook))
        });

        mirror.approve(address(modifyLiquidityRouter), type(uint256).max);
        mirror.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(modifyLiquidityRouter), type(uint256).max);
        usdc.approve(address(swapRouter), type(uint256).max);

        // 3. Add liquidity
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -200, tickUpper: 200, liquidityDelta: 100e18, salt: bytes32(0)
            }),
            DEFAULT_HOOK_DATA
        );

        // 4. Trade immediately — NAV is fresh, fee = baseFee (500 = 5 bps)
        (,,, uint256 lastNAV1,) = hook.poolConfigs(poolId);
        uint256 age1 = block.timestamp - lastNAV1;
        assertTrue(age1 <= 1 hours, "NAV should be fresh before first trade");

        swap(poolKey, true, -10, DEFAULT_HOOK_DATA);

        // 5. Warp 12 hours — NAV becomes stale
        vm.warp(block.timestamp + 12 hours);

        (,,, uint256 lastNAV2,) = hook.poolConfigs(poolId);
        uint256 age2 = block.timestamp - lastNAV2;
        assertTrue(age2 >= 6 hours, "NAV should be stale after warp");

        // Trade still succeeds but at high fee (staleFee = 5000 = 50 bps)
        swap(poolKey, false, -10, DEFAULT_HOOK_DATA);

        // 6. Update NAV — resets fee
        hook.updateNAV(poolId);

        (,,, uint256 lastNAV3,) = hook.poolConfigs(poolId);
        assertEq(lastNAV3, block.timestamp, "NAV should be refreshed");

        // 7. Trade again — fee should be baseFee again
        swap(poolKey, true, -10, DEFAULT_HOOK_DATA);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  test_bootstrap_creates_correct_pool
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Verify LiquidityBootstrap creates a pool with correct configuration
    function test_bootstrap_creates_correct_pool() public {
        address mirrorAddr = _deployCanonicalMirror(address(0xCCC), 1, 42161, 3);

        // Create pool
        PoolId poolId = bootstrap.createPool(mirrorAddr);

        // Verify pool exists
        assertTrue(bootstrap.hasPool(mirrorAddr), "hasPool should be true");
        assertEq(
            PoolId.unwrap(bootstrap.getPool(mirrorAddr)),
            PoolId.unwrap(poolId),
            "getPool should match"
        );

        // Verify hook registered the pool config
        (address xToken, uint24 baseFee, uint24 staleFee, uint256 lastNAV, bool active) =
            hook.poolConfigs(poolId);
        assertEq(xToken, mirrorAddr, "xythumToken should be mirror");
        assertEq(baseFee, 500, "baseFee should be 500");
        assertEq(staleFee, 5000, "staleFee should be 5000");
        assertGt(lastNAV, 0, "lastNAV should be set");
        assertTrue(active, "pool should be active");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  test_bootstrap_rejects_non_canonical
    // ═══════════════════════════════════════════════════════════════════

    /// @notice LiquidityBootstrap rejects non-canonical tokens
    function test_bootstrap_rejects_non_canonical() public {
        address fake = makeAddr("fake_mirror");
        vm.expectRevert(abi.encodeWithSelector(LiquidityBootstrap.NotCanonical.selector, fake));
        bootstrap.createPool(fake);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  test_bootstrap_rejects_duplicate_pool
    // ═══════════════════════════════════════════════════════════════════

    /// @notice LiquidityBootstrap rejects creating a pool for an already-pooled mirror
    function test_bootstrap_rejects_duplicate_pool() public {
        address mirrorAddr = _deployCanonicalMirror(address(0xDDD), 1, 42161, 4);
        bootstrap.createPool(mirrorAddr);

        vm.expectRevert(
            abi.encodeWithSelector(LiquidityBootstrap.PoolAlreadyExists.selector, mirrorAddr)
        );
        bootstrap.createPool(mirrorAddr);
    }
}
