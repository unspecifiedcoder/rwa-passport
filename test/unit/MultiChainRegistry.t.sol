// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MultiChainRegistry } from "../../src/registry/MultiChainRegistry.sol";

/// @title MultiChainRegistry Unit Tests
contract MultiChainRegistryTest is Test {
    MultiChainRegistry public registry;

    address public owner = makeAddr("owner");
    address public relayer = makeAddr("relayer");
    address public originRWA = makeAddr("originRWA");
    address public mirrorBNB = makeAddr("mirrorBNB");
    address public mirrorFuji = makeAddr("mirrorFuji");

    uint256 public constant ORIGIN_CHAIN = 1; // Mainnet
    uint256 public constant BNB_CHAIN = 97;
    uint256 public constant FUJI_CHAIN = 43113;

    function setUp() public {
        vm.startPrank(owner);
        registry = new MultiChainRegistry(owner);
        registry.setRelayer(relayer, true);
        registry.addChain(BNB_CHAIN, "BNB Testnet");
        registry.addChain(FUJI_CHAIN, "Avalanche Fuji");
        vm.stopPrank();
    }

    // ─── Chain Management ────────────────────────────────────────────

    function test_addChain() public view {
        (string memory name, bool active,) = registry.chainInfos(BNB_CHAIN);
        assertEq(name, "BNB Testnet");
        assertTrue(active);
    }

    function test_getSupportedChains() public view {
        uint256[] memory chains = registry.getSupportedChains();
        assertEq(chains.length, 2);
        assertEq(chains[0], BNB_CHAIN);
        assertEq(chains[1], FUJI_CHAIN);
    }

    // ─── Deployment Registration ─────────────────────────────────────

    function test_registerDeployment() public {
        vm.prank(relayer);
        registry.registerDeployment(originRWA, ORIGIN_CHAIN, BNB_CHAIN, mirrorBNB);

        assertEq(registry.totalDeployments(), 1);
        assertEq(registry.getDeploymentCount(originRWA, ORIGIN_CHAIN), 1);
    }

    function test_registerMultipleDeployments() public {
        vm.startPrank(relayer);
        registry.registerDeployment(originRWA, ORIGIN_CHAIN, BNB_CHAIN, mirrorBNB);
        registry.registerDeployment(originRWA, ORIGIN_CHAIN, FUJI_CHAIN, mirrorFuji);
        vm.stopPrank();

        assertEq(registry.totalDeployments(), 2);

        MultiChainRegistry.ChainDeployment[] memory deployments =
            registry.getDeployments(originRWA, ORIGIN_CHAIN);
        assertEq(deployments.length, 2);
        assertEq(deployments[0].mirrorAddress, mirrorBNB);
        assertEq(deployments[1].mirrorAddress, mirrorFuji);
    }

    function test_duplicateDeploymentReverts() public {
        vm.startPrank(relayer);
        registry.registerDeployment(originRWA, ORIGIN_CHAIN, BNB_CHAIN, mirrorBNB);

        vm.expectRevert();
        registry.registerDeployment(originRWA, ORIGIN_CHAIN, BNB_CHAIN, makeAddr("mirror2"));
        vm.stopPrank();
    }

    function test_unsupportedChainReverts() public {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(MultiChainRegistry.ChainNotSupported.selector, 999));
        registry.registerDeployment(originRWA, ORIGIN_CHAIN, 999, mirrorBNB);
    }

    function test_unauthorizedRelayerReverts() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(MultiChainRegistry.OnlyRelayer.selector);
        registry.registerDeployment(originRWA, ORIGIN_CHAIN, BNB_CHAIN, mirrorBNB);
    }

    // ─── Supply Sync ─────────────────────────────────────────────────

    function test_syncSupply() public {
        vm.startPrank(relayer);
        registry.registerDeployment(originRWA, ORIGIN_CHAIN, BNB_CHAIN, mirrorBNB);
        registry.registerDeployment(originRWA, ORIGIN_CHAIN, FUJI_CHAIN, mirrorFuji);

        registry.syncSupply(originRWA, BNB_CHAIN, 1_000_000 ether);
        registry.syncSupply(originRWA, FUJI_CHAIN, 500_000 ether);
        vm.stopPrank();

        assertEq(registry.getAggregateSupply(originRWA, ORIGIN_CHAIN), 1_500_000 ether);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function test_setRelayer() public {
        address newRelayer = makeAddr("newRelayer");

        vm.prank(owner);
        registry.setRelayer(newRelayer, true);

        assertTrue(registry.relayers(newRelayer));
    }

    function test_deactivateChain() public {
        vm.prank(owner);
        registry.setChainStatus(BNB_CHAIN, false);

        (, bool active,) = registry.chainInfos(BNB_CHAIN);
        assertFalse(active);
    }
}
