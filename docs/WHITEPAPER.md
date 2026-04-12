# Xythum RWA Passport — Whitepaper

**Cross-chain canonical mirrors for tokenized real-world assets.**

Version 1.0 · April 2026
Authors: Xythum Protocol contributors
Status: Pre-seed, testnet (Avalanche Fuji · BNB Testnet · Monad Testnet)

---

## Abstract

Tokenized real-world assets (RWAs) — T-bills, money-market funds, real estate, private credit — are on-chain primitives that issuers deploy on a single chain. Once issued, those assets are economically trapped: their utility is bounded by the DeFi liquidity of one chain. The dominant cross-chain solution today, generalized message bridges (CCIP, LayerZero, Wormhole, Axelar), introduces 40–70 minutes of round-trip latency, fees per hop, and a wrapped-token model that fragments liquidity into per-bridge pools.

Xythum proposes a domain-specific alternative: a cross-chain **canonical mirror** primitive that issues a 1:1 deterministic ERC-20 representation of an RWA on any EVM target chain via a 3-of-5 threshold-signed attestation, backed by an escrow-locked original on the origin chain. Mirrors are CREATE2-deployed at addresses derivable from the `(originContract, originChainId, targetChainId)` triple, eliminating address ambiguity. A user can lock, mint, use the mirror in arbitrary DeFi, burn, and redeem the original — sub-minute, fee-free, atomicity guaranteed by one-shot lockId accounting.

This whitepaper documents the V1 architecture (deployed and operational on three testnets), describes the V2 hardening roadmap (self-rescue, trustless burn-attestation, signer bonding, guardian multisig), and outlines the V3 ZK end-state where the signer set is removed entirely.

---

## Table of Contents

