// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { RWALockEscrow } from "../src/escrow/RWALockEscrow.sol";

/// @title DeployEscrow
/// @notice Deploys an RWALockEscrow on the active chain. One escrow per chain.
///         Reuses the SignerRegistry already deployed for the AttestationRegistry —
///         pulled from the env so the receipts the signer set produces remain
///         consumable across the whole protocol stack.
/// @dev    Run per chain:
///           # Fuji
///           forge script script/DeployEscrow.s.sol \
///             --rpc-url $RPC_AVALANCHE_FUJI --broadcast \
///             --sig "run(address,address)" $SIGNER_REGISTRY_FUJI $DEPLOYER
///           # BNB
///           forge script script/DeployEscrow.s.sol \
///             --rpc-url $RPC_BNB_TESTNET --broadcast \
///             --sig "run(address,address)" $SIGNER_REGISTRY_BNB $DEPLOYER
///           # Monad
///           forge script script/DeployEscrow.s.sol \
///             --rpc-url $RPC_MONAD_TESTNET --broadcast \
///             --sig "run(address,address)" $SIGNER_REGISTRY_MONAD $DEPLOYER
///
///         After each run, paste the printed escrow address into
///         frontend/src/lib/contracts.ts under the chain's `lockEscrow` field.
contract DeployEscrowScript is Script {
    /// @notice Default staleness (matches AttestationRegistry's typical setting).
    uint256 public constant DEFAULT_MAX_STALENESS = 1 days;

    /// @param signerRegistry The existing SignerRegistry on this chain
    /// @param initialOwner   Address that can pause / rescue stuck tokens
    function run(address signerRegistry, address initialOwner) external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== Xythum -- Deploy RWALockEscrow ===");
        console.log("ChainId:        ", block.chainid);
        console.log("Deployer:       ", deployer);
        console.log("SignerRegistry: ", signerRegistry);
        console.log("InitialOwner:   ", initialOwner);
        console.log("MaxStaleness:   ", DEFAULT_MAX_STALENESS);

        // Predict the escrow address before deploying.
        bytes memory creationCode = abi.encodePacked(
            type(RWALockEscrow).creationCode,
            abi.encode(signerRegistry, DEFAULT_MAX_STALENESS, initialOwner)
        );
        // Predict CREATE address (not CREATE2): keccak256(rlp(deployer, nonce))[12:]
        // We don't have rlp easily here, so just warn on the post-deploy address instead.

        vm.startBroadcast(deployerKey);

        RWALockEscrow escrow =
            new RWALockEscrow(signerRegistry, DEFAULT_MAX_STALENESS, initialOwner);

        vm.stopBroadcast();

        console.log("");
        console.log(">>> RWALockEscrow:", address(escrow));
        console.log("");

        // ─── Replay-domain safety check ────────────────────────────────
        // The EIP-712 domain pins {chainId, verifyingContract}. If a user
        // deploys two escrows at the SAME address on TWO chains, signed
        // UnlockReceipts on one chain become consumable on the other. The
        // domain check catches the chainId difference, but if the deployer
        // ever deploys at a colliding address (same nonce + same EOA) the
        // domains still differ via chainId — so this is "informational"
        // rather than a hard failure. We warn loudly so operators audit it.
        console.log("[Replay-domain check]");
        console.log(
            "  EIP-712 domain pins chainId AND verifyingContract."
        );
        console.log(
            "  Verify on a block explorer that NO contract at this same"
        );
        console.log("  address on any OTHER chain is a Xythum escrow.");
        console.log("  If it is, do NOT proceed.  Use a different deployer");
        console.log("  EOA or nonce to land at a different address.");
        console.log("");
        console.log("Bytecode hash (audit aid):", uint256(keccak256(creationCode)));
        console.log("");
        console.log("Update frontend/src/lib/contracts.ts:");
        console.log("  <chain>.lockEscrow = ", address(escrow));
    }

    /// @notice Convenience overload that takes only the SignerRegistry address;
    ///         uses the deployer as the initial owner.
    function run(address signerRegistry) external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== Xythum -- Deploy RWALockEscrow (deployer-owned) ===");
        console.log("ChainId:        ", block.chainid);
        console.log("Deployer:       ", deployer);
        console.log("SignerRegistry: ", signerRegistry);

        vm.startBroadcast(deployerKey);
        RWALockEscrow escrow = new RWALockEscrow(signerRegistry, DEFAULT_MAX_STALENESS, deployer);
        vm.stopBroadcast();

        console.log(">>> RWALockEscrow:", address(escrow));
    }
}
