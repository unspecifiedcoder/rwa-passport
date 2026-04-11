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

    /// @dev Struct to pass deployed addresses between phases without stack pressure
    struct Deployment {
        ProtocolTimelock timelock;
        ProtocolTreasury treasury;
        ProtocolToken token;
        XythumGovernor governor;
        StakingModule staking;
        FeeRouter feeRouter;
        ComplianceEngine compliance;
        EmergencyGuardian emergencyGuardian;
        OracleRouter oracle;
        MultiChainRegistry registry;
        LiquidityMining liquidityMining;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address insuranceFund = vm.envOr("INSURANCE_FUND", deployer);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("---");

        vm.startBroadcast(deployerKey);

        Deployment memory d;
        _deployGovernance(d, deployer);
        _deployDeFi(d, deployer, insuranceFund);
        _deployComplianceAndSecurity(d, deployer);
        _deployAccountability(d, deployer);
        _configureProtocol(d);

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

    // ─── Deployment Phase Helpers ────────────────────────────────────

    function _deployGovernance(Deployment memory d, address deployer) internal {
        // 1. Timelock Controller
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        d.timelock = new ProtocolTimelock(TIMELOCK_DELAY, proposers, executors, deployer);
        console.log("ProtocolTimelock:", address(d.timelock));

        // 2. Protocol Treasury
        d.treasury = new ProtocolTreasury(address(d.timelock), EPOCH_DURATION);
        console.log("ProtocolTreasury:", address(d.treasury));

        // 3. Protocol Token (XYT)
        d.token = new ProtocolToken(deployer, INITIAL_MINT, address(d.treasury));
        console.log("ProtocolToken (XYT):", address(d.token));

        // 4. Governor
        d.governor = new XythumGovernor(
            IVotes(address(d.token)), TimelockController(payable(address(d.timelock)))
        );
        console.log("XythumGovernor:", address(d.governor));

        // 5. Grant Governor proposer role on timelock
        d.timelock.grantRole(d.timelock.PROPOSER_ROLE(), address(d.governor));
        d.timelock.grantRole(d.timelock.CANCELLER_ROLE(), address(d.governor));
    }

    function _deployDeFi(Deployment memory d, address deployer, address insuranceFund) internal {
        // 6. Staking Module
        d.staking = new StakingModule(address(d.token), insuranceFund, deployer);
        d.token.setMinter(address(d.staking), true);
        d.token.setTransferLimitExempt(address(d.staking), true);
        console.log("StakingModule:", address(d.staking));

        // 7. Fee Router
        d.feeRouter = new FeeRouter(
            address(d.treasury), address(d.staking), insuranceFund, address(d.token), deployer
        );
        d.token.setTransferLimitExempt(address(d.feeRouter), true);
        console.log("FeeRouter:", address(d.feeRouter));
    }

    function _deployComplianceAndSecurity(Deployment memory d, address deployer) internal {
        // 8. Compliance Engine
        d.compliance = new ComplianceEngine(deployer);
        console.log("ComplianceEngine:", address(d.compliance));

        // 9. Emergency Guardian
        address[] memory guardians = new address[](1);
        guardians[0] = deployer;
        d.emergencyGuardian = new EmergencyGuardian(address(d.timelock), guardians);
        console.log("EmergencyGuardian:", address(d.emergencyGuardian));

        // 10. Oracle Router
        d.oracle = new OracleRouter(deployer, ORACLE_DEVIATION_BPS);
        console.log("OracleRouter:", address(d.oracle));

        // 11. Multi-Chain Registry
        d.registry = new MultiChainRegistry(deployer);
        console.log("MultiChainRegistry:", address(d.registry));
    }

    function _deployAccountability(Deployment memory d, address deployer) internal {
        // 12. Liquidity Mining (incentivizes LP providers with XYT emissions)
        d.liquidityMining = new LiquidityMining(address(d.token), deployer);
        d.token.setTransferLimitExempt(address(d.liquidityMining), true);
        console.log("LiquidityMining:", address(d.liquidityMining));

        // 13. Signer Slashing Court (optional, requires existing signer infrastructure)
        address signerRegistryAddr = vm.envOr("SIGNER_REGISTRY", address(0));
        address attestationRegistryAddr = vm.envOr("ATTESTATION_REGISTRY", address(0));
        if (signerRegistryAddr != address(0) && attestationRegistryAddr != address(0)) {
            _deploySlashingCourt(d, signerRegistryAddr, attestationRegistryAddr, deployer);
        } else {
            console.log(
                "SignerSlashingCourt skipped (set SIGNER_REGISTRY + ATTESTATION_REGISTRY env)"
            );
        }
    }

    function _deploySlashingCourt(
        Deployment memory d,
        address signerRegistryAddr,
        address attestationRegistryAddr,
        address deployer
    ) internal {
        bytes32 domainSep = AttestationRegistry(attestationRegistryAddr).DOMAIN_SEPARATOR();
        SignerSlashingCourt court =
            new SignerSlashingCourt(signerRegistryAddr, address(d.staking), domainSep, deployer);
        d.staking.setSlasher(address(court), true);
        console.log("SignerSlashingCourt:", address(court));

        SignerRegistry(signerRegistryAddr).setStakingModule(address(d.staking));
        SignerRegistry(signerRegistryAddr).setMinStake(MIN_SIGNER_STAKE);
        console.log("SignerRegistry wired: minStake =", MIN_SIGNER_STAKE / 1 ether, "XYT");
    }

    function _configureProtocol(Deployment memory d) internal {
        // Set anti-whale transfer limit
        d.token.setTransferLimit(TRANSFER_LIMIT);

        // Exempt governance contracts from transfer limit
        d.token.setTransferLimitExempt(address(d.treasury), true);
        d.token.setTransferLimitExempt(address(d.timelock), true);
        d.token.setTransferLimitExempt(address(d.governor), true);

        // Register chains in registry
        d.registry.addChain(43113, "Avalanche Fuji");
        d.registry.addChain(97, "BNB Testnet");
        d.registry.addChain(10143, "Monad Testnet");
        d.registry.addChain(11155111, "Ethereum Sepolia");
        d.registry.addChain(421614, "Arbitrum Sepolia");
        d.registry.addChain(84532, "Base Sepolia");
    }
}