1. [Problem statement](#1-problem-statement)
2. [Prior work and what's missing](#2-prior-work-and-whats-missing)
3. [Trust model](#3-trust-model)
4. [V1 — Round-trip primitive](#4-v1--round-trip-primitive)
5. [V1 — Demo lending market (Xythum Lend)](#5-v1--demo-lending-market-xythum-lend)
6. [V2.1 — Time-locked self-rescue](#6-v21--time-locked-self-rescue)
7. [V2.2 — Trustless burn-attestation via Merkle proof](#7-v22--trustless-burn-attestation-via-merkle-proof)
8. [V2.3 — Signer bonding and slashing](#8-v23--signer-bonding-and-slashing)
9. [V2.4 — Guardian multisig](#9-v24--guardian-multisig)
10. [V2.5 — Multi-RPC signer software](#10-v25--multi-rpc-signer-software)
11. [V3 — ZK migration](#11-v3--zk-migration)
12. [Economic model](#12-economic-model)
13. [Comparison to alternatives](#13-comparison-to-alternatives)
14. [Sequencing and timeline](#14-sequencing-and-timeline)
15. [Non-goals](#15-non-goals)
16. [Conclusion](#16-conclusion)

---

## 1. Problem statement

### 1.1 RWA tokenization is producing single-chain assets

The 2024–2026 RWA boom has produced significant on-chain T-bill TVL across issuers including Ondo (USDY, OUSG), Backed (bIB01, bC3M), Hashnote (USYC), Maple (Cash Management), Centrifuge (DROP/TIN tranches), and others. Each of these is deployed primarily on a single chain — usually Ethereum mainnet, sometimes Solana — for compliance, oracle availability, and audit-surface reasons.

This creates a structural inefficiency: a yield-bearing T-bill issued on Ethereum cannot be used as collateral on Aave-Avalanche, Aave-BNB, or Aave-Monad without either (a) the issuer redeploying the asset on each target chain (compliance and ops cost), or (b) a generalized bridge wrapping it into a synthetic representation (latency, fees, fragmentation).

### 1.2 Cross-chain bridges have the wrong shape for RWAs

Generalized message bridges optimize for the worst case — arbitrary message delivery between arbitrary chains under arbitrary trust assumptions. The cost of that generality is paid every time:

- **Latency**: Chainlink CCIP testnet round-trip is 40–70 minutes per hop. Mainnet is faster but still measured in minutes for finality-sensitive transfers.
- **Fees**: every hop pays a DON or relayer fee, denominated in the source chain's native token.
- **Wrapped fragmentation**: each bridge produces its own wrapped representation, splitting liquidity across `bridgeA-USDC`, `bridgeB-USDC`, `bridgeC-USDC` on the same target chain.
- **Trust model breadth**: the user has to trust both the bridge's validator set AND the bridge's smart-contract implementation, neither of which they typically audit.

For RWAs specifically, none of those costs are necessary. RWAs are slow-moving assets; their cross-chain utility is "park collateral elsewhere," not "high-frequency transfer." A purpose-built primitive with a tighter trust model can collapse the entire cost stack.

### 1.3 What Xythum is

Xythum is a **per-issuer, per-corridor** cross-chain primitive optimized for RWAs. Every (origin asset, source chain, destination chain) tuple maps to exactly one canonical mirror at a CREATE2-deterministic address on the destination chain. The mirror is fully redeemable for the original via a four-step lock → mint → burn → release cycle that completes in seconds, not minutes, without per-hop fees.

We are deliberately not a general bridge. We do not move arbitrary tokens. We do not message arbitrary contracts. We are an **issuance-side identity layer for RWAs across EVM chains.**

---

## 2. Prior work and what's missing

### 2.1 Generalized bridges

CCIP, LayerZero, Wormhole, Axelar, Hyperlane. Each maintains a validator/oracle/DON set that delivers attested messages. Excellent at general-purpose message-passing; ill-fitted to "make this RWA usable elsewhere" for the reasons above.

### 2.2 Native multichain issuance (Circle CCTP, Tether's multichain mints)

Circle's Cross-Chain Transfer Protocol burns USDC on chain A and mints native USDC on chain B with attestation from a centralized Circle endpoint. The right shape for our problem — except CCTP is single-issuer (Circle) and single-asset (USDC), with no path for third parties to participate.

Xythum can be understood as **a CCTP-like primitive generalized to any RWA, with a third-party signer set instead of the issuer's own attestation service.** The issuer keeps their existing single-chain deployment; we sit downstream and provide the cross-chain layer.

### 2.3 ERC-3643 / Onchain ID

Compliance-rail standards for tokenizing securities. Orthogonal to Xythum — we mirror whatever compliance posture the origin asset has. ERC-3643 hooks plug into Xythum mirrors via a `ComplianceEngine` interface (V1 supports this; production deployments will use it).

### 2.4 Aave RWA listings

Aave, Morpho, Maple, and Centrifuge accept RWA collateral on a per-chain, per-listing basis. Each listing requires individual governance and risk parameter setup. Xythum's claim is that with canonical mirrors, the *same* governance work can be reused across chains — list once, redeploy the mirror.

---

## 3. Trust model

V1 is honest about its trust footprint. We document failure modes and the V2 patches that close them.

### 3.1 Authority

A 5-member signer set, on-chain registered in `SignerRegistry`. Signers produce EIP-712 typed-data receipts (Attestation, LockReceipt, UnlockReceipt) consumed by `AttestationRegistry`, `RWALockEscrow`, and `CanonicalFactory`. Any 3 signatures pass the threshold check.

### 3.2 What 3 signers can do (today)

Three colluding signers can:
- Sign a fake LockReceipt → mint xRWA on a target chain without a real lock on origin (V2.3 patches via slashable bond)
- Refuse to sign an UnlockReceipt after a legitimate burn → user's mTBILL stuck in escrow indefinitely (V2.1 patches via 24h self-rescue; V2.2 patches via Merkle-proof fallback)

### 3.3 What 3 signers cannot do

- Steal an existing user's locked tokens (escrow.release verifies originChainId, lockId match, and one-shot guards)
- Replay receipts across chains (EIP-712 domain pins chainId + verifyingContract)
- Replay receipts within a chain (per-lockId mintedFromLock / burnedForLock / released bools, all one-shot)
- Mint twice for the same lockId (mintedFromLock guard)
- Release twice for the same lockId (released guard)

### 3.4 Source-of-truth hierarchy

- **Origin chain escrow's `_locks[lockId]`** is the source of truth for "tokens are locked." Signers refuse to sign receipts that don't match this.
- **Target chain mirror's `BurnedForLock(lockId)`** is the source of truth for "burn happened." Signers refuse to sign UnlockReceipts without observing this.
- **`SignerRegistry.getSignerSet()`** is the source of truth for "who is allowed to sign." Receipts signed by ex-signers fail verification.

### 3.5 Attack surface ranking (V1 → V3)

Ordered by risk, highest first:

1. **Signer collusion to mint without a lock** — patched by V2.3 (bonding + slashing) and V2.2 (Merkle-proof fallback for honest provers).
2. **Signer service infrastructure compromise** — patched by V2.5 (multi-RPC redundancy, per-signer KMS).
3. **Signer goes offline causing user funds stuck** — patched by V2.1 (24h self-rescue) and V2.2 (Merkle-proof unlock path).
4. **Replay across chains** — already mitigated in V1 by EIP-712 domain pinning.
5. **Re-org during lock-but-before-mint** — mitigated by signer policy: 12+ block confirmations before signing.
6. **Front-run on `mintFromLock`** — non-issue: `mintedFromLock` guard makes the mint one-shot per lockId regardless of who submits.

V3 (ZK migration) replaces the signer set entirely with a proof system, eliminating items 1, 2, 3 by construction.

---

## 4. V1 — Round-trip primitive

V1 is deployed on Avalanche Fuji, BNB Testnet, and Monad Testnet. End-to-end round-trip verified in 12 seconds CLI / 40 seconds UI.

### 4.1 Architecture

```
ORIGIN CHAIN (e.g. Monad)                       TARGET CHAIN (e.g. Fuji)
─────────────────────────                       ────────────────────────

mTBILL (RWA ERC-20)                             XythumToken (xRWA mirror)
       │                                                ▲
       │ ① user.transferFrom                            │ ④ mintFromLock
       ▼                                                │
RWALockEscrow                                   CanonicalFactory
  state: locks[lockId]                            state: mintedFromLock[lockId]
  emits Locked(lockId, locker, amount)            emits MintedFromLock(...)
       │                                                │
       │ ② signers sign LockReceipt                     │ ⑤ user holds xRWA
       │                                                │    uses in DeFi
       │ ③ user submits LockReceipt + sigs ──────────► │
                                                        │
                                                        ▼
                                                XythumToken.burnForLock(amount, lockId)
                                                  state: burnedForLock[lockId]
                                                  emits BurnedForLock(lockId)
       ┌────────── ⑥ signers sign UnlockReceipt ────────┘
       │
       │ ⑦ user submits UnlockReceipt + sigs to escrow
       ▼
RWALockEscrow.release(receipt, sigs, bitmap)
  · verify EIP-712 sigs against SignerRegistry
  · check lockId matches stored amount
  · transfer mTBILL to recipient
  · mark released[lockId] = true
```

### 4.2 Components

| Contract | Role | Persistence |
|---|---|---|
| `SignerRegistry` | Maintains the 5-of-5 signer set + 3-quorum threshold per chain | One per chain |
| `AttestationRegistry` | Verifies threshold-signed Attestations (issuance flow) | One per chain |
| `CanonicalFactory` | CREATE2-deploys mirrors; gates `mintFromLock` and `deployMirrorDirect` | One per chain |
| `XythumToken` | The mirror ERC-20. Mintable by factory only; burnable for lockId | One per (origin, srcChain, dstChain) corridor |
| `RWALockEscrow` | Holds escrowed originals; verifies UnlockReceipts; releases | One per chain |

### 4.3 Determinism

Mirror addresses are CREATE2-deterministic from `(originContract, originChainId, targetChainId)`. The same triple maps to the same mirror address regardless of who first deploys it. This eliminates the "which wrapped USDC is real?" ambiguity bridges introduce.

### 4.4 Latency

End-to-end round-trip on testnet:
- Lock cycle (1–4): ~15–20 seconds
- Burn cycle (5–7): ~15–20 seconds
- Total: 30–40 seconds

This is dominated by block-confirmation latency on each chain. The signer relay itself is sub-second.

### 4.5 Invariants (enforced by contract)

| Invariant | Mechanism |
|---|---|
| One mint per lockId | `mintedFromLock[lockId]` one-shot |
| One burn per lockId | `burnedForLock[lockId]` one-shot |
| One release per lockId | `released[lockId]` one-shot |
| Mint amount equals lock amount | Receipt amount signed; verified on both ends |
| Release amount equals burn amount | UnlockReceipt amount signed; matched against lock state |
| Receipts valid for one chain only | EIP-712 domain pins chainId + verifyingContract |
| Receipts expire | LOCK_RECEIPT_MAX_STALENESS = 24h |
| Signer rotation safe | Receipts include timestamp; old signers' sigs fail registry check |

### 4.6 Known limitations (acknowledged)

V1 has explicit non-goals:

- **Self-rescue if signers go silent** — patched in V2.1.
- **Trustless redemption if signers refuse to sign UnlockReceipt** — patched in V2.2.
- **Economic disincentive for signer misbehavior** — patched in V2.3.
- **Partial burns / partial unlocks** — out of scope; V1 is all-or-nothing per lockId.
- **Multi-RPC signer infrastructure** — patched in V2.5.

We document these explicitly so users understand the V1 trust footprint.

---

## 5. V1 — Demo lending market (Xythum Lend)

V1 ships with a single-pair demo lending market (`XythumLend`) on Avalanche Fuji to demonstrate the end-to-end value of canonical mirrors.

### 5.1 Purpose

The lending market exists to answer the question "what does the user *do* with the mirror in those 30 seconds?" A working demo of "lock on origin → borrow on target → repay → redeem on origin" is far more compelling than hand-waving toward "use it on Aave."

### 5.2 Design constraints

- **Single-pair**: xRWA collateral, mock USDC debt. No multi-asset support.
- **Fixed LTV**: 70%, hardcoded.
- **Fixed oracle**: $1 per xRWA, hardcoded (correct for tokenized T-bills at par).
- **No liquidations**: unnecessary when prices are fixed.
- **No interest**: round-trip is 60 seconds; interest is annualized.
- **Owner-seeded reserves**: 1M USDC seeded at deploy.
- **Pausable**: emergency kill-switch.
- **DEMO MARKET banner**: pre-empts production-readiness questions.

This is deliberately not a competitor to Aave. It is a 150-LOC primitive that demonstrates that the mirror is composable in standard DeFi without any special integration.

### 5.3 Why this is the right scope for the demo

- Proves the mirror is a regular ERC-20 (not a wrapped IOU)
- Demonstrates the full borrow-against-collateral loop
- Avoids regulatory and risk-engine questions that don't help the cross-chain pitch
- Production version would replace the hardcoded oracle with a Chainlink NAV feed and add a Gelato-keeper liquidation queue — but those are V2.6+ items, not blockers

---

## 6. V2.1 — Time-locked self-rescue

### 6.1 Problem

In V1, if signers go offline indefinitely after a user has locked tokens, the original RWA is stuck in escrow forever. There is no on-chain path to recover.

### 6.2 Solution

Add `RWALockEscrow.cancelLock(lockId)`. After a configurable timeout (default 24 hours), the original locker can self-rescue if no `MintedFromLock` event has been observed from the target chain.

```solidity
uint256 public constant CANCEL_TIMEOUT = 24 hours;
mapping(bytes32 lockId => bool) public cancelled;

function cancelLock(bytes32 lockId) external nonReentrant {
    LockState storage L = _locks[lockId];
    require(msg.sender == L.locker, "not locker");
    require(!L.released && !cancelled[lockId], "already settled");
    require(block.timestamp >= L.lockedAt + CANCEL_TIMEOUT, "too early");
    cancelled[lockId] = true;
    totalLocked[L.rwaToken] -= L.amount;
    IERC20(L.rwaToken).safeTransfer(L.locker, L.amount);
    emit LockCancelled(lockId, L.locker, L.amount);
}
```

### 6.3 Off-chain signer policy

Signers must observe `LockCancelled` events on origin chains and **refuse** to sign LockReceipts for cancelled lockIds. This prevents the double-issuance race: cancel on origin + mint on target for the same lockId.

### 6.4 Why 24 hours

- Short enough that users aren't stuck for days
- Long enough for legitimate cross-chain delays (network congestion, signer service brief outage)
- Tunable per chain; high-value corridors might use 48h

### 6.5 What this closes

Removes "user funds stuck if signers go offline" from the failure-modes table.

---

## 7. V2.2 — Trustless burn-attestation via Merkle proof

### 7.1 Problem

In V1, if a user burns xRWA on the target chain but signers refuse to sign the UnlockReceipt (collusion or service failure), the original RWA is stuck in escrow. The locker has no recourse.

### 7.2 Solution

Add a fallback path on `RWALockEscrow.release` that accepts a Merkle proof of the `BurnedForLock` event log from the target chain in lieu of a signer-attested UnlockReceipt:

```solidity
function releaseViaProof(
    UnlockReceipt calldata receipt,
    bytes calldata blockHeaderProof,
    bytes calldata burnEventProof
) external nonReentrant {
    // 1. Verify blockHeaderProof references a target-chain header signed by signers
    // 2. Verify burnEventProof shows BurnedForLock(lockId, ...) under that header
    // 3. Same lock-state checks as `release`
    // 4. Mark released, transfer
}
```

### 7.3 Two implementation options

**Option A: dedicated header oracle.** Signers sign block-header roots from each chain on a regular cadence. After the V2.1 timeout passes with no UnlockReceipt arriving, the user can submit a header proof + Merkle proof of the burn log under that header. Signers can refuse to sign UnlockReceipts but cannot refuse to sign block headers (they're objective).

**Option B: third-party light client.** Plug in LayerZero Endpoint v2, Hyperlane ISM, or Polymer to provide cryptographic proof of target-chain state. No additional signer trust beyond what the third-party already provides.

V2.2 is designed to support either; the choice is per-corridor and per-chain economics.

### 7.4 What this closes

Removes "user funds stuck after legitimate burn" from the failure-modes table. After V2.2, the only remaining custody risk is signer collusion on the *outbound* lock side, which V2.3 addresses economically.

---

## 8. V2.3 — Signer bonding and slashing

### 8.1 Problem

Three or more colluding signers can mint mirrors without a backing lock. This is a theoretical risk in V1 mitigated only by reputation; for institutional users, that's insufficient.

### 8.2 Solution

Introduce `SignerBondVault.sol`. Signers must post a bond before being registered. Provable misbehavior is slashable on-chain by anyone who submits a fraud proof:

```solidity
contract SignerBondVault {
    mapping(address signer => uint256 bond) public bonds;
    uint256 public minBond = 50 ether;

    function postBond() external payable;
    function withdrawBond() external;  // 14-day unbonding period

    /// Slash for signing two conflicting receipts with the same lockId.
    function slashConflicting(
        bytes32 lockId,
        ReceiptLib.LockReceipt calldata receiptA, bytes calldata sigA,
        ReceiptLib.LockReceipt calldata receiptB, bytes calldata sigB
    ) external;

    /// Slash for signing a LockReceipt for a lockId that has no real lock event.
    function slashFakeLock(
        bytes32 lockId,
        ReceiptLib.LockReceipt calldata receipt, bytes calldata sig,
        bytes calldata escrowStateProof
    ) external;
}
```

### 8.3 Economics

With 5 signers each bonded at 50 ETH, the total at-risk capital is 250 ETH. To make collusion profitable, the value of the fake mirror must exceed 60% of the total bond (the slashable fraction; the rest reverts to the protocol). At 50 ETH bonds, attacks below ~150 ETH equivalent are economically irrational.

Bond size is tunable per corridor. High-value corridors (e.g., a 100M T-bill mirror) would use higher bonds; low-value corridors can use less.

### 8.4 What this closes

Removes the unconditional trust assumption on signer collusion. After V2.3, signers must be economically rational to misbehave.

---

## 9. V2.4 — Guardian multisig

### 9.1 Problem

Even with bonding, a sufficiently large attack on a high-value corridor could justify slashing as a cost of doing business. We need a circuit breaker.

### 9.2 Solution

A separate 2-of-3 multisig (independent of the signer set) with circuit-breaker authority:

- `pauseEscrow(escrow)` — freeze new locks and releases on a chain
- `pauseFactory(factory)` — freeze new mints
- `invalidateLockId(lockId)` — explicitly poison a specific lockId; both escrow and factory refuse all future actions on it

```solidity
contract GuardianMultisig {
    address[3] public guardians;
    mapping(bytes32 => uint256) public confirmations;

    modifier confirmed(bytes32 op) {
        if (++confirmations[op] < 2) return;
        _;
    }

    function pauseEscrow(address escrow) external confirmed(...) {
        IRWALockEscrow(escrow).pause();
    }
    // ...
}
```

### 9.3 Composition rules

The guardian multisig must be controlled by **different parties** than the signer set. Recommended composition:

- One issuer representative (Ondo, Backed, etc., depending on the corridor)
- One Xythum protocol representative
- One external auditor or DAO-elected member

This prevents any single-party catastrophic compromise.

### 9.4 What this closes

Provides a circuit-breaker for unforeseen attack vectors. Conservative protocols deploy guardians as a default; aggressive protocols can opt out.

---

## 10. V2.5 — Multi-RPC signer software

### 10.1 Problem

In V1, signer software reads `escrow.locks[lockId]` from a single RPC before signing. A compromised RPC can lie, causing signers to sign LockReceipts for non-existent locks.

### 10.2 Solution

Signer service architecture (off-chain, no contract changes):

```
┌──────────────────────────────────────────────────────────┐
│ Signer service (per signer, runs in operator's KMS)      │
├──────────────────────────────────────────────────────────┤
│  1. Watch lock event from N=3 independent RPCs           │
│       (Alchemy + Infura + own node)                      │
│  2. Quorum check: lock event must appear in ≥2 of 3      │
│  3. Block-confirmation check: ≥12 blocks confirmed       │
│  4. Re-read escrow.locks[lockId] state from each RPC,    │
│       confirm (locker, amount, token, lockedAt) match    │
│  5. Only THEN sign LockReceipt                           │
│  6. Publish signed receipt to user-facing endpoint       │
│       + log to public audit feed                         │
└──────────────────────────────────────────────────────────┘
```

Each signer runs:
- Its key in a KMS or HSM (AWS KMS, GCP CKM, HashiCorp Vault)
- Three RPC subscriptions per chain
- A re-org buffer of 12+ blocks
- A public audit feed of every receipt signed

### 10.3 Key custody

Signers must NOT hold private keys in environment variables or filesystem. Production signer hosts use:

- AWS KMS or equivalent: keys never leave the HSM
- mTLS between aggregator and signers
- Per-operator hardening (separate cloud accounts, separate teams, separate jurisdictions)

### 10.4 What this closes

Reduces the operational attack surface from "anyone who pwns a single RPC node" to "anyone who pwns multiple independent infrastructures simultaneously."

---

## 11. V3 — ZK migration

### 11.1 The end state

V3 removes the signer set entirely. Lock and burn proofs are produced by zkSNARKs that prove origin-chain (or target-chain) state directly, verified on-chain on the consuming chain.

### 11.2 Interface continuity

The V1 interface is already designed for this:

```solidity
// V1
function mintFromLock(LockReceipt receipt, bytes sigs, uint256 bitmap)

// V3
function mintFromLockZK(bytes32 commitment, bytes proof)
```

Both consume the same `RWALockEscrow.lock()` flow on origin. The only change is what proves "the lock happened" — sigs in V1, ZK proof in V3. Existing V1 escrows remain backward-compatible; the factory adds a new entry-point.

### 11.3 Required circuits

1. **Lock proof circuit**: prove `escrow.locks[lockId].amount == claimedAmount` AND `not cancelled[lockId]` AND `not released[lockId]`, given the origin chain's state root.
2. **Burn proof circuit**: prove `BurnedForLock(lockId, amount)` was emitted on the target chain, given the target's state root.
3. **Cross-chain state-root oracle**: a header oracle (or signer-attested block-root committee) publishes verified state roots from origin and target onto the consuming chain.

### 11.4 Effort

Estimated 2–3 months of circuit development plus 2 months of audit. ZK migration is post-product-market-fit; ship V2.1–V2.4 first, then migrate to V3 once volume justifies the cryptographic infrastructure investment.

### 11.5 What V3 closes

Eliminates the signer set as a trust assumption. Replaces it with the security of the proof system (Groth16, PLONK, or whatever circuit family is dominant when this lands) and the underlying chains' consensus.

---

## 12. Economic model

### 12.1 Revenue

V1: zero protocol fees. The primitive is positioned as plumbing — a public good for RWA portability that drives transaction volume on partnered chains and DeFi protocols.

V2 and beyond:
- **Bond yield**: signer bonds (V2.3) earn yield by being deposited in low-risk vaults; protocol takes a cut.
- **Per-corridor fee**: optional, 1–5 bps on lock + release. Off by default; toggled per corridor by issuer agreement.
- **Premium SLA**: enterprise users (institutional issuers) pay for a higher-quorum signer set, faster receipt delivery, and dedicated infra.

### 12.2 Token

**No token in V1 or V2.** A governance token is premature, dilutes the customer pitch, and triggers regulatory scrutiny before product-market fit. Decisions about a token are deferred to V3+ when the protocol has demonstrated stable volume across multiple issuers.

### 12.3 Operator economics

Each of the 5 signers, by V2.3, is an independent operator with skin in the game (bond) and revenue (share of protocol fees, plus possible per-receipt micro-fees from premium tiers). Recruiting non-Xythum operators is a Q3 priority once V2.1 and V2.5 are shipped.

---

## 13. Comparison to alternatives

| Property | Xythum V1 | Xythum V3 (target) | CCIP | LayerZero | CCTP |
|---|---|---|---|---|---|
| Round-trip latency | 30–60s | 10–30s + finality | 40–70 min | 5–20 min | 15–30 min |
| Per-hop fee | 0 | 0 | $0.10–$5 | $0.50–$5 | 0 |
| Wrapped fragmentation | None (canonical mirror) | None | Yes (per-corridor) | Yes (OFTs partially fix) | None |
| Trust model | 3-of-5 ECDSA | ZK proof | DON + RMN | Two oracles + relayer | Centralized Circle |
| Domain | RWAs only | RWAs only | General | General | USDC only |
| Address determinism | CREATE2 from triple | CREATE2 from triple | Bridge-specific | Per-OFT | N/A |
| Self-rescue (V2.1+) | 24h timeout | Built-in | None | None | None |

The honest comparison: for RWAs, Xythum is a *better-shaped* primitive than generalized bridges. For non-RWA assets (USDC, ETH, arbitrary messages), CCIP / LayerZero are correct.

---

## 14. Sequencing and timeline

| Quarter | Ship | Why now |
|---|---|---|
| Q1 2026 | V1 (DONE) | Round-trip primitive + demo lending market |
| Q2 2026 | V2.1 (self-rescue) + V2.5 (multi-RPC signers) | Eliminates "stuck forever" failure modes |
| Q2–Q3 2026 | V2.4 (guardian multisig) | Operational safety net |
| Q3 2026 | V2.2 (trustless burn-attestation) | Last single-point-of-failure removal |
| Q4 2026 | V2.3 (signer bonding) | Economic security required for institutional users |
| Q1 2027 | First mainnet deploy | After V2.1 + V2.5 + audit |
| Q2–Q4 2027 | Operator recruitment + key ceremonies | Five independent operators on mainnet |
| 2028+ | V3 (ZK migration) | Once volume justifies cryptographic infrastructure |

The ordering is deliberate: things that can stuck users' funds get patched first. Things that change economics ship after the flow has demonstrated stability.

---

## 15. Non-goals

Items that will not be built into Xythum, ever:

- **Native xRWA-to-xRWA bridges**. Defer to LayerZero / CCIP / Hyperlane. We are an issuance-side identity layer, not a bridge.
- **A governance token**. Premature; dilutes the customer pitch; triggers regulatory scrutiny before product-market fit.
- **Issuer-side tokenization**. Issuers (Ondo, Centrifuge, Maple, Backed.fi) tokenize their own RWAs. We mirror what they've already issued.
- **Compliance / KYC stack**. `ComplianceEngine` integrates external compliance (ERC-3643, Onchain ID). We do not build the compliance layer ourselves.
- **Lending or AMM layer**. xRWA goes into Aave / Morpho / Curve as a regular ERC-20. We are upstream of credit, not in it. (The V1 demo lending market is a demo, not a product.)
- **Exotic asset support**. NFTs, ERC-1155s, perpetuals, options — out of scope. We mirror ERC-20 RWAs.

If a feature request doesn't fit V2.1–V2.4 or V3, it's almost certainly out of scope.

---

## 16. Conclusion

Xythum is a domain-specific cross-chain primitive for tokenized real-world assets. V1, deployed on three testnets, demonstrates a 30–60 second round-trip cycle with one-shot lockId accounting and CREATE2-deterministic mirrors. The V2 roadmap closes every known custody risk in V1 through a sequence of self-contained upgrades — self-rescue, trustless burn-attestation, signer bonding, guardian multisig, and multi-RPC signer infrastructure. V3 replaces the signer set entirely with a ZK proof system, leaving an end-state where the only trust assumptions are the underlying chains' consensus and the proof system itself.

The technical bet is that **RWAs deserve their own primitive**, not a generic bridge. The economic bet is that sub-minute, fee-free, redeemable cross-chain RWAs will produce meaningful adoption across DeFi venues that today fragment liquidity per chain.

V1 is operational. V2 is funded against the closing of a pre-seed. V3 is targeted for 2028 and beyond.

---

## Appendix A — Glossary

- **Mirror**: CREATE2-deployed ERC-20 on the target chain representing 1:1 the original RWA on the origin chain.
- **Corridor**: an `(originContract, originChainId, targetChainId)` triple. One canonical mirror per corridor.
- **LockReceipt**: an EIP-712 typed-data payload signed by signers attesting to a lock event. Consumed by `mintFromLock`.
- **UnlockReceipt**: signed payload attesting to a burn event. Consumed by `release`.
- **One-shot guards**: `mintedFromLock`, `burnedForLock`, `released` mappings that prevent double-execution per lockId.
- **Threshold signature**: 3-of-5 ECDSA, packed signatures + bitmap of signer indices.
- **Self-rescue**: V2.1 — the lock originator can reclaim the RWA after 24h if no mint has occurred.
- **Trustless burn-attestation**: V2.2 — release on origin can be triggered by a Merkle proof of the burn event without an UnlockReceipt.

## Appendix B — V1 contract addresses (testnet, April 2026)

```
Avalanche Fuji (43113):
  signerRegistry      0xF17BBD22D1d3De885d02E01805C01C0e43E64A2F
  attestationRegistry 0xd0047E6F5281Ed7d04f2eAea216cB771b80f7104
  canonicalFactory    0x0BA5bd535Ee071993643Cbb815368F55648B9365
  lockEscrow          0x557474BEd7701ee5290CeB232DDa1Fa06799aA5F
  xythumLend (demo)   0xA1488D1063930947344305D851Ef90dF98944260
  mockUsdc            0x3BeF60e85DA825AEe0449a8438FA8d943A07c848

BNB Testnet (97):
  signerRegistry      0xFA6aFAcfAA866Cf54aCCa0E23883a1597574206c
  attestationRegistry 0xe27E5e2D924F6e42ffa90C6bE817AA030dE6f48D
  canonicalFactory    0x4d0a5A6bf63a25bd6577Bdcda0f48e19843CacBC
  lockEscrow          0x6BbD75e43Bb3515c54BeCAF6B17B69458A8201A3

Monad Testnet (10143):
  signerRegistry      0x725cCe0916d2E8682438732fD9e79803B4fAB2BD
  attestationRegistry 0xe27E5e2D924F6e42ffa90C6bE817AA030dE6f48D
  canonicalFactory    0x27b678acD971f851Ce19751482371eC76b929B41
  lockEscrow          0xCe1D8aF9ae9039A12A157D6ec53eC87F906773C4
```

---

*End of Whitepaper v1.0.*
