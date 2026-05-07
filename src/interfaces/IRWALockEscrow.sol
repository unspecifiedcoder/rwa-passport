// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ReceiptLib } from "../libraries/ReceiptLib.sol";

/// @title IRWALockEscrow
/// @author Xythum Protocol
/// @notice Per-chain escrow contract that holds custody of original RWAs while
///         their canonical mirrors are active on other chains.
interface IRWALockEscrow {
    /// @notice Emitted when a user locks RWA tokens for cross-chain mirroring
    /// @param lockId Deterministic identifier for this lock
    /// @param locker Address that locked the tokens
    /// @param rwaToken The original RWA ERC-20 escrowed
    /// @param amount Amount of RWA locked
    /// @param targetChainId Chain on which the mirror is intended to live
    event Locked(
        bytes32 indexed lockId,
        address indexed locker,
        address indexed rwaToken,
        uint256 amount,
        uint256 targetChainId
    );

    /// @notice Emitted when an UnlockReceipt is consumed and the original
    ///         RWA is released to the recipient
    /// @param lockId Identifier of the lock being released
    /// @param recipient Address that receives the original RWA
    /// @param amount Amount released
    event Released(bytes32 indexed lockId, address indexed recipient, uint256 amount);

    /// @notice Lock RWA tokens in escrow for cross-chain mirroring.
    ///         Caller must have already approved `amount` of `rwaToken` to this contract.
    /// @param rwaToken The original RWA ERC-20 contract on this chain
    /// @param amount Amount to lock
    /// @param targetChainId Chain where the mirror should be minted
    /// @return lockId Deterministic identifier for this lock
    function lock(address rwaToken, uint256 amount, uint256 targetChainId)
        external
        returns (bytes32 lockId);

    /// @notice Release locked RWA tokens by presenting a threshold-signed UnlockReceipt.
    ///         Anyone may call this; the receipt's `recipient` field determines who
    ///         receives the tokens.
    /// @param receipt The UnlockReceipt
    /// @param signatures Packed 65-byte ECDSA signatures (3-of-N threshold)
    /// @param signerBitmap Bitmap of which signers signed
    function release(
        ReceiptLib.UnlockReceipt calldata receipt,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external;

    /// @notice The signer registry that issues UnlockReceipts
    function signerRegistry() external view returns (address);

    /// @notice The EIP-712 domain separator for this escrow on its chain
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice Maximum allowed staleness for an UnlockReceipt (seconds)
    function maxStaleness() external view returns (uint256);

    /// @notice Inspect the on-chain state of a lock
    function lockState(bytes32 lockId)
        external
        view
        returns (address rwaToken, address locker, uint256 amount, uint256 lockedAt, bool released);
}
