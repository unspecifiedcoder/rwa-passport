// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";
import { ProtocolTimelock } from "../../src/governance/ProtocolTimelock.sol";
import { ProtocolTreasury } from "../../src/governance/ProtocolTreasury.sol";
import { StakingModule } from "../../src/staking/StakingModule.sol";
import { FeeRouter } from "../../src/finance/FeeRouter.sol";
import { ComplianceEngine } from "../../src/compliance/ComplianceEngine.sol";
import { EmergencyGuardian } from "../../src/security/EmergencyGuardian.sol";
import { MultiChainRegistry } from "../../src/registry/MultiChainRegistry.sol";
import { IComplianceEngine } from "../../src/interfaces/IComplianceEngine.sol";

/// @title Enterprise Full Stack Integration Test
/// @notice Tests the complete enterprise protocol stack end-to-end:
///         Token -> Staking -> Fee Collection -> Distribution -> Treasury -> Governance
contract EnterpriseFullStackTest is Test {
    ProtocolToken public token;
    ProtocolTimelock public timelock;
    ProtocolTreasury public treasury;
    StakingModule public staking;
    FeeRouter public feeRouter;
    ComplianceEngine public compliance;
    EmergencyGuardian public guardian;
    MultiChainRegistry public registry;

    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public insuranceFund = makeAddr("insuranceFund");

    uint256 public constant INITIAL_MINT = 200_000_000 ether;

    function setUp() public {
        vm.startPrank(deployer);

        // 1. Deploy timelock (2-day delay)
        address[] memory proposers = new address[](1);
        proposers[0] = deployer; // Temporarily, would be Governor in prod
        address[] memory executors = new address[](1);
        executors[0] = deployer;
        timelock = new ProtocolTimelock(2 days, proposers, executors, deployer);

        // 2. Deploy treasury
        treasury = new ProtocolTreasury(address(timelock), 30 days);

        // 3. Deploy protocol token
        token = new ProtocolToken(deployer, INITIAL_MINT, address(treasury));

        // 4. Deploy staking
        staking = new StakingModule(address(token), insuranceFund, deployer);
        token.setMinter(address(staking), true);
        token.setTransferLimitExempt(address(staking), true);

        // 5. Deploy fee router
        feeRouter = new FeeRouter(
            address(treasury),
            address(staking),
            insuranceFund,
            address(token),
            deployer
        );
        token.setTransferLimitExempt(address(feeRouter), true);

        // 6. Deploy compliance
        compliance = new ComplianceEngine(deployer);

        // 7. Deploy emergency guardian
        address[] memory guardians = new address[](2);
        guardians[0] = alice;
        guardians[1] = bob;
        guardian = new EmergencyGuardian(address(timelock), guardians);

        // 8. Deploy multi-chain registry
        registry = new MultiChainRegistry(deployer);
        registry.addChain(97, "BNB Testnet");
        registry.addChain(43113, "Avalanche Fuji");
        registry.addChain(10143, "Monad Testnet");

        vm.stopPrank();
    }

    // ─── Full Stack Integration ──────────────────────────────────────

    function test_fullProtocolLifecycle() public {
        // 1. Treasury receives initial tokens
        assertEq(token.balanceOf(address(treasury)), INITIAL_MINT);

        // 2. Governance disburses tokens to staking rewards and users
        vm.startPrank(address(timelock));
        treasury.disburseToken(address(token), alice, 1_000_000 ether, keccak256("grant-alice"));
        treasury.disburseToken(address(token), bob, 1_000_000 ether, keccak256("grant-bob"));
        vm.stopPrank();

        // 3. Users stake XYT
        vm.prank(alice);
        token.approve(address(staking), type(uint256).max);
        vm.prank(alice);
        staking.stake(500_000 ether, 90 days); // 2x multiplier

        vm.prank(bob);
        token.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        staking.stake(300_000 ether, 30 days); // 1.5x multiplier

        // 4. Verify staking state
        assertEq(staking.stakedBalance(alice), 500_000 ether);
        assertEq(staking.stakedBalance(bob), 300_000 ether);

        // 5. Fee collection (simulating protocol fees)
        vm.prank(deployer);
        feeRouter.setFeeCollector(deployer, true);

        // Deployer needs tokens to pay fees
        vm.prank(address(timelock));
        treasury.disburseToken(address(token), deployer, 10_000 ether, keccak256("fees"));

        vm.startPrank(deployer);
        token.approve(address(feeRouter), type(uint256).max);
        feeRouter.collectFee(address(token), 10_000 ether, deployer);
        vm.stopPrank();

        // 6. Distribute fees
        feeRouter.distributeFees(address(token));

        // Verify distribution (40% treasury, 30% staking, 20% insurance, 10% burn)
        assertEq(token.balanceOf(address(staking)), 800_000 ether + 3_000 ether);
        assertEq(token.balanceOf(insuranceFund), 2_000 ether);
    }

    function test_complianceIntegration() public {
        // Set up credentials
        vm.startPrank(deployer);
        compliance.setCredential(
            alice, IComplianceEngine.InvestorTier.ACCREDITED, block.timestamp + 365 days
        );
        compliance.setCredential(
            bob, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days
        );
        vm.stopPrank();

        // Both credentialed - transfer should be compliant
        assertTrue(compliance.isTransferCompliant(alice, bob, 1000 ether));

        // Blacklist bob
        vm.prank(deployer);
        compliance.blacklist(bob, keccak256("sanctions"));

        // Transfer should now fail
        assertFalse(compliance.isTransferCompliant(alice, bob, 1000 ether));
    }

    function test_emergencyGuardianIntegration() public {
        // Configure circuit breaker
        vm.prank(address(timelock));
        guardian.configureCircuitBreaker(keccak256("TVL"), 1_000_000 ether, false, 1 hours);

        // Report normal TVL - should not trip
        guardian.reportMetric(keccak256("TVL"), 5_000_000 ether);
        assertFalse(guardian.isCircuitBreakerTripped(keccak256("TVL")));

        // Report critical TVL drop
        guardian.reportMetric(keccak256("TVL"), 500_000 ether);
        assertTrue(guardian.isCircuitBreakerTripped(keccak256("TVL")));

        // Guardian activates emergency
        vm.prank(alice);
        guardian.activateEmergency(keccak256("tvl_critical"));
        assertTrue(guardian.isEmergencyActive());

        // Only governance can deactivate
        vm.prank(address(timelock));
        guardian.deactivateEmergency();
        assertFalse(guardian.isEmergencyActive());
    }

    function test_multiChainRegistryIntegration() public {
        address originRWA = makeAddr("originRWA");

        vm.startPrank(deployer);
        registry.registerDeployment(originRWA, 1, 97, makeAddr("mirrorBNB"));
        registry.registerDeployment(originRWA, 1, 43113, makeAddr("mirrorFuji"));
        registry.registerDeployment(originRWA, 1, 10143, makeAddr("mirrorMonad"));

        registry.syncSupply(originRWA, 97, 5_000_000 ether);
        registry.syncSupply(originRWA, 43113, 3_000_000 ether);
        registry.syncSupply(originRWA, 10143, 2_000_000 ether);
        vm.stopPrank();

        // Total aggregate supply across all chains
        assertEq(registry.getAggregateSupply(originRWA, 1), 10_000_000 ether);
        assertEq(registry.totalDeployments(), 3);
    }

    function test_vestingScheduleIntegration() public {
        // Create vesting for team member
        vm.prank(deployer);
        token.createVestingSchedule(charlie, 1_000_000 ether, 180 days, 730 days, true);

        // Before cliff: nothing releasable
        vm.warp(block.timestamp + 90 days);
        assertEq(token.getReleasableAmount(charlie), 0);

        // After cliff: partial release
        vm.warp(block.timestamp + 180 days); // 270 days total
        uint256 releasable = token.getReleasableAmount(charlie);
        assertGt(releasable, 0);

        // Release tokens
        token.releaseVestedTokens(charlie);
        assertEq(token.balanceOf(charlie), releasable);

        // Charlie stakes vested tokens
        vm.prank(charlie);
        token.approve(address(staking), type(uint256).max);
        vm.prank(charlie);
        staking.stake(releasable, 365 days); // Max lock for 3x multiplier

        assertEq(staking.stakedBalance(charlie), releasable);
    }
}
