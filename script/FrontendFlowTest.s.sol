// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {AttestationLib} from "../src/libraries/AttestationLib.sol";
import {CanonicalFactory} from "../src/core/CanonicalFactory.sol";
import {AttestationRegistry} from "../src/core/AttestationRegistry.sol";
import {SignerRegistry} from "../src/core/SignerRegistry.sol";
import {XythumToken} from "../src/core/XythumToken.sol";

/// @title FrontendFlowTest
/// @notice Comprehensive end-to-end test of all flows the frontend triggers.
///         Tests CORRECT flows and BAD flows against live testnets.
///
/// Usage:
///   # Test on BNB Testnet (target for Fuji→BNB direction)
///   forge script script/FrontendFlowTest.s.sol:TestBnbCorrectFlows \
///       --rpc-url https://bsc-testnet-rpc.publicnode.com -vvvv
///
///   forge script script/FrontendFlowTest.s.sol:TestBnbBadFlows \
///       --rpc-url https://bsc-testnet-rpc.publicnode.com -vvvv
///
///   # Test on Fuji (target for BNB→Fuji direction)
///   forge script script/FrontendFlowTest.s.sol:TestFujiCorrectFlows \
///       --rpc-url https://avalanche-fuji-c-chain-rpc.publicnode.com -vvvv

// ═══════════════════════════════════════════════════════════════
//  SHARED BASE — common addresses and helpers
// ═══════════════════════════════════════════════════════════════
abstract contract TestBase is Script {
    // Demo signer keys (same as frontend signing.ts)
    uint256 constant SIGNER_KEY_1 = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_KEY_2 = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_KEY_3 = uint256(keccak256("xythum-demo-signer-3"));
    uint256 constant SIGNER_KEY_4 = uint256(keccak256("xythum-demo-signer-4"));
    uint256 constant SIGNER_KEY_5 = uint256(keccak256("xythum-demo-signer-5"));

    // ── BNB Testnet contracts ──
    address constant BNB_FACTORY    = 0x99AB8C07C0082CBdD0306B30BC52eA15e6dB2521;
    address constant BNB_ATT_REG    = 0xe27E5e2D924F6e42ffa90C6bE817AA030dE6f48D;
    address constant BNB_SIGNER_REG = 0xFA6aFAcfAA866Cf54aCCa0E23883a1597574206c;
    address constant BNB_CCIP_SENDER = 0x3823baE274eB188D3dF66D8bc4eAAaf0F050dAD6;
    address constant BNB_CCIP_RECV  = 0xDc1f35F18607c8ee5a823b1ebBc5eDFe0fb253F3;
    address constant BNB_MOCK_RWA   = 0x31004d16339C54f49FDb0dE061846268eE59B4af;
    address constant BNB_MIRROR     = 0xD8885030b36DDDf303A8F6Eb3A78A5609432f209;

    // ── Fuji contracts ──
    address constant FUJI_FACTORY    = 0x4934985287C28e647ecF38d485E448ac4A4A4Ab7;
    address constant FUJI_ATT_REG    = 0xd0047E6F5281Ed7d04f2eAea216cB771b80f7104;
    address constant FUJI_SIGNER_REG = 0xF17BBD22D1d3De885d02E01805C01C0e43E64A2F;
    address constant FUJI_CCIP_SENDER = 0x1062C2fBebd13862d4D503430E3E1A81907c2bD7;
    address constant FUJI_CCIP_RECV  = 0xC740E9D56c126eb447f84404dDd9dffbB7AEd5F8;
    address constant FUJI_MOCK_RWA   = 0xD52b37AD931F221A902fC7F43A9ed2D87Ce07C5F;
    address constant FUJI_MIRROR     = 0x50Cef4543E676089F9C1D66851F1F6bAb269CEfC;

    uint256 constant FUJI_CHAIN_ID = 43113;
    uint256 constant BNB_CHAIN_ID  = 97;

    function _signAttestation(
        AttestationLib.Attestation memory att,
        address attRegistry,
        uint256[] memory keys
    ) internal view returns (bytes memory signatures, uint256 bitmap) {
        bytes32 domainSep = AttestationLib.domainSeparator(att.targetChainId, attRegistry);
        bytes32 digest = AttestationLib.toTypedDataHash(att, domainSep);

        bytes memory sigs;
        for (uint256 i = 0; i < keys.length; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            sigs = abi.encodePacked(sigs, r, s, v);
            bitmap |= (1 << i);
        }
        signatures = sigs;
    }

    function _sign3of5(
        AttestationLib.Attestation memory att,
        address attRegistry
    ) internal view returns (bytes memory signatures, uint256 bitmap) {
        uint256[] memory keys = new uint256[](3);
        keys[0] = SIGNER_KEY_1;
        keys[1] = SIGNER_KEY_2;
        keys[2] = SIGNER_KEY_3;
        return _signAttestation(att, attRegistry, keys);
    }

    function _sign2of5(
        AttestationLib.Attestation memory att,
        address attRegistry
    ) internal view returns (bytes memory signatures, uint256 bitmap) {
        uint256[] memory keys = new uint256[](2);
        keys[0] = SIGNER_KEY_1;
        keys[1] = SIGNER_KEY_2;
        return _signAttestation(att, attRegistry, keys);
    }

    function _pass(string memory name) internal pure {
        console.log(unicode"  ✅", name);
    }

    function _fail(string memory name, string memory reason) internal pure {
        console.log(unicode"  ❌", name, "-", reason);
    }
}

