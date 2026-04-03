# XYTHUM RWA PASSPORT — Billion-Dollar Protocol Design Spec
## The Canonical Standard for Real-World Asset Verification
**Date:** 2026-04-03 | **Status:** Approved

---

## 1. Vision

Transform XYTHUM from a working cross-chain mirror protocol into **the canonical RWA identity layer** — a public good that every chain, protocol, and user depends on to answer: *"Is this RWA token real?"*

**Strategic model:** Infrastructure adoption drives TVL, TVL drives fee revenue, revenue drives token value, token value attracts more signers, more signers increase security, more security attracts more TVL. Flywheel.

**Go-to-market:** Permissionless "prove it first" — mirror existing RWA tokens (Ondo OUSG, BlackRock BUIDL, Franklin BENJI) without issuer permission. Become the verification standard, then issuers come to you.

**Beachhead:** Tokenized Treasuries / T-Bills (~$5B+ AUM, fastest-growing RWA category, institutional names, high cross-chain velocity).

---

## 2. Strategic Approach: "The Canonical Standard"

### Phase 1: Build Complete Production-Ready Testnet
Ship a bulletproof, fully-featured protocol on testnet with zero mocks and zero shortcuts. One chance at credibility — launching half-baked on mainnet kills trust permanently.

### Phase 2: Mainnet Launch (Post-Testnet)
Deploy to Ethereum + Arbitrum + Base. Permissionlessly mirror top RWA tokens. Launch public Canonical Registry Explorer.

### Phase 3: Growth + Integrations
Adapter SDK for lending protocols. Grant applications. Protocol integrations. Community building.

### Future Layer: Privacy (Approach 3)
Once established as the canonical standard with real TVL, layer ZK privacy proofs on top — "prove collateral without revealing positions." This becomes the institutional unlock.

---

## 3. Three Revenue Engines

### Engine 1: Attestation Fees
- One-time fee per mirror deployment: flat fee (0.01-0.05 ETH) + basis points on locked value (5bps)
- Distribution (post-token): 60% signers, 20% delegators, 15% treasury, 5% burn
- Pre-token: fees go to protocol treasury, distributed to signers manually or via simple splitter contract
- Scale math: 10,000 mirrors x $50M avg locked x 5bps = $25M/year

### Engine 2: Canonical Verification API
- On-chain: `isCanonical(address)` — free basic check (drives adoption), paid tier for rich metadata (NAV, compliance, collateral ratio)
- Off-chain API: subscription for exchanges, custodians, analytics platforms
- Scale math: 50 integrations x $5K-50K/year = $250K-2.5M/year
- Real value: makes Xythum indispensable infrastructure

### Engine 3: Liquidity Hook Fees
- Dynamic 5-30bps fee on every swap through Xythum-powered Uniswap V4 pools (via RWAHook)
- Small protocol cut (1-3bps) on top of LP fees
- Scale math: $100M daily volume x 2bps = $7.3M/year

### Revenue Trajectory

| Stage | TVL | Annual Revenue | Implied Valuation (25x) |
|---|---|---|---|
| Early (Year 1) | $50M | ~$500K | $12.5M |
| Growth (Year 2) | $500M | ~$5M | $125M |
| Scale (Year 3) | $5B | ~$50M | $1.25B |

---

## 4. Protocol Evolution — What Changes From Current State

### What Exists (Solid Foundation)
- 4 core contracts: CanonicalFactory, AttestationRegistry, SignerRegistry, XythumToken
- CCIP sender/receiver for cross-chain messaging
- Uniswap V4 hooks (RWAHook, LiquidityBootstrap)
- Basic ZK (CollateralVerifier with mock, circom circuits)
- AaveAdapter
- 214 passing tests
- Next.js 15 frontend dashboard
- Live on 3 testnets (Fuji, BNB, Monad)

### Key Shifts

| From (Current) | To (Target) |
|---|---|
| Testnet demos | Production-ready testnet, then mainnet |
| 3-of-5 hardcoded ECDSA signers | MPC-ECDSA threshold signatures (5-of-9) |
| MockGroth16Verifier | Real Groth16 with trusted setup |
| One-way mirroring only | Full lock -> mint -> burn -> redeem lifecycle |
| Read-only dashboard | Public Canonical Registry Explorer |
| Basic circom circuits | Optimized, audited circuits with proper constraints |
| No revenue model | Three revenue engines |

### What Stays The Same
Core architecture is sound — CREATE2 deterministic deployment, EIP-712 attestations, CCIP delivery, Uniswap V4 hooks. Building on top, not replacing.

---

## 5. Canonical Registry Explorer — The "Etherscan Moment"

The single most important product for visibility and inbound demand.

### Core Features
1. **Look up any RWA** — Enter address or token name, see canonical mirror on any chain with full provenance
2. **Verify authenticity** — "Is this OUSG on Arbitrum real?" One-click answer with cryptographic proof
3. **Browse all mirrored RWAs** — Live leaderboard sortable by TVL, chain, issuer, asset type
4. **Chain coverage map** — Visual showing which RWAs are on which chains

