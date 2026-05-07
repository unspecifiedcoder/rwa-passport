// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { ReceiptLib } from "../../src/libraries/ReceiptLib.sol";

/// @title ReceiptHelper
/// @notice Test helper to construct and sign LockReceipt / UnlockReceipt
///         payloads using the same in-memory signer key set as AttestationHelper.
/// @dev Designed to be combined with AttestationHelper's `signerKeys` array
///      via inheritance OR composition — the simplest approach is to give it
///      its own keys via `generateSigners`. Indices match the bitmap layout.
contract ReceiptHelper is Test {
    /// @notice Private keys for test signers (deterministic)
    uint256[] public signerKeys;
    /// @notice Corresponding addresses
    address[] public signerAddresses;

    function generateSigners(uint256 count) public {
        for (uint256 i = 0; i < count; i++) {
            uint256 pk = 100 + i; // matches AttestationHelper convention
            signerKeys.push(pk);
            signerAddresses.push(vm.addr(pk));
        }
    }

    function getSignerAddress(uint256 index) external view returns (address) {
        return signerAddresses[index];
    }

    function signLockReceipt(
        ReceiptLib.LockReceipt memory r,
        bytes32 domainSeparator,
        uint256[] memory indices
    ) external view returns (bytes memory signatures, uint256 bitmap) {
        uint256[] memory sorted = _sortIndices(indices);
        bytes32 digest = ReceiptLib.toTypedDataHash(r, domainSeparator);

        bytes memory sigs;
        for (uint256 i = 0; i < sorted.length; i++) {
            uint256 idx = sorted[i];
            bitmap |= (1 << idx);
            (uint8 v, bytes32 r_, bytes32 s_) = vm.sign(signerKeys[idx], digest);
            sigs = abi.encodePacked(sigs, r_, s_, v);
        }
        return (sigs, bitmap);
    }

    function signUnlockReceipt(
        ReceiptLib.UnlockReceipt memory r,
        bytes32 domainSeparator,
        uint256[] memory indices
    ) external view returns (bytes memory signatures, uint256 bitmap) {
        uint256[] memory sorted = _sortIndices(indices);
        bytes32 digest = ReceiptLib.toTypedDataHash(r, domainSeparator);

        bytes memory sigs;
        for (uint256 i = 0; i < sorted.length; i++) {
            uint256 idx = sorted[i];
            bitmap |= (1 << idx);
            (uint8 v, bytes32 r_, bytes32 s_) = vm.sign(signerKeys[idx], digest);
            sigs = abi.encodePacked(sigs, r_, s_, v);
        }
        return (sigs, bitmap);
    }

    function _sortIndices(uint256[] memory arr) internal pure returns (uint256[] memory) {
        uint256[] memory sorted = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) sorted[i] = arr[i];
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