// ═══════════════════════════════════════════════════════════════
//  CORRECT FLOWS — BNB Testnet
// ═══════════════════════════════════════════════════════════════
contract TestBnbCorrectFlows is TestBase {
    function run() external view {
        console.log("=== BNB TESTNET CORRECT FLOW TESTS ===");
        console.log("Chain ID:", block.chainid);
        console.log("");

        _testIsCanonical();
        _testIsCanonicalNegative();
        _testMirrorMetadata();
        _testSignerRegistry();
        _testEnumerationGetters();
        _testComputeMirrorAddress();
        _testAttestationRegistryState();

        console.log("");
        console.log("=== ALL BNB CORRECT FLOW TESTS DONE ===");
    }

    function _testIsCanonical() internal view {
        bool result = CanonicalFactory(BNB_FACTORY).isCanonical(BNB_MIRROR);
        if (result) {
            _pass("isCanonical(deployed mirror) = true");
        } else {
            _fail("isCanonical(deployed mirror)", "expected true, got false");
        }
    }

    function _testIsCanonicalNegative() internal view {
        bool result = CanonicalFactory(BNB_FACTORY).isCanonical(address(0xdead));
        if (!result) {
            _pass("isCanonical(random address) = false");
        } else {
            _fail("isCanonical(random)", "expected false, got true");
        }
    }

    function _testMirrorMetadata() internal view {
        XythumToken mirror = XythumToken(BNB_MIRROR);

        string memory name = mirror.name();
        string memory symbol = mirror.symbol();
        address origin = mirror.originContract();
        uint256 originChain = mirror.originChainId();
        uint256 cap = mirror.mintCap();

        bool nameOk = keccak256(bytes(name)) == keccak256("Xythum Mirror");
        bool symbolOk = keccak256(bytes(symbol)) == keccak256("xRWA");
        bool originOk = origin == FUJI_MOCK_RWA;
        bool chainOk = originChain == FUJI_CHAIN_ID;
        bool capOk = cap == 1_000_000 ether;

        if (nameOk) _pass("mirror.name() = 'Xythum Mirror'");
        else _fail("mirror.name()", name);

        if (symbolOk) _pass("mirror.symbol() = 'xRWA'");
        else _fail("mirror.symbol()", symbol);

        if (originOk) _pass("mirror.originContract() = Fuji MockRWA");
        else _fail("mirror.originContract()", "mismatch");

        if (chainOk) _pass("mirror.originChainId() = 43113 (Fuji)");
        else _fail("mirror.originChainId()", "mismatch");

        if (capOk) _pass("mirror.mintCap() = 1,000,000 tokens");
        else _fail("mirror.mintCap()", "mismatch");
    }

    function _testSignerRegistry() internal view {
        SignerRegistry reg = SignerRegistry(BNB_SIGNER_REG);
        uint256 count = reg.getSignerCount();
        uint256 threshold = reg.threshold();
        address[] memory signers = reg.getSignerSet();

        if (count == 5) _pass("signerCount = 5");
        else _fail("signerCount", "expected 5");

        if (threshold == 3) _pass("threshold = 3");
        else _fail("threshold", "expected 3");

        // Verify signer addresses match demo keys
        address expected0 = vm.addr(SIGNER_KEY_1);
        if (signers.length >= 1 && signers[0] == expected0)
            _pass("signer[0] matches demo key 1");
        else
            _fail("signer[0]", "mismatch with demo key");

        console.log("    Signer addresses:");
        for (uint256 i = 0; i < signers.length; i++) {
            console.log("      [%d] %s", i, signers[i]);
        }
    }

    function _testEnumerationGetters() internal view {
        CanonicalFactory factory = CanonicalFactory(BNB_FACTORY);

        uint256 count = factory.getMirrorCount();
        if (count >= 1) _pass(string.concat("getMirrorCount() = ", vm.toString(count)));
        else _fail("getMirrorCount()", "expected >= 1");

        address[] memory all = factory.getAllMirrors();
        if (all.length == count)
            _pass("getAllMirrors().length matches getMirrorCount()");
        else
            _fail("getAllMirrors()", "length mismatch");

        if (all.length > 0 && all[0] == BNB_MIRROR)
            _pass("getAllMirrors()[0] = deployed mirror");
        else
            _fail("getAllMirrors()[0]", "mismatch");

        // Pagination test
        address[] memory page = factory.getMirrors(0, 1);
        if (page.length == 1 && page[0] == BNB_MIRROR)
            _pass("getMirrors(0, 1) returns first mirror");
        else
            _fail("getMirrors(0,1)", "mismatch");
    }

    function _testComputeMirrorAddress() internal view {
        CanonicalFactory factory = CanonicalFactory(BNB_FACTORY);

        // Build the same attestation that was used to deploy
        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: FUJI_MOCK_RWA,
            originChainId: FUJI_CHAIN_ID,
            targetChainId: BNB_CHAIN_ID,
            navRoot: keccak256("nav-placeholder"),
            complianceRoot: keccak256("compliance-placeholder"),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp, // doesn't affect address
            nonce: 1                    // doesn't affect address
        });

        address computed = factory.computeMirrorAddress(att);
        if (computed == BNB_MIRROR)
            _pass("computeMirrorAddress() matches deployed mirror");
        else {
            _fail("computeMirrorAddress()", "mismatch");
            console.log("    Expected:", BNB_MIRROR);
            console.log("    Got:     ", computed);
        }
    }

    function _testAttestationRegistryState() internal view {
        AttestationRegistry reg = AttestationRegistry(BNB_ATT_REG);

        // Check isAttested for the deployed mirror's pair
        bool attested = reg.isAttested(FUJI_MOCK_RWA, FUJI_CHAIN_ID, BNB_CHAIN_ID);
        if (attested) _pass("isAttested(Fuji MockRWA -> BNB) = true");
        else _fail("isAttested", "expected true");

        // Check domain separator is non-zero
        bytes32 ds = reg.DOMAIN_SEPARATOR();
        if (ds != bytes32(0)) _pass("DOMAIN_SEPARATOR is set (non-zero)");
        else _fail("DOMAIN_SEPARATOR", "is zero");

        // Check immutables
        uint256 staleness = reg.maxStaleness();
        uint256 rateLimit = reg.rateLimitPeriod();
        console.log("    maxStaleness:", staleness, "seconds");
        console.log("    rateLimitPeriod:", rateLimit, "seconds");
    }
}

