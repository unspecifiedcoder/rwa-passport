# Xythum RWA Passport - Architecture

## Overview

Xythum RWA Passport is a cross-chain canonical mirror system for Real-World Assets (RWAs). It creates deterministic, verifiable ERC-20 mirror tokens on any EVM chain, backed by threshold-signed attestations, with built-in compliance, Uniswap V4 liquidity hooks, and zero-knowledge collateral proofs.

## System Diagram

```
Source Chain                           Target Chain(s)
+------------------+                  +------------------+
| ERC-3643 RWA     |                  | XythumToken      |
| (Real Asset)     |                  | (Canonical Mirror)|
+--------+---------+                  +--------+---------+
         |                                     ^
    [1. Attestation]                    [4. CREATE2 Deploy]
         |                                     |
+--------v---------+    [3. CCIP]    +--------+---------+
| AttestationRegistry| ------------> | CanonicalFactory |
| (Verify Threshold |               | (Deterministic)  |
|  Signatures)     |                +--------+---------+
+--------+---------+                         |
         ^                          +--------v---------+
         |                          | RWAHook (V4)     |
+--------+---------+                | - Compliance     |
| SignerRegistry   |                | - Dynamic Fees   |
| (21 signers,     |                | - Pause          |
|  threshold=11)   |                +--------+---------+
+------------------+                         |
                                    +--------v---------+
                                    | LiquidityBootstrap|
                                    | (Auto Pool Create)|
                                    +--------+---------+
                                             |
                                    +--------v---------+
                                    | CollateralVerifier|
                                    | (ZK Groth16)     |
                                    +--------+---------+
                                             |
                                    +--------v---------+
                                    | AaveAdapter      |
                                    | (Receipt Tokens) |
                                    +------------------+
```

## Data Flow

### 1. Attestation Creation

A threshold signer network attests to the state of an RWA on the source chain:

1. Signers observe the source chain RWA contract (ERC-3643)
2. Each signer creates an EIP-712 typed attestation containing:
   - `originContract`: RWA address on source chain
   - `originChainId`: Source chain ID
   - `targetChainId`: Destination chain ID
   - `navRoot`: Merkle root of NAV data
   - `complianceRoot`: Merkle root of compliance data
   - `lockedAmount`: Amount locked on source chain
   - `timestamp`: When attestation was created
   - `nonce`: Monotonically increasing nonce
3. At least `threshold` signers must sign for the attestation to be valid

### 2. Attestation Verification

`AttestationRegistry` verifies the attestation on-chain:

- Recovers ECDSA signers from packed signatures using a bitmap
- Validates each signer is registered and active in `SignerRegistry`
- Ensures the signature count meets the threshold
- Enforces rate limiting (one attestation per origin/target pair per period)
- Stores the verified attestation for later reference

### 3. Cross-Chain Delivery (CCIP)

`CCIPSender` dispatches the verified attestation to the target chain:

- Encodes attestation + signatures as a CCIP message
- Sends via Chainlink CCIP router to the target chain
- `XythumCCIPReceiver` on the target chain decodes and calls `CanonicalFactory`

### 4. Mirror Deployment

`CanonicalFactory` deploys the canonical mirror at a deterministic address:

- Computes CREATE2 salt from `(originContract, originChainId, targetChainId)`
- Deploys `XythumToken` with immutable origin metadata
- The address is deterministic: anyone can predict it before deployment
- Duplicate deployments revert (`MirrorAlreadyDeployed`)

### 5. DEX Liquidity (Uniswap V4)

`RWAHook` + `LiquidityBootstrap` provide automated liquidity:

- `LiquidityBootstrap.createPool(mirror)` initializes a V4 pool
- `RWAHook` enforces on every pool interaction:
  - **Compliance**: `tx.origin` must pass `isCompliant()` check
  - **Dynamic fees**: Fee scales linearly with NAV staleness (5bps fresh, 50bps stale)
  - **Pause**: Owner can pause individual pools

### 6. ZK Collateral Proofs

`CollateralVerifier` + `AaveAdapter` enable private lending:

- User generates a ZK proof: "I control >= $X of asset Y"
- Proof is verified on-chain (Groth16 via `IGroth16Verifier`)
- Nullifier system prevents double-spending of proofs
- `AaveAdapter` mints receipt tokens against verified proofs
- Receipt tokens can be deposited into Aave as collateral

## Contract Dependency Graph

```
SignerRegistry
    |
    v
AttestationRegistry
    |
    v
CanonicalFactory -----> XythumToken (deployed via CREATE2)
    |                        |
    v                        v
CCIPSender/Receiver     RWAHook (Uniswap V4)
                             |
                             v
                        LiquidityBootstrap
                             |
                             v
                        CollateralVerifier <--- IGroth16Verifier
                             |
                             v
                        AaveAdapter
```

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Signature scheme | ECDSA multi-sig | Battle-tested, cheap to verify on-chain. BLS planned for v2 |
| Mirror deployment | CREATE2 | Deterministic addresses enable cross-chain address prediction |
| Compliance | Pluggable `ICompliance` | Supports simple allowlist now, full ERC-3643 T-REX later |
| V4 Hook fees | Dynamic (NAV-staleness) | Incentivizes fresh NAV attestations, protects LPs |
| ZK proofs | Groth16 (mock for MVP) | Mature proving system. Halo2 planned for v2 |
| Cross-chain | Chainlink CCIP | Production-grade message passing with finality guarantees |

## Storage Layout

### SignerRegistry
- `signers[]`: Dynamic array of active signer addresses
- `signerIndex[addr]`: Signer address to array index mapping
- `isActive[addr]`: Whether a signer is active
- `removalCooldown[addr]`: Timestamp when removal was initiated

### AttestationRegistry
- `attestations[pairKey][nonce]`: Stored attestation data
- `latestNonce[pairKey]`: Latest nonce per origin/target pair
- `lastAttestationTime[pairKey]`: Rate limiting timestamp

### CanonicalFactory
- `mirrors[salt]`: Salt to deployed mirror address
- `mirrorInfo[addr]`: Mirror address to origin metadata

### RWAHook
- `poolConfigs[poolId]`: Per-pool configuration (token, fees, NAV, active)

### CollateralVerifier
- `proofs[proofId]`: Verified proof records
- `usedNullifiers[nullifier]`: Replay protection
- `assetIds[addr]` / `assetAddresses[id]`: Asset registry
