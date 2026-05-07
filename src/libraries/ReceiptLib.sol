// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AttestationLib } from "./AttestationLib.sol";

/// @title ReceiptLib
/// @author Xythum Protocol
/// @notice EIP-712 typed-data structures for the lock-mint-burn-unlock round-trip.
/// @dev Companion to AttestationLib. Reuses the same EIP-712 domain
///      (`name = "Xythum RWA Passport"`, `version = "1"`) so the same 3-of-5
///      signer set can sign both attestations AND receipts. Pure library, no state.
library ReceiptLib {
    /// @notice Receipt that the protocol's signers issue after observing a
    ///         valid `Locked` event on the origin chain. Consumed on the
    ///         target chain by `CanonicalFactory.mintFromLock` to mint xRWA.
    struct LockReceipt {
        address originContract; // RWA token address on the origin chain
        uint256 originChainId; // Origin chain ID
        uint256 targetChainId; // Target chain ID where xRWA will be minted
        address locker; // Address that called escrow.lock()
        uint256 amount; // Amount of original RWA escrowed
        bytes32 lockId; // Unique lock identifier (deterministic, see RWALockEscrow.lock)
        uint256 timestamp; // Receipt issuance time (unix seconds)
    }

    /// @notice Receipt that the protocol's signers issue after observing a
    ///         valid `BurnedForLock` event on the target chain. Consumed on
    ///         the origin chain by `RWALockEscrow.release` to return the
    ///         original RWA to the recipient.
    struct UnlockReceipt {
        address originContract; // RWA token address on the origin chain
        uint256 originChainId; // Origin chain ID (where escrow lives)
        uint256 targetChainId; // Target chain ID where the burn happened
        address recipient; // Who receives the original RWA back
        uint256 amount; // Amount to release (must match locks[lockId].amount)
        bytes32 lockId; // Must match the original lockId
        uint256 burnTxBlock; // Target-chain block number of the burn (audit trail)
        uint256 timestamp; // Receipt issuance time (unix seconds)
    }

    /// @notice EIP-712 typehash for LockReceipt
    bytes32 internal constant LOCK_RECEIPT_TYPEHASH = keccak256(
        "LockReceipt(address originContract,uint256 originChainId,uint256 targetChainId,"
        "address locker,uint256 amount,bytes32 lockId,uint256 timestamp)"
    );

    /// @notice EIP-712 typehash for UnlockReceipt
    bytes32 internal constant UNLOCK_RECEIPT_TYPEHASH = keccak256(
        "UnlockReceipt(address originContract,uint256 originChainId,uint256 targetChainId,"
        "address recipient,uint256 amount,bytes32 lockId,uint256 burnTxBlock,uint256 timestamp)"
    );

    // ─── LockReceipt helpers ─────────────────────────────────────────

    function hashLockReceipt(LockReceipt memory r) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                LOCK_RECEIPT_TYPEHASH,
                r.originContract,
                r.originChainId,
                r.targetChainId,
                r.locker,
                r.amount,
                r.lockId,
                r.timestamp
            )
        );
    }

    function toTypedDataHash(LockReceipt memory r, bytes32 _domainSeparator)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator, hashLockReceipt(r)));
    }

    // ─── UnlockReceipt helpers ───────────────────────────────────────

    function hashUnlockReceipt(UnlockReceipt memory r) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                UNLOCK_RECEIPT_TYPEHASH,
                r.originContract,
                r.originChainId,
                r.targetChainId,
                r.recipient,
                r.amount,
                r.lockId,
                r.burnTxBlock,
                r.timestamp
            )
        );
    }

    function toTypedDataHash(UnlockReceipt memory r, bytes32 _domainSeparator)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator, hashUnlockReceipt(r)));
    }

    /// @notice Convenience: build the EIP-712 domain separator using the
    ///         shared protocol domain name + version from AttestationLib.
    function domainSeparator(uint256 chainId, address verifyingContract)
        internal
        pure
        returns (bytes32)
    {
        return AttestationLib.domainSeparator(chainId, verifyingContract);
    }
}
