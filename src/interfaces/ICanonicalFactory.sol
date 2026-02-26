// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AttestationLib} from "../libraries/AttestationLib.sol";

/// @title ICanonicalFactory
/// @author Xythum Protocol
/// @notice Deploys canonical mirror tokens at deterministic CREATE2 addresses
interface ICanonicalFactory {
    /// @notice Emitted when a new canonical mirror is deployed
    /// @param mirror Address of the deployed mirror token
    /// @param originContract Address of the RWA on the source chain
    /// @param originChainId Source chain ID
    /// @param targetChainId Destination chain ID
    /// @param salt The CREATE2 salt used for deployment
    event MirrorDeployed(
        address indexed mirror,
        address indexed originContract,
        uint256 originChainId,
        uint256 targetChainId,
        bytes32 salt
    );

    /// @notice Deploy a canonical mirror token for an attested RWA (CCIP path)
    /// @param att The verified attestation
    /// @param signatures Packed ECDSA signatures
    /// @param signerBitmap Bitmap of signing signers
    /// @return mirror Address of the deployed mirror token
    function deployMirror(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external payable returns (address mirror);

    /// @notice Deploy a canonical mirror by submitting attestation + signatures directly.
    ///         Same security as CCIP path — attestation still requires threshold signatures
    ///         verified by AttestationRegistry. This just removes the CCIP transport delay.
    /// @param att The attestation data (must reference this chain as targetChainId)
    /// @param signatures Packed ECDSA signatures from threshold signers
    /// @param signerBitmap Bitmap indicating which signers signed
    /// @return mirror Address of the deployed mirror token
    function deployMirrorDirect(
        AttestationLib.Attestation calldata att,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external payable returns (address mirror);

    /// @notice Compute the deterministic address where a mirror would be deployed
    /// @param att The attestation data
    /// @return The predicted mirror address
    function computeMirrorAddress(AttestationLib.Attestation calldata att)
        external view returns (address);

    /// @notice Check if an address is a canonical Xythum mirror
    /// @param mirror Address to check
    /// @return True if deployed by this factory with valid attestation
    function isCanonical(address mirror) external view returns (bool);

    /// @notice Get the total number of deployed mirrors
    /// @return The number of mirrors deployed by this factory
    function getMirrorCount() external view returns (uint256);

    /// @notice Get all deployed mirror addresses
    /// @return Array of all mirror addresses
    function getAllMirrors() external view returns (address[] memory);

    /// @notice Get a paginated list of mirror addresses
    /// @param offset Starting index
    /// @param limit Maximum number of mirrors to return
    /// @return result Array of mirror addresses
    function getMirrors(uint256 offset, uint256 limit) external view returns (address[] memory result);
}
