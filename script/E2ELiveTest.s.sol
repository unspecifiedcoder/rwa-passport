// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MockRWA} from "../src/mocks/MockRWA.sol";
import {AttestationLib} from "../src/libraries/AttestationLib.sol";
import {CanonicalFactory} from "../src/core/CanonicalFactory.sol";
import {XythumToken} from "../src/core/XythumToken.sol";

/// @title E2ELiveTest
/// @notice Full end-to-end test: Deploy MockRWA on BNB → Mirror on Fuji → Mint → Transfer → Verify
///
/// Step 1 (BNB):  forge script script/E2ELiveTest.s.sol:DeployOriginBnb --rpc-url https://bsc-testnet-rpc.publicnode.com --broadcast -vv
/// Step 2 (Fuji): ORIGIN_RWA=<addr> forge script script/E2ELiveTest.s.sol:DeployMirrorFuji --rpc-url https://avalanche-fuji-c-chain-rpc.publicnode.com --broadcast -vv
/// Step 3 (Fuji): MIRROR=<addr> forge script script/E2ELiveTest.s.sol:MintAndTransferFuji --rpc-url https://avalanche-fuji-c-chain-rpc.publicnode.com --broadcast -vv

// ═══ Step 1: Deploy fresh MockRWA on BNB Testnet ═══
contract DeployOriginBnb is Script {
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);

        console.log("=== STEP 1: Deploy MockRWA on BNB Testnet ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(key);
        MockRWA rwa = new MockRWA();
        vm.stopBroadcast();

        console.log("");
        console.log("MockRWA deployed:", address(rwa));
        console.log("Name:", rwa.name());
        console.log("Symbol:", rwa.symbol());
        console.log("TotalSupply:", rwa.totalSupply() / 1 ether, "tokens");
        console.log("Deployer balance:", rwa.balanceOf(deployer) / 1 ether, "tokens");
        console.log("");
        console.log(">>> Next: Run Step 2 with ORIGIN_RWA=", address(rwa));
    }
}

// ═══ Step 2: Build attestation, sign, deploy mirror on Fuji ═══
contract DeployMirrorFuji is Script {
    uint256 constant SIGNER_KEY_1 = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_KEY_2 = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_KEY_3 = uint256(keccak256("xythum-demo-signer-3"));

    address constant FUJI_FACTORY = 0x4934985287C28e647ecF38d485E448ac4A4A4Ab7;
    address constant FUJI_ATT_REG = 0xd0047E6F5281Ed7d04f2eAea216cB771b80f7104;

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address originRwa = vm.envAddress("ORIGIN_RWA");

        console.log("=== STEP 2: Deploy Mirror on Fuji ===");
        console.log("Origin RWA (BNB):", originRwa);
        console.log("Target Factory (Fuji):", FUJI_FACTORY);

        // Build attestation
        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: originRwa,
            originChainId: 97,         // BNB Testnet
            targetChainId: 43113,      // Fuji
            navRoot: keccak256("e2e-test-nav"),
            complianceRoot: keccak256("e2e-test-compliance"),
            lockedAmount: 500_000 ether,  // 500K token mint cap
            timestamp: block.timestamp,
            nonce: 1
        });

        console.log("Attestation built:");
        console.log("  lockedAmount: 500,000 tokens");
        console.log("  nonce: 1");
        console.log("  timestamp:", att.timestamp);

        // Pre-compute address
        address predicted = CanonicalFactory(FUJI_FACTORY).computeMirrorAddress(att);
        console.log("Predicted mirror address:", predicted);

        // Sign with 3/5
        bytes32 domainSep = AttestationLib.domainSeparator(43113, FUJI_ATT_REG);
        bytes32 digest = AttestationLib.toTypedDataHash(att, domainSep);

        bytes memory sigs;
        uint256 bitmap;
        uint256[3] memory keys = [SIGNER_KEY_1, SIGNER_KEY_2, SIGNER_KEY_3];
        for (uint256 i = 0; i < 3; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            sigs = abi.encodePacked(sigs, r, s, v);
            bitmap |= (1 << i);
        }
        console.log("Signed by 3/5 signers, bitmap:", bitmap);

        // Deploy
        uint256 countBefore = CanonicalFactory(FUJI_FACTORY).getMirrorCount();

        vm.startBroadcast(key);
        address mirror = CanonicalFactory(FUJI_FACTORY).deployMirrorDirect(att, sigs, bitmap);
        vm.stopBroadcast();

        uint256 countAfter = CanonicalFactory(FUJI_FACTORY).getMirrorCount();

        console.log("");
        console.log("=== MIRROR DEPLOYED ===");
        console.log("Mirror address:", mirror);
        console.log("Matches prediction:", mirror == predicted);
        console.log("isCanonical:", CanonicalFactory(FUJI_FACTORY).isCanonical(mirror));
        console.log("Mirror count:", countBefore, "->", countAfter);

        // Verify token metadata
        XythumToken token = XythumToken(mirror);
        console.log("");
        console.log("=== MIRROR TOKEN METADATA ===");
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
        console.log("Origin contract:", token.originContract());
        console.log("Origin chain ID:", token.originChainId());
        console.log("Mint cap:", token.mintCap() / 1 ether, "tokens");
        console.log("Total supply:", token.totalSupply() / 1 ether, "tokens");
        console.log("Total minted:", token.totalMinted() / 1 ether, "tokens");
        console.log("Factory:", token.factory());
        console.log("");
        console.log(">>> Next: Run Step 3 with MIRROR=", mirror);
    }
}