### Why This Is The Growth Hack
- **Crypto Twitter bait:** "Every Ondo and BlackRock token is now verifiable across 5 chains" — the tweet writes itself
- **SEO magnet:** People searching "is OUSG on Arbitrum legit" land on your explorer
- **Protocol BD inbound:** Aave governance sees the explorer, integrates `isCanonical()` for collateral whitelisting
- **Issuer inbound:** Ondo sees their tokens with canonical cross-chain verification they didn't build

### Frontend Evolution

| Current Page | Becomes |
|---|---|
| Dashboard | Protocol Overview — live stats, TVL, chains, recent attestations |
| Mirrors | Registry Explorer — searchable, filterable, the main product |
| Verify | Merged into Registry — verification is inline |
| Attest | "Request Mirror" for power users/protocols |

### Embeddable Verification Badge
Widget any dApp can embed: "Canonical RWA — Verified by Xythum" with origin, attestation date, signer count. Zero-cost brand distribution across every DeFi frontend using RWA tokens.

---

## 6. Signing Architecture — MPC-ECDSA to FROST

### Evolution Path

**Stage 1 — MPC-ECDSA (Build Now)**
- Single threshold signature on-chain (~25K gas vs ~120K for current 3-sig)
- Distributed Key Generation — no single party holds full key
- 5-of-9 threshold on testnet
- Signer rotation via key resharing without changing on-chain public key
- Mature tooling, production-proven

**Stage 2 — FROST (Future)**
- 2-round signing (vs 3-4 for MPC-ECDSA) — critical at 21+ signers
- Migrate when team scales and signer set grows

**Stage 3 — EigenLayer AVS (At Scale)**
- ETH restakers secure Xythum attestations
- Massive economic security without standalone validator set

### Signature Scheme Comparison

| Factor | Current (k-of-n ECDSA) | MPC-ECDSA (Stage 1) | FROST (Stage 2) |
|---|---|---|---|
| On-chain gas | ~120K (3 sigs) | ~25K (1 sig) | ~25K (1 sig) |
| Key custody | Each signer has full key | No single party has key | No single party has key |
| Signer rotation | New keys, redeploy | Reshare, same pubkey | Reshare, same pubkey |
| Communication rounds | 1 | 3-4 | 2 |

### New Contracts (Stage 1)

| Contract | Purpose |
|---|---|
| Updated AttestationRegistry | Verify single threshold signature vs group public key |
| Updated SignerRegistry | Store group public key + signer metadata |

### New Off-Chain Component: Signer Client

```
Signer Node (off-chain daemon)
+-- Chain Watcher       monitors source chains for RWA events
+-- Attestation Engine   validates RWA data (NAV, compliance, locked amount)
+-- TSS Module          participates in MPC-ECDSA signing rounds
+-- P2P Comms           libp2p mesh for signer-to-signer coordination
+-- API                 status, health, metrics
```

Lightweight TypeScript daemon for Stage 1 (faster iteration for solo founder; rewrite hot paths in Rust if performance demands it at scale).

---

## 7. ZK Proofs — Production Groth16

### Why Groth16 (Not PLONK, Halo2, STARK)
- **Smallest proof** (~128 bytes) = cheapest on-chain verification (~230K gas)
- **Circuits are simple and stable** — collateral proofs, Merkle inclusion. Won't change often, so per-circuit trusted setup is acceptable.
- **Best tooling** — circom + snarkjs is the most mature, documented, auditable ZK stack
- **Battle-tested** — Tornado Cash, Semaphore, WorldCoin all used Groth16

### What Gets Built

| Component | Current State | Production Target |
|---|---|---|
| CollateralVerifier | MockGroth16Verifier | Real Groth16 verifier with production keys |
| collateral.circom | Basic | Optimized, minimized constraints, range proofs |
| merkle.circom | Basic | Production-grade Merkle inclusion proof |
| Trusted setup | None | Hermez PoT Phase 1 + Phase 2 ceremony |
| Proof generation | Not wired | Off-chain prover CLI/API via snarkjs |
| Nullifier tracking | Basic | Production nullifier set, double-use prevention |
| On-chain verification | Mock returns true | Real pairing check, ~230K gas |

### New Circuits To Add

| Circuit | Purpose |
|---|---|
| `range_proof.circom` | Prove value is within range without revealing exact amount |
| `multi_collateral.circom` | Prove aggregate collateral across multiple assets |
| `compliance_status.circom` | Prove KYC/compliance status without revealing identity (future) |

### Trusted Setup Process
1. Phase 1: Reuse Hermez/Polygon Powers of Tau ceremony (supports up to 2^28 constraints)
2. Phase 2: Circuit-specific ceremony with 3-5 independent participants
3. Generate verification key + proving key
4. Deploy real verifier contract from ceremony output

---

## 8. Burn/Redeem Lifecycle

Completes the bidirectional mirroring that gives mirrors a hard peg to underlying assets.

