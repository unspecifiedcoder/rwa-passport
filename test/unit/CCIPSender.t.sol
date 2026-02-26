// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPSender} from "../../src/ccip/CCIPSender.sol";
import {MockCCIPRouter} from "../helpers/MockCCIPRouter.sol";
import {AttestationLib} from "../../src/libraries/AttestationLib.sol";
import {TestConstants} from "../helpers/TestConstants.sol";

/// @title CCIPSenderTest
/// @notice Unit tests for CCIPSender — source chain attestation dispatch
contract CCIPSenderTest is Test {
    CCIPSender public sender;
    MockCCIPRouter public router;

    address public owner;
    address public user;
    address public receiver;

    uint64 public constant TARGET_SELECTOR = 3478487238524512106; // Arb Sepolia

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        receiver = makeAddr("receiver");

        router = new MockCCIPRouter();
        sender = new CCIPSender(address(router), owner);

        // Configure target chain
        sender.setSupportedChain(TARGET_SELECTOR, true);
        sender.setReceiver(TARGET_SELECTOR, receiver);

        // Register receiver in mock router (so ccipSend actually delivers)
        router.setReceiver(TARGET_SELECTOR, receiver);

        // Fund user
        vm.deal(user, 10 ether);
    }

    /// @notice Build a simple test attestation
    function _buildTestAtt() internal view returns (AttestationLib.Attestation memory) {
        return AttestationLib.Attestation({
            originContract: address(0xAAA),
            originChainId: 1,
            targetChainId: 42161,
            navRoot: keccak256("nav"),
            complianceRoot: keccak256("compliance"),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp,
            nonce: 1
        });
    }

    // ─── Success Tests ───────────────────────────────────────────────

    function test_sendAttestation_success() public {
        AttestationLib.Attestation memory att = _buildTestAtt();
        bytes memory sigs = hex"aabb"; // dummy sigs (mock router doesn't validate)
        uint256 bitmap = 7; // bits 0,1,2

        // The mock router will try to deliver to `receiver`, which is an EOA
        // and will revert. For this test, we need to skip delivery.
        // Let's set fixed fee to 0 and use a simple receiver mock.
        router.setFixedFee(0);

        // We need receiver to not revert on ccipReceive. Deploy a dummy.
        DummyCCIPReceiver dummy = new DummyCCIPReceiver();
        sender.setReceiver(TARGET_SELECTOR, address(dummy));
        router.setReceiver(TARGET_SELECTOR, address(dummy));

        vm.prank(user);
        bytes32 messageId = sender.sendAttestation(TARGET_SELECTOR, att, sigs, bitmap);

        assertTrue(messageId != bytes32(0), "Should return a message ID");
    }

    function test_sendAttestation_emits_event() public {
        AttestationLib.Attestation memory att = _buildTestAtt();
        bytes memory sigs = hex"aabb";
        uint256 bitmap = 7;

        router.setFixedFee(0);
        DummyCCIPReceiver dummy = new DummyCCIPReceiver();
        sender.setReceiver(TARGET_SELECTOR, address(dummy));
        router.setReceiver(TARGET_SELECTOR, address(dummy));

        vm.prank(user);
        vm.expectEmit(false, true, true, true);
        emit CCIPSender.AttestationSent(bytes32(0), TARGET_SELECTOR, att.originContract, att.nonce);
        sender.sendAttestation(TARGET_SELECTOR, att, sigs, bitmap);
    }

    // ─── Revert Tests ────────────────────────────────────────────────

    function test_sendAttestation_unsupported_chain_reverts() public {
        AttestationLib.Attestation memory att = _buildTestAtt();
        uint64 unsupportedSelector = 999;

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(CCIPSender.UnsupportedChain.selector, unsupportedSelector)
        );
        sender.sendAttestation{value: 1 ether}(unsupportedSelector, att, hex"", 0);
    }

    function test_sendAttestation_receiver_not_set_reverts() public {
        // Enable chain but don't set receiver
        uint64 newSelector = 12345;
        sender.setSupportedChain(newSelector, true);

        AttestationLib.Attestation memory att = _buildTestAtt();

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(CCIPSender.ReceiverNotSet.selector, newSelector)
        );
        sender.sendAttestation{value: 1 ether}(newSelector, att, hex"", 0);
    }

    function test_sendAttestation_insufficient_fee_reverts() public {
        AttestationLib.Attestation memory att = _buildTestAtt();
        router.setFixedFee(0.5 ether);

        vm.prank(user);
        vm.expectRevert(); // InsufficientFee
        sender.sendAttestation{value: 0.1 ether}(TARGET_SELECTOR, att, hex"", 0);
    }

    function test_sendAttestation_refunds_excess() public {
        router.setFixedFee(0.01 ether);
        DummyCCIPReceiver dummy = new DummyCCIPReceiver();
        sender.setReceiver(TARGET_SELECTOR, address(dummy));
        router.setReceiver(TARGET_SELECTOR, address(dummy));

        AttestationLib.Attestation memory att = _buildTestAtt();

        uint256 balanceBefore = user.balance;
        vm.prank(user);
        sender.sendAttestation{value: 1 ether}(TARGET_SELECTOR, att, hex"aabb", 7);
        uint256 balanceAfter = user.balance;

        // User should get 0.99 ETH back
        assertEq(balanceBefore - balanceAfter, 0.01 ether, "Only fee should be consumed");
    }

    // ─── Fee Estimation Tests ────────────────────────────────────────

    function test_estimateFee_returns_router_fee() public view {
        uint256 fee = sender.estimateFee(TARGET_SELECTOR, hex"deadbeef");
        assertEq(fee, router.fixedFee());
    }

    function test_estimateFee_receiver_not_set_reverts() public {
        uint64 noReceiver = 99999;
        vm.expectRevert(
            abi.encodeWithSelector(CCIPSender.ReceiverNotSet.selector, noReceiver)
        );
        sender.estimateFee(noReceiver, hex"deadbeef");
    }

    // ─── Admin Tests ─────────────────────────────────────────────────

    function test_setReceiver_onlyOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        sender.setReceiver(TARGET_SELECTOR, attacker);
    }

    function test_setSupportedChain_onlyOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        sender.setSupportedChain(TARGET_SELECTOR, false);
    }

    function test_setReceiver_works() public {
        address newReceiver = makeAddr("newReceiver");
        sender.setReceiver(TARGET_SELECTOR, newReceiver);
        assertEq(sender.allowedReceivers(TARGET_SELECTOR), newReceiver);
    }

    function test_setSupportedChain_works() public {
        sender.setSupportedChain(TARGET_SELECTOR, false);
        assertFalse(sender.supportedChains(TARGET_SELECTOR));
    }
}

/// @notice Dummy receiver that accepts any ccipReceive call without reverting
contract DummyCCIPReceiver {
    fallback() external payable {}
    receive() external payable {}
}
