# Agent Task: Rewrite Xythum Whitepaper for ePrint Submission

## Context

You have an existing whitepaper (`WHITEPAPER.md`) for **Xythum RWA Passport** — a cross-chain canonical mirror protocol for tokenized real-world assets (T-bills, money-market funds, etc.). The system uses a lock-mint-burn-release cycle with threshold-signed attestations (3-of-5 EIP-712 signers) to create 1:1 ERC-20 mirrors of RWA tokens on destination chains. V1 is deployed on three EVM testnets (Avalanche Fuji, BNB Testnet, Monad Testnet).

The current whitepaper reads like an industry design doc — Solidity snippets, product roadmap, marketing comparisons. It needs to be rewritten as a **cryptographic protocol paper** suitable for submission to **IACR ePrint** (the Cryptology ePrint Archive).

You also have a companion document (`XYTHUM_V3_SP1_INTEGRATION_GUIDE.md`) that details how V3 replaces the signer set with SP1 zkVM proofs. Use this for the V3/ZK sections.

---

## What ePrint Expects (Non-Negotiable Requirements)

### 1. Formal Threat Model (NEW — does not exist in current paper)

Write a section titled **"Security Model"** that defines:

- **System model**: a set of N origin chains and M target chains, each running EVM-compatible consensus. An escrow contract E_i on each origin chain, a factory contract F_j on each target chain. A signer set S = {s_1, ..., s_n} with threshold t (in V1: n=5, t=3).

- **Adversary model**: a PPT adversary A who can corrupt up to t-1 signers, observe all public chain state, submit arbitrary transactions, and control network delivery timing (but not break ECDSA or keccak256 preimage resistance). State the honest majority assumption explicitly: "We assume at most t-1 of n signers are Byzantine."

- **Security properties** (define each formally, then prove/argue each one):

  **Property 1 — Supply Conservation (Safety):**
  For any lockId, the total supply of xRWA minted across all target chains for that lockId never exceeds the amount locked in the origin escrow for that lockId. Formally: ∀ lockId: Σ_j minted_j(lockId) ≤ locked(lockId).

  **Property 2 — No Unbacked Mints (Safety):**
  xRWA can only be minted for a lockId if a corresponding lock of equal amount exists in the origin escrow and has not been cancelled or released. Formally: mintedFromLock[lockId] = true ⟹ ∃ lock in E_i where lock.amount = mint.amount ∧ ¬cancelled[lockId] ∧ ¬released[lockId].

  **Property 3 — Redeemability (Liveness):**
  If a user burns xRWA on a target chain for a lockId, the user can eventually reclaim the original RWA from the origin escrow, assuming at least t honest signers are online (V1) or the origin chain is live and the proof system is sound (V3). Formally: burnedForLock[lockId] = true ∧ liveness_assumption ⟹ ◇ released[lockId] = true.

  **Property 4 — No Double Spend:**
  Each lockId can result in at most one mint, one burn, and one release. Formally: the mappings mintedFromLock, burnedForLock, and released are monotonic (false → true, never true → false), and each is written at most once per lockId.

  **Property 5 — Cross-Chain Replay Resistance:**
  A receipt valid on chain j cannot be used to mint on chain k ≠ j. Argue from EIP-712 domain separation (chainId + verifyingContract pinned in domain).

### 2. Proof Sketches (NEW — does not exist in current paper)

For each security property above, write a **proof sketch** (not a full formal proof, but a rigorous argument). Example structure:

```
Claim: Property 1 (Supply Conservation) holds under the honest majority assumption.

Proof sketch: 
(1) mintFromLock(lockId) checks mintedFromLock[lockId] == false before setting 
    it to true (one-shot guard). Since EVM storage writes are atomic within a 
    transaction, concurrent calls for the same lockId are serialized by the 
    chain's consensus, and exactly one succeeds.
(2) The lockId is deterministically computed from (escrow, locker, rwaToken, 
    amount, nonce). The nonce is incremented atomically in escrow.lock(), so 
    distinct lock operations produce distinct lockIds.
(3) Under the honest majority assumption (≥ t honest signers), no valid 
    LockReceipt can be produced for a lockId that does not correspond to a 
    real lock in E_i, because honest signers verify escrow.locks[lockId] 
    before signing.
(4) Therefore, each lockId maps to exactly one lock and at most one mint, 
    and the minted amount equals the locked amount (enforced by the receipt's 
    signed amount field). ∎
```

