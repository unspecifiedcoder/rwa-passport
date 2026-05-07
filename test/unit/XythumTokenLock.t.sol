// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";

/// @notice Unit tests for the lock-cycle additions to XythumToken:
///         `burnForLock(amount, lockId)` and `bumpCapAndMint(to, amount, lockId)`.
contract XythumTokenLockTest is Test {
    XythumToken public token;

    address public user = makeAddr("user");
    address public attacker = makeAddr("attacker");
    bytes32 public constant LOCK_ID_A = keccak256("lock-A");
    bytes32 public constant LOCK_ID_B = keccak256("lock-B");

    event BurnedForLock(bytes32 indexed lockId, address indexed burner, uint256 amount);

    function setUp() public {
        // This test contract acts as the factory.
        token = new XythumToken(
            "Xythum Mirror",
            "xRWA",
            address(0xAAA), // origin
            1,
            address(0), // no compliance
            0 // initial cap = 0; will grow via bumpCapAndMint
        );
    }

    // ─── bumpCapAndMint ──────────────────────────────────────────────

    function test_bumpCapAndMint_growsCapAndMints() public {
        token.bumpCapAndMint(user, 100 ether, LOCK_ID_A);
        assertEq(token.balanceOf(user), 100 ether);
        assertEq(token.mintCap(), 100 ether);
        assertEq(token.totalMinted(), 100 ether);
    }

    function test_bumpCapAndMint_isCumulative() public {
        token.bumpCapAndMint(user, 60 ether, LOCK_ID_A);
        token.bumpCapAndMint(user, 40 ether, LOCK_ID_B);
        assertEq(token.balanceOf(user), 100 ether);
        assertEq(token.mintCap(), 100 ether); // cap = sum of bumps
    }

    function test_bumpCapAndMint_revertsForUnauthorized() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(XythumToken.Unauthorized.selector, attacker));
        token.bumpCapAndMint(user, 1, LOCK_ID_A);
    }

    function test_bumpCapAndMint_revertsForZeroRecipient() public {
        vm.expectRevert(XythumToken.ZeroAddress.selector);
        token.bumpCapAndMint(address(0), 1, LOCK_ID_A);
    }

    // ─── burnForLock ─────────────────────────────────────────────────

    function test_burnForLock_happyPath() public {
        token.bumpCapAndMint(user, 100 ether, LOCK_ID_A);

        vm.expectEmit(true, true, false, true);
        emit BurnedForLock(LOCK_ID_A, user, 100 ether);
        vm.prank(user);
        token.burnForLock(100 ether, LOCK_ID_A);

        assertEq(token.balanceOf(user), 0);
        assertTrue(token.burnedForLock(LOCK_ID_A));
        // totalMinted is a high-water mark — does NOT decrease.
        assertEq(token.totalMinted(), 100 ether);
        // mintCap also unchanged (cumulative high-water mark per design).
        assertEq(token.mintCap(), 100 ether);
    }

    function test_burnForLock_revertsOnDoubleBurn() public {
        token.bumpCapAndMint(user, 100 ether, LOCK_ID_A);

        vm.prank(user);
        token.burnForLock(50 ether, LOCK_ID_A);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(XythumToken.AlreadyBurnedForLock.selector, LOCK_ID_A)
        );
        token.burnForLock(50 ether, LOCK_ID_A);
    }

    function test_burnForLock_revertsOnInsufficientBalance() public {
        token.bumpCapAndMint(user, 10 ether, LOCK_ID_A);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                XythumToken.InsufficientBalanceForBurn.selector, user, 100 ether, 10 ether
            )
        );
        token.burnForLock(100 ether, LOCK_ID_A);
    }

    function test_burnForLock_anyHolderCanBurnTheirOwn() public {
        // Mint to two distinct holders.
        token.bumpCapAndMint(user, 50 ether, LOCK_ID_A);
        token.bumpCapAndMint(attacker, 30 ether, LOCK_ID_B);

        vm.prank(user);
        token.burnForLock(50 ether, LOCK_ID_A);

        // attacker can still burn THEIR balance against LOCK_ID_B.
        vm.prank(attacker);
        token.burnForLock(30 ether, LOCK_ID_B);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(attacker), 0);
        assertTrue(token.burnedForLock(LOCK_ID_A));
        assertTrue(token.burnedForLock(LOCK_ID_B));
    }
}
