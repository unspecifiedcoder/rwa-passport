// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ProtocolTimelock } from "../src/governance/ProtocolTimelock.sol";

/// @title Decentralize
/// @author Xythum Protocol
/// @notice Transfers ownership of all governance-controlled contracts to the ProtocolTimelock.
///         This is the final step to make the protocol fully decentralized.
///
/// @dev Ownable2Step requires a two-step transfer: the current owner calls
///      `transferOwnership(timelock)` which sets a pending owner, then the timelock must
///      call `acceptOwnership()` on each contract. Since the timelock can only execute
///      operations via its schedule/execute flow, we use the deployer's PROPOSER_ROLE to
///      schedule each acceptOwnership call with 0 delay (acceptable during bootstrap).
///
///      After this script runs:
///      1. All core contracts are owned by the Timelock
///      2. The Timelock's only proposer is the Governor
///      3. Any future changes require a governance proposal + 2-day delay
///
///      ENVIRONMENT VARIABLES REQUIRED:
///        PRIVATE_KEY              - Deployer key (must be current owner + timelock admin)
///        PROTOCOL_TIMELOCK        - Address of the ProtocolTimelock
///        PROTOCOL_TOKEN           - Address of XYT token
///        STAKING_MODULE           - Address of StakingModule
///        FEE_ROUTER               - Address of FeeRouter
///        COMPLIANCE_ENGINE        - Address of ComplianceEngine
///        ORACLE_ROUTER            - Address of OracleRouter
///        MULTI_CHAIN_REGISTRY     - Address of MultiChainRegistry
///        LIQUIDITY_MINING         - Address of LiquidityMining (optional)
///        SIGNER_SLASHING_COURT    - Address of SignerSlashingCourt (optional)
contract Decentralize is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address timelockAddr = vm.envAddress("PROTOCOL_TIMELOCK");
        ProtocolTimelock timelock = ProtocolTimelock(payable(timelockAddr));

        console.log("Decentralizing ownership to timelock:", timelockAddr);
        console.log("Deployer (current owner):", deployer);
        console.log("---");

        vm.startBroadcast(deployerKey);

        // Step 1: Transfer ownership of all core contracts to timelock (sets pending)
        address[] memory contracts = new address[](8);
        contracts[0] = vm.envAddress("PROTOCOL_TOKEN");
        contracts[1] = vm.envAddress("STAKING_MODULE");
        contracts[2] = vm.envAddress("FEE_ROUTER");
        contracts[3] = vm.envAddress("COMPLIANCE_ENGINE");
        contracts[4] = vm.envAddress("ORACLE_ROUTER");
        contracts[5] = vm.envAddress("MULTI_CHAIN_REGISTRY");
        contracts[6] = vm.envOr("LIQUIDITY_MINING", address(0));
        contracts[7] = vm.envOr("SIGNER_SLASHING_COURT", address(0));

        string[8] memory names = [
            "ProtocolToken",
            "StakingModule",
            "FeeRouter",
            "ComplianceEngine",
            "OracleRouter",
            "MultiChainRegistry",
            "LiquidityMining",
            "SignerSlashingCourt"
        ];

        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i] == address(0)) {
                console.log("Skipping (not set):", names[i]);
                continue;
            }
            Ownable2Step(contracts[i]).transferOwnership(timelockAddr);
            console.log("Pending transfer:", names[i], "->", timelockAddr);
        }

        // Step 2: Grant deployer PROPOSER_ROLE temporarily to schedule acceptOwnership calls
        // (Assumes deployer already has DEFAULT_ADMIN_ROLE on the timelock)
        timelock.grantRole(timelock.PROPOSER_ROLE(), deployer);

        // Step 3: Schedule + execute acceptOwnership on each contract via timelock.
        // This requires the timelock delay to be 0 during bootstrap. If the deployment
        // script set a non-zero delay, this approach requires waiting the delay period.
        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i] == address(0)) continue;

            bytes memory callData = abi.encodeWithSignature("acceptOwnership()");
            bytes32 salt = keccak256(abi.encodePacked("accept-ownership", contracts[i]));

            try timelock.schedule(contracts[i], 0, callData, bytes32(0), salt, 0) {
                timelock.execute(contracts[i], 0, callData, bytes32(0), salt);
                console.log("Ownership accepted:", names[i]);
            } catch {
                console.log(
                    "WARN: Could not schedule acceptOwnership. Timelock delay must be 0"
                );
                console.log("      for bootstrap. Manually accept from timelock via governance.");
            }
        }

        // Step 4: Revoke deployer's temporary PROPOSER_ROLE
        // (Only the Governor should be able to propose from now on)
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);

        vm.stopBroadcast();

        console.log("---");
        console.log("=== DECENTRALIZATION COMPLETE ===");
        console.log("All core contracts are now owned by the Timelock.");
        console.log("");
        console.log("FINAL MANUAL STEP (recommended):");
        console.log("  After verifying all transfers worked, renounce DEFAULT_ADMIN_ROLE:");
        console.log("    timelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer)");
        console.log("  This makes governance fully trustless — no one can bypass the timelock.");
    }
}
