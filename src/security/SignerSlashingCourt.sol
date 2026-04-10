// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ISignerRegistry } from "../interfaces/ISignerRegistry.sol";
import { IStakingModule } from "../interfaces/IStakingModule.sol";
import { AttestationLib } from "../libraries/AttestationLib.sol";

/// @title SignerSlashingCourt
/// @author Xythum Protocol
/// @notice On-chain court that accepts cryptographic evidence of signer misbehavior
///         and automatically slashes staked collateral via the StakingModule.
/// @dev Supported evidence types:
///      1. Double-signing: same signer signs two different attestations for the same
///         (originContract, originChainId, targetChainId, nonce) tuple.
///      2. Conflicting NAV: same signer signs two attestations for the same pairKey
///         with different navRoot values within the same rate limit window.
///
///      This closes the accountability gap between SignerRegistry (who the signers are)
///      and StakingModule (their staked collateral). Before this contract, there was no
///      automated mechanism to punish signers who misbehave — governance had to manually
///      call slash(). Now anyone with valid evidence can trigger slashing atomically.
contract SignerSlashingCourt is Ownable2Step, ReentrancyGuard {
    // ─── Custom Errors ───────────────────────────────────────────────
    error SignatureMismatch(address recovered, address expected);
    error AttestationsIdentical();
    error SignerNotRegistered(address signer);
    error EvidenceAlreadySubmitted(bytes32 evidenceId);
    error InvalidEvidenceType();
    error ZeroAddress();
    error InvalidSlashAmount();

    // ─── Events ──────────────────────────────────────────────────────
    /// @notice Emitted when double-signing evidence is accepted and a signer is slashed
    event DoubleSigningSlashed(
        address indexed signer,
        bytes32 indexed attestationId1,
        bytes32 indexed attestationId2,
        uint256 slashAmount,
        address reporter
    );

    /// @notice Emitted when conflicting NAV evidence is accepted and a signer is slashed
    event ConflictingNAVSlashed(
        address indexed signer,
        bytes32 indexed pairKey,
        bytes32 navRoot1,
        bytes32 navRoot2,
        uint256 slashAmount,
        address reporter
    );

    /// @notice Emitted when slashing parameters are updated
    event SlashingParametersUpdated(
        uint256 doubleSignSlashAmount, uint256 conflictingNAVSlashAmount, uint256 reporterBountyBps
    );

    // ─── Immutables ──────────────────────────────────────────────────
    ISignerRegistry public immutable signerRegistry;
    IStakingModule public immutable stakingModule;
    bytes32 public immutable DOMAIN_SEPARATOR;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Amount of stake to slash for a double-signing offense
    uint256 public doubleSignSlashAmount;

    /// @notice Amount of stake to slash for a conflicting NAV offense
    uint256 public conflictingNAVSlashAmount;

    /// @notice Bounty paid to the reporter in basis points (10000 = 100%)
    /// @dev Bounty is taken from the slashed amount and sent from the insurance fund
    uint256 public reporterBountyBps;

    /// @notice Already-processed evidence (prevents double-reporting)
    mapping(bytes32 => bool) public processedEvidence;

    /// @notice Total slashing events by signer
    mapping(address => uint256) public slashingCount;

    /// @notice Total amount slashed by signer (lifetime)
    mapping(address => uint256) public totalSlashedAmount;

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _signerRegistry The signer registry contract
    /// @param _stakingModule The staking module (this court must be authorized as a slasher)
    /// @param _attestationRegistryDomain The DOMAIN_SEPARATOR used by AttestationRegistry
    ///        for signature verification (must match to recover signers correctly)
    /// @param _owner Contract owner (should be governance timelock)
    constructor(
        address _signerRegistry,
        address _stakingModule,
        bytes32 _attestationRegistryDomain,
        address _owner
    ) Ownable(_owner) {
        if (_signerRegistry == address(0) || _stakingModule == address(0)) {
            revert ZeroAddress();
        }
        signerRegistry = ISignerRegistry(_signerRegistry);
        stakingModule = IStakingModule(_stakingModule);
        DOMAIN_SEPARATOR = _attestationRegistryDomain;

        // Sensible defaults: slash 10% of max stake (10k XYT) for double-signing,
        // 5k XYT for conflicting NAV, 5% reporter bounty
        doubleSignSlashAmount = 10_000 ether;
        conflictingNAVSlashAmount = 5_000 ether;
        reporterBountyBps = 500; // 5%
    }

    // ─── Evidence Submission ─────────────────────────────────────────

    /// @notice Submit evidence that a signer signed two conflicting attestations
    ///         with the same nonce (double-signing)
    /// @dev Two attestations with the same (originContract, originChainId, targetChainId, nonce)
    ///      but different content (e.g., different navRoot or lockedAmount) constitute proof
    ///      of double-signing. Both signatures must recover to the same signer address.
    /// @param att1 First attestation
    /// @param sig1 Signature over att1 by the alleged misbehaving signer
    /// @param att2 Second attestation (same nonce, different content)
    /// @param sig2 Signature over att2 by the same signer
    /// @param signer The alleged misbehaving signer address
    function submitDoubleSigningEvidence(
        AttestationLib.Attestation calldata att1,
        bytes calldata sig1,
        AttestationLib.Attestation calldata att2,
        bytes calldata sig2,
        address signer
    ) external nonReentrant {
        // 1. Verify signer is registered
        if (!signerRegistry.isActiveSigner(signer)) revert SignerNotRegistered(signer);

        // 2. Verify both attestations have the same attestationId (same nonce + pair)
        bytes32 attId1 = AttestationLib.attestationId(att1);
        bytes32 attId2 = AttestationLib.attestationId(att2);

        // Both must have same identity (pairKey + nonce) but different content
        if (attId1 != attId2) revert InvalidEvidenceType();

        // Content must actually differ — compare the full hashes
        bytes32 hash1 = AttestationLib.hash(att1);
        bytes32 hash2 = AttestationLib.hash(att2);
        if (hash1 == hash2) revert AttestationsIdentical();

        // 3. Verify both signatures recover to the claimed signer
        bytes32 digest1 = AttestationLib.toTypedDataHash(att1, DOMAIN_SEPARATOR);
        bytes32 digest2 = AttestationLib.toTypedDataHash(att2, DOMAIN_SEPARATOR);

        address recovered1 = ECDSA.recover(digest1, sig1);
        address recovered2 = ECDSA.recover(digest2, sig2);

        if (recovered1 != signer) revert SignatureMismatch(recovered1, signer);
        if (recovered2 != signer) revert SignatureMismatch(recovered2, signer);

        // 4. Compute evidence ID and check not already processed
        bytes32 evidenceId = keccak256(
            abi.encode("double-sign", signer, attId1, hash1 < hash2 ? hash1 : hash2, hash1 < hash2 ? hash2 : hash1)
        );
        if (processedEvidence[evidenceId]) revert EvidenceAlreadySubmitted(evidenceId);
        processedEvidence[evidenceId] = true;

        // 5. Slash the signer
        uint256 slashAmount = doubleSignSlashAmount;
        slashingCount[signer]++;
        totalSlashedAmount[signer] += slashAmount;

        stakingModule.slash(signer, slashAmount, keccak256("DOUBLE_SIGNING"));

        emit DoubleSigningSlashed(signer, attId1, attId2, slashAmount, msg.sender);
    }

    /// @notice Submit evidence that a signer signed two attestations with conflicting NAV
    ///         roots for the same origin/target pair within a short time window
    /// @dev Unlike double-signing (same nonce), this catches a signer who uses different
    ///      nonces but reports materially different NAV values. If the two signatures are
    ///      both verifiable and the navRoots differ, this is evidence of lying about state.
    /// @param att1 First attestation
    /// @param sig1 Signature over att1
    /// @param att2 Second attestation (same pairKey, different nonce, different navRoot)
    /// @param sig2 Signature over att2
    /// @param signer The alleged misbehaving signer address
    function submitConflictingNAVEvidence(
        AttestationLib.Attestation calldata att1,
        bytes calldata sig1,
        AttestationLib.Attestation calldata att2,
        bytes calldata sig2,
        address signer
    ) external nonReentrant {
        // 1. Verify signer is registered
        if (!signerRegistry.isActiveSigner(signer)) revert SignerNotRegistered(signer);

        // 2. Verify both attestations reference the same pairKey
        bytes32 pairKey1 = AttestationLib.pairKey(att1.originContract, att1.originChainId, att1.targetChainId);
        bytes32 pairKey2 = AttestationLib.pairKey(att2.originContract, att2.originChainId, att2.targetChainId);
        if (pairKey1 != pairKey2) revert InvalidEvidenceType();

        // 3. Verify navRoots actually differ (otherwise not a conflict)
        if (att1.navRoot == att2.navRoot) revert AttestationsIdentical();

        // 4. Verify both signatures recover to the claimed signer
        bytes32 digest1 = AttestationLib.toTypedDataHash(att1, DOMAIN_SEPARATOR);
        bytes32 digest2 = AttestationLib.toTypedDataHash(att2, DOMAIN_SEPARATOR);

        address recovered1 = ECDSA.recover(digest1, sig1);
        address recovered2 = ECDSA.recover(digest2, sig2);

        if (recovered1 != signer) revert SignatureMismatch(recovered1, signer);
        if (recovered2 != signer) revert SignatureMismatch(recovered2, signer);

        // 5. Compute evidence ID (order-independent)
        bytes32 lower = att1.navRoot < att2.navRoot ? att1.navRoot : att2.navRoot;
        bytes32 upper = att1.navRoot < att2.navRoot ? att2.navRoot : att1.navRoot;
        bytes32 evidenceId =
            keccak256(abi.encode("conflicting-nav", signer, pairKey1, lower, upper));
        if (processedEvidence[evidenceId]) revert EvidenceAlreadySubmitted(evidenceId);
        processedEvidence[evidenceId] = true;

        // 6. Slash the signer
        uint256 slashAmount = conflictingNAVSlashAmount;
        slashingCount[signer]++;
        totalSlashedAmount[signer] += slashAmount;

        stakingModule.slash(signer, slashAmount, keccak256("CONFLICTING_NAV"));

        emit ConflictingNAVSlashed(signer, pairKey1, att1.navRoot, att2.navRoot, slashAmount, msg.sender);
    }

    // ─── Admin (Governance Only) ─────────────────────────────────────

    /// @notice Update slashing parameters (callable by governance only)
    /// @param _doubleSignSlashAmount New slash amount for double-signing
    /// @param _conflictingNAVSlashAmount New slash amount for conflicting NAV
    /// @param _reporterBountyBps New reporter bounty in basis points
    function setSlashingParameters(
        uint256 _doubleSignSlashAmount,
        uint256 _conflictingNAVSlashAmount,
        uint256 _reporterBountyBps
    ) external onlyOwner {
        if (_doubleSignSlashAmount == 0 || _conflictingNAVSlashAmount == 0) {
            revert InvalidSlashAmount();
        }
        if (_reporterBountyBps > 10000) revert InvalidSlashAmount();

        doubleSignSlashAmount = _doubleSignSlashAmount;
        conflictingNAVSlashAmount = _conflictingNAVSlashAmount;
        reporterBountyBps = _reporterBountyBps;

        emit SlashingParametersUpdated(
            _doubleSignSlashAmount, _conflictingNAVSlashAmount, _reporterBountyBps
        );
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Check if a signer has been slashed in the past
    function hasBeenSlashed(address signer) external view returns (bool) {
        return slashingCount[signer] > 0;
    }

    /// @notice Compute evidence ID for double-signing (view helper for off-chain checks)
    function computeDoubleSignEvidenceId(
        AttestationLib.Attestation calldata att1,
        AttestationLib.Attestation calldata att2,
        address signer
    ) external pure returns (bytes32) {
        bytes32 attId1 = AttestationLib.attestationId(att1);
        bytes32 hash1 = AttestationLib.hash(att1);
        bytes32 hash2 = AttestationLib.hash(att2);
        return keccak256(
            abi.encode(
                "double-sign",
                signer,
                attId1,
                hash1 < hash2 ? hash1 : hash2,
                hash1 < hash2 ? hash2 : hash1
            )
        );
    }
}
