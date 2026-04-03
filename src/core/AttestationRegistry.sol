// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IAttestationVerifier } from "../interfaces/IAttestationVerifier.sol";
import { ISignerRegistry } from "../interfaces/ISignerRegistry.sol";
import { AttestationLib } from "../libraries/AttestationLib.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title AttestationRegistry
/// @author Xythum Protocol
/// @notice Receives, verifies, and stores cross-chain RWA attestations.
///         Verifies threshold ECDSA signatures via SignerRegistry.
/// @dev Attestations are indexed by attestationId and by origin/target pair key.
///      Includes rate limiting and staleness checks.
contract AttestationRegistry is IAttestationVerifier {
    // ─── Custom Errors ───────────────────────────────────────────────
    error InsufficientSignatures(uint256 provided, uint256 required);
    error InvalidSignature(address recovered, uint256 signerIndex);
    error AttestationExpired(uint256 attestationTimestamp, uint256 maxAge);
    error RateLimited(bytes32 pairKey, uint256 nextAllowedTime);
    error AttestationAlreadyExists(bytes32 attestationId);
    error AttestationNotFound(bytes32 attestationId);
    error WrongTargetChain(uint256 provided, uint256 expected);
    error SignatureTooShort(uint256 provided, uint256 required);

    // ─── Immutables ──────────────────────────────────────────────────
    /// @notice The signer registry used for signature verification
    ISignerRegistry public immutable signerRegistry;

    /// @notice Maximum age of an attestation before it's considered stale (seconds)
    uint256 public immutable maxStaleness;

    /// @notice Minimum time between attestations for the same origin/target pair (seconds)
    uint256 public immutable rateLimitPeriod;

    /// @notice EIP-712 domain separator (computed at deployment)
    bytes32 public immutable DOMAIN_SEPARATOR;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Stored attestations indexed by attestation ID
    mapping(bytes32 => AttestationLib.Attestation) internal _attestations;

    /// @notice Latest attestation ID for each origin/target pair
    mapping(bytes32 => bytes32) public latestAttestation;

    /// @notice Timestamp of the last attestation for each origin/target pair
    mapping(bytes32 => uint256) public lastAttestationTime;

    // ─── Constructor ─────────────────────────────────────────────────
    /// @notice Initialize the attestation registry
    /// @param _signerRegistry Address of the signer registry contract
    /// @param _maxStaleness Maximum attestation age in seconds (e.g. 24 hours)
    /// @param _rateLimitPeriod Minimum time between attestations per pair (e.g. 1 hour)
    constructor(address _signerRegistry, uint256 _maxStaleness, uint256 _rateLimitPeriod) {
        signerRegistry = ISignerRegistry(_signerRegistry);
        maxStaleness = _maxStaleness;
        rateLimitPeriod = _rateLimitPeriod;
        DOMAIN_SEPARATOR = AttestationLib.domainSeparator(block.chainid, address(this));
    }

    // ─── External Functions ──────────────────────────────────────────

    /// @inheritdoc IAttestationVerifier
    function verifyAttestation(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external returns (bytes32) {
        // 1. Staleness check
        _checkStaleness(att.timestamp);

        // 2. Rate limit check + compute pair key
        bytes32 _pairKey = _checkRateLimit(att.originContract, att.originChainId, att.targetChainId);

        // 3. Count signatures and verify threshold
        _checkSignatureCount(signerBitmap);

        // 4. Check attestation doesn't already exist
        bytes32 attId = AttestationLib.attestationId(att);
        if (_attestations[attId].timestamp != 0) {
            revert AttestationAlreadyExists(attId);
        }

        // 5-6. Verify signatures against signer set
        _verifySignatures(att, signatures, signerBitmap);

        // 7. Store attestation
        _storeAttestation(attId, att, _pairKey);

        return attId;
    }

    /// @inheritdoc IAttestationVerifier
    function getAttestation(bytes32 attestationId_)
        external
        view
        returns (AttestationLib.Attestation memory)
    {
        AttestationLib.Attestation storage att = _attestations[attestationId_];
        if (att.timestamp == 0) revert AttestationNotFound(attestationId_);
        return att;
    }

    /// @inheritdoc IAttestationVerifier
    function isAttested(address originContract, uint256 originChainId, uint256 targetChainId)
        external
        view
        returns (bool)
    {
        bytes32 _pairKey = AttestationLib.pairKey(originContract, originChainId, targetChainId);
        return latestAttestation[_pairKey] != bytes32(0);
    }

    /// @inheritdoc IAttestationVerifier
    function getLatestAttestation(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId
    ) external view returns (bytes32) {
        bytes32 _pairKey = AttestationLib.pairKey(originContract, originChainId, targetChainId);
        return latestAttestation[_pairKey];
    }

    /// @inheritdoc IAttestationVerifier
    /// @notice Submit and verify an attestation directly (no CCIP required).
    ///         This is the fast path for attestation submission.
    ///         Same verification as when called via CanonicalFactory.
    /// @dev Adds a chain ID guard to ensure the attestation targets this chain.
    ///      Useful for NAV updates or any attestation that doesn't need CCIP transport.
    function submitAttestation(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external returns (bytes32 attId) {
        // Verify target chain matches this chain
        if (att.targetChainId != block.chainid) {
            revert WrongTargetChain(att.targetChainId, block.chainid);
        }

        // Use existing verification logic
        return this.verifyAttestation(att, signatures, signerBitmap);
    }

    // ─── Internal Functions ──────────────────────────────────────────

    /// @notice Verify attestation timestamp is not stale
    function _checkStaleness(uint256 attestationTimestamp) internal view {
        if (block.timestamp > attestationTimestamp + maxStaleness) {
            revert AttestationExpired(attestationTimestamp, maxStaleness);
        }
    }

    /// @notice Check rate limit for an origin/target pair
    /// @return _pairKey The computed pair key
    function _checkRateLimit(address originContract, uint256 originChainId, uint256 targetChainId)
        internal
        view
        returns (bytes32 _pairKey)
    {
        _pairKey = AttestationLib.pairKey(originContract, originChainId, targetChainId);
        uint256 lastTime = lastAttestationTime[_pairKey];
        if (lastTime != 0 && block.timestamp < lastTime + rateLimitPeriod) {
            revert RateLimited(_pairKey, lastTime + rateLimitPeriod);
        }
    }

    /// @notice Check that enough signers have signed
    function _checkSignatureCount(uint256 signerBitmap) internal view {
        uint256 sigCount = _countBits(signerBitmap);
        uint256 requiredThreshold = signerRegistry.getThreshold();
        if (sigCount < requiredThreshold) {
            revert InsufficientSignatures(sigCount, requiredThreshold);
        }
    }

    /// @notice Verify ECDSA signatures against the signer set
    function _verifySignatures(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) internal view {
        bytes32 digest = AttestationLib.toTypedDataHash(att, DOMAIN_SEPARATOR);
        address[] memory signers = signerRegistry.getSignerSet();
        uint256 sigOffset = 0;

        for (uint256 i = 0; i < 256; i++) {
            if (signerBitmap & (1 << i) == 0) continue;

            // Extract 65-byte signature (r=32, s=32, v=1)
            if (signatures.length < sigOffset + 65) {
                revert SignatureTooShort(signatures.length, sigOffset + 65);
            }
            bytes memory sig = signatures[sigOffset:sigOffset + 65];
            sigOffset += 65;

            // Recover signer and verify
            address recovered = ECDSA.recover(digest, sig);
            if (i >= signers.length || recovered != signers[i]) {
                revert InvalidSignature(recovered, i);
            }
        }
    }

    /// @notice Store a verified attestation and update indices
    function _storeAttestation(
        bytes32 attId,
        AttestationLib.Attestation calldata att,
        bytes32 _pairKey
    ) internal {
        _attestations[attId] = att;
        latestAttestation[_pairKey] = attId;
        lastAttestationTime[_pairKey] = block.timestamp;

        emit AttestationVerified(
            attId, att.originContract, att.originChainId, att.targetChainId, att.timestamp
        );
    }

    /// @notice Count the number of set bits in a bitmap (Brian Kernighan's algorithm)
    /// @param bitmap The bitmap to count
    /// @return count Number of set bits
    function _countBits(uint256 bitmap) internal pure returns (uint256 count) {
        while (bitmap != 0) {
            bitmap &= bitmap - 1;
            count++;
        }
    }
}
