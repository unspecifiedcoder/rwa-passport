# Xythum v2 Roadmap

## Position relative to v1

v1 (the lock → mint → burn → unlock round-trip we just shipped) gives you:

- Deterministic CREATE2 mirrors per `(origin, srcChain, dstChain)`
- 3-of-5 ECDSA threshold-signed lock and unlock receipts
- ~60-second round-trip latency on testnet (vs 40-70 min for CCIP)
- Cumulative `mintCap` high-water-mark accounting

What v1 deliberately does NOT solve, and what v2 must:

1. Funds stuck if signers are offline (no self-rescue)
2. Mirrors mintable without real lock if signers collude (no slashing)
3. Original RWA stuck in escrow if burn happens but signers refuse to sign UnlockReceipt (no trustless redemption path)
4. Operational — signer software must trust on-chain state, not a single RPC

v2 is structured so each item ships as an independent module without breaking
v1 contracts already in production.

---

## v2.1 — Time-locked self-rescue (priority: HIGH)

**Problem:** in v1, if signers go offline indefinitely after a user has locked,
the user's RWA is stuck in escrow forever.

**Solution:** add `RWALockEscrow.cancelLock(lockId)`. After a configurable
timeout (default 24h), the original locker can self-rescue if no
`MintedFromLock` event has been observed from the target chain.

```solidity
// in RWALockEscrow.sol
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

**Off-chain signer policy update:** signers refuse to sign a LockReceipt for
any `lockId` whose `cancelLock` event they have observed on the origin chain.
This is the contract-and-policy combo that prevents double-issuance (one mint
on target + one cancel on origin for the same lockId).

**Interaction with `mintFromLock`:** add a new check that mirrors the cancel.
If `mirror` already exists for the corridor and the user proves cancellation
via Merkle/event proof, the factory blocks the mint. (See v2.2.)

---

## v2.2 — Trustless burn-attestation via Merkle proof (priority: HIGH)

**Problem:** if a user burns xRWA on the target chain but the signers refuse
to sign the UnlockReceipt, the original RWA is stuck in escrow.

**Solution:** add a fallback path on `RWALockEscrow.release` that accepts a
Merkle proof of the `BurnedForLock` event log from the target chain in lieu
of an UnlockReceipt. This requires either:

- **Light-client of the target chain** on the origin chain (e.g., LayerZero
  Endpoint v2, Hyperlane ISM, or a dedicated header oracle).
- **Hybrid**: signers sign block-header roots periodically. After 24h with no
  UnlockReceipt arriving, the user can submit a header proof + Merkle proof
  of the burn log under that header.

```solidity
function releaseViaProof(
    UnlockReceipt calldata receipt,
    bytes calldata blockHeaderProof,
    bytes calldata burnEventProof
) external {
    // Verify blockHeaderProof references a target-chain header signed by signers
    // Verify burnEventProof shows BurnedForLock(lockId, ...) under that header
    // Same lock-state checks as `release`
    // Mark released, transfer
}
```

**Why this matters:** removes "stuck after burn" from the failure modes table.
Once shipped, the only remaining custody risk is signer collusion on the
*outbound* lock side, which v2.3 handles.

---

## v2.3 — Signer bonding + slashing (priority: MEDIUM)

**Problem:** 3+ colluding signers can mint mirrors without backing.

**Solution:** introduce `SignerBondVault.sol`. Signers must post a bond (ETH
or stablecoin) before they can be registered. Provable misbehavior (two
conflicting receipts for the same lockId, signing a receipt without a real
lock event) is slashable by anyone via on-chain proof.

```solidity
contract SignerBondVault {
    mapping(address signer => uint256 bond) public bonds;
    uint256 public minBond = 50 ether;

    function postBond() external payable;
    function withdrawBond() external; // 14-day unbonding period

    /// @notice Anyone can prove that `signer` signed two receipts with the same
    ///         lockId but different content. If proven, the signer's bond is slashed.
    function slashConflicting(
        bytes32 lockId,
        ReceiptLib.LockReceipt calldata receiptA, bytes calldata sigA,
        ReceiptLib.LockReceipt calldata receiptB, bytes calldata sigB
    ) external;

    /// @notice Slashable: signer signed a LockReceipt for an originContract
    ///         that has no Locked event in the escrow.
    function slashFakeLock(
        bytes32 lockId,
        ReceiptLib.LockReceipt calldata receipt, bytes calldata sig,
        bytes calldata escrowStateProof  // proves escrow.locks[lockId].amount == 0
    ) external;
}
```

**Cost-of-attack:** with `minBond = 50 ETH × 5 signers = 250 ETH at risk`,
collusion to mint a $X mirror requires `X > 250 ETH × 0.6` to be profitable
(60% of bonds are slashable to honest provers). Tunable per chain.

---

## v2.4 — Guardian multisig (priority: MEDIUM)

**Problem:** even with bonding, a sufficiently large attack on a high-value
corridor could justify slashing as a cost of doing business. Need a circuit
breaker.

**Solution:** a separate 2-of-3 multisig (independent of the signer set) that
can:

- `pauseEscrow(escrow)` — freeze new locks and releases
- `pauseFactory(factory)` — freeze new mints
- `invalidateLockId(lockId)` — explicitly mark a lockId as poisoned. Mirror
  factory and escrow refuse all future actions on that lockId.

```solidity
contract GuardianMultisig {
    address[3] public guardians;
    mapping(bytes32 => uint256 confirmations) public ops;

    modifier confirmed(bytes32 op) {
        if (++ops[op] < 2) return;  // 2-of-3
        _;
    }

    function pauseEscrow(address escrow) external confirmed(...) {
        IRWALockEscrow(escrow).pause();
    }
    // ...
}
```

The guardian multisig should be controlled by **different parties** than the
signer set — ideally one issuer rep, one Xythum rep, one external auditor
or DAO-elected member. This prevents 1-party catastrophic compromise.

---

## v2.5 — Operational: multi-RPC signer software (priority: HIGH)

**Problem:** in v1, signer software reads `escrow.locks[lockId]` from a
single RPC before signing. A compromised RPC can lie, causing signers to
sign LockReceipts for non-existent locks.

**Solution:** signer service architecture (off-chain, no contract changes):

```
┌──────────────────────────────────────────────────────────┐
│ Signer service (per signer)                              │
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