Write similar sketches for Properties 2–5. For V2 upgrades (self-rescue, slashing), state which property they strengthen and how.

### 3. Protocol Specification (REWRITE of current §4)

Replace the architecture diagram and Solidity snippets with a **formal protocol description**. Use the following format:

**State**: Define the state maintained by each contract as a set of mappings/variables.

**Messages**: Define the message types (LockReceipt, UnlockReceipt) as typed tuples with their EIP-712 domain.

**Protocol phases**: Describe as numbered steps with preconditions and postconditions:

```
Phase 1 — Lock:
  Precondition: User holds ≥ amount of rwaToken on origin chain.
  Action: User calls E.lock(rwaToken, amount, targetChainId).
  State change: E.locks[lockId] ← (locker, rwaToken, amount, timestamp, false).
                E.nonce ← E.nonce + 1.
                rwaToken.balanceOf(user) decreased by amount.
                rwaToken.balanceOf(E) increased by amount.
  Output: Locked(lockId, locker, rwaToken, amount, targetChainId) event.
  
Phase 2 — Attestation:
  Precondition: Signer s_i observes Locked event on origin chain with ≥ 12 
                block confirmations. s_i verifies E.locks[lockId] matches 
                event data via RPC query against ≥ 2 independent RPCs.
  Action: s_i signs LockReceipt = EIP712Sign(domain, {lockId, locker, 
          rwaToken, amount, originChainId, targetChainId, timestamp}).
  Output: Signature σ_i.
  
Phase 3 — Mint:
  Precondition: User has collected ≥ t valid signatures {σ_i} for a 
                LockReceipt R. F.mintedFromLock[lockId] == false.
  Action: User calls F.mintFromLock(R, signatures, bitmap).
  Verification: F recovers signer addresses from signatures via ecrecover.
                F checks each recovered address ∈ SignerRegistry.getSignerSet().
                F checks |valid signatures| ≥ t.
                F checks mintedFromLock[lockId] == false.
  State change: F.mintedFromLock[lockId] ← true.
                If no mirror exists for corridor: CREATE2-deploy XythumToken.
                XythumToken.mint(locker, amount).
  Output: MintedFromLock(lockId, locker, mirror, amount) event.
```

Do the same for Phase 4 (Burn), Phase 5 (Unlock Attestation), Phase 6 (Release). Also describe the Cancel path (V2.1) and the Merkle Proof Release path (V2.2) as alternative Phase 6 variants.

Include a **state machine diagram** for a lockId's lifecycle:

```
             lock()              mintFromLock()
  EMPTY ──────────► LOCKED ──────────────────► MINTED
                      │                           │
                      │ cancelLock()     burnForLock()
                      │ (after 24h)               │
                      ▼                           ▼
                  CANCELLED                    BURNED
                                                  │
                                        release() │ or releaseViaProof()
                                                  ▼
                                              RELEASED
```

### 4. Evaluation Section (NEW — does not exist in current paper)

Extract real data from your testnet deployments and present:

- **Gas costs**: Measure and report gas for each operation:
  - `lock()` — expected ~80-120k gas
  - `mintFromLock()` (with mirror deployment) — expected ~300-500k gas
  - `mintFromLock()` (mirror exists) — expected ~100-150k gas
  - `burnForLock()` — expected ~60-80k gas
  - `release()` — expected ~100-150k gas
  - `mintFromLockZK()` (V3) — expected ~280k for proof verification + ~100k for mint logic

  Present as a table. Compare to CCIP and LayerZero costs for equivalent operations.

- **Latency breakdown**: Measure each phase:
  - Lock tx confirmation: X seconds
  - Signer attestation collection: X seconds
  - Mint tx submission + confirmation: X seconds
  - Total round-trip: X seconds

  Present as a timeline diagram or table across the three testnets.

- **Proof generation benchmarks** (for V3 section):
  - SP1 lock proof cycle count (estimate from sp1-eth-get-proof-verifier benchmarks)
  - Estimated proving time on CPU / GPU
  - Estimated proving cost on Succinct Prover Network
  - On-chain verification gas

