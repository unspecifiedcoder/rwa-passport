// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";

/// @title XythumTokenTest
/// @notice Unit tests for XythumToken — the canonical mirror ERC-20
contract XythumTokenTest is Test {
    XythumToken public token;
    XythumToken public tokenNoCompliance;
    MockCompliance public compliance;

    address public constant ORIGIN_CONTRACT = address(0xAAA);
    uint256 public constant ORIGIN_CHAIN_ID = 1;
    address public user1;
    address public user2;
    address public attacker;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");

        // Deploy compliance
        compliance = new MockCompliance();

        // Deploy token (this test contract is the "factory" / msg.sender)
        token = new XythumToken(
            "Xythum Mirror",
            "xRWA",
            ORIGIN_CONTRACT,
            ORIGIN_CHAIN_ID,
            address(compliance),
            1_000_000 ether
        );

        // Deploy a second token with no compliance (address(0))
        tokenNoCompliance = new XythumToken(
            "Xythum Mirror NC",
            "xRWA-NC",
            ORIGIN_CONTRACT,
            ORIGIN_CHAIN_ID,
            address(0),
            1_000_000 ether
        );

        // Whitelist users in compliance for the main token
        compliance.setWhitelisted(user1, true);
        compliance.setWhitelisted(user2, true);
    }

    // ─── Constructor Tests ───────────────────────────────────────────

    function test_constructor_sets_immutables() public view {
        assertEq(token.originContract(), ORIGIN_CONTRACT);
        assertEq(token.originChainId(), ORIGIN_CHAIN_ID);
        assertEq(token.factory(), address(this));
        assertEq(token.compliance(), address(compliance));
    }

    function test_name_and_symbol() public view {
        assertEq(token.name(), "Xythum Mirror");
        assertEq(token.symbol(), "xRWA");
    }

    function test_factory_is_authorized_minter() public view {
        assertTrue(token.authorizedMinters(address(this)));
    }

    // ─── Mint Tests ──────────────────────────────────────────────────

    function test_mint_by_factory() public {
        token.mint(user1, 1000 ether);
        assertEq(token.balanceOf(user1), 1000 ether);
        assertEq(token.totalSupply(), 1000 ether);
    }

    function test_mint_emits_transfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), user1, 1000 ether);
        token.mint(user1, 1000 ether);
    }

    function test_mint_by_unauthorized_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(XythumToken.Unauthorized.selector, attacker));
        token.mint(user1, 1000 ether);
    }

    function test_mint_to_zero_address_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(XythumToken.ZeroAddress.selector));
        token.mint(address(0), 1000 ether);
    }

    function test_mint_bypasses_compliance() public {
        // user1 is whitelisted but let's test mint to a NON-whitelisted address
        address unwhitelisted = makeAddr("unwhitelisted");
        // Not whitelisted, but mint should still succeed (mint bypasses compliance)
        token.mint(unwhitelisted, 500 ether);
        assertEq(token.balanceOf(unwhitelisted), 500 ether);
    }

    // ─── Burn Tests ──────────────────────────────────────────────────

    function test_burn_by_factory() public {
        token.mint(user1, 1000 ether);
        token.burn(user1, 400 ether);
        assertEq(token.balanceOf(user1), 600 ether);
        assertEq(token.totalSupply(), 600 ether);
    }

    function test_burn_by_unauthorized_reverts() public {
        token.mint(user1, 1000 ether);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(XythumToken.Unauthorized.selector, attacker));
        token.burn(user1, 500 ether);
    }

    function test_burn_bypasses_compliance() public {
        // Mint to unwhitelisted address, then burn from it
        address unwhitelisted = makeAddr("unwhitelisted");
        token.mint(unwhitelisted, 500 ether);
        // Not whitelisted, but burn should succeed (burn bypasses compliance)
        token.burn(unwhitelisted, 200 ether);
        assertEq(token.balanceOf(unwhitelisted), 300 ether);
    }

    // ─── Transfer / Compliance Tests ─────────────────────────────────

    function test_transfer_compliant_succeeds() public {
        token.mint(user1, 1000 ether);
        vm.prank(user1);
        token.transfer(user2, 300 ether);
        assertEq(token.balanceOf(user1), 700 ether);
        assertEq(token.balanceOf(user2), 300 ether);
    }

    function test_transfer_non_compliant_reverts() public {
        address unwhitelisted = makeAddr("unwhitelisted");
        token.mint(user1, 1000 ether);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(XythumToken.TransferNotCompliant.selector, user1, unwhitelisted)
        );
        token.transfer(unwhitelisted, 300 ether);
    }

    function test_transferFrom_checks_compliance() public {
        address unwhitelisted = makeAddr("unwhitelisted");
        token.mint(user1, 1000 ether);

        // user1 approves attacker
        vm.prank(user1);
        token.approve(attacker, 500 ether);

        // attacker tries to transferFrom to unwhitelisted
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(XythumToken.TransferNotCompliant.selector, user1, unwhitelisted)
        );
        token.transferFrom(user1, unwhitelisted, 300 ether);
    }

    function test_transferFrom_compliant_succeeds() public {
        token.mint(user1, 1000 ether);

        // user1 approves user2
        vm.prank(user1);
        token.approve(user2, 500 ether);

        // user2 transfers from user1 to user2 (both whitelisted)
        vm.prank(user2);
        token.transferFrom(user1, user2, 300 ether);
        assertEq(token.balanceOf(user1), 700 ether);
        assertEq(token.balanceOf(user2), 300 ether);
    }

    // ─── Compliance Disabled Tests ───────────────────────────────────

    function test_compliance_disabled_allows_any_transfer() public {
        address anyone1 = makeAddr("anyone1");
        address anyone2 = makeAddr("anyone2");
        // Using tokenNoCompliance (compliance = address(0))
        tokenNoCompliance.mint(anyone1, 1000 ether);
        vm.prank(anyone1);
        tokenNoCompliance.transfer(anyone2, 500 ether);
        assertEq(tokenNoCompliance.balanceOf(anyone1), 500 ether);
        assertEq(tokenNoCompliance.balanceOf(anyone2), 500 ether);
    }

    function test_isCompliant_returns_true_when_disabled() public view {
        assertTrue(tokenNoCompliance.isCompliant(user1, user2));
    }

    function test_isCompliant_checks_compliance_contract() public {
        // Both whitelisted
        assertTrue(token.isCompliant(user1, user2));
        // Unwhitelisted receiver
        address random = makeAddr("random");
        assertFalse(token.isCompliant(user1, random));
    }

    function test_compliance_toggle_enforcement() public {
        address unwhitelisted = makeAddr("unwhitelisted");
        token.mint(user1, 1000 ether);

        // Should fail (compliance enforced, unwhitelisted not in whitelist)
        vm.prank(user1);
        vm.expectRevert();
        token.transfer(unwhitelisted, 100 ether);

        // Disable enforcement
        compliance.setEnforceCompliance(false);

        // Should succeed now
        vm.prank(user1);
        token.transfer(unwhitelisted, 100 ether);
        assertEq(token.balanceOf(unwhitelisted), 100 ether);
    }

    // ─── Authorized Minter Tests ─────────────────────────────────────

    function test_setAuthorizedMinter() public {
        address newMinter = makeAddr("ccipAdapter");
        token.setAuthorizedMinter(newMinter, true);
        assertTrue(token.authorizedMinters(newMinter));

        // New minter can mint
        vm.prank(newMinter);
        token.mint(user1, 500 ether);
        assertEq(token.balanceOf(user1), 500 ether);
    }

    function test_setAuthorizedMinter_revoke() public {
        address newMinter = makeAddr("ccipAdapter");
        token.setAuthorizedMinter(newMinter, true);
        token.setAuthorizedMinter(newMinter, false);
        assertFalse(token.authorizedMinters(newMinter));

        // Revoked minter cannot mint
        vm.prank(newMinter);
        vm.expectRevert(abi.encodeWithSelector(XythumToken.Unauthorized.selector, newMinter));
        token.mint(user1, 500 ether);
    }

    function test_setAuthorizedMinter_non_factory_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(XythumToken.Unauthorized.selector, attacker));
        token.setAuthorizedMinter(attacker, true);
    }

    // ─── ERC-20 Standard Behavior ────────────────────────────────────

    function test_decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_total_supply_tracks_mint_and_burn() public {
        assertEq(token.totalSupply(), 0);
        token.mint(user1, 500 ether);
        assertEq(token.totalSupply(), 500 ether);
        token.mint(user2, 300 ether);
        assertEq(token.totalSupply(), 800 ether);
        token.burn(user1, 200 ether);
        assertEq(token.totalSupply(), 600 ether);
    }

    // ─── MintCap Tests (QW-2) ────────────────────────────────────────

    function test_mint_within_cap_succeeds() public {
        // mintCap is 1_000_000 ether, minting 500_000 should succeed
        token.mint(user1, 500_000 ether);
        assertEq(token.balanceOf(user1), 500_000 ether);
        assertEq(token.totalMinted(), 500_000 ether);
    }

    function test_mint_exceeds_cap_reverts() public {
        // mintCap is 1_000_000 ether, try minting 1_000_001 ether
        vm.expectRevert(
            abi.encodeWithSelector(
                XythumToken.MintCapExceeded.selector, 1_000_001 ether, 1_000_000 ether
            )
        );
        token.mint(user1, 1_000_001 ether);
    }

    function test_mint_exact_cap_succeeds() public {
        // Mint exactly the cap
        token.mint(user1, 1_000_000 ether);
        assertEq(token.balanceOf(user1), 1_000_000 ether);
        assertEq(token.totalMinted(), 1_000_000 ether);

        // One more wei should fail
        vm.expectRevert(abi.encodeWithSelector(XythumToken.MintCapExceeded.selector, 1, 0));
        token.mint(user1, 1);
    }

    function test_updateMintCap_by_factory() public {
        // This test contract is the factory (deployed the token)
        token.updateMintCap(2_000_000 ether);
        assertEq(token.mintCap(), 2_000_000 ether);
    }

    function test_updateMintCap_below_supply_reverts() public {
        // Mint some tokens first
        token.mint(user1, 500_000 ether);

        // Try to set cap below current supply — should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                XythumToken.InvalidMintCap.selector, 100_000 ether, 500_000 ether
            )
        );
        token.updateMintCap(100_000 ether);
    }

    function test_updateMintCap_by_non_factory_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(XythumToken.Unauthorized.selector, attacker));
        token.updateMintCap(2_000_000 ether);
    }

    function test_burn_does_not_decrease_totalMinted() public {
        token.mint(user1, 1000 ether);
        assertEq(token.totalMinted(), 1000 ether);

        token.burn(user1, 500 ether);
        // totalMinted should NOT decrease — it tracks issuance, not current supply
        assertEq(token.totalMinted(), 1000 ether);
        assertEq(token.totalSupply(), 500 ether);
    }

    function test_constructor_sets_mintCap() public view {
        assertEq(token.mintCap(), 1_000_000 ether);
        assertEq(token.totalMinted(), 0);
    }
}
