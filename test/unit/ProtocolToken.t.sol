// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";

/// @title ProtocolToken Unit Tests
/// @notice 25+ tests covering minting, vesting, anti-whale, delegation, and edge cases
contract ProtocolTokenTest is Test {
    ProtocolToken public token;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public minter = makeAddr("minter");

    uint256 public constant INITIAL_MINT = 100_000_000 ether; // 100M

    function setUp() public {
        vm.prank(owner);
        token = new ProtocolToken(owner, INITIAL_MINT, treasury);
    }

    // ─── Basic Properties ────────────────────────────────────────────

    function test_name() public view {
        assertEq(token.name(), "Xythum Protocol");
    }

    function test_symbol() public view {
        assertEq(token.symbol(), "XYT");
    }

    function test_maxSupply() public view {
        assertEq(token.maxSupply(), 1_000_000_000 ether);
    }

    function test_initialMint() public view {
        assertEq(token.totalSupply(), INITIAL_MINT);
        assertEq(token.balanceOf(treasury), INITIAL_MINT);
    }

    function test_ownerIsSet() public view {
        assertEq(token.owner(), owner);
    }

    // ─── Minting ─────────────────────────────────────────────────────

    function test_authorizedMinterCanMint() public {
        vm.prank(owner);
        token.setMinter(minter, true);

        vm.prank(minter);
        token.mint(alice, 1000 ether);

        assertEq(token.balanceOf(alice), 1000 ether);
    }

    function test_unauthorizedMinterReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ProtocolToken.UnauthorizedMinter.selector, alice));
        token.mint(bob, 1000 ether);
    }

    function test_mintExceedingMaxSupplyReverts() public {
        vm.prank(owner);
        token.setMinter(minter, true);

        uint256 remaining = token.maxSupply() - token.totalSupply();

        vm.prank(minter);
        vm.expectRevert();
        token.mint(alice, remaining + 1);
    }

    function test_mintToZeroAddressReverts() public {
        vm.prank(owner);
        token.setMinter(minter, true);

        vm.prank(minter);
        vm.expectRevert(ProtocolToken.ZeroAddress.selector);
        token.mint(address(0), 1000 ether);
    }

    function test_burn() public {
        vm.prank(treasury);
        token.burn(1000 ether);
        assertEq(token.balanceOf(treasury), INITIAL_MINT - 1000 ether);
    }

    // ─── Vesting ─────────────────────────────────────────────────────

    function test_createVestingSchedule() public {
        vm.prank(owner);
        token.createVestingSchedule(alice, 10_000 ether, 90 days, 365 days, true);

        (uint256 total, uint256 released,,,,) = token.vestingSchedules(alice);
        assertEq(total, 10_000 ether);
        assertEq(released, 0);
    }

    function test_vestingCliffBlocksRelease() public {
        vm.prank(owner);
        token.createVestingSchedule(alice, 10_000 ether, 90 days, 365 days, true);

        // Before cliff: nothing releasable
        vm.warp(block.timestamp + 30 days);
        assertEq(token.getReleasableAmount(alice), 0);
    }

    function test_vestingReleasesAfterCliff() public {
        vm.prank(owner);
        token.createVestingSchedule(alice, 10_000 ether, 90 days, 365 days, true);

        // After cliff but before full vest: partial release
        vm.warp(block.timestamp + 180 days);
        uint256 releasable = token.getReleasableAmount(alice);
        assertGt(releasable, 0);
        assertLt(releasable, 10_000 ether);
    }

    function test_vestingFullRelease() public {
        vm.prank(owner);
        token.createVestingSchedule(alice, 10_000 ether, 90 days, 365 days, true);

        // After full vesting: everything releasable
        vm.warp(block.timestamp + 400 days);
        assertEq(token.getReleasableAmount(alice), 10_000 ether);
    }

    function test_releaseVestedTokens() public {
        vm.prank(owner);
        token.createVestingSchedule(alice, 10_000 ether, 90 days, 365 days, true);

        vm.warp(block.timestamp + 400 days);
        token.releaseVestedTokens(alice);

        assertEq(token.balanceOf(alice), 10_000 ether);
    }

    function test_revokeVesting() public {
        vm.prank(owner);
        token.createVestingSchedule(alice, 10_000 ether, 90 days, 365 days, true);

        vm.warp(block.timestamp + 180 days);

        vm.prank(owner);
        token.revokeVesting(alice);

        // Alice should have received the vested portion
        assertGt(token.balanceOf(alice), 0);
        assertLt(token.balanceOf(alice), 10_000 ether);
    }

    function test_duplicateVestingReverts() public {
        vm.startPrank(owner);
        token.createVestingSchedule(alice, 10_000 ether, 90 days, 365 days, true);

        vm.expectRevert(abi.encodeWithSelector(ProtocolToken.VestingAlreadyExists.selector, alice));
        token.createVestingSchedule(alice, 5_000 ether, 90 days, 365 days, true);
        vm.stopPrank();
    }

    // ─── Anti-Whale ──────────────────────────────────────────────────

    function test_transferLimitEnforced() public {
        vm.prank(owner);
        token.setTransferLimit(1000 ether);

        // Fund alice
        vm.prank(treasury);
        token.transfer(alice, 5000 ether);

        // Transfer within limit works
        vm.prank(alice);
        token.transfer(bob, 500 ether);
        assertEq(token.balanceOf(bob), 500 ether);

        // Transfer exceeding limit reverts
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1500 ether);
    }

    function test_transferLimitExemptBypass() public {
        vm.startPrank(owner);
        token.setTransferLimit(1000 ether);
        token.setTransferLimitExempt(treasury, true);
        vm.stopPrank();

        // Treasury is exempt - can transfer above limit
        vm.prank(treasury);
        token.transfer(alice, 50_000 ether);
        assertEq(token.balanceOf(alice), 50_000 ether);
    }

    function test_transferLimitZeroMeansUnlimited() public {
        // Default is 0 (unlimited)
        vm.prank(treasury);
        token.transfer(alice, 50_000_000 ether);
        assertEq(token.balanceOf(alice), 50_000_000 ether);
    }

    // ─── Vote Delegation ─────────────────────────────────────────────

    function test_delegateVotes() public {
        vm.prank(treasury);
        token.delegate(alice);

        assertEq(token.delegates(treasury), alice);
        assertEq(token.getVotes(alice), INITIAL_MINT);
    }

    function test_selfDelegate() public {
        vm.prank(treasury);
        token.delegate(treasury);

        assertEq(token.getVotes(treasury), INITIAL_MINT);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function test_onlyOwnerCanSetMinter() public {
        vm.prank(alice);
        vm.expectRevert();
        token.setMinter(minter, true);
    }

    function test_onlyOwnerCanSetTransferLimit() public {
        vm.prank(alice);
        vm.expectRevert();
        token.setTransferLimit(1000 ether);
    }

    function test_onlyOwnerCanCreateVesting() public {
        vm.prank(alice);
        vm.expectRevert();
        token.createVestingSchedule(bob, 1000 ether, 90 days, 365 days, true);
    }

    // ─── Fuzz Tests ──────────────────────────────────────────────────

    function testFuzz_mintUpToMaxSupply(uint256 amount) public {
        uint256 remaining = token.maxSupply() - token.totalSupply();
        amount = bound(amount, 1, remaining);

        vm.prank(owner);
        token.setMinter(minter, true);

        vm.prank(minter);
        token.mint(alice, amount);
        assertEq(token.balanceOf(alice), amount);
    }

    function testFuzz_transferWithinLimit(uint256 limit, uint256 amount) public {
        limit = bound(limit, 1 ether, 1_000_000 ether);
        amount = bound(amount, 1, limit);

        vm.prank(owner);
        token.setTransferLimit(limit);

        vm.prank(treasury);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
    }
}