// ═══════════════════════════════════════════════════════════════
//  CORRECT FLOWS — Fuji (reverse direction)
// ═══════════════════════════════════════════════════════════════
contract TestFujiCorrectFlows is TestBase {
    function run() external view {
        console.log("=== FUJI CORRECT FLOW TESTS ===");
        console.log("Chain ID:", block.chainid);
        console.log("");

        _testIsCanonical();
        _testMirrorMetadata();
        _testSignerRegistry();
        _testEnumerationGetters();
        _testComputeMirrorAddress();
        _testAttestationRegistryState();

        console.log("");
        console.log("=== ALL FUJI CORRECT FLOW TESTS DONE ===");
    }

    function _testIsCanonical() internal view {
        bool result = CanonicalFactory(FUJI_FACTORY).isCanonical(FUJI_MIRROR);
        if (result) _pass("isCanonical(Fuji mirror) = true");
        else _fail("isCanonical(Fuji mirror)", "expected true");

        bool resultNeg = CanonicalFactory(FUJI_FACTORY).isCanonical(address(0xdead));
        if (!resultNeg) _pass("isCanonical(random) = false");
        else _fail("isCanonical(random)", "expected false");
    }

    function _testMirrorMetadata() internal view {
        XythumToken mirror = XythumToken(FUJI_MIRROR);
        bool nameOk = keccak256(bytes(mirror.name())) == keccak256("Xythum Mirror");
        bool symbolOk = keccak256(bytes(mirror.symbol())) == keccak256("xRWA");
        bool originOk = mirror.originContract() == BNB_MOCK_RWA;
        bool chainOk = mirror.originChainId() == BNB_CHAIN_ID;

        if (nameOk) _pass("mirror.name() = 'Xythum Mirror'");
        else _fail("mirror.name()", "wrong");
        if (symbolOk) _pass("mirror.symbol() = 'xRWA'");
        else _fail("mirror.symbol()", "wrong");
        if (originOk) _pass("mirror.originContract() = BNB MockRWA");
        else _fail("mirror.originContract()", "mismatch");
        if (chainOk) _pass("mirror.originChainId() = 97 (BNB)");
        else _fail("mirror.originChainId()", "mismatch");
    }

    function _testSignerRegistry() internal view {
        SignerRegistry reg = SignerRegistry(FUJI_SIGNER_REG);
        uint256 count = reg.getSignerCount();
        uint256 threshold = reg.threshold();
        if (count == 5) _pass("signerCount = 5");
        else _fail("signerCount", "expected 5");
        if (threshold == 3) _pass("threshold = 3");
        else _fail("threshold", "expected 3");
    }

    function _testEnumerationGetters() internal view {
        CanonicalFactory factory = CanonicalFactory(FUJI_FACTORY);
        uint256 count = factory.getMirrorCount();
        if (count >= 1) _pass(string.concat("getMirrorCount() = ", vm.toString(count)));
        else _fail("getMirrorCount()", "expected >= 1");

        address[] memory all = factory.getAllMirrors();
        if (all.length > 0 && all[0] == FUJI_MIRROR)
            _pass("getAllMirrors()[0] = deployed Fuji mirror");
        else _fail("getAllMirrors()[0]", "mismatch");
    }

    function _testComputeMirrorAddress() internal view {
        CanonicalFactory factory = CanonicalFactory(FUJI_FACTORY);
        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: BNB_MOCK_RWA,
            originChainId: BNB_CHAIN_ID,
            targetChainId: FUJI_CHAIN_ID,
            navRoot: keccak256("nav-placeholder"),
            complianceRoot: keccak256("compliance-placeholder"),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp,
            nonce: 1
        });
        address computed = factory.computeMirrorAddress(att);
        if (computed == FUJI_MIRROR)
            _pass("computeMirrorAddress() matches Fuji mirror");
        else {
            _fail("computeMirrorAddress()", "mismatch");
            console.log("    Expected:", FUJI_MIRROR);
            console.log("    Got:     ", computed);
        }
    }

    function _testAttestationRegistryState() internal view {
        AttestationRegistry reg = AttestationRegistry(FUJI_ATT_REG);
        bool attested = reg.isAttested(BNB_MOCK_RWA, BNB_CHAIN_ID, FUJI_CHAIN_ID);
        if (attested) _pass("isAttested(BNB MockRWA -> Fuji) = true");
        else _fail("isAttested", "expected true");
    }
}

