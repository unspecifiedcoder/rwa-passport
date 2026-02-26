# XYTHUM RWA PASSPORT — Detailed RWA Movement Flow

This document explains, step by step, exactly what happens when a Real-World Asset (RWA) token on one chain is "mirrored" to another chain using the Xythum protocol. It covers every contract call, cryptographic operation, and event emitted throughout the process.

---

## Table of Contents

1. [High-Level Overview](#1-high-level-overview)
2. [Actors and Contracts](#2-actors-and-contracts)
3. [Phase A: Origin Setup](#3-phase-a-origin-setup)
4. [Phase B: Attestation Construction](#4-phase-b-attestation-construction)
5. [Phase C: EIP-712 Threshold Signing](#5-phase-c-eip-712-threshold-signing)
6. [Phase D: Delivery — Two Paths](#6-phase-d-delivery--two-paths)
   - [Path 1: Direct Deploy (Instant)](#path-1-direct-deploy-instant)
   - [Path 2: CCIP Relay (~20 min)](#path-2-ccip-relay-20-min)
7. [Phase E: On-Chain Verification](#7-phase-e-on-chain-verification)
8. [Phase F: CREATE2 Mirror Deployment](#8-phase-f-create2-mirror-deployment)
9. [Phase G: Post-Deployment — Trading](#9-phase-g-post-deployment--trading)
10. [Phase H: ZK Collateral & DeFi Integration](#10-phase-h-zk-collateral--defi-integration)
11. [Address Determinism Deep Dive](#11-address-determinism-deep-dive)
12. [Security Properties](#12-security-properties)

---

## 1. High-Level Overview

```
Source Chain (e.g. Fuji)           Target Chain (e.g. BNB Testnet)
┌──────────────────────┐           ┌───────────────────────────────┐
│  ERC-20 RWA Token    │           │  XythumToken (mirror)         │
│  (e.g. mTBILL)       │           │  deployed at deterministic    │
│                      │           │  CREATE2 address              │
│  Tokens are "locked" │   ───►    │  Mirror tokens can be minted  │
│  (conceptually)      │           │  up to lockedAmount cap       │
└──────────────────────┘           └───────────────────────────────┘
         │                                      ▲
         │                                      │
    3/5 signers                          CanonicalFactory
    attest to state                    deploys the mirror
```

The core idea: a **threshold signer network** (3 of 5 signers) observes the RWA state on the source chain, produces a cryptographic **attestation**, and either delivers it directly or relays it via Chainlink CCIP to the target chain. On the target chain, the attestation is verified on-chain and a **canonical mirror token** is deployed at a mathematically predetermined address.

---

## 2. Actors and Contracts

### Actors
| Actor | Role |
|-------|------|
| **RWA Issuer** | Deploys the original ERC-20 RWA token on the source chain |
| **Signer Network** | 5 registered ECDSA key holders; any 3 can produce a valid attestation |
| **Deployer** | Anyone who submits the signed attestation to trigger mirror deployment |
| **Trader/LP** | Interacts with the mirror token on the target chain (swaps, liquidity) |

### Contracts (per chain)
| Contract | Purpose |
|----------|---------|
| `SignerRegistry` | Stores the 5 authorized signer addresses + threshold (3) |
| `AttestationRegistry` | Verifies EIP-712 signatures, stores attestation records, enforces rate limits |
| `CanonicalFactory` | Deploys XythumToken mirrors via CREATE2, maintains canonical registry |
| `CCIPSender` | (Source only) Wraps attestation into a CCIP message and sends it cross-chain |
| `CCIPReceiver` | (Target only) Receives CCIP messages and calls CanonicalFactory |
| `XythumToken` | The mirror ERC-20 with compliance enforcement, mint cap, origin metadata |
| `RWAHook` | Uniswap V4 hook enforcing compliance + dynamic fees on mirror pools |
| `CollateralVerifier` | Verifies ZK proofs of collateral (Groth16) |
| `AaveAdapter` | Bridges ZK-verified collateral into DeFi lending |

---

## 3. Phase A: Origin Setup

**What happens:** An ERC-20 RWA token exists (or is deployed) on the source chain.

```
Source Chain:
  1. RWA Issuer deploys ERC-20 token (e.g. MockRWA "mTBILL")
     → constructor mints 1,000,000 tokens to the issuer
     → contract deployed at address X (e.g. 0xD52b37AD...on Fuji)

  2. The origin contract address + source chain ID become the
     unique identity of this RWA in the Xythum protocol.
```

**Frontend (Step 1 in `/attest` page):**
- User can use a pre-deployed MockRWA or deploy a fresh one
- `useDeployContract()` sends the MockRWA bytecode on-chain
- Once confirmed, the new contract address becomes `originContract`

**Key point:** The Xythum protocol does NOT actually lock tokens in an escrow contract (in this MVP). The attestation's `lockedAmount` is a **claim** signed by the signer network that a certain amount is locked/reserved for mirroring. In production, this would be backed by a real lock mechanism.

---

## 4. Phase B: Attestation Construction

**What happens:** An attestation struct is assembled from the RWA state.

The `AttestationLib.Attestation` struct contains 8 fields:

```solidity
struct Attestation {
    address originContract;   // RWA token address on source chain
    uint256 originChainId;    // Source chain ID (e.g. 43113 for Fuji)
    uint256 targetChainId;    // Target chain ID (e.g. 97 for BNB Testnet)
    bytes32 navRoot;          // Merkle root of NAV data (price, timestamp, source)
    bytes32 complianceRoot;   // Merkle root of compliance/identity registry
    uint256 lockedAmount;     // Total supply locked for this target chain (in wei)
    uint256 timestamp;        // Attestation creation time (unix seconds)
    uint256 nonce;            // Monotonically increasing per (origin, target) pair
}
```

**Frontend (Step 2 in `/attest` page):**
```typescript
const att: Attestation = {
  originContract: "0xD52b37AD...",        // from Step 1
  originChainId: 43113n,                   // Fuji
  targetChainId: 97n,                      // BNB Testnet
  navRoot: keccak256(toHex("demo-nav")),   // placeholder Merkle root
  complianceRoot: keccak256(toHex("demo")),// placeholder Merkle root
  lockedAmount: parseEther("1000000"),     // 1M tokens
  timestamp: BigInt(Math.floor(Date.now() / 1000)),
  nonce: 3n,                               // must be unique per pair
};
```

**Critical fields explained:**
- `originContract + originChainId + targetChainId` → uniquely identifies this mirror pair. Used to compute the deterministic CREATE2 salt.
- `lockedAmount` → becomes the `mintCap` of the deployed XythumToken. No more than this amount can ever be minted on the target chain.
- `nonce` → prevents replay. Each attestation for the same origin/target pair must have a unique nonce.
- `timestamp` → used for staleness checks. AttestationRegistry rejects attestations older than `maxStaleness` (default: 24 hours).

---

## 5. Phase C: EIP-712 Threshold Signing

**What happens:** 3 out of 5 authorized signers produce ECDSA signatures over the attestation using EIP-712 typed structured data.

### Step-by-step:

#### 1. Compute the EIP-712 Domain Separator

The domain separator binds the signature to a **specific chain and contract**:

```solidity
bytes32 DOMAIN_SEPARATOR = keccak256(abi.encode(
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
    keccak256("Xythum RWA Passport"),  // protocol name
    keccak256("1"),                     // version
    TARGET_CHAIN_ID,                    // e.g. 97 (BNB Testnet) — NOT the source chain!
    ATTESTATION_REGISTRY_ADDRESS        // on the TARGET chain
));
```

**Critical:** The domain separator uses the **target** chain's ID and the target chain's `AttestationRegistry` address. This is because the signatures will be verified on the target chain. If a signer accidentally signs against the wrong chain ID, the recovered address will not match, and verification will fail.

#### 2. Compute the Struct Hash

```solidity
bytes32 structHash = keccak256(abi.encode(
    keccak256("Attestation(address originContract,uint256 originChainId,uint256 targetChainId,bytes32 navRoot,bytes32 complianceRoot,uint256 lockedAmount,uint256 timestamp,uint256 nonce)"),
    att.originContract,
    att.originChainId,
    att.targetChainId,
    att.navRoot,
    att.complianceRoot,
    att.lockedAmount,
    att.timestamp,
    att.nonce
));
```

#### 3. Compute the EIP-712 Digest

```solidity
bytes32 digest = keccak256(abi.encodePacked(
    "\x19\x01",          // EIP-712 prefix
    DOMAIN_SEPARATOR,    // chain + contract binding
    structHash           // attestation data
));
```

This `digest` is the 32-byte value that each signer signs with their private key.

#### 4. Each Signer Produces an ECDSA Signature

Each of the 3 selected signers calls `signTypedData()` (or `vm.sign()` in Foundry):

```
Signer 0: (r0, s0, v0) = sign(privateKey0, digest) → 65 bytes
Signer 1: (r1, s1, v1) = sign(privateKey1, digest) → 65 bytes
Signer 2: (r2, s2, v2) = sign(privateKey2, digest) → 65 bytes
```

#### 5. Pack Signatures + Build Bitmap

Signatures are concatenated into a single `bytes` blob:
```
signatures = r0 || s0 || v0 || r1 || s1 || v1 || r2 || s2 || v2
           = 65 + 65 + 65 = 195 bytes total
```

The `signerBitmap` is a `uint256` where bit `i` is set if signer at index `i` signed:
```
Signers 0, 1, 2 signed → bitmap = 0b111 = 7
```

**Frontend (Step 3 in `/attest` page):**
```typescript
const result = await signAttestation(att, targetChainId, attRegistryAddress);
// result.signatures = "0x..." (195 bytes packed)
// result.signerBitmap = 7n (bits 0,1,2)
```

The `signing.ts` utility uses viem's `privateKeyToAccount().signTypedData()` with the 5 demo signer keys (deterministic `keccak256("xythum-demo-signer-N")`). In production, this would be an off-chain signing service.

---

## 6. Phase D: Delivery — Two Paths

The signed attestation now needs to reach the target chain. There are two paths:

### Path 1: Direct Deploy (Instant)

```
User's Wallet (on target chain)
      │
      ▼
CanonicalFactory.deployMirrorDirect(att, signatures, signerBitmap)
      │
      ├─ Checks att.targetChainId == block.chainid
      ├─ Calls _deployMirrorInternal(att, signatures, signerBitmap)
      │      │
      │      ├─ Fee check (0 for MVP)
      │      ├─ Compute salt, check not already deployed
      │      ├─ attestationRegistry.verifyAttestation(att, sigs, bitmap) ◄── FULL VERIFICATION
      │      ├─ CREATE2 deploy XythumToken
      │      ├─ Register mirror in all mappings + allMirrors[]
      │      └─ Emit MirrorDeployed event
      │
      └─ Returns mirror address
```

**How it works:**
1. User switches wallet to the **target chain** (e.g. BNB Testnet)
2. User calls `CanonicalFactory.deployMirrorDirect()` with the attestation + signatures
3. The factory first validates `att.targetChainId == block.chainid` (prevents submitting a Fuji-targeted attestation on BNB)
4. Delegates to `_deployMirrorInternal()` which does the full verification and deployment
5. Mirror is deployed in the same transaction (~5 seconds)

**Advantages:** Instant, simple, one transaction.
**Requirement:** User must have gas on the target chain.

### Path 2: CCIP Relay (~20 min)

```
User's Wallet (on source chain)                    Target Chain
      │
      ▼
CCIPSender.sendAttestation(chainSelector, att, sigs, bitmap)
      │
      ├─ Validates chain is supported
      ├─ Validates receiver is set for this chain
      ├─ Encodes payload: abi.encode(MESSAGE_TYPE_DEPLOY, abi.encode(att), sigs, bitmap)
      ├─ Builds CCIP message (receiver, data, gasLimit=1.5M)
      ├─ Gets fee estimate from CCIP Router
      ├─ Sends via ccipRouter.ccipSend{value: fee}()
      ├─ Refunds excess fee to user
      └─ Emits AttestationSent(messageId, chainSelector, originContract, nonce)
                │
                │  ~~~ Chainlink CCIP Network (20-35 min) ~~~
                │
                ▼
      XythumCCIPReceiver._ccipReceive(message)
            │
            ├─ Validates sender is allowed (trusted CCIPSender on source chain)
            ├─ Replay protection (messageId not already processed)
            ├─ Decodes payload → (messageType, attEncoded, signatures, bitmap)
            ├─ Routes by messageType (DEPLOY=1)
            └─ try factory.deployMirror(att, sigs, bitmap)
                  │
                  └─ Same _deployMirrorInternal() as Direct path
                        ├─ Verify attestation signatures
                        ├─ CREATE2 deploy
                        ├─ Register mirror
                        └─ Emit MirrorDeployed + MirrorDeployedViaCCIP
```

**How it works:**
1. User stays on the **source chain** (e.g. Fuji)
2. User calls `CCIPSender.sendAttestation()` with CCIP fee (~0.13 AVAX)
3. CCIPSender encodes the payload and sends it via the Chainlink CCIP Router
4. CCIP's decentralized oracle network relays the message cross-chain (20-35 min on testnet)
5. CCIPReceiver on the target chain receives the message
6. CCIPReceiver decodes the payload and calls `CanonicalFactory.deployMirror()`
7. The factory does the same full verification as the Direct path
8. Mirror is deployed automatically — no user action needed on the target chain

**Advantages:** User doesn't need gas on the target chain. Automated.
**Disadvantages:** 20-35 minute delay. Costs CCIP fee.

**Both paths produce the same mirror at the same deterministic address** — the path doesn't affect the outcome.

---

## 7. Phase E: On-Chain Verification

Regardless of which path is used, `AttestationRegistry.verifyAttestation()` is called on the target chain. This is the security gate.

```
verifyAttestation(att, signatures, signerBitmap)
   │
   ├─ 1. STALENESS CHECK
   │     if (block.timestamp > att.timestamp + maxStaleness) → revert AttestationExpired
   │     (default maxStaleness = 24 hours)
   │
   ├─ 2. RATE LIMIT CHECK
   │     pairKey = keccak256(originContract, originChainId, targetChainId)
   │     if (lastAttestationTime[pairKey] + rateLimitPeriod > now) → revert RateLimited
   │     (default rateLimitPeriod = 1 hour)
   │
   ├─ 3. THRESHOLD CHECK
   │     Count set bits in signerBitmap using Brian Kernighan's algorithm
   │     if (bitCount < signerRegistry.getThreshold()) → revert InsufficientSignatures
   │     (threshold = 3)
   │
   ├─ 4. REPLAY CHECK
   │     attId = keccak256(originContract, originChainId, targetChainId, nonce)
   │     if (_attestations[attId].timestamp != 0) → revert AttestationAlreadyExists
   │
   ├─ 5. SIGNATURE VERIFICATION (the core cryptographic check)
   │     digest = EIP-712 digest (computed from att + DOMAIN_SEPARATOR)
   │     signers = signerRegistry.getSignerSet() → [addr0, addr1, addr2, addr3, addr4]
   │
   │     For each bit i set in signerBitmap:
   │       Extract 65 bytes from signatures at offset (r=32, s=32, v=1)
   │       recovered = ECDSA.recover(digest, sig)
   │       if (recovered != signers[i]) → revert InvalidSignature
   │
   │     Example with bitmap=7 (bits 0,1,2):
   │       Bit 0 set → extract sig[0:65]  → recover → must equal signers[0]
   │       Bit 1 set → extract sig[65:130] → recover → must equal signers[1]
   │       Bit 2 set → extract sig[130:195] → recover → must equal signers[2]
   │
   ├─ 6. STORE ATTESTATION
   │     _attestations[attId] = att
   │     latestAttestation[pairKey] = attId
   │     lastAttestationTime[pairKey] = block.timestamp
   │
   └─ 7. EMIT EVENT
         emit AttestationVerified(attId, originContract, originChainId, targetChainId, timestamp)
```

**Security guarantees at this point:**
- The attestation is fresh (not stale)
- It hasn't been submitted before (no replay)
- The origin/target pair hasn't had an attestation within the rate limit window
- At least 3 of the 5 registered signers produced valid ECDSA signatures over the exact attestation data, bound to this specific chain and contract via EIP-712

---

## 8. Phase F: CREATE2 Mirror Deployment

After verification passes, `CanonicalFactory._deployMirrorInternal()` deploys the mirror token.

### Step 1: Compute the CREATE2 Salt

```solidity
bytes32 salt = keccak256(abi.encode(
    att.originContract,   // e.g. 0xD52b37AD...
    att.originChainId,    // e.g. 43113
    att.targetChainId     // e.g. 97
));
```

The salt depends **only** on the origin identity + target chain. This means:
- The same origin on different target chains gets different mirrors
- Re-attesting the same origin/target pair with a different nonce will revert (mirror already deployed)
- **Exactly one mirror per (originContract, originChainId, targetChainId) triple**

### Step 2: Build the Creation Code

```solidity
bytes memory creationCode = abi.encodePacked(
    type(XythumToken).creationCode,     // compiled bytecode of XythumToken
    abi.encode(
        "Xythum Mirror",                // name
        "xRWA",                          // symbol
        att.originContract,              // origin address (immutable in token)
        att.originChainId,               // origin chain ID (immutable in token)
        complianceContract,              // compliance check address
        att.lockedAmount                 // mint cap
    )
);
```

The creation code includes the constructor arguments. Since `lockedAmount` is part of the constructor args, different attestations for the same pair (if they somehow passed the duplicate check) would produce different bytecode hashes and thus different addresses.

### Step 3: Deploy via CREATE2

```solidity
assembly {
    mirror := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
    if iszero(mirror) { revert(0, 0) }
}
```

The `CREATE2` opcode computes the deployment address as:

```
address = keccak256(0xff ++ factory_address ++ salt ++ keccak256(creationCode))[12:]
```

This address is **deterministic** — anyone can predict it off-chain before deployment.

### Step 4: Register the Mirror

```solidity
mirrors[salt] = mirror;                    // salt → address mapping
isCanonicalMirror[mirror] = true;          // canonical flag
mirrorInfoMap[mirror] = MirrorInfo({...}); // full metadata
allMirrors.push(mirror);                   // enumeration array

emit MirrorDeployed(mirror, att.originContract, att.originChainId, att.targetChainId, salt);
```

### What the Deployed XythumToken Looks Like

The newly created `XythumToken` has these properties set at construction:

| Property | Value | Storage |
|----------|-------|---------|
| `name` | "Xythum Mirror" | ERC-20 |
| `symbol` | "xRWA" | ERC-20 |
| `originContract` | RWA address from attestation | immutable |
| `originChainId` | Source chain ID from attestation | immutable |
| `factory` | CanonicalFactory address (msg.sender) | immutable |
| `compliance` | Compliance contract address | immutable |
| `mintCap` | `att.lockedAmount` (e.g. 1M tokens) | storage |
| `authorizedMinters[factory]` | `true` | storage |

The factory is the only initial authorized minter. The factory (owner) can add more minters (e.g. CCIP adapters) via `setAuthorizedMinter()`.

---

## 9. Phase G: Post-Deployment — Trading

Once the mirror token exists, it can be traded on Uniswap V4 with RWA-specific rules enforced by the `RWAHook`.

### Pool Initialization

```
LiquidityBootstrap.bootstrapPool(mirror, counterToken, initialPrice)
   │
   └─ Initializes a Uniswap V4 pool with RWAHook attached
      │
      └─ RWAHook.beforeInitialize()
            ├─ Checks factory.isCanonical(token0) or isCanonical(token1)
            │  (at least one token must be a canonical mirror)
            ├─ Stores PoolConfig: xythumToken, baseFee=5bps, staleFee=50bps
            └─ emit PoolConfigured(poolId, xythumToken)
```

### Swap Flow

```
User calls swap on Uniswap V4 PoolManager
   │
   ├─ PoolManager calls RWAHook.beforeSwap(sender, key, params, hookData)
   │      │
   │      ├─ Check pool is not paused
   │      ├─ Decode swapper address:
   │      │    if hookData.length >= 20: swapper = abi.decode(hookData, (address))
   │      │    else: swapper = tx.origin (fallback)
   │      ├─ Check compliance: xythumToken.isCompliant(swapper, swapper)
   │      │    → if compliance contract is set, calls ICompliance.isTransferCompliant()
   │      │    → if compliance == address(0), returns true (disabled)
   │      │    → if not compliant → revert SwapperNotCompliant
   │      └─ Calculate dynamic fee based on NAV staleness:
   │           age = now - lastNAVUpdate
   │           if age ≤ 1 hour  → baseFee (5 bps)
   │           if age ≥ 6 hours → staleFee (50 bps)
   │           between          → linear interpolation
   │           return (selector, ZERO_DELTA, fee | OVERRIDE_FEE_FLAG)
   │
   ├─ Swap executes at the dynamic fee rate
   │
   └─ PoolManager calls RWAHook.afterSwap() → no-op (returns selector + 0)
```

### Transfer Compliance

Every ERC-20 `transfer()` and `transferFrom()` on the XythumToken calls `_update()`, which:

```solidity
function _update(address from, address to, uint256 amount) internal override {
    // Skip compliance on mint (from=0) and burn (to=0)
    if (from != address(0) && to != address(0)) {
        if (!isCompliant(from, to)) {
            revert TransferNotCompliant(from, to);
        }
    }
    super._update(from, to, amount);
}
```

This means **every transfer of the mirror token** is compliance-gated, not just swaps.

---

## 10. Phase H: ZK Collateral & DeFi Integration

The mirror token can be used as collateral in DeFi protocols. The `CollateralVerifier` and `AaveAdapter` enable this with zero-knowledge proofs.

### ZK Proof Flow

```
1. Off-chain: User generates a Groth16 ZK proof proving:
   - They hold collateral backed by an attested RWA
   - The collateral value ≥ minimumValue
   - The NAV price is correct per the attestation's navRoot
   Public inputs: [attestationRoot, assetId, minimumValue, navPrice]

2. On-chain: CollateralVerifier.verifyCollateralProof(proof, publicInputs)
   │
   ├─ Validate 4 public inputs
   ├─ Look up asset address from assetId
   ├─ Compute nullifier = keccak256(proof) → prevent replay
   ├─ Call Groth16Verifier.verifyProof(a, b, c, pubSignals)
   │   (MockVerifier in MVP — always returns true for valid format)
   ├─ Store ProofRecord { prover, asset, minimumValue, navPrice, verifiedAt, active }
   └─ emit CollateralProofVerified(proofId, asset, minimumValue, timestamp)
```

### Aave Integration Flow

```
3. AaveAdapter.depositWithProof(proofId)
   │
   ├─ Get proof details from CollateralVerifier.getCollateralValue(proofId)
   ├─ Check proof freshness (age ≤ maxProofAge)
   ├─ Check proof not already used for deposit
   ├─ Check asset is a canonical mirror: factory.isCanonical(asset)
   ├─ Mint receipt tokens = minimumValue to user
   └─ emit CollateralDeposited(user, proofId, receiptAmount)

   User now holds receipt tokens → deposits them into Aave as collateral
   → borrows against the ZK-proven RWA collateral value

4. AaveAdapter.redeemReceipt(amount)
   │
   ├─ Burns receipt tokens from user
   └─ emit ReceiptRedeemed(user, amount)
```

---

## 11. Address Determinism Deep Dive

The entire protocol revolves around the fact that mirror addresses are **predictable before deployment**. Here's exactly how:

```
Input:
  factory_address = 0x99AB8C07...  (CanonicalFactory on BNB Testnet)
  att = { originContract: 0xD52b37AD..., originChainId: 43113, targetChainId: 97, ... }

Step 1: Compute salt
  salt = keccak256(abi.encode(0xD52b37AD..., 43113, 97))
       = 0x7a3b...

Step 2: Compute initCodeHash
  creationCode = XythumToken.bytecode ++ abi.encode("Xythum Mirror", "xRWA", 0xD52b37AD..., 43113, compliance, lockedAmount)
  initCodeHash = keccak256(creationCode)
               = 0x4f1c...

Step 3: Compute address
  address = keccak256(0xff ++ 0x99AB8C07... ++ 0x7a3b... ++ 0x4f1c...)[12:]
          = 0xD8885030b36DDDf303A8F6Eb3A78A5609432f209
```

This means:
- **Anyone can compute the mirror address before it exists** by calling `factory.computeMirrorAddress(att)`
- **The address is the same regardless of who deploys** (direct or CCIP)
- **The address proves the attestation data** — if any field is different, the address changes
- **No two mirrors can have the same address** — CREATE2 would fail if the address already has code

### What Changes the Address

| Change | Effect on salt | Effect on initCodeHash | Address changes? |
|--------|---------------|----------------------|-----------------|
| Different `originContract` | Yes | Yes | Yes |
| Different `originChainId` | Yes | Yes | Yes |
| Different `targetChainId` | Yes | No | Yes |
| Different `lockedAmount` | No | Yes | Yes |
| Different `nonce` | No | No | No (but deploy reverts — already deployed) |
| Different `timestamp` | No | No | No |
| Different `navRoot` | No | No | No |
| Different factory address | N/A | N/A | Yes (different deployer) |

---

## 12. Security Properties

### What the Protocol Guarantees

1. **Threshold security**: No mirror can be deployed without 3/5 signers agreeing on the attestation data. A single compromised signer cannot deploy rogue mirrors.

2. **Replay protection**: Each attestation has a unique `(originContract, originChainId, targetChainId, nonce)` ID. Submitting the same attestation twice reverts. The nonce is monotonically increasing per pair.

3. **Chain binding**: EIP-712 domain separator binds signatures to the target chain's `AttestationRegistry`. A signature valid on BNB Testnet cannot be replayed on Fuji (different `chainId` in domain → different digest → different recovered address).

4. **Canonical uniqueness**: The CREATE2 salt ensures exactly one mirror per `(origin, sourceChain, targetChain)` triple. Attempting to deploy a second mirror for the same pair reverts with `MirrorAlreadyDeployed`.

5. **Address determinism**: Anyone can predict the mirror address before deployment. The address cryptographically commits to the attestation data and the factory address.

6. **Compliance enforcement**: Every transfer of a mirror token passes through the compliance contract. Non-compliant addresses cannot hold, send, or receive mirror tokens.

7. **Mint cap**: The mirror token cannot mint more than `lockedAmount` from the attestation. This prevents unbacked inflation.

8. **Rate limiting**: Attestations for the same pair are rate-limited (default 1 hour). Prevents spamming the registry.

9. **Staleness**: Attestations older than 24 hours are rejected. Ensures the attested state is reasonably current.

10. **Signer removal cooldown**: 7-day cooldown to remove a signer from the registry. Prevents flash attacks where an attacker gains owner access, removes honest signers, and pushes fraudulent attestations.

### Attack Surface (see THREAT_MODEL.md for full analysis)

| Attack | Mitigation |
|--------|-----------|
| Replay attestation on another chain | EIP-712 domain separator includes chainId |
| Replay same attestation | AttestationId uniqueness check + nonce |
| Rogue signer | Threshold (3/5) — need 3 colluding signers |
| Frontrun mirror deployment | CREATE2 determinism — address is the same regardless of deployer |
| Unauthorized mint | Only `authorizedMinters` can mint; factory is the only initial minter |
| Compliance bypass | `_update()` hook checks every transfer (not just the first) |
| Stale NAV exploitation | RWAHook increases swap fees as NAV ages (5bps → 50bps over 6 hours) |
| Double-spend ZK proof | CollateralVerifier tracks nullifiers; AaveAdapter tracks used proofIds |

---

## Complete Transaction Timeline (Direct Path)

```
T+0s    User clicks "Deploy Mirror Direct" on frontend
T+0s    Wallet prompts for signature
T+1s    User confirms TX
T+2s    TX submitted to target chain mempool
T+3s    TX included in block
        │
        ├─ CanonicalFactory.deployMirrorDirect() called
        │   ├─ Validates targetChainId == block.chainid
        │   ├─ Computes salt, checks mirror not deployed
        │   ├─ Calls AttestationRegistry.verifyAttestation()
        │   │   ├─ Staleness check ✓
        │   │   ├─ Rate limit check ✓
        │   │   ├─ Threshold check (3 ≥ 3) ✓
        │   │   ├─ Replay check ✓
        │   │   ├─ ECDSA recover signer 0 ✓
        │   │   ├─ ECDSA recover signer 1 ✓
        │   │   ├─ ECDSA recover signer 2 ✓
        │   │   ├─ Store attestation
        │   │   └─ emit AttestationVerified
        │   ├─ CREATE2 deploy XythumToken (~1.5M gas)
        │   ├─ Register mirror in all mappings
        │   └─ emit MirrorDeployed
        │
T+5s    TX confirmed. Mirror token is live.
        │
        ├─ Address: deterministic, predictable, canonical
        ├─ Mint cap: locked to attestation's lockedAmount
        ├─ Compliance: enforced on every transfer
        └─ Ready for Uniswap V4 pool, ZK collateral proofs, etc.
```

## Complete Transaction Timeline (CCIP Path)

```
T+0s      User clicks "Send via CCIP" on frontend
T+1s      Wallet prompts for signature (~0.13 AVAX fee)
T+3s      TX confirmed on source chain
           └─ CCIPSender.sendAttestation() → emit AttestationSent(messageId)

T+3s      CCIP message enters Chainlink DON relay queue
  ...     Chainlink oracles observe source chain finality
  ...     Oracles reach consensus on the message
  ...     Message relayed to target chain CCIP Router

T+20min   CCIPReceiver._ccipReceive() triggered by CCIP Router
           ├─ Validates sender (CCIPSender on source chain is trusted)
           ├─ Replay protection
           ├─ Decodes payload
           └─ try factory.deployMirror(att, sigs, bitmap)
                ├─ Same full verification as Direct path
                ├─ CREATE2 deploy
                ├─ emit MirrorDeployed
                └─ emit MirrorDeployedViaCCIP(messageId, mirror)

T+20min   Mirror token is live. Same deterministic address as Direct path would produce.
```
