// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ComplianceEngine } from "../../src/compliance/ComplianceEngine.sol";
import { IComplianceEngine } from "../../src/interfaces/IComplianceEngine.sol";

/// @title ComplianceEdgeCases
/// @notice Credential bypass, tier downgrade, and batch edge case tests
contract ComplianceEdgeCasesTest is Test {
    ComplianceEngine public compliance;

    address public owner = makeAddr("owner");
    address public provider = makeAddr("provider");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        vm.warp(100_000);
        vm.startPrank(owner);
        compliance = new ComplianceEngine(owner);
        compliance.setProvider(provider, true);
        vm.stopPrank();
    }

    // ─── Credential downgrade: ACCREDITED -> RETAIL ─────────────────

    function test_credentialDowngrade_overwritesPreviousTier() public {
        vm.startPrank(provider);
        compliance.setCredential(
            alice, IComplianceEngine.InvestorTier.ACCREDITED, block.timestamp + 365 days
        );
        assertEq(
            uint256(compliance.getInvestorTier(alice)),
            uint256(IComplianceEngine.InvestorTier.ACCREDITED)
        );

        // Downgrade to RETAIL
        compliance.setCredential(
            alice, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days
        );
        assertEq(
            uint256(compliance.getInvestorTier(alice)),
            uint256(IComplianceEngine.InvestorTier.RETAIL)
        );
        vm.stopPrank();
    }

    // ─── Expired credential at exact boundary ───────────────────────

    function test_credentialExpiry_exactBoundaryIsInvalid() public {
        uint256 expiry = block.timestamp + 30 days;
        vm.prank(provider);
        compliance.setCredential(alice, IComplianceEngine.InvestorTier.RETAIL, expiry);

        // At expiry timestamp: credential should be invalid (expiry > block.timestamp fails)
        vm.warp(expiry);
        assertFalse(compliance.isCredentialValid(alice));
    }

    // ─── Provider removed after credentials issued ──────────────────

    function test_providerRemoval_credentialsStillValid() public {
        vm.prank(provider);
        compliance.setCredential(
            alice, IComplianceEngine.InvestorTier.ACCREDITED, block.timestamp + 365 days
        );

        // Remove provider
        vm.prank(owner);
        compliance.setProvider(provider, false);

        // Alice's credential is still valid (provider removal doesn't revoke)
        assertTrue(compliance.isCredentialValid(alice));
    }

    function test_removedProviderCannotSetNewCredentials() public {
        vm.prank(owner);
        compliance.setProvider(provider, false);

        vm.prank(provider);
        vm.expectRevert(ComplianceEngine.OnlyProvider.selector);
        compliance.setCredential(
            bob, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days
        );
    }

    // ─── Blacklist + mint bypass ─────────────────────────────────────

    function test_blacklistedUser_mintBypassesCompliance() public {
        vm.startPrank(provider);
        compliance.setCredential(
            alice, IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days
        );
        compliance.blacklist(alice, keccak256("sanctions"));
        vm.stopPrank();

        // Mint (from address(0)) bypasses compliance even for blacklisted
        assertTrue(compliance.isTransferCompliant(address(0), alice, 1000 ether));

        // But transfers FROM blacklisted user are blocked
        assertFalse(compliance.isTransferCompliant(alice, bob, 1000 ether));
    }

    // ─── batchSetCredentials with mismatched arrays ─────────────────

    function test_batchSetCredentials_mismatchedArraysReverts() public {
        address[] memory investors = new address[](2);
        investors[0] = alice;
        investors[1] = bob;

        IComplianceEngine.InvestorTier[] memory tiers = new IComplianceEngine.InvestorTier[](1);
        tiers[0] = IComplianceEngine.InvestorTier.RETAIL;

        uint256[] memory expiries = new uint256[](2);
        expiries[0] = block.timestamp + 365 days;
        expiries[1] = block.timestamp + 365 days;

        vm.prank(provider);
        vm.expectRevert(ComplianceEngine.ArrayLengthMismatch.selector);
        compliance.batchSetCredentials(investors, tiers, expiries);
    }

    // ─── Setting credential with NONE tier reverts ──────────────────

    function test_setCredential_noneTierReverts() public {
        vm.prank(provider);
        vm.expectRevert(ComplianceEngine.InvalidTier.selector);
        compliance.setCredential(
            alice, IComplianceEngine.InvestorTier.NONE, block.timestamp + 365 days
        );
    }

    // ─── Zero address credential reverts ────────────────────────────

    function test_setCredential_zeroAddressReverts() public {
        vm.prank(provider);
        vm.expectRevert(ComplianceEngine.ZeroAddress.selector);
        compliance.setCredential(
            address(0), IComplianceEngine.InvestorTier.RETAIL, block.timestamp + 365 days
        );
    }
}
