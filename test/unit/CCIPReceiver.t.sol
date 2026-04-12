// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { XythumCCIPReceiver } from "../../src/ccip/CCIPReceiver.sol";
import { MockCCIPRouter } from "../helpers/MockCCIPRouter.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";
import { AttestationHelper } from "../helpers/AttestationHelper.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/// @title CCIPReceiverTest
/// @notice Unit tests for XythumCCIPReceiver — target chain attestation handling
contract CCIPReceiverTest is Test {
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    CanonicalFactory public factory;
    MockCompliance public compliance;
    MockCCIPRouter public router;
    XythumCCIPReceiver public ccipReceiver;
    AttestationHelper public helper;

    address public owner;
    address public ccipSender; // Simulated sender on source chain

    uint64 public constant SOURCE_SELECTOR = 16015286601757825753; // ETH Sepolia
    uint256 public constant NUM_SIGNERS = 5;
    uint256 public constant THRESHOLD = 3;

    function setUp() public {
        vm.warp(100_000);

        owner = address(this);
        ccipSender = makeAddr("ccipSender");

        // 1. Deploy full stack
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

        // 2. Deploy CCIP components
        router = new MockCCIPRouter();
        ccipReceiver = new XythumCCIPReceiver(address(router), address(factory), owner);

        // 3. Configure allowed sender
        ccipReceiver.setAllowedSender(SOURCE_SELECTOR, ccipSender, true);
        router.setSourceChainSelector(SOURCE_SELECTOR);
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    /// @notice Build a CCIP message simulating delivery from ccipSender
    function _buildCCIPMessage(bytes32 messageId, bytes memory payload)
        internal
        view
        returns (Client.Any2EVMMessage memory)
    {
        return Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: SOURCE_SELECTOR,
            sender: abi.encode(ccipSender),
            data: payload,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
    }

    /// @notice Build a deploy payload with valid attestation + signatures
    function _buildDeployPayload(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 nonce
    ) internal view returns (bytes memory) {
        AttestationLib.Attestation memory att = helper.buildAttestation(
            originContract, originChainId, targetChainId, nonce
        );

        uint256[] memory signerIndices = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            signerIndices[i] = i;
        }

        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (bytes memory sigs, uint256 bitmap) = helper.signAttestation(att, domainSep, signerIndices);

        return abi.encode(
            uint8(1), // MESSAGE_TYPE_DEPLOY
            abi.encode(att),
            sigs,
            bitmap
        );
    }

    // ─── Deployment Tests ────────────────────────────────────────────

    function test_receive_deploy_message_deploys_mirror() public {
        bytes memory payload = _buildDeployPayload(address(0xAAA), 1, block.chainid, 1);
        bytes32 messageId = keccak256("test_message_1");

        Client.Any2EVMMessage memory message = _buildCCIPMessage(messageId, payload);

        // Call as router (onlyRouter modifier)
        vm.prank(address(router));
        ccipReceiver.ccipReceive(message);

        // Verify message processed
        assertTrue(ccipReceiver.processedMessages(messageId));

        // Verify mirror deployed
        AttestationLib.Attestation memory att = helper.buildAttestation(address(0xAAA), 1, block.chainid, 1);
        address predicted = factory.computeMirrorAddress(att);
        assertTrue(factory.isCanonical(predicted), "Mirror should be canonical");

        // Verify mirror metadata
        XythumToken mirror = XythumToken(predicted);
        assertEq(mirror.originContract(), address(0xAAA));
        assertEq(mirror.originChainId(), 1);
    }

    function test_receive_deploy_emits_events() public {
        bytes memory payload = _buildDeployPayload(address(0xAAA), 1, block.chainid, 1);
        bytes32 messageId = keccak256("test_message_events");

        Client.Any2EVMMessage memory message = _buildCCIPMessage(messageId, payload);

        // Expect MirrorDeployedViaCCIP + AttestationReceived
        vm.prank(address(router));
        vm.expectEmit(true, false, false, false);
        emit XythumCCIPReceiver.MirrorDeployedViaCCIP(messageId, address(0)); // mirror addr unknown pre-emit

        ccipReceiver.ccipReceive(message);
    }

    // ─── Authorization Tests ─────────────────────────────────────────

    function test_receive_unauthorized_sender_reverts() public {
        address unauthorizedSender = makeAddr("unauthorized");
        bytes memory payload = _buildDeployPayload(address(0xAAA), 1, block.chainid, 1);
        bytes32 messageId = keccak256("test_unauth");

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: SOURCE_SELECTOR,
            sender: abi.encode(unauthorizedSender),
            data: payload,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        vm.expectRevert(
            abi.encodeWithSelector(
                XythumCCIPReceiver.UnauthorizedSender.selector, SOURCE_SELECTOR, unauthorizedSender
            )
        );
        ccipReceiver.ccipReceive(message);
    }

    function test_receive_wrong_router_reverts() public {
        bytes memory payload = _buildDeployPayload(address(0xAAA), 1, block.chainid, 1);
        bytes32 messageId = keccak256("test_wrong_router");
        Client.Any2EVMMessage memory message = _buildCCIPMessage(messageId, payload);

        // Call from non-router address
        address notRouter = makeAddr("notRouter");
        vm.prank(notRouter);
        vm.expectRevert(); // InvalidRouter
        ccipReceiver.ccipReceive(message);
    }

    // ─── Replay Protection Tests ─────────────────────────────────────

    function test_receive_replay_reverts() public {
        bytes memory payload = _buildDeployPayload(address(0xAAA), 1, block.chainid, 1);
        bytes32 messageId = keccak256("test_replay");
        Client.Any2EVMMessage memory message = _buildCCIPMessage(messageId, payload);

        // First call succeeds
        vm.prank(address(router));
        ccipReceiver.ccipReceive(message);

        // Second call with same messageId reverts
        vm.prank(address(router));
        vm.expectRevert(
            abi.encodeWithSelector(XythumCCIPReceiver.MessageAlreadyProcessed.selector, messageId)
        );
        ccipReceiver.ccipReceive(message);
    }

    // ─── Message Type Tests ──────────────────────────────────────────

    function test_receive_unknown_message_type_reverts() public {
        // Build payload with invalid message type
        bytes memory payload = abi.encode(
            uint8(99), // Unknown type
            abi.encode("dummy"),
            hex"",
            uint256(0)
        );
        bytes32 messageId = keccak256("test_unknown_type");
        Client.Any2EVMMessage memory message = _buildCCIPMessage(messageId, payload);

        vm.prank(address(router));
        vm.expectRevert(
            abi.encodeWithSelector(XythumCCIPReceiver.UnknownMessageType.selector, uint8(99))
        );
        ccipReceiver.ccipReceive(message);
    }

    // ─── Deployment Failure Handling ─────────────────────────────────

    function test_receive_deploy_failure_doesnt_revert() public {
        // First deploy succeeds
        bytes memory payload = _buildDeployPayload(address(0xAAA), 1, block.chainid, 1);
        bytes32 messageId1 = keccak256("test_first_deploy");
        Client.Any2EVMMessage memory message1 = _buildCCIPMessage(messageId1, payload);

        vm.prank(address(router));
        ccipReceiver.ccipReceive(message1);

        // Second deploy for SAME pair — will fail at factory (MirrorAlreadyDeployed)
        // But CCIP message should still process (try/catch)
        vm.warp(block.timestamp + 1 hours + 1); // bypass rate limit
        bytes memory payload2 = _buildDeployPayload(address(0xAAA), 1, block.chainid, 2);
        bytes32 messageId2 = keccak256("test_second_deploy");
        Client.Any2EVMMessage memory message2 = _buildCCIPMessage(messageId2, payload2);

        vm.prank(address(router));
        ccipReceiver.ccipReceive(message2); // Should NOT revert

        // Verify message was still processed
        assertTrue(
            ccipReceiver.processedMessages(messageId2),
            "Failed deploy should still be marked processed"
        );
    }

    // ─── Source Chain Validation ──────────────────────────────────────

    function test_receive_from_wrong_source_chain() public {
        // Sender is allowed on SOURCE_SELECTOR but not on another chain
        uint64 wrongSelector = 999;
        bytes memory payload = _buildDeployPayload(address(0xAAA), 1, block.chainid, 1);
        bytes32 messageId = keccak256("test_wrong_chain");

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: wrongSelector,
            sender: abi.encode(ccipSender),
            data: payload,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        vm.expectRevert(
            abi.encodeWithSelector(
                XythumCCIPReceiver.UnauthorizedSender.selector, wrongSelector, ccipSender
            )
        );
        ccipReceiver.ccipReceive(message);
    }

    // ─── Admin Tests ─────────────────────────────────────────────────

    function test_setAllowedSender_onlyOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        ccipReceiver.setAllowedSender(SOURCE_SELECTOR, attacker, true);
    }

    function test_setAllowedSender_works() public {
        address newSender = makeAddr("newSender");
        ccipReceiver.setAllowedSender(SOURCE_SELECTOR, newSender, true);
        assertTrue(ccipReceiver.allowedSenders(SOURCE_SELECTOR, newSender));
    }
}