### 5. Related Work with Citations (REWRITE of current §2)

The current §2 mentions protocols by name but has zero citations. Add proper academic/technical references. Minimum 15-25 citations including:

- LayerZero ePrint paper: "LayerZero: Trustless Omnichain Interoperability Protocol" (if available on ePrint)
- Chainlink CCIP whitepaper
- Wormhole whitepaper / security documentation
- ERC-3643 standard (EIP)
- EIP-712 typed data signing
- Groth16: "On the Size of Pairing-based Non-interactive Arguments" (Groth, 2016)
- PLONK: "PLONK: Permutations over Lagrange-bases for Oecumenical Noninteractive arguments of Knowledge" (Gabizon et al., 2019)
- SP1/Succinct: reference the SP1 documentation and audit reports
- Nova folding: "Nova: Recursive Zero-Knowledge Arguments from Folding Schemes" (Kothapalli, Setty, Tzialla, 2022)
- Bridge security analysis papers (Ronin post-mortem, Wormhole post-mortem)
- RWA tokenization: cite RWA.xyz data, BlackRock BUIDL announcements, relevant DeFi research
- Merkle Patricia Tries: cite the Ethereum Yellow Paper (Wood, 2014)
- Cross-chain security: "SoK: Communication Across Distributed Ledgers" (Zamyatin et al., 2021) — this is on ePrint
- Circle CCTP documentation
- "xRWA: A cross-chain framework for interoperability of real-world assets" (ScienceDirect, 2026) — NOTE: this paper exists and covers similar ground. You MUST cite it and differentiate. The key difference is: xRWA (the paper) uses DID/VC-based identity and SPV-based authentication. Xythum uses threshold-signed attestations with a clear V3 migration to ZK state proofs. Xythum also has working testnet deployments with concrete gas benchmarks.

### 6. V3 ZK Section (REWRITE of current §11)

The current V3 section is 1 page of hand-waving. Expand it to 3-4 pages using the SP1 integration guide. Cover:

- **Concrete proof construction**: The guest program verifies block header integrity (keccak256), MPT account proof (escrow exists under stateRoot), MPT storage proof (locks[lockId] data matches), and optionally receipt proof (Locked event emitted). Public values committed: blockHash, lockId, locker, rwaToken, amount, originChainId, escrowAddress.

- **Block hash oracle problem**: Explain that the SP1 proof is conditioned on a trusted block hash. Describe the three options for block hash delivery (ZK light client, signer-attested headers, third-party header feed). Be explicit that Option B (signer-attested headers) still requires a trust assumption, but it's strictly weaker than V1 (signers attest to objective data, not subjective claims).

- **On-chain verification**: SP1 wraps STARK proofs into PLONK on BN254. Verification cost is ~280k gas via Succinct's pre-deployed SP1VerifierGateway contracts. The factory contract calls `ISP1Verifier.verifyProof(vkey, publicValues, proofBytes)`.

- **Why SP1 over alternatives**: SP1 has a native keccak256 precompile critical for MPT verification. RISC Zero lacks this. Hand-rolled PLONK/Groth16 circuits would require 2-3 months of circuit development; SP1 lets you write the verification logic in Rust.

---

## Structural Changes

### New Paper Structure (replace current TOC):

