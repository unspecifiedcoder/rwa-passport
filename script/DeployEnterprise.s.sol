// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { ProtocolToken } from "../src/governance/ProtocolToken.sol";
import { ProtocolTimelock } from "../src/governance/ProtocolTimelock.sol";
import { XythumGovernor } from "../src/governance/XythumGovernor.sol";
import { ProtocolTreasury } from "../src/governance/ProtocolTreasury.sol";
import { StakingModule } from "../src/staking/StakingModule.sol";
import { LiquidityMining } from "../src/staking/LiquidityMining.sol";
import { FeeRouter } from "../src/finance/FeeRouter.sol";
import { ComplianceEngine } from "../src/compliance/ComplianceEngine.sol";
import { EmergencyGuardian } from "../src/security/EmergencyGuardian.sol";
import { SignerSlashingCourt } from "../src/security/SignerSlashingCourt.sol";
import { OracleRouter } from "../src/oracle/OracleRouter.sol";
import { MultiChainRegistry } from "../src/registry/MultiChainRegistry.sol";
import { SignerRegistry } from "../src/core/SignerRegistry.sol";
import { AttestationRegistry } from "../src/core/AttestationRegistry.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title DeployEnterprise
/// @author Xythum Protocol
/// @notice Full enterprise deployment script for the Xythum governance and DeFi layer.
///         Deploys and wires: Token -> Timelock -> Governor -> Treasury -> Staking ->
///         FeeRouter -> Compliance -> Emergency -> Oracle -> Registry
/// @dev Run with:
///      forge script script/DeployEnterprise.s.sol:DeployEnterprise \
///        --rpc-url $RPC_URL --broadcast -vvvv
contract DeployEnterprise is Script {
    // ─── Configuration ───────────────────────────────────────────────
    uint256 constant INITIAL_MINT = 200_000_000 ether; // 200M to treasury
    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant EPOCH_DURATION = 30 days;
    uint256 constant ORACLE_DEVIATION_BPS = 500; // 5%
    uint256 constant TRANSFER_LIMIT = 10_000_000 ether; // 10M anti-whale
    uint256 constant MIN_SIGNER_STAKE = 100_000 ether; // 100K XYT minimum to be a signer

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address insuranceFund = vm.envOr("INSURANCE_FUND", deployer);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("---");

        vm.startBroadcast(deployerKey);

        // ── Phase 1: Governance Infrastructure ───────────────────────

        // 1. Timelock Controller
        address[] memory proposers = new address[](1);
        proposers[0] = deployer; // Temporary, will be updated to Governor
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Open execution (anyone can execute after delay)

        ProtocolTimelock timelock =
            new ProtocolTimelock(TIMELOCK_DELAY, proposers, executors, deployer);
        console.log("ProtocolTimelock:", address(timelock));

        // 2. Protocol Treasury
        ProtocolTreasury treasury = new ProtocolTreasury(address(timelock), EPOCH_DURATION);
        console.log("ProtocolTreasury:", address(treasury));

        // 3. Protocol Token (XYT)
        ProtocolToken token = new ProtocolToken(deployer, INITIAL_MINT, address(treasury));
        console.log("ProtocolToken (XYT):", address(token));

        // 4. Governor
        XythumGovernor governor = new XythumGovernor(
            IVotes(address(token)), TimelockController(payable(address(timelock)))
        );
        console.log("XythumGovernor:", address(governor));

        // 5. Grant Governor proposer role on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // ── Phase 2: DeFi Infrastructure ─────────────────────────────

        // 6. Staking Module
        StakingModule staking = new StakingModule(address(token), insuranceFund, deployer);
        token.setMinter(address(staking), true);
        token.setTransferLimitExempt(address(staking), true);
        console.log("StakingModule:", address(staking));

        // 7. Fee Router
        FeeRouter feeRouter = new FeeRouter(
            address(treasury), address(staking), insuranceFund, address(token), deployer
        );
        token.setTransferLimitExempt(address(feeRouter), true);
        console.log("FeeRouter:", address(feeRouter));

        // ── Phase 3: Compliance & Security ───────────────────────────

        // 8. Compliance Engine
        ComplianceEngine compliance = new ComplianceEngine(deployer);
        console.log("ComplianceEngine:", address(compliance));

        // 9. Emergency Guardian
        address[] memory guardians = new address[](1);
        guardians[0] = deployer;
        EmergencyGuardian emergencyGuardian = new EmergencyGuardian(address(timelock), guardians);
        console.log("EmergencyGuardian:", address(emergencyGuardian));

        // 10. Oracle Router
        OracleRouter oracle = new OracleRouter(deployer, ORACLE_DEVIATION_BPS);
        console.log("OracleRouter:", address(oracle));

        // 11. Multi-Chain Registry
        MultiChainRegistry registry = new MultiChainRegistry(deployer);
        console.log("MultiChainRegistry:", address(registry));

        // ── Phase 4: Accountability Layer (NEW) ──────────────────────

        // 12. Liquidity Mining (incentivizes LP providers with XYT emissions)
        LiquidityMining liquidityMining = new LiquidityMining(address(token), deployer);
        token.setTransferLimitExempt(address(liquidityMining), true);
        console.log("LiquidityMining:", address(liquidityMining));

        // 13. Signer Slashing Court
        //     NOTE: Requires an existing SignerRegistry + AttestationRegistry address.
        //     On a fresh deployment these would be read from env vars; here we skip
        //     wiring unless SIGNER_REGISTRY env var is set.
        address signerRegistryAddr = vm.envOr("SIGNER_REGISTRY", address(0));
        address attestationRegistryAddr = vm.envOr("ATTESTATION_REGISTRY", address(0));
        if (signerRegistryAddr != address(0) && attestationRegistryAddr != address(0)) {
            bytes32 domainSep = AttestationRegistry(attestationRegistryAddr).DOMAIN_SEPARATOR();
            SignerSlashingCourt court = new SignerSlashingCourt(
                signerRegistryAddr, address(staking), domainSep, deployer
            );
            staking.setSlasher(address(court), true);
            console.log("SignerSlashingCourt:", address(court));

            // Wire the StakingModule into SignerRegistry + set minimum stake
            SignerRegistry(signerRegistryAddr).setStakingModule(address(staking));
            SignerRegistry(signerRegistryAddr).setMinStake(MIN_SIGNER_STAKE);
            console.log("SignerRegistry wired: minStake =", MIN_SIGNER_STAKE / 1 ether, "XYT");
        } else {
            console.log(
                "SignerSlashingCourt skipped (set SIGNER_REGISTRY + ATTESTATION_REGISTRY env)"
            );
        }

        // ── Phase 5: Wire & Configure ────────────────────────────────

        // Set anti-whale transfer limit
        token.setTransferLimit(TRANSFER_LIMIT);

        // Exempt governance contracts from transfer limit
        token.setTransferLimitExempt(address(treasury), true);
        token.setTransferLimitExempt(address(timelock), true);
        token.setTransferLimitExempt(address(governor), true);

        // Register chains in registry
        registry.addChain(43113, "Avalanche Fuji");
        registry.addChain(97, "BNB Testnet");
        registry.addChain(10143, "Monad Testnet");
        registry.addChain(11155111, "Ethereum Sepolia");
        registry.addChain(421614, "Arbitrum Sepolia");
        registry.addChain(84532, "Base Sepolia");

        // Register emergency guardian pausable contracts
        // (these would be existing core contracts)

        vm.stopBroadcast();

        // ── Summary ──────────────────────────────────────────────────
        console.log("---");
        console.log("=== ENTERPRISE DEPLOYMENT COMPLETE ===");
        console.log("Initial XYT supply:", INITIAL_MINT / 1 ether, "XYT");
        console.log("Transfer limit:", TRANSFER_LIMIT / 1 ether, "XYT");
        console.log("Timelock delay:", TIMELOCK_DELAY / 1 hours, "hours");
        console.log("Min signer stake:", MIN_SIGNER_STAKE / 1 ether, "XYT");
        console.log("---");
        console.log("NEXT STEP: Run Decentralize.s.sol to transfer ownership to timelock.");
        console.log("  forge script script/Decentralize.s.sol:Decentralize \\");
        console.log("    --rpc-url $RPC_URL --broadcast -vvvv");
    }
}
