// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IOracleRouter
/// @author Xythum Protocol
/// @notice Interface for oracle-validated NAV pricing with Chainlink feeds
interface IOracleRouter {
    /// @notice Price data from an oracle source
    struct PriceData {
        uint256 price; // Price in 18 decimals
        uint256 timestamp; // When the price was fetched
        uint8 decimals; // Oracle decimals
        bool isValid; // Whether the price is within acceptable bounds
    }

    /// @notice Emitted when a price feed is registered
    event PriceFeedRegistered(address indexed asset, address indexed feed);

    /// @notice Emitted when a price is validated against NAV attestation
    event NAVValidated(
        address indexed asset, uint256 oraclePrice, uint256 attestedNAV, bool withinThreshold
    );

    /// @notice Emitted when price deviation threshold is updated
    event DeviationThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /// @notice Register a Chainlink price feed for an asset
    function registerPriceFeed(address asset, address priceFeed) external;

    /// @notice Get the latest validated price for an asset
    function getPrice(address asset) external view returns (PriceData memory);

    /// @notice Validate that oracle price matches attested NAV within threshold
    function validateNAV(address asset, uint256 attestedNAV) external returns (bool);

    /// @notice Get the TWAP for an asset over a period
    function getTWAP(address asset, uint256 period) external view returns (uint256);

    /// @notice Set the deviation threshold (in basis points)
    function setDeviationThreshold(uint256 thresholdBps) external;
}
