// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ICanonicalFactory} from "../interfaces/ICanonicalFactory.sol";
import {IAttestationVerifier} from "../interfaces/IAttestationVerifier.sol";
import {AttestationLib} from "../libraries/AttestationLib.sol";
import {XythumToken} from "./XythumToken.sol";

/// @title CanonicalFactory
/// @author Xythum Protocol
/// @notice Deploys XythumToken mirrors at deterministic CREATE2 addresses.
///         Provides the isCanonical() check that all downstream integrations rely on.
/// @dev The crown jewel of the protocol. The address of every mirror is mathematically
///      determined by the attestation data, ensuring exactly one canonical mirror per
///      (originContract, originChainId, targetChainId) tuple.
contract CanonicalFactory is ICanonicalFactory, Ownable2Step, Pausable {
    // ─── Custom Errors ───────────────────────────────────────────────
    error MirrorAlreadyDeployed(address existing);
    error InsufficientFee(uint256 sent, uint256 required);
    error MirrorNotFound(address mirror);
    error DeploymentFailed();
    error WrongTargetChain(uint256 provided, uint256 expected);
    error OutOfBounds(uint256 offset, uint256 length);

    // ─── Structs ─────────────────────────────────────────────────────
    /// @notice Metadata about a deployed canonical mirror
    struct MirrorInfo {
        address originContract;
        uint256 originChainId;
        uint256 targetChainId;
        bytes32 attestationId;
        uint256 deployedAt;
        bool active;
    }

    // ─── Immutables ──────────────────────────────────────────────────
    /// @notice The attestation registry for verifying attestations
    IAttestationVerifier public immutable attestationRegistry;

    /// @notice Default compliance contract for new mirrors
    address public immutable complianceContract;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Canonical salt → deployed mirror address
    mapping(bytes32 => address) public mirrors;

    /// @notice Mirror address → true if deployed by this factory
    mapping(address => bool) public isCanonicalMirror;

    /// @notice Mirror address → full metadata
    mapping(address => MirrorInfo) public mirrorInfoMap;

    /// @notice Deployment fee in wei (0 for MVP)
    uint256 public deploymentFee;

    /// @notice Fee recipient address
    address public treasury;

    /// @notice All deployed mirror addresses (for enumeration)
    address[] public allMirrors;

    // ─── Events ──────────────────────────────────────────────────────
    /// @notice Emitted when deployment fee is updated
    event DeploymentFeeUpdated(uint256 oldFee, uint256 newFee);

    /// @notice Emitted when treasury is updated
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    /// @notice Emitted when a mirror is paused/unpaused
    event MirrorActiveStatusChanged(address indexed mirror, bool active);

    // ─── Constructor ─────────────────────────────────────────────────
    /// @notice Initialize the canonical factory
    /// @param _attestationRegistry Address of the attestation registry
    /// @param _compliance Default compliance contract for new mirrors
    /// @param _treasury Fee recipient address
    /// @param _owner Contract owner
    constructor(
        address _attestationRegistry,
        address _compliance,
        address _treasury,
        address _owner
    ) Ownable(_owner) {
        attestationRegistry = IAttestationVerifier(_attestationRegistry);
        complianceContract = _compliance;
        treasury = _treasury;
    }

    // ─── External Functions ──────────────────────────────────────────

    /// @inheritdoc ICanonicalFactory
    function deployMirror(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external payable whenNotPaused returns (address mirror) {
        return _deployMirrorInternal(att, signatures, signerBitmap);
    }

    /// @inheritdoc ICanonicalFactory
    /// @notice Deploy a canonical mirror by submitting attestation + signatures directly.
    ///         Same security as CCIP path — attestation still requires threshold signatures
    ///         verified by AttestationRegistry. This just removes the CCIP transport delay.
    /// @dev    Anyone can call this. The attestation verification is the access control.
    ///         This is the recommended path for manual/interactive deployments.
    function deployMirrorDirect(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external payable whenNotPaused returns (address mirror) {
        // CRITICAL: Verify the attestation targets THIS chain
        if (att.targetChainId != block.chainid) {
            revert WrongTargetChain(att.targetChainId, block.chainid);
        }

        return _deployMirrorInternal(att, signatures, signerBitmap);
    }

    /// @inheritdoc ICanonicalFactory
    function computeMirrorAddress(AttestationLib.Attestation calldata att)
        external view returns (address)
    {
        bytes32 salt = AttestationLib.canonicalSalt(att);
        bytes32 initCodeHash = _computeInitCodeHash(att);
        return _computeCreate2Address(salt, initCodeHash);
    }

    /// @inheritdoc ICanonicalFactory
    function isCanonical(address mirror) external view returns (bool) {
        return isCanonicalMirror[mirror];
    }

    /// @notice Get metadata about a deployed mirror
    /// @param mirror The mirror token address
    /// @return info The mirror metadata
    function getMirrorInfo(address mirror) external view returns (MirrorInfo memory info) {
        if (!isCanonicalMirror[mirror]) revert MirrorNotFound(mirror);
        return mirrorInfoMap[mirror];
    }

    // ─── Enumeration Functions ───────────────────────────────────────

    /// @notice Get the total number of deployed mirrors
    /// @return The number of mirrors deployed by this factory
    function getMirrorCount() external view returns (uint256) {
        return allMirrors.length;
    }

    /// @notice Get all deployed mirror addresses
    /// @return Array of all mirror addresses
    function getAllMirrors() external view returns (address[] memory) {
        return allMirrors;
    }

    /// @notice Get a paginated list of mirror addresses
    /// @param offset Starting index
    /// @param limit Maximum number of mirrors to return
    /// @return result Array of mirror addresses
    function getMirrors(uint256 offset, uint256 limit) external view returns (address[] memory result) {
        uint256 total = allMirrors.length;
        if (offset >= total) {
            revert OutOfBounds(offset, total);
        }
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 count = end - offset;
        result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = allMirrors[offset + i];
        }
    }

    // ─── Mirror Management Functions ────────────────────────────────

    /// @notice Mint mirror tokens to a recipient (only callable by factory owner)
    /// @param mirror The canonical mirror token address
    /// @param to Recipient address
    /// @param amount Amount to mint (subject to mirror's mintCap)
    function mintMirror(address mirror, address to, uint256 amount) external onlyOwner {
        if (!isCanonicalMirror[mirror]) revert MirrorNotFound(mirror);
        XythumToken(mirror).mint(to, amount);
    }

    /// @notice Authorize or revoke an address as a minter on a mirror token
    /// @dev This allows the factory owner to grant minting rights to CCIP adapters, bridges, etc.
    /// @param mirror The canonical mirror token address
    /// @param minter The address to authorize or revoke
    /// @param authorized Whether the address should be authorized
    function setMirrorMinter(address mirror, address minter, bool authorized) external onlyOwner {
        if (!isCanonicalMirror[mirror]) revert MirrorNotFound(mirror);
        XythumToken(mirror).setAuthorizedMinter(minter, authorized);
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    /// @notice Set the deployment fee
    /// @param fee New fee in wei
    function setDeploymentFee(uint256 fee) external onlyOwner {
        uint256 oldFee = deploymentFee;
        deploymentFee = fee;
        emit DeploymentFeeUpdated(oldFee, fee);
    }

    /// @notice Set the treasury address
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) external onlyOwner {
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /// @notice Pause a specific mirror
    /// @param mirror The mirror to pause
    function pauseMirror(address mirror) external onlyOwner {
        if (!isCanonicalMirror[mirror]) revert MirrorNotFound(mirror);
        mirrorInfoMap[mirror].active = false;
        emit MirrorActiveStatusChanged(mirror, false);
    }

    /// @notice Pause the entire factory (emergency)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the factory
    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── Internal Functions ──────────────────────────────────────────

    /// @notice Shared internal logic for mirror deployment (used by both paths)
    /// @dev Both deployMirror (CCIP path) and deployMirrorDirect (instant path) delegate here.
    function _deployMirrorInternal(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) internal returns (address mirror) {
        // 1. Fee check
        if (msg.value < deploymentFee) {
            revert InsufficientFee(msg.value, deploymentFee);
        }

        // 2. Compute salt and check not already deployed
        bytes32 salt = AttestationLib.canonicalSalt(att);
        if (mirrors[salt] != address(0)) {
            revert MirrorAlreadyDeployed(mirrors[salt]);
        }

        // 3. Verify attestation (stores it in the registry)
        bytes32 attId = attestationRegistry.verifyAttestation(att, signatures, signerBitmap);

        // 4. Deploy via CREATE2
        mirror = _deployToken(salt, att);

        // 5. Register mirror
        _registerMirror(salt, mirror, att, attId);

        // 6. Collect fee
        if (msg.value > 0 && treasury != address(0)) {
            (bool sent,) = treasury.call{value: msg.value}("");
            require(sent, "Fee transfer failed");
        }

        // 7. Emit event
        emit MirrorDeployed(mirror, att.originContract, att.originChainId, att.targetChainId, salt);
    }

    /// @notice Deploy XythumToken via CREATE2
    function _deployToken(
        bytes32 salt,
        AttestationLib.Attestation calldata att
    ) internal returns (address mirror) {
        bytes memory creationCode = _getCreationCode(att);

        assembly {
            mirror := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
            if iszero(mirror) { revert(0, 0) }
        }
    }

    /// @notice Register a deployed mirror in all mappings and enumeration array
    function _registerMirror(
        bytes32 salt,
        address mirror,
        AttestationLib.Attestation calldata att,
        bytes32 attId
    ) internal {
        mirrors[salt] = mirror;
        isCanonicalMirror[mirror] = true;
        mirrorInfoMap[mirror] = MirrorInfo({
            originContract: att.originContract,
            originChainId: att.originChainId,
            targetChainId: att.targetChainId,
            attestationId: attId,
            deployedAt: block.timestamp,
            active: true
        });
        allMirrors.push(mirror);
    }

    /// @notice Build the full creation code (bytecode + constructor args)
    function _getCreationCode(AttestationLib.Attestation calldata att)
        internal view returns (bytes memory)
    {
        return abi.encodePacked(
            type(XythumToken).creationCode,
            abi.encode(
                _defaultName(),
                _defaultSymbol(),
                att.originContract,
                att.originChainId,
                complianceContract,
                att.lockedAmount
            )
        );
    }

    /// @notice Compute the init code hash for CREATE2 address prediction
    function _computeInitCodeHash(AttestationLib.Attestation calldata att)
        internal view returns (bytes32)
    {
        return keccak256(_getCreationCode(att));
    }

    /// @notice Compute a CREATE2 address
    function _computeCreate2Address(bytes32 salt, bytes32 initCodeHash)
        internal view returns (address)
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            initCodeHash
        )))));
    }

    /// @notice Default mirror token name
    /// @dev TODO(v2): derive name from attested metadata
    function _defaultName() internal pure returns (string memory) {
        return "Xythum Mirror";
    }

    /// @notice Default mirror token symbol
    /// @dev TODO(v2): derive symbol from attested metadata
    function _defaultSymbol() internal pure returns (string memory) {
        return "xRWA";
    }
}
