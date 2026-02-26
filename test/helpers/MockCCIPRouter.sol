// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/// @title MockCCIPRouter
/// @notice Simulates Chainlink CCIP router for single-chain testing.
///         When ccipSend() is called, it immediately delivers the message to the
///         registered receiver on the same chain (simulating cross-chain delivery).
contract MockCCIPRouter is IRouterClient {
    /// @notice Chain selector → receiver contract on that "chain"
    mapping(uint64 => address) public receivers;

    /// @notice Total messages sent
    uint256 public messageCount;

    /// @notice Fixed fee for testing (0.01 ETH)
    uint256 public fixedFee = 0.01 ether;

    /// @notice Source chain selector to use when delivering messages
    uint64 public sourceChainSelector = 16015286601757825753; // ETH Sepolia

    /// @notice Last delivered message ID (for assertions in tests)
    bytes32 public lastMessageId;

    /// @notice Register a receiver for a chain selector
    /// @param chainSelector The destination chain selector
    /// @param receiver The receiver contract address
    function setReceiver(uint64 chainSelector, address receiver) external {
        receivers[chainSelector] = receiver;
    }

    /// @notice Set the fixed fee
    function setFixedFee(uint256 fee) external {
        fixedFee = fee;
    }

    /// @notice Set the source chain selector for delivered messages
    function setSourceChainSelector(uint64 selector) external {
        sourceChainSelector = selector;
    }

    /// @inheritdoc IRouterClient
    function isChainSupported(uint64 destChainSelector) external view override returns (bool) {
        return receivers[destChainSelector] != address(0);
    }

    /// @inheritdoc IRouterClient
    function getFee(uint64, Client.EVM2AnyMessage memory) external view override returns (uint256) {
        return fixedFee;
    }

    /// @inheritdoc IRouterClient
    /// @dev Immediately delivers to the receiver — simulates cross-chain in one tx
    function ccipSend(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage calldata message
    ) external payable override returns (bytes32) {
        address receiver = receivers[destinationChainSelector];
        require(receiver != address(0), "MockCCIPRouter: no receiver");
        require(msg.value >= fixedFee, "MockCCIPRouter: insufficient fee");

        bytes32 messageId = keccak256(abi.encode(messageCount++, block.timestamp, msg.sender));
        lastMessageId = messageId;

        // Build the received message struct
        Client.Any2EVMMessage memory receivedMessage = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(msg.sender),
            data: message.data,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        // Deliver immediately (simulates cross-chain delivery)
        IAny2EVMMessageReceiver(receiver).ccipReceive(receivedMessage);

        return messageId;
    }
}
