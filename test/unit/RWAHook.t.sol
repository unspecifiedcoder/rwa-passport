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
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";
import { AttestationHelper } from "../helpers/AttestationHelper.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { HookMiner } from "../helpers/HookMiner.sol";

/// @title RWAHookTest
/// @notice Unit tests for RWAHook — V4 hook with compliance, dynamic fees, pause
contract RWAHookTest is Test, Deployers {
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
    MockERC20 public usdc;
    XythumToken public mirrorToken;
    address public mirrorAddress;

    // ─── Pool ────────────────────────────────────────────────────────
    PoolKey public poolKey;
    PoolId public poolId;

    // ─── Config ──────────────────────────────────────────────────────
    address public owner;
    address public trader;
    uint256 constant NUM_SIGNERS = 5;
    uint256 constant THRESHOLD = 3;

    /// @dev Foundry's default tx.origin — vm.prank only changes msg.sender,
    ///      not tx.origin. The hook uses tx.origin for compliance checks.
    address constant DEFAULT_TX_ORIGIN = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    /// @notice Default hookData encoding DEFAULT_TX_ORIGIN (required after tx.origin removal)
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

        // 2. Deploy canonical mirror via factory
        mirrorAddress = _deployCanonicalMirror(address(0xAAA), 1, 42161, 1);
        mirrorToken = XythumToken(mirrorAddress);

        // 3. Deploy V4 PoolManager and routers
        deployFreshManagerAndRouters();

        // 4. Deploy USDC mock
        usdc = new MockERC20("USD Coin", "USDC", 18);
        usdc.mint(address(this), type(uint128).max);
        usdc.mint(trader, type(uint128).max);

        // 5. Mine and deploy RWAHook at valid address
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

        // Deploy hook at the mined address using CREATE2
        hook = new RWAHook{ salt: salt }(manager, address(factory), owner);
        require(address(hook) == hookAddr, "Hook address mismatch");

        // 6. Whitelist key addresses in compliance
        // For pool operations, many V4 internal contracts transfer tokens.
        // Disable enforcement globally, then re-enable for specific compliance tests.
        compliance.setEnforceCompliance(false);

        // 7. Set up pool: mirror + USDC with dynamic fee
        (Currency c0, Currency c1) = mirrorAddress < address(usdc)
            ? (Currency.wrap(mirrorAddress), Currency.wrap(address(usdc)))
            : (Currency.wrap(address(usdc)), Currency.wrap(mirrorAddress));

        poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        // Initialize pool
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        poolId = poolKey.toId();

        // 8. Approve tokens to routers and mint mirror tokens for liquidity
        factory.deployMirror; // factory already deployed mirror — now mint tokens via factory as authorized minter
        // Factory is the authorized minter — we need it to mint for us, but factory doesn't have a public mint
        // Instead, set this test contract as authorized minter on the mirror
        // The factory deployed the mirror, so factory can call setAuthorizedMinter
        // But CanonicalFactory doesn't expose that. Let's use the factory as the deployer:
        // Actually, XythumToken.factory() is set to the CanonicalFactory address.
        // We need CanonicalFactory to call setAuthorizedMinter. That's not in the factory API.
        // For testing: we deploy the mirror, factory is the authorized minter. We need factory to mint.
        // Hmm — the factory is authorized but has no public mint function.
        // Solution: use vm.prank to impersonate the factory
        vm.prank(address(factory));
        mirrorToken.setAuthorizedMinter(address(this), true);

        // Now mint mirror tokens for testing (within mintCap of 1_000_000 ether)
        // Leave headroom for per-test mints (e.g. compliance tests mint 1000 ether)
        mirrorToken.mint(address(this), 400_000 ether);
        mirrorToken.mint(trader, 400_000 ether);

        // Approve all routers
        mirrorToken.approve(address(swapRouter), type(uint256).max);
        mirrorToken.approve(address(modifyLiquidityRouter), type(uint256).max);
        usdc.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(modifyLiquidityRouter), type(uint256).max);

        // 9. Add initial liquidity (hookData required with user address)
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)
            }),
            DEFAULT_HOOK_DATA
        );
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

    function _doSwap(bool zeroForOne, int256 amount) internal returns (BalanceDelta) {
        return swap(poolKey, zeroForOne, amount, DEFAULT_HOOK_DATA);
    }

    // ─── beforeInitialize Tests ──────────────────────────────────────

    function test_beforeInitialize_canonical_token_succeeds() public view {
        // Pool was initialized in setUp — verify config was set
        (address xToken, uint24 baseFee, uint24 staleFee, uint256 lastNAV, bool active) =
            hook.poolConfigs(poolId);
        assertEq(xToken, mirrorAddress, "xythumToken should be mirror");
        assertEq(baseFee, 500, "baseFee should be 500");
        assertEq(staleFee, 5000, "staleFee should be 5000");
        assertGt(lastNAV, 0, "lastNAVUpdate should be set");
        assertTrue(active, "pool should be active");
    }

    function test_beforeInitialize_non_canonical_reverts() public {
        // Create two non-canonical tokens
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);

        (Currency c0, Currency c1) = address(tokenA) < address(tokenB)
            ? (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)))
            : (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));

        PoolKey memory badKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        vm.expectRevert(); // NotCanonicalToken
        manager.initialize(badKey, SQRT_PRICE_1_1);
    }

    // ─── beforeSwap Compliance Tests ─────────────────────────────────

    function test_beforeSwap_compliant_user_succeeds() public {
        // Enable compliance for this test
        compliance.setEnforceCompliance(true);
        // Whitelist DEFAULT_TX_ORIGIN because tx.origin in Foundry tests is always
        // DefaultSender (0x1804c8AB...), not the pranked address.
        // The hook checks tx.origin for compliance (MVP approach).
        compliance.setWhitelisted(DEFAULT_TX_ORIGIN, true);
        // Also whitelist all V4 internal addresses that do token transfers
        compliance.setWhitelisted(trader, true);
        compliance.setWhitelisted(address(swapRouter), true);
        compliance.setWhitelisted(address(manager), true);

        vm.startPrank(trader);
        mirrorToken.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(swapRouter), type(uint256).max);

        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            DEFAULT_HOOK_DATA
        );
        vm.stopPrank();
    }

    function test_beforeSwap_non_compliant_reverts() public {
        // Enable compliance for this test
        compliance.setEnforceCompliance(true);
        // Do NOT whitelist DEFAULT_TX_ORIGIN — this means tx.origin is non-compliant
        // and the hook will revert with SwapperNotCompliant(DEFAULT_TX_ORIGIN).

        address nonCompliant = makeAddr("nonCompliant");

        // Give them tokens (compliance disabled temporarily for mint)
        compliance.setEnforceCompliance(false);
        mirrorToken.mint(nonCompliant, 1000 ether);
        usdc.mint(nonCompliant, 1000 ether);
        compliance.setEnforceCompliance(true);

        vm.startPrank(nonCompliant);
        mirrorToken.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(swapRouter), type(uint256).max);

        // V4 wraps hook reverts in WrappedError, so we use bare expectRevert
        vm.expectRevert();
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            DEFAULT_HOOK_DATA
        );
        vm.stopPrank();
    }

    // ─── Dynamic Fee Tests ───────────────────────────────────────────

    function test_beforeSwap_dynamic_fee_fresh_nav() public view {
        // NAV was just set in setUp (lastNAVUpdate = block.timestamp)
        // Fee should be baseFee = 500
        (,,, uint256 lastNAV,) = hook.poolConfigs(poolId);
        uint256 age = block.timestamp - lastNAV;
        assertTrue(age <= 1 hours, "NAV should be fresh");
    }

    function test_beforeSwap_dynamic_fee_stale_nav() public {
        // Warp 12 hours — NAV becomes very stale
        vm.warp(block.timestamp + 12 hours);

        // Swap should still work (compliance is OK) but fee is max
        _doSwap(true, -10);

        // Verify via poolConfigs that NAV is stale
        (,,, uint256 lastNAV,) = hook.poolConfigs(poolId);
        uint256 age = block.timestamp - lastNAV;
        assertTrue(age >= 6 hours, "NAV should be stale");
    }

    function test_beforeSwap_dynamic_fee_aging_nav() public {
        // Warp 3.5 hours — between fresh (1hr) and stale (6hr)
        vm.warp(block.timestamp + 3.5 hours);

        // Swap succeeds
        _doSwap(true, -10);

        // Verify NAV age is in interpolation range
        (,,, uint256 lastNAV,) = hook.poolConfigs(poolId);
        uint256 age = block.timestamp - lastNAV;
        assertTrue(age > 1 hours && age < 6 hours, "NAV should be aging");
    }

    function test_updateNAV_resets_fee() public {
        // Age the NAV
        vm.warp(block.timestamp + 12 hours);

        // Update NAV
        hook.updateNAV(poolId);

        // Verify NAV is fresh again
        (,,, uint256 lastNAV,) = hook.poolConfigs(poolId);
        assertEq(lastNAV, block.timestamp, "NAV should be refreshed");
    }

    // ─── beforeAddLiquidity Tests ────────────────────────────────────

    function test_beforeAddLiquidity_compliant_succeeds() public {
        // Enable compliance + whitelist DEFAULT_TX_ORIGIN (tx.origin in Foundry)
        compliance.setEnforceCompliance(true);
        compliance.setWhitelisted(DEFAULT_TX_ORIGIN, true);
        // Also whitelist V4 internal addresses for token transfers
        compliance.setWhitelisted(address(this), true);
        compliance.setWhitelisted(address(modifyLiquidityRouter), true);
        compliance.setWhitelisted(address(manager), true);

        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(uint256(1))
            }),
            ZERO_BYTES
        );
    }

    function test_beforeAddLiquidity_non_compliant_reverts() public {
        // Enable compliance — do NOT whitelist DEFAULT_TX_ORIGIN so tx.origin
        // is non-compliant and the hook reverts with LPNotCompliant.
        compliance.setEnforceCompliance(true);

        address nonCompliantLP = makeAddr("nonCompliantLP");

        // Mint tokens with compliance disabled
        compliance.setEnforceCompliance(false);
        mirrorToken.mint(nonCompliantLP, 1000 ether);
        usdc.mint(nonCompliantLP, 1000 ether);
        compliance.setEnforceCompliance(true);

        vm.startPrank(nonCompliantLP);
        mirrorToken.approve(address(modifyLiquidityRouter), type(uint256).max);
        usdc.approve(address(modifyLiquidityRouter), type(uint256).max);

        // V4 wraps hook reverts in WrappedError, so we use bare expectRevert
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
    }

    // ─── Pause Tests ─────────────────────────────────────────────────

    function test_pausePool_blocks_swaps() public {
        hook.pausePool(poolId);

        // V4 wraps hook reverts in WrappedError, so we use bare expectRevert
        vm.expectRevert();
        _doSwap(true, -10);
    }

    function test_unpausePool_allows_swaps() public {
        hook.pausePool(poolId);
        hook.unpausePool(poolId);
        _doSwap(true, -10); // Should succeed
    }

    function test_pausePool_onlyOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(RWAHook.OnlyOwner.selector);
        hook.pausePool(poolId);
    }

    // ─── hookData Compliance Tests (QW-1: tx.origin fix) ─────────────

    function test_beforeSwap_hookData_overrides_txOrigin() public {
        // Enable compliance
        compliance.setEnforceCompliance(true);
        // Whitelist DEFAULT_TX_ORIGIN (tx.origin) so old path would pass
        compliance.setWhitelisted(DEFAULT_TX_ORIGIN, true);
        // Also whitelist V4 internals for token transfers
        compliance.setWhitelisted(address(swapRouter), true);
        compliance.setWhitelisted(address(manager), true);

        // Create a non-compliant address to pass via hookData
        address nonCompliant = makeAddr("nonCompliantViaHookData");
        // Do NOT whitelist nonCompliant

        // Even though tx.origin is compliant, hookData overrides it to nonCompliant
        // The swap should REVERT because hookData address is checked, not tx.origin
        vm.expectRevert();
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            abi.encode(nonCompliant)
        );
    }

    function test_beforeSwap_empty_hookData_reverts() public {
        // Empty hookData should revert with HookDataRequired (tx.origin fallback removed)
        vm.expectRevert();
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ZERO_BYTES
        );
    }

    function test_beforeSwap_hookData_compliant_address_succeeds() public {
        // Enable compliance
        compliance.setEnforceCompliance(true);
        address compliantUser = makeAddr("compliantUser");
        compliance.setWhitelisted(compliantUser, true);
        // Whitelist all addresses involved in V4 token transfers
        compliance.setWhitelisted(address(this), true);
        compliance.setWhitelisted(address(swapRouter), true);
        compliance.setWhitelisted(address(manager), true);

        // Pass compliant address in hookData — should succeed
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            abi.encode(compliantUser)
        );
    }

    function test_beforeAddLiquidity_hookData_non_compliant_reverts() public {
        // Enable compliance
        compliance.setEnforceCompliance(true);
        compliance.setWhitelisted(DEFAULT_TX_ORIGIN, true);
        compliance.setWhitelisted(address(modifyLiquidityRouter), true);
        compliance.setWhitelisted(address(manager), true);

        address nonCompliantLP = makeAddr("nonCompliantLPviaHookData");
        // Do NOT whitelist nonCompliantLP

        // hookData overrides tx.origin for LP check → should revert
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(uint256(99))
            }),
            abi.encode(nonCompliantLP)
        );
    }
}