// ═══════════════════════════════════════════════════════════════
//  BAD FLOWS — BNB Testnet (test reverts)
// ═══════════════════════════════════════════════════════════════
contract TestBnbBadFlows is TestBase {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        console.log("=== BNB TESTNET BAD FLOW TESTS ===");
        console.log("Chain ID:", block.chainid);
        console.log("");

        _testDuplicateNonce(deployerKey);
        _testWrongTargetChain(deployerKey);
        _testInsufficientSignatures(deployerKey);
        _testStaleTimestamp(deployerKey);
        _testOutOfBoundsPagination();

        console.log("");
        console.log("=== ALL BNB BAD FLOW TESTS DONE ===");
    }

    /// @notice Attempt to deploy with nonce=1 which was already used → should revert
    function _testDuplicateNonce(uint256 deployerKey) internal {
        CanonicalFactory factory = CanonicalFactory(BNB_FACTORY);

        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: FUJI_MOCK_RWA,
            originChainId: FUJI_CHAIN_ID,
            targetChainId: BNB_CHAIN_ID,
            navRoot: keccak256("nav-placeholder"),
            complianceRoot: keccak256("compliance-placeholder"),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp,
            nonce: 1  // Already used!
        });

        (bytes memory sigs, uint256 bitmap) = _sign3of5(att, BNB_ATT_REG);

        vm.startBroadcast(deployerKey);
        try factory.deployMirrorDirect(att, sigs, bitmap) returns (address) {
            _fail("duplicate nonce", "should have reverted but succeeded");
        } catch {
            _pass("duplicate nonce (1) correctly reverts");
        }
        vm.stopBroadcast();
    }

    /// @notice Attempt to deploy with targetChainId = Fuji but on BNB → should revert WrongTargetChain
    function _testWrongTargetChain(uint256 deployerKey) internal {
        CanonicalFactory factory = CanonicalFactory(BNB_FACTORY);

        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: FUJI_MOCK_RWA,
            originChainId: FUJI_CHAIN_ID,
            targetChainId: FUJI_CHAIN_ID,  // Wrong! Should be BNB_CHAIN_ID
            navRoot: keccak256("nav"),
            complianceRoot: keccak256("comp"),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp,
            nonce: 999
        });

        // Sign against Fuji's ATT_REG (since targetChainId=Fuji)
        (bytes memory sigs, uint256 bitmap) = _sign3of5(att, FUJI_ATT_REG);

        vm.startBroadcast(deployerKey);
        try factory.deployMirrorDirect(att, sigs, bitmap) returns (address) {
            _fail("wrong targetChainId", "should have reverted but succeeded");
        } catch {
            _pass("wrong targetChainId correctly reverts (WrongTargetChain)");
        }
        vm.stopBroadcast();
    }

    /// @notice Attempt to deploy with only 2/5 signatures → should revert InsufficientSignatures
    function _testInsufficientSignatures(uint256 deployerKey) internal {
        CanonicalFactory factory = CanonicalFactory(BNB_FACTORY);

        // Use a unique origin to avoid MirrorAlreadyDeployed masking the real error
        address uniqueOrigin = address(uint160(uint256(keccak256("test-insuf-sigs-origin"))));

        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: uniqueOrigin,
            originChainId: FUJI_CHAIN_ID,
            targetChainId: BNB_CHAIN_ID,
            navRoot: keccak256("nav"),
            complianceRoot: keccak256("comp"),
            lockedAmount: 1_000_000 ether,
            timestamp: block.timestamp,
            nonce: 1
        });

        (bytes memory sigs, uint256 bitmap) = _sign2of5(att, BNB_ATT_REG);

        vm.startBroadcast(deployerKey);
        try factory.deployMirrorDirect(att, sigs, bitmap) returns (address) {
            _fail("insufficient signatures", "should have reverted but succeeded");
        } catch {
            _pass("insufficient signatures (2/5) correctly reverts");
        }
        vm.stopBroadcast();
    }

    /// @notice Attempt to deploy with timestamp far in the past → should revert AttestationExpired
    function _testStaleTimestamp(uint256 deployerKey) internal {
        CanonicalFactory factory = CanonicalFactory(BNB_FACTORY);

        // Use a unique origin to avoid MirrorAlreadyDeployed masking the real error
        address uniqueOrigin = address(uint160(uint256(keccak256("test-stale-ts-origin"))));

        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: uniqueOrigin,
            originChainId: FUJI_CHAIN_ID,
            targetChainId: BNB_CHAIN_ID,
            navRoot: keccak256("nav-stale"),
            complianceRoot: keccak256("comp-stale"),
            lockedAmount: 1_000_000 ether,
            timestamp: 1000,  // Way in the past (year 1970)
            nonce: 1
        });

        (bytes memory sigs, uint256 bitmap) = _sign3of5(att, BNB_ATT_REG);

        vm.startBroadcast(deployerKey);
        try factory.deployMirrorDirect(att, sigs, bitmap) returns (address) {
            _fail("stale timestamp", "should have reverted but succeeded");
        } catch {
            _pass("stale timestamp correctly reverts (AttestationExpired)");
        }
        vm.stopBroadcast();
    }

    /// @notice Call getMirrors with out-of-bounds offset → should revert OutOfBounds
    function _testOutOfBoundsPagination() internal view {
        CanonicalFactory factory = CanonicalFactory(BNB_FACTORY);

        try factory.getMirrors(1000, 10) returns (address[] memory) {
            _fail("out-of-bounds pagination", "should have reverted");
        } catch {
            _pass("getMirrors(1000, 10) correctly reverts (OutOfBounds)");
        }
    }
}

