// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title SignatureLib
/// @author Xythum Protocol
/// @notice Shared ECDSA threshold-signature verification used across the protocol.
/// @dev Extracted from AttestationRegistry._verifySignatures so that
///      AttestationRegistry, RWALockEscrow, and CanonicalFactory.mintFromLock
///      share one audited recovery loop. Pure library, no state.
library SignatureLib {
    error InsufficientSignatures(uint256 provided, uint256 required);
    error SignatureTooShort(uint256 provided, uint256 required);
    error InvalidSignature(address recovered, uint256 signerIndex);

    /// @notice Count the number of set bits in a uint256 bitmap
    /// @dev Brian Kernighan's algorithm
    function countBits(uint256 bitmap) internal pure returns (uint256 count) {
        while (bitmap != 0) {
            bitmap &= bitmap - 1;
            count++;
        }
    }

    /// @notice Verify that `signatures` contains valid threshold signatures over `digest`
    ///         from members of `signers` indicated by `signerBitmap`.
    /// @param digest        EIP-712 typed data digest (already hashed with domain separator).
    /// @param signatures    Packed 65-byte ECDSA signatures concatenated in bit-order.
    /// @param signerBitmap  Bitmap of which signer indices signed (bit i ↔ signers[i]).
    /// @param signers       The full active signer set (from SignerRegistry.getSignerSet()).
    /// @param threshold     Minimum signatures required.
    /// @dev Reverts with InsufficientSignatures, SignatureTooShort, or InvalidSignature.
    function verifyThreshold(
        bytes32 digest,
        bytes calldata signatures,
        uint256 signerBitmap,
        address[] memory signers,
        uint256 threshold
    ) internal pure {
        uint256 sigCount = countBits(signerBitmap);
        if (sigCount < threshold) revert InsufficientSignatures(sigCount, threshold);

        uint256 sigOffset = 0;
        for (uint256 i = 0; i < 256; i++) {
            if (signerBitmap & (1 << i) == 0) continue;

            if (signatures.length < sigOffset + 65) {
                revert SignatureTooShort(signatures.length, sigOffset + 65);
            }
            bytes calldata sig = signatures[sigOffset:sigOffset + 65];
            sigOffset += 65;

            address recovered = ECDSA.recover(digest, sig);
            if (i >= signers.length || recovered != signers[i]) {
                revert InvalidSignature(recovered, i);
            }
        }
    }
}
