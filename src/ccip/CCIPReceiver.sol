// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {CCIPReceiver as ChainlinkCCIPReceiver} from
    "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {ICanonicalFactory} from "../interfaces/ICanonicalFactory.sol";
import {AttestationLib} from "../libraries/AttestationLib.sol";

/// @title XythumCCIPReceiver
/// @author Xythum Protocol
/// @notice Target chain contract: receives CCIP messages containing attestations
///         and triggers mirror deployments or NAV updates via CanonicalFactory.
/// @dev Uses try/catch for factory calls to prevent CCIP message replay on failure.
///      TODO(upgrade): handle NAV updates for existing mirrors
contract XythumCCIPReceiver is ChainlinkCCIPReceiver, Ownable2Step {
    // ─── Constants ───────────────────────────────────────────────────
    uint8 public constant MESSAGE_TYPE_DEPLOY = 1;
    uint8 public constant MESSAGE_TYPE_UPDATE = 2;

    // ─── Custom Errors ───────────────────────────────────────────────
    error UnauthorizedSender(uint64 sourceChain, address sender);
    error MessageAlreadyProcessed(bytes32 messageId);
    error UnknownMessageType(uint8 messageType);

    // ─── Events ──────────────────────────────────────────────────────
    /// @notice Emitted when a CCIP message is received and processed
    event AttestationReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        uint8 messageType
    );

    /// @notice Emitted when a mirror is successfully deployed via CCIP
    event MirrorDeployedViaCCIP(
        bytes32 indexed messageId,
        address indexed mirror
    );

    /// @notice Emitted when a deployment fails (logged, not reverted)
    event DeploymentFailed(
        bytes32 indexed messageId,
        bytes reason
    );

    // ─── Immutables ──────────────────────────────────────────────────
    /// @notice The CanonicalFactory for deploying mirrors
    ICanonicalFactory public immutable factory;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice sourceChainSelector → sender address → allowed
    mapping(uint64 => mapping(address => bool)) public allowedSenders;

    /// @notice Processed message IDs (replay protection)
    mapping(bytes32 => bool) public processedMessages;

    // ─── Constructor ─────────────────────────────────────────────────
    /// @notice Initialize the CCIP receiver
    /// @param _router Address of the Chainlink CCIP router
    /// @param _factory Address of the CanonicalFactory
    /// @param _owner Contract owner
    constructor(
        address _router,
        address _factory,
        address _owner
    ) ChainlinkCCIPReceiver(_router) Ownable(_owner) {
        factory = ICanonicalFactory(_factory);
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    /// @notice Set whether a sender on a source chain is allowed
    /// @param sourceChain Source chain selector
    /// @param sender Sender address
    /// @param allowed Whether to allow
    function setAllowedSender(
        uint64 sourceChain,
        address sender,
        bool allowed
    ) external onlyOwner {
        allowedSenders[sourceChain][sender] = allowed;
    }

    // ─── Internal Overrides ──────────────────────────────────────────

    /// @notice Handle incoming CCIP messages
    /// @dev Overrides Chainlink's CCIPReceiver._ccipReceive
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        // 1. Extract sender
        address sender = abi.decode(message.sender, (address));

        // 2. Validate sender
        if (!allowedSenders[message.sourceChainSelector][sender]) {
            revert UnauthorizedSender(message.sourceChainSelector, sender);
        }

        // 3. Replay protection
        if (processedMessages[message.messageId]) {
            revert MessageAlreadyProcessed(message.messageId);
        }
        processedMessages[message.messageId] = true;

        // 4. Decode payload
        (uint8 messageType, bytes memory attEncoded, bytes memory signatures, uint256 signerBitmap) =
            abi.decode(message.data, (uint8, bytes, bytes, uint256));

        // 5. Route by message type
        if (messageType == MESSAGE_TYPE_DEPLOY) {
            _handleDeploy(message.messageId, attEncoded, signatures, signerBitmap);
        } else if (messageType == MESSAGE_TYPE_UPDATE) {
            _handleNAVUpdate(attEncoded, signatures, signerBitmap);
        } else {
            revert UnknownMessageType(messageType);
        }

        // 6. Emit received event
        emit AttestationReceived(message.messageId, message.sourceChainSelector, messageType);
    }

    /// @notice Handle a mirror deployment request
    function _handleDeploy(
        bytes32 messageId,
        bytes memory attEncoded,
        bytes memory signatures,
        uint256 signerBitmap
    ) internal {
        AttestationLib.Attestation memory att = abi.decode(attEncoded, (AttestationLib.Attestation));

        // Use try/catch to prevent CCIP retry on app-level failure
        try factory.deployMirror(att, signatures, signerBitmap) returns (address mirror) {
            emit MirrorDeployedViaCCIP(messageId, mirror);
        } catch (bytes memory reason) {
            emit DeploymentFailed(messageId, reason);
        }
    }

    /// @notice Handle a NAV update
    /// @dev TODO(v2): Implement NAV update logic for existing mirrors
    function _handleNAVUpdate(
        bytes memory, // attEncoded
        bytes memory, // signatures
        uint256 // signerBitmap
    ) internal {
        // MVP: NAV updates not yet implemented
        // In v2, this would update the NAV data on existing mirrors
    }
}