```
1. Introduction
2. Related Work (with citations)
3. System Model and Security Definitions
   3.1 System Model
   3.2 Adversary Model
   3.3 Security Properties
4. Protocol Description
   4.1 State Definitions
   4.2 Message Types
   4.3 Lock-Mint-Burn-Release Protocol
   4.4 LockId Lifecycle State Machine
   4.5 Invariants
5. V1: Threshold-Signed Attestation
   5.1 Signer Registry and Quorum
   5.2 EIP-712 Receipt Structure
   5.3 Attack Surface Analysis
6. V2: Progressive Trust Reduction
   6.1 Time-Locked Self-Rescue (V2.1)
   6.2 Trustless Burn-Attestation via Merkle Proof (V2.2)
   6.3 Signer Bonding and Slashing (V2.3)
   6.4 Guardian Circuit Breaker (V2.4)
   6.5 Multi-RPC Signer Infrastructure (V2.5)
7. V3: ZK State Proof Migration
   7.1 SP1 zkVM Lock Proof Construction
   7.2 Burn Proof Construction
   7.3 Block Hash Oracle Design
   7.4 On-Chain Verification
   7.5 Migration Path (V1 → V3 Coexistence)
8. Security Analysis
   8.1 Proof of Supply Conservation
   8.2 Proof of No Unbacked Mints
   8.3 Proof of Redeemability
   8.4 Proof of No Double Spend
   8.5 Proof of Cross-Chain Replay Resistance
   8.6 V2 Upgrade Impact on Security Properties
9. Evaluation
   9.1 Gas Cost Analysis
   9.2 Latency Measurements
   9.3 V3 Proof Generation Benchmarks
   9.4 Comparison with CCIP, LayerZero, CCTP
10. Discussion
    10.1 Limitations
    10.2 Non-Goals
    10.3 Compliance Considerations
11. Conclusion
Appendix A: Glossary
Appendix B: Testnet Deployment Addresses
Appendix C: Solidity Interface Specifications
References
```

### Formatting Rules for ePrint:

- Use LaTeX. ePrint accepts PDF generated from LaTeX. Use the `iacr.cls` class if available, otherwise `article` class with standard crypto paper formatting.
- All Solidity code goes in **Appendix C**, not inline. The main body uses **pseudocode** for protocol steps.
- Tables for gas costs, comparisons, and benchmarks.
- Figures for the state machine diagram and the architecture overview.
- No marketing language. Remove phrases like "Xythum is a better-shaped primitive" — replace with neutral technical comparisons.
- No roadmap/timeline table. The ePrint paper describes V1 (implemented), V2 (designed), and V3 (specified). It does not promise delivery dates.
- Remove the "No token in V1 or V2" discussion. Irrelevant to a protocol paper.
- Remove the "economic model" section (§12). This is business, not protocol. If signer bond economics are relevant, fold them into §6.3 as a security parameter analysis.

---

## What to Keep from the Current Paper

These sections are strong and should be preserved (with formatting changes):

- **Trust model (§3)**: The "what 3 signers can do / cannot do" enumeration is excellent. Keep it, but formalize the claims as properties and prove them.
- **Invariants table (§4.5)**: This becomes the basis for the security properties. Formalize each row.
- **V2.1–V2.5 designs (§6–§10)**: The problem/solution structure is good. Remove inline Solidity; use pseudocode. Add which security property each upgrade strengthens.
- **Non-goals (§15)**: Keep as §10.2. Rare and credible in academic papers too.
- **Architecture diagram (§4.1)**: Keep as a figure but redraw cleanly (not ASCII art).
- **Testnet addresses (Appendix B)**: Keep. Shows this is implemented, not vaporware.

---

## What to Remove or Relocate

- **§5 (Demo lending market)**: Remove entirely. It's a product demo, not a protocol contribution. Mention in one sentence in the introduction: "We demonstrate composability via a minimal lending market on testnet."
- **§12 (Economic model)**: Remove. Token/revenue discussion is not protocol.
- **§13 (Comparison table)**: Rewrite as a proper related work comparison in §2 and a benchmarks comparison in §9.4. Remove marketing framing.
- **§14 (Timeline)**: Remove. No roadmap in ePrint papers.
- **Inline Solidity**: Move all code to Appendix C. Main body uses pseudocode only.

---

## Deliverable

A single markdown file (or LaTeX source) with the complete rewritten paper following the structure above. Target length: 18-25 pages in standard academic formatting (single column, 11pt, reasonable margins). The current paper is ~15 pages with lots of code; the rewrite will be similar length but denser on analysis and lighter on implementation detail.

Priority order if you need to cut scope:
1. Security model + proof sketches (MUST HAVE)
2. Protocol specification with state machine (MUST HAVE)
3. V3 ZK section expansion (MUST HAVE)
4. Evaluation with gas benchmarks (SHOULD HAVE — can use estimates if testnet data unavailable)
5. Full related work with citations (SHOULD HAVE)
6. LaTeX formatting (NICE TO HAVE — markdown is fine as draft)