### Flow

```
MINT:   User deposits RWA into LockVault (source) -> Signers attest -> Mirror minted (target)
REDEEM: User burns mirror via RedemptionRouter (target) -> CCIP message -> LockVault releases RWA (source)
INVARIANT: lockedAmount >= totalMirrorSupply (always)
```

### New Contracts

| Contract | Chain | Purpose |
|---|---|---|
| LockVault | Source | Escrow for original RWA tokens. Accepts deposits, releases on valid burn proof. |
| RedemptionRouter | Target | Burns mirror tokens, sends CCIP unlock message to source chain. |
| CCIPUnlockReceiver | Source | Receives burn proof from target chain, triggers LockVault release. |

### XythumToken Modification
- Add `burn(uint256 amount)` public function (only callable via RedemptionRouter or authorized burner)
- Invariant test: `totalSupply` can never exceed `LockVault.lockedAmount` for that mirror

---

## 9. Adapter SDK

Make it trivial for any DeFi protocol to accept Xythum mirrors.

### Core Interface

```solidity
interface IXythumConsumer {
    function isCanonical(address token) external view returns (bool);
    function getMirrorMetadata(address token) external view returns (
        address originContract,
        uint256 originChainId,
        uint256 lockedAmount,
        bytes32 navRoot,
        uint256 lastAttestationTime
    );
}
```

### Adapters To Ship

| Adapter | Protocol | Status |
|---|---|---|
| AaveAdapter | Aave V3 | Exists, needs hardening |
| MorphoAdapter | Morpho Blue | Template exists in docs |
| GenericAdapter | Any protocol | New — reference implementation |

### Deliverables
- Published npm package: `@xythum/sdk`
- Published Foundry package: `xythum-contracts`
- Integration guide with copy-paste examples
- Example repo: "Accept Xythum mirrors in your protocol in 10 minutes"

---

## 10. Testing & Hardening

### Target: 300+ Tests

| Category | Current | Target | New Coverage |
|---|---|---|---|
| Unit | ~155 | 200+ | Burn/redeem, real ZK, MPC sig verification |
| Integration | ~24 | 50+ | Full lifecycle with real proofs, cross-chain burn/redeem |
| Invariant/Fuzz | ~8 | 30+ | lockedAmount >= supply, nullifier uniqueness, signer stake |
| Attack scenarios | ~10 | 20+ | Burn replay, double-redeem, malicious prover, signer collusion with threshold |

### Key Test Requirements
- Zero mock verifiers in test suite — all ZK tests use real Groth16 proofs
- Burn/redeem invariant: fuzz test that randomly mints and burns, asserts invariant holds
- Chaos tests: signer offline during signing round, CCIP delay/failure, proof with expired nullifier
- Gas benchmarks: tracked per-contract, regression alerts if gas increases

---

## 11. Build Phases

| Phase | Focus | Duration | Key Deliverables |
|---|---|---|---|
| **1** | Burn/Redeem lifecycle | 3-4 weeks | LockVault, RedemptionRouter, CCIPUnlockReceiver, invariant tests |
| **2** | Production ZK proofs | 4-6 weeks | Real Groth16 verifier, optimized circuits, trusted setup, prover tooling |
| **3** | MPC-ECDSA signer network | 3-4 weeks | DKG, signer client daemon, updated AttestationRegistry + SignerRegistry |
| **4** | Canonical Registry Explorer | 2-3 weeks | Public explorer UI, embeddable badge, search/verify/browse |
| **5** | Adapter SDK | 2-3 weeks | Aave + Morpho adapters, npm/foundry packages, integration docs |
| **6** | Hardening + Testing | 2-3 weeks | 300+ tests, gas optimization, chaos testing |
| **7** | Documentation + Demo | 1-2 weeks | Video demo, grant materials, complete integration guide |

**Total: ~18-24 weeks to production-ready testnet**

---

## 12. Out of Scope (Deferred)

- Token launch / tokenomics design (separate brainstorm when product has traction)
- Mainnet deployment (after testnet is production-ready)
- EigenLayer AVS integration (after token + mainnet)
- FROST migration (MPC-ECDSA sufficient for now)
- Full ERC-3643 T-REX compliance (keep simple compliance for now)
- ZK identity/compliance proofs (Phase 2 after mainnet)
- Cross-chain RWA DEX/aggregator (future product)

---

## 13. Success Criteria (Testnet)

Before considering mainnet:
- [ ] Full lock -> mint -> burn -> redeem lifecycle working end-to-end
- [ ] Real Groth16 proofs generated and verified on-chain (zero mocks)
- [ ] MPC-ECDSA threshold signing with 5+ independent signer nodes
- [ ] Canonical Registry Explorer publicly accessible
- [ ] Adapter SDK published with working Aave integration on testnet
- [ ] 300+ tests passing, including real ZK and burn/redeem invariants
- [ ] Gas benchmarks documented for all operations
- [ ] Complete documentation and video demo
- [ ] At least 2 ecosystem grant applications submitted
