// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { CanonicalFactory } from "../../../src/core/CanonicalFactory.sol";
import { AttestationRegistry } from "../../../src/core/AttestationRegistry.sol";
import { SignerRegistry } from "../../../src/core/SignerRegistry.sol";
import { XythumToken } from "../../../src/core/XythumToken.sol";
import { AttestationLib } from "../../../src/libraries/AttestationLib.sol";
import { ReceiptLib } from "../../../src/libraries/ReceiptLib.sol";
import { SignatureLib } from "../../../src/libraries/SignatureLib.sol";

import { ReceiptHelper } from "../../helpers/ReceiptHelper.sol";

/// @notice Unit tests for CanonicalFactory.mintFromLock (M3)
contract CanonicalFactoryMintFromLockTest is Test {
    SignerRegistry public signerRegistry;
    AttestationRegistry public attRegistry;
    CanonicalFactory public factory;
    ReceiptHelper public helper;

    address public locker = makeAddr("locker");
    address public constant ORIGIN_CONTRACT = address(0xAAA);
    uint256 public constant ORIGIN_CHAIN = 43113; // Fuji
    uint256 public constant TARGET_CHAIN = 31337; // forge default

    uint256 public constant THRESHOLD = 3;
    uint256 public constant SIGNER_COUNT = 5;
    uint256 public constant MAX_STALENESS = 1 days;
    uint256 public constant RATE_LIMIT = 1 hours;

    function setUp() public {
        // Deploy + populate signer set
        signerRegistry = new SignerRegistry(address(this), THRESHOLD);
        helper = new ReceiptHelper();
        helper.generateSigners(SIGNER_COUNT);
        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            signerRegistry.registerSigner(helper.getSignerAddress(i));
        }

        // Deploy attestation registry
        attRegistry = new AttestationRegistry(address(signerRegistry), MAX_STALENESS, RATE_LIMIT);

        // Deploy factory (compliance disabled, treasury = self)
        factory =
            new CanonicalFactory(address(attRegistry), address(0), address(this), address(this));
    }

    // ─── helpers ─────────────────────────────────────────────────────

    function _buildLockReceipt(bytes32 lockId, uint256 amount)
        internal
        view
        returns (ReceiptLib.LockReceipt memory)
    {
        return ReceiptLib.LockReceipt({
            originContract: ORIGIN_CONTRACT,
            originChainId: ORIGIN_CHAIN,
            targetChainId: TARGET_CHAIN, // == block.chainid in tests
            locker: locker,
            amount: amount,
            lockId: lockId,
            timestamp: block.timestamp
        });
    }

    function _factoryDomainSeparator() internal view returns (bytes32) {
        return AttestationLib.domainSeparator(block.chainid, address(factory));
    }

    function _signWith(ReceiptLib.LockReceipt memory r, uint256[] memory indices)
        internal
        view
        returns (bytes memory sigs, uint256 bitmap)
    {
        return helper.signLockReceipt(r, _factoryDomainSeparator(), indices);
    }

    function _thresholdIndices() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            ids[i] = i;
        }
        return ids;
    }

    // ─── happy path: auto-deploy + mint ──────────────────────────────

    function test_mintFromLock_autoDeploysMirrorAndMints() public {
        bytes32 lockId = keccak256("first-lock");
        uint256 amount = 100_000 ether;

        ReceiptLib.LockReceipt memory r = _buildLockReceipt(lockId, amount);
        (bytes memory sigs, uint256 bitmap) = _signWith(r, _thresholdIndices());

        // Mirror does not exist yet.
        bytes32 salt = keccak256(abi.encode(ORIGIN_CONTRACT, ORIGIN_CHAIN, TARGET_CHAIN));
        assertEq(factory.mirrors(salt), address(0));

        address mirror = factory.mintFromLock(r, sigs, bitmap);

        // Mirror was deployed and recorded.
        assertEq(factory.mirrors(salt), mirror);
        assertTrue(factory.isCanonical(mirror));
        assertEq(factory.getMirrorCount(), 1);

        // Locker received the freshly minted xRWA, cap matches amount.
        XythumToken token = XythumToken(mirror);
        assertEq(token.balanceOf(locker), amount);
        assertEq(token.mintCap(), amount);
        assertEq(token.totalMinted(), amount);

        // One-shot guard set.
        assertTrue(factory.mintedFromLock(lockId));
    }

    // ─── second lock for same corridor: bumps cap ────────────────────

    function test_mintFromLock_secondLockBumpsCap() public {
        // First lock — auto-deploys mirror with cap 100k
        ReceiptLib.LockReceipt memory r1 = _buildLockReceipt(keccak256("L1"), 100_000 ether);
        (bytes memory sigs1, uint256 bm1) = _signWith(r1, _thresholdIndices());
        address mirror = factory.mintFromLock(r1, sigs1, bm1);

        // Second lock — same corridor, different lockId, +50k
        ReceiptLib.LockReceipt memory r2 = _buildLockReceipt(keccak256("L2"), 50_000 ether);
        (bytes memory sigs2, uint256 bm2) = _signWith(r2, _thresholdIndices());

        address mirror2 = factory.mintFromLock(r2, sigs2, bm2);

        // Same mirror — cap bumped, totalMinted accumulated.
        assertEq(mirror, mirror2);
        XythumToken token = XythumToken(mirror);
        assertEq(token.balanceOf(locker), 150_000 ether);
        assertEq(token.mintCap(), 150_000 ether); // cumulative high-water mark
        assertEq(token.totalMinted(), 150_000 ether);

        // Still only one mirror in registry.
        assertEq(factory.getMirrorCount(), 1);
    }

    // ─── reverts ─────────────────────────────────────────────────────

    function test_mintFromLock_revertsOnDoubleConsumption() public {
        ReceiptLib.LockReceipt memory r = _buildLockReceipt(keccak256("L1"), 1 ether);
        (bytes memory sigs, uint256 bm) = _signWith(r, _thresholdIndices());

        factory.mintFromLock(r, sigs, bm);

        vm.expectRevert(
            abi.encodeWithSelector(CanonicalFactory.AlreadyMintedFromLock.selector, r.lockId)
        );
        factory.mintFromLock(r, sigs, bm);
    }

    function test_mintFromLock_revertsOnWrongTargetChain() public {
        ReceiptLib.LockReceipt memory r = _buildLockReceipt(keccak256("L1"), 1 ether);
        r.targetChainId = 999;
        (bytes memory sigs, uint256 bm) = _signWith(r, _thresholdIndices());

        vm.expectRevert(
            abi.encodeWithSelector(CanonicalFactory.WrongTargetChain.selector, 999, block.chainid)
        );
        factory.mintFromLock(r, sigs, bm);
    }

    function test_mintFromLock_revertsOnFutureReceipt() public {
        ReceiptLib.LockReceipt memory r = _buildLockReceipt(keccak256("L1"), 1 ether);
        r.timestamp = block.timestamp + 1 hours;
        (bytes memory sigs, uint256 bm) = _signWith(r, _thresholdIndices());

        vm.expectRevert(
            abi.encodeWithSelector(CanonicalFactory.LockReceiptInFuture.selector, r.timestamp)
        );
        factory.mintFromLock(r, sigs, bm);
    }

    function test_mintFromLock_revertsOnStaleReceipt() public {
        ReceiptLib.LockReceipt memory r = _buildLockReceipt(keccak256("L1"), 1 ether);
        (bytes memory sigs, uint256 bm) = _signWith(r, _thresholdIndices());

        // Jump past staleness.
        vm.warp(r.timestamp + 1 days + 1);

        vm.expectRevert(
            abi.encodeWithSelector(CanonicalFactory.LockReceiptStale.selector, r.timestamp, 1 days)
        );
        factory.mintFromLock(r, sigs, bm);
    }

    function test_mintFromLock_revertsOnInsufficientSignatures() public {
        ReceiptLib.LockReceipt memory r = _buildLockReceipt(keccak256("L1"), 1 ether);
        uint256[] memory only2 = new uint256[](2);
        only2[0] = 0;
        only2[1] = 1;
        (bytes memory sigs, uint256 bm) = _signWith(r, only2);

        vm.expectRevert(abi.encodeWithSelector(SignatureLib.InsufficientSignatures.selector, 2, 3));
        factory.mintFromLock(r, sigs, bm);
    }

    function test_mintFromLock_revertsOnTamperedReceipt() public {
        ReceiptLib.LockReceipt memory r = _buildLockReceipt(keccak256("L1"), 100 ether);
        (bytes memory sigs, uint256 bm) = _signWith(r, _thresholdIndices());

        // Mutate amount AFTER signing — sigs no longer recover signers[i].
        r.amount = 999_999_999 ether;

        vm.expectRevert();
        factory.mintFromLock(r, sigs, bm);
    }
}
