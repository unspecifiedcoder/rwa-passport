// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {AttestationLib} from "../libraries/AttestationLib.sol";

/// @title CCIPSender
/// @author Xythum Protocol
/// @notice Source chain contract: sends attestations via Chainlink CCIP to target chains.
///         Allows anyone to request a mirror deployment on a target chain by submitting
///         a pre-signed attestation.
/// @dev The message payload encodes: messageType + attestation + signatures + bitmap.
///      TODO(upgrade): support ERC-20 fee payment (currently native only)
contract CCIPSender is Ownable2Step {
    // ─── Constants ───────────────────────────────────────────────────
    /// @notice Message type for mirror deployment requests
    uint8 public constant MESSAGE_TYPE_DEPLOY = 1;

    /// @notice Message type for NAV updates
    uint8 public constant MESSAGE_TYPE_UPDATE = 2;

    /// @notice Gas limit for CCIP message execution on target chain
    uint256 public constant CCIP_GAS_LIMIT = 1_500_000;

    // ─── Custom Errors ───────────────────────────────────────────────
    error UnsupportedChain(uint64 chainSelector);
    error InsufficientFee(uint256 required, uint256 sent);
    error ReceiverNotSet(uint64 chainSelector);
    error RefundFailed();

    // ─── Events ──────────────────────────────────────────────────────
    /// @notice Emitted when an attestation is sent via CCIP
    event AttestationSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address originContract,
        uint256 nonce
    );

    // ─── Immutables ──────────────────────────────────────────────────
    /// @notice The CCIP router contract
    IRouterClient public immutable ccipRouter;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Chain selector → receiver address on that target chain
    mapping(uint64 => address) public allowedReceivers;

    /// @notice Which target chains are supported
    mapping(uint64 => bool) public supportedChains;

    // ─── Constructor ─────────────────────────────────────────────────
    /// @notice Initialize the CCIP sender
    /// @param _router Address of the Chainlink CCIP router
    /// @param _owner Contract owner
    constructor(address _router, address _owner) Ownable(_owner) {
        ccipRouter = IRouterClient(_router);
    }

    // ─── External Functions ──────────────────────────────────────────

    /// @notice Send an attestation to a target chain for mirror deployment
    /// @param destinationChainSelector CCIP selector for the target chain
    /// @param att The attestation data
    /// @param signatures Packed ECDSA signatures
    /// @param signerBitmap Bitmap of signing signers
    /// @return messageId The CCIP message ID
    function sendAttestation(
        uint64 destinationChainSelector,
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external payable returns (bytes32 messageId) {
        return _sendMessage(
            destinationChainSelector,
            MESSAGE_TYPE_DEPLOY,
            att,
            signatures,
            signerBitmap
        );
    }

    /// @notice Send a NAV update to a target chain
    /// @param destinationChainSelector CCIP selector for the target chain
    /// @param att The attestation data with updated NAV
    /// @param signatures Packed ECDSA signatures
    /// @param signerBitmap Bitmap of signing signers
    /// @return messageId The CCIP message ID
    function sendNAVUpdate(
        uint64 destinationChainSelector,
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external payable returns (bytes32 messageId) {
        return _sendMessage(
            destinationChainSelector,
            MESSAGE_TYPE_UPDATE,
            att,
            signatures,
            signerBitmap
        );
    }

    /// @notice Estimate the CCIP fee for sending a message
    /// @param destinationChainSelector CCIP selector for the target chain
    /// @param payload The encoded payload
    /// @return fee The estimated fee in native currency
    function estimateFee(
        uint64 destinationChainSelector,
        bytes calldata payload
    ) external view returns (uint256 fee) {
        address receiver = allowedReceivers[destinationChainSelector];
        if (receiver == address(0)) revert ReceiverNotSet(destinationChainSelector);

        Client.EVM2AnyMessage memory message = _buildCCIPMessage(receiver, payload);
        return ccipRouter.getFee(destinationChainSelector, message);
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    /// @notice Set the receiver address for a target chain
    /// @param chainSelector CCIP chain selector
    /// @param receiver Receiver contract address on the target chain
    function setReceiver(uint64 chainSelector, address receiver) external onlyOwner {
        allowedReceivers[chainSelector] = receiver;
    }

    /// @notice Enable or disable a target chain
    /// @param chainSelector CCIP chain selector
    /// @param supported Whether the chain is supported
    function setSupportedChain(uint64 chainSelector, bool supported) external onlyOwner {
        supportedChains[chainSelector] = supported;
    }

    // ─── Internal Functions ──────────────────────────────────────────

    /// @notice Build and send a CCIP message
    function _sendMessage(
        uint64 destinationChainSelector,
        uint8 messageType,
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) internal returns (bytes32 messageId) {
        // 1. Validate chain supported
        if (!supportedChains[destinationChainSelector]) {
            revert UnsupportedChain(destinationChainSelector);
        }

        // 2. Validate receiver set
        address receiver = allowedReceivers[destinationChainSelector];
        if (receiver == address(0)) {
            revert ReceiverNotSet(destinationChainSelector);
        }

        // 3. Encode payload
        bytes memory payload = abi.encode(
            messageType,
            abi.encode(att),
            signatures,
            signerBitmap
        );

        // 4. Build CCIP message
        Client.EVM2AnyMessage memory message = _buildCCIPMessage(receiver, payload);

        // 5. Get fee estimate
        uint256 fee = ccipRouter.getFee(destinationChainSelector, message);
        if (msg.value < fee) {
            revert InsufficientFee(fee, msg.value);
        }

        // 6. Send via CCIP
        messageId = ccipRouter.ccipSend{value: fee}(destinationChainSelector, message);

        // 7. Refund excess fee
        uint256 refund = msg.value - fee;
        if (refund > 0) {
            (bool sent,) = msg.sender.call{value: refund}("");
            if (!sent) revert RefundFailed();
        }

        // 8. Emit event
        emit AttestationSent(messageId, destinationChainSelector, att.originContract, att.nonce);
    }

    /// @notice Build a CCIP message struct
    function _buildCCIPMessage(
        address receiver,
        bytes memory payload
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: address(0), // pay in native
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: CCIP_GAS_LIMIT})
            )
        });
    }
}