// ═══════════════════════════════════════════════════════════════
//  NEW DEPLOY TEST — Deploy a fresh mirror with a new origin
// ═══════════════════════════════════════════════════════════════
contract TestNewDirectDeploy is TestBase {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        console.log("=== NEW DIRECT DEPLOY TEST (BNB Testnet) ===");
        console.log("Chain ID:", block.chainid);
        console.log("");

        CanonicalFactory factory = CanonicalFactory(BNB_FACTORY);

        // Use a random "origin" address to simulate a new RWA deployment
        address newOrigin = address(uint160(uint256(keccak256(abi.encode(block.timestamp, "test-origin-v2")))));
        console.log("New origin address:", newOrigin);

        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: newOrigin,
            originChainId: FUJI_CHAIN_ID,
            targetChainId: BNB_CHAIN_ID,
            navRoot: keccak256("nav-test"),
            complianceRoot: keccak256("comp-test"),
            lockedAmount: 500_000 ether,
            timestamp: block.timestamp,
            nonce: 1
        });

        // Pre-compute expected address
        address expected = factory.computeMirrorAddress(att);
        console.log("Expected mirror address:", expected);

        // Count before
        uint256 countBefore = factory.getMirrorCount();
        console.log("Mirror count before:", countBefore);

        // Sign and deploy
        (bytes memory sigs, uint256 bitmap) = _sign3of5(att, BNB_ATT_REG);

        vm.startBroadcast(deployerKey);
        address mirror = factory.deployMirrorDirect(att, sigs, bitmap);
        vm.stopBroadcast();

        console.log("Deployed mirror:", mirror);

        // Verify
        uint256 countAfter = factory.getMirrorCount();
        bool addressMatch = mirror == expected;
        bool canonical = factory.isCanonical(mirror);
        bool countInc = countAfter == countBefore + 1;

        if (addressMatch) _pass("deployed address matches predicted address");
        else _fail("address match", "mismatch");

        if (canonical) _pass("new mirror isCanonical = true");
        else _fail("isCanonical", "expected true");

        if (countInc) _pass(string.concat("mirrorCount incremented to ", vm.toString(countAfter)));
        else _fail("mirrorCount", "did not increment");

        // Check token metadata
        XythumToken token = XythumToken(mirror);
        bool nameOk = keccak256(bytes(token.name())) == keccak256("Xythum Mirror");
        bool originOk = token.originContract() == newOrigin;
        bool capOk = token.mintCap() == 500_000 ether;

        if (nameOk) _pass("new mirror name = 'Xythum Mirror'");
        else _fail("name", "wrong");
        if (originOk) _pass("new mirror originContract matches");
        else _fail("originContract", "mismatch");
        if (capOk) _pass("new mirror mintCap = 500,000 tokens");
        else _fail("mintCap", "wrong");

        console.log("");
        console.log("=== NEW DIRECT DEPLOY TEST DONE ===");
    }
}

