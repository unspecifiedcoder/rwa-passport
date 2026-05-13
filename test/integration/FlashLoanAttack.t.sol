// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProtocolToken } from "../../src/governance/ProtocolToken.sol";
import { StakingModule } from "../../src/staking/StakingModule.sol";
import { FeeRouter } from "../../src/finance/FeeRouter.sol";
import { XythumToken } from "../../src/core/XythumToken.sol";
import { CanonicalFactory } from "../../src/core/CanonicalFactory.sol";
import { AttestationRegistry } from "../../src/core/AttestationRegistry.sol";
import { SignerRegistry } from "../../src/core/SignerRegistry.sol";
import { MockCompliance } from "../helpers/MockCompliance.sol";
import { AttestationHelper } from "../helpers/AttestationHelper.sol";
import { AttestationLib } from "../../src/libraries/AttestationLib.sol";

/// @title FlashLoanAttack
/// @notice Same-block manipulation, double-burn, and zero-amount edge cases
contract FlashLoanAttackTest is Test {
    ProtocolToken public xyt;
    StakingModule public staking;
    FeeRouter public feeRouter;
    CanonicalFactory public factory;
    SignerRegistry public signerRegistry;
    AttestationRegistry public attestationRegistry;
    MockCompliance public compliance;
    AttestationHelper public helper;

    address public owner;
    address public treasury = makeAddr("treasury");
    address public insurance = makeAddr("insurance");
    address public alice = makeAddr("alice");

    uint256 public constant INITIAL_MINT = 100_000_000 ether;

    function setUp() public {
        vm.warp(100_000);
        owner = address(this);

        xyt = new ProtocolToken(owner, INITIAL_MINT, treasury);
        staking = new StakingModule(address(xyt), insurance, owner);
        xyt.setMinter(address(staking), true);
        xyt.setTransferLimitExempt(address(staking), true);

        feeRouter = new FeeRouter(
            treasury, address(staking), insurance, address(xyt), owner
        );
        feeRouter.setFeeCollector(owner, true);
        xyt.setTransferLimitExempt(address(feeRouter), true);

        signerRegistry = new SignerRegistry(owner, 3);
        helper = new AttestationHelper();
        helper.generateSigners(5);
        for (uint256 i = 0; i < 5; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }
        attestationRegistry =
            new AttestationRegistry(address(signerRegistry), 24 hours, 1 hours);
        compliance = new MockCompliance();
        factory = new CanonicalFactory(
            address(attestationRegistry), address(compliance), treasury, owner
        );

        vm.prank(treasury);
        xyt.transfer(alice, 1_000_000 ether);
        vm.prank(alice);
        xyt.approve(address(staking), type(uint256).max);
    }

    // ─── Stake + claim + unstake in same block ──────────────────────

    function test_stakeClaimUnstake_sameBlock_noRewardExtraction() public {
        // Fund rewards first
        vm.prank(treasury);
        xyt.transfer(owner, 100_000 ether);
        vm.startPrank(owner);
        xyt.approve(address(staking), 100_000 ether);
        staking.notifyRewardAmount(100_000 ether, 30 days);
        vm.stopPrank();

        // Advance 15 days so rewards accumulate
        vm.warp(block.timestamp + 15 days);

        // Alice stakes, claims, unstakes in same block
        uint256 balBefore = xyt.balanceOf(alice);
        vm.startPrank(alice);
        staking.stake(100_000 ether, 0);
        uint256 pending = staking.pendingRewards(alice);
        // In same block: no time elapsed since stake, so 0 rewards
        assertEq(pending, 0);
        staking.unstake(100_000 ether);
        vm.stopPrank();

        // Balance unchanged (no rewards extracted in same block)
        assertEq(xyt.balanceOf(alice), balBefore);
    }

    // ─── Double burn prevention with burnForLock ────────────────────

    function test_burnForLock_doubleBurnReverts() public {
        address mirror = _deployMirror(address(0xAAA), 1, block.chainid, 1);
        XythumToken token = XythumToken(mirror);

        // Mint tokens to alice
        factory.mintMirror(mirror, alice, 10_000 ether);

        bytes32 lockId = keccak256("lock-1");

        // First burn succeeds
        vm.prank(alice);
        token.burnForLock(5_000 ether, lockId);

        // Second burn with same lockId reverts
        vm.prank(alice);
        vm.expectRevert();
        token.burnForLock(5_000 ether, lockId);
    }

    // ─── Fee collect + distribute in same tx ────────────────────────

    function test_feeCollectAndDistribute_sameBlock() public {
        vm.prank(treasury);
        xyt.transfer(owner, 10_000 ether);

        vm.startPrank(owner);
        xyt.approve(address(feeRouter), 10_000 ether);
        feeRouter.collectFee(address(xyt), 10_000 ether, owner);

        // Distribute in same block — should work normally
        feeRouter.distributeFees(address(xyt));
        vm.stopPrank();

        // Fees distributed: pending should be 0
        assertEq(feeRouter.pendingFees(address(xyt)), 0);
        assertGt(feeRouter.totalFeesDistributed(address(xyt)), 0);
    }

    // ─── Transfer to self (balance invariant) ───────────────────────

    function test_transferToSelf_balanceUnchanged() public {
        uint256 balBefore = xyt.balanceOf(alice);

        vm.prank(alice);
        xyt.transfer(alice, 1000 ether);

        assertEq(xyt.balanceOf(alice), balBefore);
    }

    // ─── Claim rewards with no prior stake ──────────────────────────

    function test_claimRewards_noStake_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.claimRewards();
    }

    // ─── Helper ─────────────────────────────────────────────────────

    function _deployMirror(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        uint256 nonce
    ) internal returns (address mirror) {
        AttestationLib.Attestation memory att =
            helper.buildAttestation(originContract, originChainId, targetChainId, nonce);
        uint256[] memory signerIndices = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            signerIndices[i] = i;
        }
        bytes32 domainSep = attestationRegistry.DOMAIN_SEPARATOR();
        (bytes memory sigs, uint256 bitmap) =
            helper.signAttestation(att, domainSep, signerIndices);
        mirror = factory.deployMirror(att, sigs, bitmap);
    }
}
