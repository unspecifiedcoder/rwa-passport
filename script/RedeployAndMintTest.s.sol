// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { AttestationLib } from "../src/libraries/AttestationLib.sol";
import { CanonicalFactory } from "../src/core/CanonicalFactory.sol";
import { AttestationRegistry } from "../src/core/AttestationRegistry.sol";
import { XythumToken } from "../src/core/XythumToken.sol";

/// @title RedeployAndMintTest
/// @notice Redeploy Fuji factory (with mintMirror), deploy mirror, mint tokens, transfer, verify.
///
/// Run: forge script script/RedeployAndMintTest.s.sol:FullE2E --rpc-url https://avalanche-fuji-c-chain-rpc.publicnode.com --broadcast -vv
contract FullE2E is Script {
    uint256 constant SIGNER_KEY_1 = uint256(keccak256("xythum-demo-signer-1"));
    uint256 constant SIGNER_KEY_2 = uint256(keccak256("xythum-demo-signer-2"));
    uint256 constant SIGNER_KEY_3 = uint256(keccak256("xythum-demo-signer-3"));

    address constant FUJI_ATT_REG = 0xd0047E6F5281Ed7d04f2eAea216cB771b80f7104;
    // Use a fresh address that has never been attested (no rate limit)
    address constant ORIGIN_RWA = 0x000000000000000000000000000000000000e2E1;

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);

        console.log("=== FULL E2E: Factory + Mirror + Mint + Transfer ===");

        vm.startBroadcast(key);

        // 1. Deploy factory
        CanonicalFactory factory =
            new CanonicalFactory(FUJI_ATT_REG, address(0), deployer, deployer);
        console.log("1. Factory:", address(factory));

        // 2. Build & sign attestation, deploy mirror
        address mirror = _deployMirror(factory);

        // 3. Mint + Transfer + Verify
        _mintAndVerify(factory, mirror, deployer);

        vm.stopBroadcast();
        console.log("");
        console.log("=== E2E COMPLETE ===");
    }

    function _deployMirror(CanonicalFactory factory) internal returns (address) {
        AttestationLib.Attestation memory att = AttestationLib.Attestation({
            originContract: ORIGIN_RWA,
            originChainId: 97,
            targetChainId: 43113,
            navRoot: keccak256("e2e-full-nav"),
            complianceRoot: keccak256("e2e-full-comp"),
            lockedAmount: 500_000 ether,
            timestamp: block.timestamp,
            nonce: 2
        });

        (bytes memory sigs, uint256 bitmap) = _sign(att);
        console.log("2. Signed (bitmap:", bitmap, ")");

        address predicted = factory.computeMirrorAddress(att);
        address mirror = factory.deployMirrorDirect(att, sigs, bitmap);
        console.log("3. Mirror:", mirror);
        console.log("   Predicted match:", mirror == predicted);
        console.log("   isCanonical:", factory.isCanonical(mirror));
        return mirror;
    }

    function _mintAndVerify(CanonicalFactory factory, address mirror, address deployer) internal {
        XythumToken token = XythumToken(mirror);
        address recipient = address(0xCAFE);

        // Mint via factory
        factory.mintMirror(mirror, deployer, 10_000 ether);
        console.log("4. Minted 10,000 xRWA to deployer");
        _logBalances(token, deployer, recipient);

        // Transfer
        token.transfer(recipient, 2_500 ether);
        console.log("5. Transferred 2,500 xRWA to 0xCAFE");
        _logBalances(token, deployer, recipient);

        // Authorize deployer as direct minter
        factory.setMirrorMinter(mirror, deployer, true);
        token.mint(recipient, 1_000 ether);
        console.log("6. Direct-minted 1,000 xRWA to 0xCAFE");
        _logBalances(token, deployer, recipient);

        // Metadata
        console.log("   Name:", token.name());
        console.log("   Symbol:", token.symbol());
        console.log("   Origin:", token.originContract());
        console.log("   OriginChain:", token.originChainId());
        console.log("   MintCap:", token.mintCap() / 1 ether);
    }

    function _logBalances(XythumToken token, address a, address b) internal view {
        console.log("   Deployer bal:", token.balanceOf(a) / 1 ether);
        console.log("   Recipient bal:", token.balanceOf(b) / 1 ether);
        console.log("   Total supply:", token.totalSupply() / 1 ether);
    }

    function _sign(AttestationLib.Attestation memory att)
        internal
        pure
        returns (bytes memory sigs, uint256 bitmap)
    {
        bytes32 domainSep = AttestationLib.domainSeparator(43113, FUJI_ATT_REG);
        bytes32 digest = AttestationLib.toTypedDataHash(att, domainSep);
        uint256[3] memory keys = [SIGNER_KEY_1, SIGNER_KEY_2, SIGNER_KEY_3];
        for (uint256 i = 0; i < 3; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            sigs = abi.encodePacked(sigs, r, s, v);
            bitmap |= (1 << i);
        }
    }
}
