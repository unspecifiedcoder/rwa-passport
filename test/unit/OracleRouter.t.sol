// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { OracleRouter, IAggregatorV3 } from "../../src/oracle/OracleRouter.sol";

/// @title Mock Chainlink Aggregator
contract MockAggregator is IAggregatorV3 {
    int256 public price;
    uint8 public override decimals;
    uint256 public updatedAt;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals = _decimals;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, price, block.timestamp, updatedAt, 1);
    }
}

    /// @title OracleRouter Unit Tests
    contract OracleRouterTest is Test {
        OracleRouter public oracle;
        MockAggregator public mockFeed;

        address public owner = makeAddr("owner");
        address public asset = makeAddr("asset");

        function setUp() public {
            // Warp to a reasonable block timestamp to avoid underflow on
            // stale-price tests that compute block.timestamp - 2 hours
            vm.warp(100_000);

            vm.prank(owner);
            oracle = new OracleRouter(owner, 500); // 5% deviation threshold

            mockFeed = new MockAggregator(100_000_000, 8); // $1.00 in 8 decimals
        }

        // ─── Price Feed Registration ─────────────────────────────────────

        function test_registerPriceFeed() public {
            vm.prank(owner);
            oracle.registerPriceFeed(asset, address(mockFeed));

            (address feed,,, bool active) = oracle.feedConfigs(asset);
            assertEq(feed, address(mockFeed));
            assertTrue(active);
        }

        function test_registerFeedZeroAddressReverts() public {
            vm.prank(owner);
            vm.expectRevert(OracleRouter.ZeroAddress.selector);
            oracle.registerPriceFeed(address(0), address(mockFeed));
        }

        // ─── Price Queries ───────────────────────────────────────────────

        function test_getPrice() public {
            vm.prank(owner);
            oracle.registerPriceFeed(asset, address(mockFeed));

            OracleRouter.PriceData memory data = oracle.getPrice(asset);

            // $1.00 normalized to 18 decimals = 1e18
            assertEq(data.price, 1e18);
            assertTrue(data.isValid);
            assertEq(data.decimals, 8);
        }

        function test_getPriceStaleInvalid() public {
            vm.prank(owner);
            oracle.registerPriceFeed(asset, address(mockFeed));

            // Set feed to be stale
            mockFeed.setUpdatedAt(block.timestamp - 2 hours);

            OracleRouter.PriceData memory data = oracle.getPrice(asset);
            assertFalse(data.isValid);
        }

        function test_getUnregisteredFeedReverts() public {
            vm.expectRevert(abi.encodeWithSelector(OracleRouter.FeedNotRegistered.selector, asset));
            oracle.getPrice(asset);
        }

        // ─── NAV Validation ──────────────────────────────────────────────

        function test_validateNAVWithinThreshold() public {
            vm.prank(owner);
            oracle.registerPriceFeed(asset, address(mockFeed));

            // Oracle says $1.00, attested NAV is $1.02 (~2% deviation, within 5%)
            bool valid = oracle.validateNAV(asset, 1.02e18);
            assertTrue(valid);
        }

        function test_validateNAVExceedsThreshold() public {
            vm.prank(owner);
            oracle.registerPriceFeed(asset, address(mockFeed));

            // Oracle says $1.00, attested NAV is $1.10 (~10% deviation, exceeds 5%)
            bool valid = oracle.validateNAV(asset, 1.1e18);
            assertFalse(valid);
        }

        // ─── TWAP ────────────────────────────────────────────────────────

        function test_recordAndGetTWAP() public {
            vm.prank(owner);
            oracle.registerPriceFeed(asset, address(mockFeed));

            // Record observations at different prices
            mockFeed.setPrice(100_000_000); // $1.00
            oracle.recordObservation(asset);

            vm.warp(block.timestamp + 1 hours);
            mockFeed.setPrice(200_000_000); // $2.00
            oracle.recordObservation(asset);

            vm.warp(block.timestamp + 1 hours);
            mockFeed.setPrice(150_000_000); // $1.50
            oracle.recordObservation(asset);

            // TWAP over 3 hours should be average of all 3
            uint256 twap = oracle.getTWAP(asset, 3 hours);
            assertEq(twap, 1.5e18); // ($1 + $2 + $1.5) / 3
        }

        // ─── Admin ───────────────────────────────────────────────────────

        function test_setDeviationThreshold() public {
            vm.prank(owner);
            oracle.setDeviationThreshold(1000); // 10%

            assertEq(oracle.deviationThresholdBps(), 1000);
        }

        function test_invalidThresholdReverts() public {
            vm.prank(owner);
            vm.expectRevert(OracleRouter.InvalidThreshold.selector);
            oracle.setDeviationThreshold(0);
        }
    }
