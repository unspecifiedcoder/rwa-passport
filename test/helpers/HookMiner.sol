// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title HookMiner
/// @notice Utility to find a CREATE2 salt that produces a hook address whose
///         lowest 14 bits EXACTLY match the required Uniswap V4 hook permissions.
/// @dev V4 validates that EVERY permission flag matches the address bits —
///      enabled flags must be 1 AND disabled flags must be 0.
library HookMiner {
    /// @notice Mask covering all 14 hook permission bits
    uint160 internal constant ALL_HOOK_MASK = uint160((1 << 14) - 1); // 0x3FFF

    /// @notice Find a salt producing a CREATE2 address with exact flag match
    /// @param deployer The address that will deploy the hook via CREATE2
    /// @param flags The EXACT required flag bits (lowest 14 bits of the hook address)
    /// @param creationCode The contract creation code (type(Hook).creationCode)
    /// @param constructorArgs ABI-encoded constructor arguments
    /// @return hookAddress The computed address with correct flags
    /// @return salt The salt to use for CREATE2
    function find(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(initCode);

        // Brute-force search for a valid salt
        for (uint256 i = 0; i < 500_000; i++) {
            salt = bytes32(i);
            hookAddress = _computeCreate2(deployer, salt, initCodeHash);

            // All 14 bits must match EXACTLY (set bits = 1, unset bits = 0)
            if (uint160(hookAddress) & ALL_HOOK_MASK == flags) {
                return (hookAddress, salt);
            }
        }
        revert("HookMiner: could not find valid salt");
    }

    /// @notice Compute a CREATE2 address
    function _computeCreate2(address deployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))
            )
        );
    }
}