// ═══════════════════════════════════════════════════════════════
//  CCIP CONFIG VERIFICATION
// ═══════════════════════════════════════════════════════════════
contract TestCCIPConfig is TestBase {
    // CCIP chain selectors
    uint64 constant FUJI_SELECTOR = 14767482510784806043;
    uint64 constant BNB_SELECTOR  = 13264668187771770619;

    function run() external view {
        console.log("=== CCIP CONFIGURATION TEST ===");
        console.log("Chain ID:", block.chainid);
        console.log("");

        if (block.chainid == FUJI_CHAIN_ID) {
            _testFujiCCIPSender();
        } else if (block.chainid == BNB_CHAIN_ID) {
            _testBnbCCIPSender();
        }

        console.log("");
        console.log("=== CCIP CONFIG TEST DONE ===");
    }

    function _testFujiCCIPSender() internal view {
        console.log("Testing Fuji CCIPSender -> BNB:");

        // Check supported chain
        (bool success, bytes memory data) = FUJI_CCIP_SENDER.staticcall(
            abi.encodeWithSignature("supportedChains(uint64)", BNB_SELECTOR)
        );
        if (success && abi.decode(data, (bool))) {
            _pass("BNB chain selector is supported on Fuji CCIPSender");
        } else {
            _fail("BNB supported", "not supported");
        }

        // Check receiver
        (success, data) = FUJI_CCIP_SENDER.staticcall(
            abi.encodeWithSignature("allowedReceivers(uint64)", BNB_SELECTOR)
        );
        if (success) {
            address recv = abi.decode(data, (address));
            console.log("    Receiver for BNB:", recv);
            if (recv == BNB_CCIP_RECV) {
                _pass("Fuji CCIPSender points to correct BNB CCIPReceiver");
            } else {
                _fail("receiver", "wrong address");
                console.log("    Expected:", BNB_CCIP_RECV);
            }
        }
    }

    function _testBnbCCIPSender() internal view {
        console.log("Testing BNB CCIPSender -> Fuji:");

        (bool success, bytes memory data) = BNB_CCIP_SENDER.staticcall(
            abi.encodeWithSignature("supportedChains(uint64)", FUJI_SELECTOR)
        );
        if (success && abi.decode(data, (bool))) {
            _pass("Fuji chain selector is supported on BNB CCIPSender");
        } else {
            _fail("Fuji supported", "not supported");
        }

        (success, data) = BNB_CCIP_SENDER.staticcall(
            abi.encodeWithSignature("allowedReceivers(uint64)", FUJI_SELECTOR)
        );
        if (success) {
            address recv = abi.decode(data, (address));
            console.log("    Receiver for Fuji:", recv);
            if (recv == FUJI_CCIP_RECV) {
                _pass("BNB CCIPSender points to correct Fuji CCIPReceiver");
            } else {
                _fail("receiver", "wrong address");
                console.log("    Expected:", FUJI_CCIP_RECV);
            }
        }
    }
}
