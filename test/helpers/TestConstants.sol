// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title TestConstants
/// @notice Shared constants for all test files
library TestConstants {
    // Chain IDs
    uint256 constant SOURCE_CHAIN_ID = 11155111; // Ethereum Sepolia
    uint256 constant TARGET_CHAIN_ID_1 = 421614; // Arbitrum Sepolia
    uint256 constant TARGET_CHAIN_ID_2 = 84532; // Base Sepolia

    // CCIP chain selectors (Sepolia)
    uint64 constant CCIP_ETH_SEPOLIA = 16015286601757825753;
    uint64 constant CCIP_ARB_SEPOLIA = 3478487238524512106;
    uint64 constant CCIP_BASE_SEPOLIA = 10344971235874465080;

    // Test addresses
    address constant DEPLOYER = address(0x1);
    address constant GOVERNANCE = address(0x2);
    address constant TREASURY = address(0x3);
    address constant ATTACKER = address(0xBAD);

    // Protocol defaults
    uint256 constant DEFAULT_THRESHOLD = 11;
    uint256 constant DEFAULT_SIGNER_COUNT = 21;
    uint256 constant MAX_STALENESS = 24 hours;
    uint256 constant RATE_LIMIT_PERIOD = 1 hours;

    // Fee defaults (basis points)
    uint256 constant DEPLOYMENT_FEE_BPS = 10; // 0.10%
    uint256 constant SWAP_FEE_BPS = 5; // 0.05%
    uint256 constant BPS_DENOMINATOR = 10000;
}
