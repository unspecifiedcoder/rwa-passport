// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";

/// @title AttestationHelper
/// @notice Helper contract that generates valid attestations and signatures for tests.
///         Note: Signer registration must be done by the registry owner (the test contract).
///         This helper only stores keys/addresses and provides signing utilities.
contract AttestationHelper is Test {
    /// @notice Private keys for test signers
    uint256[] public signerKeys;

    /// @notice Corresponding addresses for test signers
    address[] public signerAddresses;

    /// @notice Generate signer keys and addresses (does NOT register them)
    /// @param count Number of signers to create
    function generateSigners(uint256 count) public {
        for (uint256 i = 0; i < count; i++) {
            // Use deterministic private keys starting from 100
            uint256 pk = 100 + i;
            address signer = vm.addr(pk);
            signerKeys.push(pk);
            signerAddresses.push(signer);
        }
    }

    /// @notice Get a signer address by index
    function getSignerAddress(uint256 index) public view returns (address) {
        return signerAddresses[index];
    }

    /// @notice Get the number of generated signers
    function getSignerCount() public view returns (uint256) {
        return signerAddresses.length;
    }

    /// @notice Build a test attestation with default values
    /// @param originContract Origin RWA contract address
    /// @param originChainId Source chain ID
    /// @param targetChainId Destination chain ID
    /// @param nonce Attestation nonce
    /// @return att The constructed attestation
    function buildAttestation(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 nonce
    ) public view returns (AttestationLib.Attestation memory att) {
        att = AttestationLib.Attestation({
            originContract: originContract,
            originChainId: originChainId,
            targetChainId: targetChainId,
            navRoot: keccak256(abi.encodePacked("nav", nonce)),
            complianceRoot: keccak256(abi.encodePacked("compliance", nonce)),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp,
            nonce: nonce
        });
    }

    /// @notice Sign an attestation with specific signer indices
    /// @param att The attestation to sign
    /// @param domainSeparator The EIP-712 domain separator
    /// @param signerIndices Array of indices into the signerKeys array to sign with
    /// @return signatures Packed 65-byte signatures in order of signer index
    /// @return bitmap Bitmap of signing signers
    function signAttestation(
        AttestationLib.Attestation memory att,
        bytes32 domainSeparator,
        uint256[] memory signerIndices
    ) public view returns (bytes memory signatures, uint256 bitmap) {
        // Sort indices for bitmap ordering (signatures must be in order of bit index)
        uint256[] memory sorted = _sortIndices(signerIndices);

        bytes32 digest = AttestationLib.toTypedDataHash(att, domainSeparator);

        bytes memory sigs;
        for (uint256 i = 0; i < sorted.length; i++) {
            uint256 idx = sorted[i];
            bitmap |= (1 << idx);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKeys[idx], digest);
            sigs = abi.encodePacked(sigs, r, s, v);
        }

        return (sigs, bitmap);
    }

    /// @notice Simple insertion sort for small arrays
    function _sortIndices(uint256[] memory arr) internal pure returns (uint256[] memory) {
        uint256[] memory sorted = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            sorted[i] = arr[i];
        }

        for (uint256 i = 1; i < sorted.length; i++) {
            uint256 key = sorted[i];
            uint256 j = i;
            while (j > 0 && sorted[j - 1] > key) {
                sorted[j] = sorted[j - 1];
                j--;
            }
            sorted[j] = key;
        }
        return sorted;
    }
}