Out of scope for the contract layer. Belongs in a separate `signer-service/`
package (Rust or Go) with its own CI and threat model. Documented here so
deployers know what's expected of operators.

---

## v3 — ZK migration

The end-state where signers are removed entirely. The interface boundary in
v1 is already designed for this:

```solidity
// in CanonicalFactory.sol (v1)
function mintFromLock(LockReceipt receipt, bytes sigs, uint256 bitmap)

// in CanonicalFactory.sol (v3)
function mintFromLockZK(bytes32 commitment, bytes proof)
```

Both functions consume the same `RWALockEscrow.lock()` flow on the origin
chain. The only thing that changes is what proves "the lock happened."

### Required circuit work

1. **Lock proof circuit**: prove `escrow.locks[lockId].amount == claimedAmount`
   AND `not cancelled[lockId]` AND `not released[lockId]` for a given lockId,
   given the origin chain's state root.
2. **Burn proof circuit**: prove `BurnedForLock(lockId, amount)` was emitted
   on the target chain, given a target-chain state root.
3. **Cross-chain state-root oracle**: a header oracle (or signer-attested
   block-root committee) that publishes verified state roots from origin and
   target chains onto the chain where the proof is consumed.

Estimated effort: 2-3 months of circuit dev + 2 months audit. ZK upgrade is
post-product-market-fit; ship v2.1-v2.4 first.

---

## Sequencing

| Quarter | Ship | Why now |
|---|---|---|
| Q1 (now) | v1 (DONE) | Prove the round-trip works |
| Q2 | v2.1 (self-rescue) + v2.5 (multi-RPC signers) | Removes "stuck forever" failure mode for users |
| Q2-Q3 | v2.4 (guardian multisig) | Operational safety net |
| Q3 | v2.2 (trustless burn-attestation) | Last single-point-of-failure removal |
| Q4 | v2.3 (signer bonding) | Economic security; required before institutional users sign |
| Q5+ | v3 (ZK migration) | Once flow is proven and audited at scale |

The order is deliberate: things that can stuck users' funds get patched first.
Things that change economics ship after the flow has demonstrated stability.

---

## Items NOT on the roadmap (and won't be)

- **Native xRWA-to-xRWA bridges** — defer to LayerZero / CCIP / Hyperlane. We
  are an issuance-side identity layer, not a bridge.
- **A governance token** — premature; dilutes the customer pitch and triggers
  regulatory scrutiny before product-market fit.
- **Issuer-side tokenization** — issuers tokenize their own RWAs (Ondo,
  Centrifuge, Maple, Backed.fi). We mirror what they've already issued.
- **Compliance / KYC stack** — `ComplianceEngine` integrates external
  compliance (ERC-3643, Onchain ID). We do not build the compliance layer.
- **Lending or AMM layer** — xRWA goes into Aave / Morpho / Curve as a regular
  ERC-20. We are upstream of credit, not in it.

If a feature request doesn't fit one of v2.1-v2.4 or v3, it's almost
certainly out of scope.
