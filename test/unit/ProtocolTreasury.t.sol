// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProtocolTreasury } from "../../src/governance/ProtocolTreasury.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";

/// @title ProtocolTreasury Unit Tests
contract ProtocolTreasuryTest is Test {
    ProtocolTreasury public treasury;
    ProtocolToken public token;

    address public governance = makeAddr("governance");
    address public recipient = makeAddr("recipient");
    address public owner = makeAddr("owner");
    address public tokenTreasury; // The address that receives initial mint

    uint256 public constant INITIAL_MINT = 100_000_000 ether;

    function setUp() public {
        vm.startPrank(owner);
        treasury = new ProtocolTreasury(governance, 30 days);
        token = new ProtocolToken(owner, INITIAL_MINT, address(treasury));
        vm.stopPrank();
        tokenTreasury = address(treasury);
    }

    function test_disburseToken() public {
        vm.prank(governance);
        treasury.disburseToken(address(token), recipient, 1_000_000 ether, keccak256("proposal-1"));

        assertEq(token.balanceOf(recipient), 1_000_000 ether);
        assertEq(treasury.disbursementCount(), 1);
    }

    function test_disburseETH() public {
        vm.deal(address(treasury), 10 ether);

        vm.prank(governance);
        treasury.disburseETH(recipient, 5 ether, keccak256("proposal-2"));

        assertEq(recipient.balance, 5 ether);
        assertEq(treasury.ethBalance(), 5 ether);
    }

    function test_onlyGovernanceCanDisburse() public {
        vm.prank(recipient);
        vm.expectRevert(ProtocolTreasury.OnlyGovernance.selector);
        treasury.disburseToken(address(token), recipient, 1000 ether, keccak256("unauthorized"));
    }

    function test_insufficientBalanceReverts() public {
        vm.prank(governance);
        vm.expectRevert();
        treasury.disburseToken(address(token), recipient, INITIAL_MINT + 1, keccak256("too-much"));
    }

    function test_spendingLimits() public {
        vm.startPrank(governance);
        treasury.setSpendingLimit(address(token), 5_000_000 ether);

        // First disbursement within limit
        treasury.disburseToken(address(token), recipient, 3_000_000 ether, keccak256("p1"));

        // Second disbursement exceeds limit
        vm.expectRevert();
        treasury.disburseToken(address(token), recipient, 3_000_000 ether, keccak256("p2"));
        vm.stopPrank();
    }

    function test_remainingSpendingLimit() public {
        vm.startPrank(governance);
        treasury.setSpendingLimit(address(token), 5_000_000 ether);
        treasury.disburseToken(address(token), recipient, 2_000_000 ether, keccak256("p1"));
        vm.stopPrank();

        assertEq(treasury.remainingSpendingLimit(address(token)), 3_000_000 ether);
    }

    function test_receiveETH() public {
        vm.deal(owner, 10 ether);
        vm.prank(owner);
        (bool s,) = address(treasury).call{ value: 5 ether }("");
        assertTrue(s);
        assertEq(treasury.ethBalance(), 5 ether);
    }
}
