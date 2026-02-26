// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AttestationLib
/// @author Xythum Protocol
/// @notice Core data structures and utilities for cross-chain RWA attestations
/// @dev All functions are pure — no storage, no side effects
library AttestationLib {
    /// @notice The canonical attestation payload for cross-chain RWA state
    struct Attestation {
        address originContract;     // ERC-3643 token address on source chain
        uint256 originChainId;      // Source chain ID
        uint256 targetChainId;      // Destination chain ID
        bytes32 navRoot;            // Merkle root of NAV data (price, timestamp, source)
        bytes32 complianceRoot;     // Merkle root of compliance/identity registry
        uint256 lockedAmount;       // Total supply locked for this target chain
        uint256 timestamp;          // Attestation creation time (unix seconds)
        uint256 nonce;              // Monotonically increasing, prevents replay
    }

    /// @notice EIP-712 typehash for the Attestation struct
    bytes32 internal constant ATTESTATION_TYPEHASH = keccak256(
        "Attestation(address originContract,uint256 originChainId,uint256 targetChainId,"
        "bytes32 navRoot,bytes32 complianceRoot,uint256 lockedAmount,"
        "uint256 timestamp,uint256 nonce)"
    );

    /// @notice EIP-712 domain separator components
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    string internal constant DOMAIN_NAME = "Xythum RWA Passport";
    string internal constant DOMAIN_VERSION = "1";

    /// @notice Compute the EIP-712 struct hash of an attestation
    /// @param att The attestation to hash
    /// @return The keccak256 hash
    function hash(Attestation memory att) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ATTESTATION_TYPEHASH,
            att.originContract,
            att.originChainId,
            att.targetChainId,
            att.navRoot,
            att.complianceRoot,
            att.lockedAmount,
            att.timestamp,
            att.nonce
        ));
    }

    /// @notice Compute the EIP-712 domain separator
    /// @param chainId The chain ID for the domain
    /// @param verifyingContract The contract address for the domain
    /// @return The domain separator hash
    function domainSeparator(
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            DOMAIN_TYPEHASH,
            keccak256(bytes(DOMAIN_NAME)),
            keccak256(bytes(DOMAIN_VERSION)),
            chainId,
            verifyingContract
        ));
    }

    /// @notice Compute the full EIP-712 digest for signing
    /// @param att The attestation
    /// @param _domainSeparator Pre-computed domain separator
    /// @return The digest to be signed
    function toTypedDataHash(
        Attestation memory att,
        bytes32 _domainSeparator
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            _domainSeparator,
            hash(att)
        ));
    }

    /// @notice Compute the deterministic salt for CREATE2 deployment
    /// @dev Salt is derived from origin identity + target chain.
    ///      This guarantees exactly one mirror address per origin/target pair.
    /// @param att The attestation
    /// @return The CREATE2 salt
    function canonicalSalt(Attestation memory att) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            att.originContract,
            att.originChainId,
            att.targetChainId
        ));
    }

    /// @notice Compute the unique attestation ID
    /// @param att The attestation
    /// @return The attestation identifier
    function attestationId(Attestation memory att) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            att.originContract,
            att.originChainId,
            att.targetChainId,
            att.nonce
        ));
    }

    /// @notice Compute the lookup key for an origin/target pair
    /// @param originContract Origin RWA address
    /// @param originChainId Source chain ID
    /// @param targetChainId Destination chain ID
    /// @return The lookup key
    function pairKey(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(originContract, originChainId, targetChainId));
    }
}
