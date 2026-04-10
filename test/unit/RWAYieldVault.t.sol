// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { RWAYieldVault } from "../../src/finance/RWAYieldVault.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";

/// @title RWAYieldVault Unit Tests
contract RWAYieldVaultTest is Test {
    RWAYieldVault public vault;
    ProtocolToken public token;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public feeRecipient = makeAddr("feeRecipient");
    address public yieldSource = makeAddr("yieldSource");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_MINT = 100_000_000 ether;
    uint256 public constant DEPOSIT_CAP = 10_000_000 ether;

    function setUp() public {
        vm.startPrank(owner);
        token = new ProtocolToken(owner, INITIAL_MINT, treasury);
        vault = new RWAYieldVault(
            address(token), "Xythum RWA Vault", "xVault", owner, feeRecipient, DEPOSIT_CAP
        );
        vault.setYieldSource(yieldSource, true);
        vm.stopPrank();

        // Fund users
        vm.startPrank(treasury);
        token.transfer(alice, 1_000_000 ether);
        token.transfer(bob, 1_000_000 ether);
        token.transfer(yieldSource, 100_000 ether);
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);

        vm.prank(yieldSource);
        token.approve(address(vault), type(uint256).max);
    }

    // ─── Deposits ────────────────────────────────────────────────────

    function test_deposit() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000 ether, alice);

        assertEq(shares, 10_000 ether); // 1:1 for first deposit
        assertEq(vault.totalAssets(), 10_000 ether);
        assertEq(vault.balanceOf(alice), 10_000 ether);
    }

    function test_depositCapEnforced() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(DEPOSIT_CAP + 1, alice);
    }

    function test_depositZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(RWAYieldVault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    // ─── Withdrawals ─────────────────────────────────────────────────

    function test_withdraw() public {
        vm.prank(alice);
        vault.deposit(10_000 ether, alice);

        vm.prank(alice);
        vault.withdraw(2_000 ether, alice, alice);

        assertEq(vault.totalAssets(), 8_000 ether);
        assertEq(token.balanceOf(alice), 992_000 ether);
    }

    function test_redeem() public {
        vm.prank(alice);
        vault.deposit(10_000 ether, alice);

        vm.prank(alice);
        vault.redeem(5_000 ether, alice, alice);

        assertEq(vault.totalAssets(), 5_000 ether);
        assertEq(vault.balanceOf(alice), 5_000 ether);
    }

    function test_withdrawalLimit() public {
        vm.prank(alice);
        vault.deposit(100_000 ether, alice);

        // Max instant withdrawal is 20% = 20_000 ether
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(50_000 ether, alice, alice);
    }

    // ─── Yield ───────────────────────────────────────────────────────

    function test_yieldHarvest() public {
        vm.prank(alice);
        vault.deposit(100_000 ether, alice);

        // Yield source deposits yield
        vm.prank(yieldSource);
        vault.harvest(10_000 ether);

        // Vault now has 110k assets, alice has 100k shares
        assertEq(vault.totalAssets(), 110_000 ether);
        assertEq(vault.totalYieldHarvested(), 10_000 ether);
    }

    function test_sharePrice_increasesWithYield() public {
        vm.prank(alice);
        vault.deposit(100_000 ether, alice);

        uint256 priceBefore = vault.sharePrice();

        vm.prank(yieldSource);
        vault.harvest(10_000 ether);

        uint256 priceAfter = vault.sharePrice();
        assertGt(priceAfter, priceBefore);
    }

    function test_proportionalYieldDistribution() public {
        // Alice deposits 75k, Bob deposits 25k
        vm.prank(alice);
        vault.deposit(75_000 ether, alice);

        vm.prank(bob);
        vault.deposit(25_000 ether, bob);

        // 10k yield
        vm.prank(yieldSource);
        vault.harvest(10_000 ether);

        // Alice redeems all shares
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        // Alice should get ~75% of total including yield
        // (minus performance fee)
        assertGt(token.balanceOf(alice), 925_000 ether + 75_000 ether); // More than initial
    }

    function test_unauthorizedYieldSourceReverts() public {
        vm.prank(alice);
        vm.expectRevert(RWAYieldVault.NotYieldSource.selector);
        vault.harvest(1000 ether);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function test_setDepositCap() public {
        vm.prank(owner);
        vault.setDepositCap(50_000_000 ether);
        assertEq(vault.depositCap(), 50_000_000 ether);
    }

    function test_pause() public {
        vm.prank(owner);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(1000 ether, alice);
    }

    // ─── Fuzz Tests ──────────────────────────────────────────────────

    function testFuzz_depositAndWithdraw(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 1_000_000 ether);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 maxWithdraw = (depositAmount * 2000) / 10000; // 20% instant max
        uint256 withdrawAmount = bound(depositAmount, 1, maxWithdraw);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        assertEq(vault.totalAssets(), depositAmount - withdrawAmount);
    }
}
