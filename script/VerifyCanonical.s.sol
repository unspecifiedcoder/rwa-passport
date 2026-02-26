// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ICanonicalFactory } from "../src/interfaces/ICanonicalFactory.sol";

/// @title VerifyCanonical
/// @notice Verify that an address is a canonical Xythum mirror token.
///         Useful for integrators to validate tokens before interacting.
/// @dev Run: forge script script/VerifyCanonical.s.sol --rpc-url $RPC
///
///      Required env vars:
///        FACTORY          — CanonicalFactory address
///        TOKEN_TO_VERIFY  — Token address to check
contract VerifyCanonical is Script {
    function run() external view {
        address factoryAddr = vm.envAddress("FACTORY");
        address token = vm.envAddress("TOKEN_TO_VERIFY");

        ICanonicalFactory factory = ICanonicalFactory(factoryAddr);

        bool canonical = factory.isCanonical(token);

        console.log("=== Canonical Verification ===");
        console.log("Factory:", factoryAddr);
        console.log("Token:", token);
        console.log("Is Canonical:", canonical);

        if (canonical) {
            console.log("STATUS: VERIFIED - This is a canonical Xythum mirror token");
        } else {
            console.log("STATUS: NOT CANONICAL - This token was NOT deployed by the Xythum factory");
        }
    }
}
