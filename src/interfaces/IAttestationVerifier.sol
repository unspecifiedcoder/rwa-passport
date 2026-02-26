// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AttestationLib} from "../libraries/AttestationLib.sol";

/// @title IAttestationVerifier
/// @author Xythum Protocol
/// @notice Verifies and stores cross-chain RWA attestations
interface IAttestationVerifier {
    /// @notice Emitted when an attestation is verified and stored
    /// @param attestationId Unique identifier for the attestation
    /// @param originContract Address of the RWA on the source chain
    /// @param originChainId Source chain ID
    /// @param targetChainId Destination chain ID
    /// @param timestamp Attestation creation time
    event AttestationVerified(
        bytes32 indexed attestationId,
        address indexed originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 timestamp
    );

    /// @notice Verify an attestation with threshold signatures
    /// @param att The attestation data
    /// @param signatures Packed ECDSA signatures (65 bytes each)
    /// @param signerBitmap Bitmap indicating which signers signed (bit i = signer at index i)
    /// @return attestationId The unique ID of the stored attestation
    function verifyAttestation(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external returns (bytes32 attestationId);

    /// @notice Get a stored attestation by its ID
    /// @param attestationId The unique attestation identifier
    /// @return The attestation data
    function getAttestation(bytes32 attestationId)
        external view returns (AttestationLib.Attestation memory);

    /// @notice Check if an origin/target pair has been attested
    /// @param originContract Address of the RWA on source chain
    /// @param originChainId Source chain ID
    /// @param targetChainId Destination chain ID
    /// @return True if a valid attestation exists
    function isAttested(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId
    ) external view returns (bool);

    /// @notice Get the latest attestation for an origin/target pair
    /// @param originContract Address of the RWA on source chain
    /// @param originChainId Source chain ID
    /// @param targetChainId Destination chain ID
    /// @return The attestation ID
    function getLatestAttestation(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId
    ) external view returns (bytes32);

    /// @notice Submit and verify an attestation directly (no CCIP required).
    ///         Adds a chain ID guard to ensure the attestation targets this chain.
    /// @param att The attestation data
    /// @param signatures Packed ECDSA signatures
    /// @param signerBitmap Bitmap of signing signers
    /// @return attId The verified attestation ID
    function submitAttestation(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external returns (bytes32 attId);
}
