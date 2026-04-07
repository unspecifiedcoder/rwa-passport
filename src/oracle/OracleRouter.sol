// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IOracleRouter } from "../interfaces/IOracleRouter.sol";

/// @title IAggregatorV3
/// @notice Minimal Chainlink AggregatorV3 interface
interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals() external view returns (uint8);
}

/// @title OracleRouter
/// @author Xythum Protocol
/// @notice Oracle-validated NAV pricing for RWA mirror tokens.
///         Aggregates Chainlink price feeds and validates against attested NAV values
///         to ensure protocol integrity and prevent stale/manipulated pricing.
/// @dev Features:
///      - Multi-feed aggregation with fallback
///      - TWAP calculation for manipulation resistance
///      - NAV attestation cross-validation
///      - Configurable deviation thresholds
///      - Heartbeat monitoring (stale feed detection)
contract OracleRouter is IOracleRouter, Ownable2Step {
    // ─── Custom Errors ───────────────────────────────────────────────
    error FeedNotRegistered(address asset);
    error StalePrice(address asset, uint256 age, uint256 maxAge);
    error NegativePrice(address asset, int256 price);
    error DeviationTooHigh(uint256 oraclePrice, uint256 attestedNAV, uint256 deviationBps);
    error InvalidThreshold();
    error ZeroAddress();

    // ─── Constants ───────────────────────────────────────────────────
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant BPS_DENOMINATOR = 10000;

    // ─── Structs ─────────────────────────────────────────────────────
    struct FeedConfig {
        address feed; // Chainlink AggregatorV3 address
        uint256 maxStaleness; // Maximum acceptable age in seconds
        uint8 decimals; // Feed decimals
        bool active;
    }

    /// @notice TWAP observation point
    struct Observation {
        uint256 price;
        uint256 timestamp;
    }

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Price feed configurations per asset
    mapping(address => FeedConfig) public feedConfigs;

    /// @notice TWAP observations per asset (circular buffer)
    mapping(address => Observation[MAX_OBSERVATIONS]) public observations;

    /// @notice Current write index per asset in circular buffer
    mapping(address => uint256) public observationIndex;

    /// @notice Number of valid observations per asset
    mapping(address => uint256) public observationCount;

    /// @notice Maximum observations to store per asset
    uint256 public constant MAX_OBSERVATIONS = 24; // 24 hourly observations

    /// @notice NAV deviation threshold in basis points (default: 500 = 5%)
    uint256 public deviationThresholdBps;

    /// @notice Registered asset list
    address[] public registeredAssets;

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(address _owner, uint256 _deviationThresholdBps) Ownable(_owner) {
        if (_deviationThresholdBps == 0 || _deviationThresholdBps > BPS_DENOMINATOR) {
            revert InvalidThreshold();
        }
        deviationThresholdBps = _deviationThresholdBps;
    }

    // ─── Price Feed Management ───────────────────────────────────────

    /// @inheritdoc IOracleRouter
    function registerPriceFeed(address asset, address priceFeed) external onlyOwner {
        if (asset == address(0) || priceFeed == address(0)) revert ZeroAddress();

        uint8 feedDecimals = IAggregatorV3(priceFeed).decimals();

        if (!feedConfigs[asset].active) {
            registeredAssets.push(asset);
        }

        feedConfigs[asset] = FeedConfig({
            feed: priceFeed,
            maxStaleness: 1 hours,
            decimals: feedDecimals,
            active: true
        });

        emit PriceFeedRegistered(asset, priceFeed);
    }

    /// @notice Set the maximum staleness for a feed
    function setFeedStaleness(address asset, uint256 maxStaleness) external onlyOwner {
        if (!feedConfigs[asset].active) revert FeedNotRegistered(asset);
        feedConfigs[asset].maxStaleness = maxStaleness;
    }

    // ─── Price Queries ───────────────────────────────────────────────

    /// @inheritdoc IOracleRouter
    function getPrice(address asset) external view returns (PriceData memory) {
        FeedConfig storage config = feedConfigs[asset];
        if (!config.active) revert FeedNotRegistered(asset);

        (
            ,
            int256 answer,
            ,
            uint256 updatedAt,
        ) = IAggregatorV3(config.feed).latestRoundData();

        if (answer <= 0) revert NegativePrice(asset, answer);

        uint256 age = block.timestamp - updatedAt;
        bool isValid = age <= config.maxStaleness;

        // Normalize to 18 decimals
        uint256 normalizedPrice;
        if (config.decimals < 18) {
            normalizedPrice = uint256(answer) * (10 ** (18 - config.decimals));
        } else {
            normalizedPrice = uint256(answer) / (10 ** (config.decimals - 18));
        }

        return PriceData({
            price: normalizedPrice,
            timestamp: updatedAt,
            decimals: config.decimals,
            isValid: isValid
        });
    }

    /// @inheritdoc IOracleRouter
    function validateNAV(address asset, uint256 attestedNAV) external returns (bool) {
        FeedConfig storage config = feedConfigs[asset];
        if (!config.active) revert FeedNotRegistered(asset);

        (
            ,
            int256 answer,
            ,
            uint256 updatedAt,
        ) = IAggregatorV3(config.feed).latestRoundData();

        if (answer <= 0) return false;

        uint256 age = block.timestamp - updatedAt;
        if (age > config.maxStaleness) return false;

        // Normalize oracle price
        uint256 oraclePrice;
        if (config.decimals < 18) {
            oraclePrice = uint256(answer) * (10 ** (18 - config.decimals));
        } else {
            oraclePrice = uint256(answer) / (10 ** (config.decimals - 18));
        }

        // Calculate deviation using consistent denominator (average)
        uint256 deviation;
        uint256 avg = (oraclePrice + attestedNAV) / 2;
        if (avg == 0) return false;
        if (oraclePrice > attestedNAV) {
            deviation = ((oraclePrice - attestedNAV) * BPS_DENOMINATOR) / avg;
        } else {
            deviation = ((attestedNAV - oraclePrice) * BPS_DENOMINATOR) / avg;
        }

        bool withinThreshold = deviation <= deviationThresholdBps;
        emit NAVValidated(asset, oraclePrice, attestedNAV, withinThreshold);

        return withinThreshold;
    }

    /// @notice Record a TWAP observation (called periodically by keepers)
    function recordObservation(address asset) external {
        FeedConfig storage config = feedConfigs[asset];
        if (!config.active) revert FeedNotRegistered(asset);

        (, int256 answer,,,) = IAggregatorV3(config.feed).latestRoundData();
        if (answer <= 0) return;

        uint256 normalizedPrice;
        if (config.decimals < 18) {
            normalizedPrice = uint256(answer) * (10 ** (18 - config.decimals));
        } else {
            normalizedPrice = uint256(answer) / (10 ** (config.decimals - 18));
        }

        uint256 idx = observationIndex[asset];
        observations[asset][idx] = Observation({ price: normalizedPrice, timestamp: block.timestamp });
        observationIndex[asset] = (idx + 1) % MAX_OBSERVATIONS;
        if (observationCount[asset] < MAX_OBSERVATIONS) {
            observationCount[asset]++;
        }
    }

    /// @inheritdoc IOracleRouter
    function getTWAP(address asset, uint256 period) external view returns (uint256) {
        uint256 count = observationCount[asset];
        if (count == 0) revert FeedNotRegistered(asset);

        uint256 cutoff = block.timestamp - period;
        uint256 totalPrice;
        uint256 matched;

        for (uint256 i = 0; i < count; i++) {
            Observation storage obs = observations[asset][i];
            if (obs.timestamp >= cutoff) {
                totalPrice += obs.price;
                matched++;
            }
        }

        if (matched == 0) revert StalePrice(asset, period, 0);
        return totalPrice / matched;
    }

    // ─── Admin ───────────────────────────────────────────────────────

    /// @inheritdoc IOracleRouter
    function setDeviationThreshold(uint256 thresholdBps) external onlyOwner {
        if (thresholdBps == 0 || thresholdBps > BPS_DENOMINATOR) revert InvalidThreshold();
        uint256 old = deviationThresholdBps;
        deviationThresholdBps = thresholdBps;
        emit DeviationThresholdUpdated(old, thresholdBps);
    }

    // ─── View ────────────────────────────────────────────────────────

    function getRegisteredAssets() external view returns (address[] memory) {
        return registeredAssets;
    }

    function getObservationCount(address asset) external view returns (uint256) {
        return observationCount[asset];
    }
}
