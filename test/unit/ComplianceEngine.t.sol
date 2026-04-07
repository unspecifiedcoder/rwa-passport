// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ComplianceEngine } from "../../src/compliance/ComplianceEngine.sol";
import { IComplianceEngine } from "../../src/interfaces/IComplianceEngine.sol";

/// @title ComplianceEngine Unit Tests
contract ComplianceEngineTest is Test {
    ComplianceEngine public compliance;

    address public owner = makeAddr("owner");
    address public provider = makeAddr("provider");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    function setUp() public {
        vm.startPrank(owner);
        compliance = new ComplianceEngine(owner);
        compliance.setProvider(provider, true);
        vm.stopPrank();
    }

    // ─── Credential Management ───────────────────────────────────────

    function test_setCredential() public {
        vm.prank(provider);
        compliance.setCredential(alice, IComplianceEngine.InvestorTier.ACCREDITED, block.timestamp + 365 days);

        assertEq(uint256(compliance.getInvestorTier(alice)), uint256(IComplianceEngine.InvestorTier.ACCREDITED));
        assertTrue(compliance.isCredentialValid(alice));
    }

    function test_credentialExpiry() public {
        vm.prank(provider);
        compliance.setCredential(alice, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 30 days);

        assertTrue(compliance.isCredentialValid(alice));

        vm.warp(block.timestamp + 31 days);
        assertFalse(compliance.isCredentialValid(alice));
    }

    function test_batchSetCredentials() public {
        address[] memory investors = new address[](3);
        investors[0] = alice;
        investors[1] = bob;
        investors[2] = charlie;

        IComplianceEngine.InvestorTier[] memory tiers = new IComplianceEngine.InvestorTier[](3);
        tiers[0] = IComplianceEngine.InvestorTier.ACCREDITED;
        tiers[1] = IComplianceEngine.InvestorTier.RETAIL;
        tiers[2] = IComplianceEngine.InvestorTier.INSTITUTIONAL;

        uint256[] memory expiries = new uint256[](3);
        expiries[0] = block.timestamp + 365 days;
        expiries[1] = block.timestamp + 365 days;
        expiries[2] = block.timestamp + 365 days;

        vm.prank(provider);
        compliance.batchSetCredentials(investors, tiers, expiries);

        assertEq(uint256(compliance.getInvestorTier(alice)), uint256(IComplianceEngine.InvestorTier.ACCREDITED));
        assertEq(uint256(compliance.getInvestorTier(bob)), uint256(IComplianceEngine.InvestorTier.RETAIL));
        assertEq(uint256(compliance.getInvestorTier(charlie)), uint256(IComplianceEngine.InvestorTier.INSTITUTIONAL));
        assertEq(compliance.totalCredentialed(), 3);
    }

    function test_unauthorizedProviderReverts() public {
        vm.prank(charlie);
        vm.expectRevert(ComplianceEngine.OnlyProvider.selector);
        compliance.setCredential(alice, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days);
    }

    // ─── Blacklist ───────────────────────────────────────────────────

    function test_blacklist() public {
        vm.prank(provider);
        compliance.blacklist(alice, keccak256("sanctions"));

        assertTrue(compliance.isBlacklisted(alice));
        assertEq(compliance.totalBlacklisted(), 1);
    }

    function test_removeBlacklist() public {
        vm.prank(provider);
        compliance.blacklist(alice, keccak256("sanctions"));

        vm.prank(owner);
        compliance.removeBlacklist(alice);

        assertFalse(compliance.isBlacklisted(alice));
    }

    function test_doubleBlacklistReverts() public {
        vm.prank(provider);
        compliance.blacklist(alice, keccak256("sanctions"));

        vm.prank(provider);
        vm.expectRevert(abi.encodeWithSelector(ComplianceEngine.AlreadyBlacklisted.selector, alice));
        compliance.blacklist(alice, keccak256("sanctions_again"));
    }

    // ─── Transfer Compliance ─────────────────────────────────────────

    function test_compliantTransfer() public {
        vm.startPrank(provider);
        compliance.setCredential(alice, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days);
        compliance.setCredential(bob, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days);
        vm.stopPrank();

        assertTrue(compliance.isTransferCompliant(alice, bob, 1000 ether));
    }

    function test_nonCompliantTransferNoCredential() public {
        vm.prank(provider);
        compliance.setCredential(alice, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days);

        // Bob has no credential
        assertFalse(compliance.isTransferCompliant(alice, bob, 1000 ether));
    }

    function test_nonCompliantTransferBlacklisted() public {
        vm.startPrank(provider);
        compliance.setCredential(alice, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days);
        compliance.setCredential(bob, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days);
        compliance.blacklist(bob, keccak256("sanctions"));
        vm.stopPrank();

        assertFalse(compliance.isTransferCompliant(alice, bob, 1000 ether));
    }

    function test_mintBurnBypassCompliance() public {
        // Mint/burn (from/to address(0)) should always pass
        assertTrue(compliance.isTransferCompliant(address(0), alice, 1000 ether));
        assertTrue(compliance.isTransferCompliant(alice, address(0), 1000 ether));
    }

    // ─── Asset Rules ─────────────────────────────────────────────────

    function test_assetSpecificRules() public {
        address asset = makeAddr("rwaToken");

        vm.prank(owner);
        compliance.setAssetRule(
            asset,
            IComplianceEngine.InvestorTier.ACCREDITED,
            1_000_000 ether,
            true
        );

        vm.startPrank(provider);
        compliance.setCredential(alice, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days);
        compliance.setCredential(bob, IComplianceEngine.InvestorTier.ACCREDITED, block.timestamp + 365 days);
        vm.stopPrank();

        // Retail investor fails asset-level check (requires ACCREDITED)
        assertFalse(compliance.isAssetTransferCompliant(asset, alice, bob, 1000 ether));

        // Both accredited passes
        vm.prank(provider);
        compliance.setCredential(alice, IComplianceEngine.InvestorTier.ACCREDITED, block.timestamp + 365 days);
        assertTrue(compliance.isAssetTransferCompliant(asset, alice, bob, 1000 ether));
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function test_setDefaultMinimumTier() public {
        vm.prank(owner);
        compliance.setDefaultMinimumTier(IComplianceEngine.InvestorTier.ACCREDITED);

        assertEq(uint256(compliance.defaultMinimumTier()), uint256(IComplianceEngine.InvestorTier.ACCREDITED));
    }
}