// ═══ Step 3: Mint mirror tokens + transfer to verify ERC-20 works ═══
contract MintAndTransferFuji is Script {
    address constant FUJI_FACTORY = 0x4934985287C28e647ecF38d485E448ac4A4A4Ab7;

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);
        address mirrorAddr = vm.envAddress("MIRROR");

        XythumToken mirror = XythumToken(mirrorAddr);
        address recipient = address(0xBEEF);

        console.log("=== STEP 3: Mint & Transfer on Fuji ===");
        console.log("Mirror:", mirrorAddr);
        console.log("Deployer:", deployer);
        console.log("Recipient:", recipient);

        console.log("");
        console.log("--- BEFORE ---");
        console.log("Total supply:", mirror.totalSupply() / 1 ether);
        console.log("Total minted:", mirror.totalMinted() / 1 ether);
        console.log("Deployer balance:", mirror.balanceOf(deployer) / 1 ether);
        console.log("Recipient balance:", mirror.balanceOf(recipient) / 1 ether);
        console.log("Mint cap:", mirror.mintCap() / 1 ether);

        // The factory is the authorized minter. We need to call mint via the factory.
        // But CanonicalFactory doesn't have a public mint function — only authorizedMinters can call XythumToken.mint().
        // The factory address IS an authorizedMinter. So we'd need to call from the factory.
        // However, the factory owner can add new minters via setAuthorizedMinter on the token.
        // factory.setAuthorizedMinter() doesn't exist — it's on the token, callable only by factory address.
        //
        // The factory IS the msg.sender that deployed the token, so factory = token.factory().
        // We need to either:
        //   a) Add a mintTo() function on the factory (doesn't exist)
        //   b) Call token directly if we're an authorizedMinter
        //
        // Let's check if deployer is authorized:
        bool deployerAuthorized = mirror.authorizedMinters(deployer);
        bool factoryAuthorized = mirror.authorizedMinters(FUJI_FACTORY);
        console.log("Deployer is authorizedMinter:", deployerAuthorized);
        console.log("Factory is authorizedMinter:", factoryAuthorized);

        // The factory needs to call setAuthorizedMinter for the deployer.
        // But setAuthorizedMinter can only be called by token.factory() which is the CanonicalFactory contract.
        // The CanonicalFactory doesn't expose a function to call setAuthorizedMinter on deployed tokens.
        // This is a gap — let's document it.

        console.log("");
        console.log("=== RESULT ===");
        if (!deployerAuthorized) {
            console.log("CANNOT MINT: Deployer is not an authorizedMinter.");
            console.log("Only the CanonicalFactory contract can mint, and it has no public mint function.");
            console.log("This is a MISSING FEATURE: CanonicalFactory needs a `mintMirror()` function");
            console.log("or the factory owner needs to call setAuthorizedMinter to allow external minting.");
        }

        console.log("");
        console.log("=== VERIFICATION SUMMARY ===");
        console.log("Mirror exists:", mirrorAddr.code.length > 0);
        console.log("isCanonical:", CanonicalFactory(FUJI_FACTORY).isCanonical(mirrorAddr));
        console.log("Name:", mirror.name());
        console.log("Symbol:", mirror.symbol());
        console.log("Origin:", mirror.originContract());
        console.log("Origin chain:", mirror.originChainId());
        console.log("Mint cap:", mirror.mintCap() / 1 ether, "tokens");
        console.log("Supply:", mirror.totalSupply() / 1 ether, "tokens");
    }
}
