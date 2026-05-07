# Session Handoff — Xythum RWA Passport

> **Purpose:** durable context for any new chat session. Read this file first
> after a `/compact` or new session — everything important is here, so the
> agent doesn't have to dig through prior turns.

Last updated: 2026-04-28

---

## TL;DR — current state in 5 lines

1. **v1 of the lock-mint-burn-unlock round-trip is done and live on testnet** — Fuji ↔ BNB ↔ Monad.
2. **38/38 contract tests passing.** `forge test --via-ir`.
3. **Frontend `/lock` page is wired** and corridors show `READY` once dev server is restarted (env reload).
4. **3 RWALockEscrow contracts deployed.** Addresses in `frontend/src/lib/contracts.ts` and `.env`.
5. **We work from `~/xythum-frontend` (native WSL Linux fs) for speed.** Edits are made on `/mnt/e/.../frontend/` (canonical) and rsync'd to `~/xythum-frontend`.

---

## Where things live

### Two working copies — keep them in sync

| Path | Purpose | Speed |
|---|---|---|
| `/mnt/e/github2/XYTHUM RWA PASSPORT/xythum-rwa/` | **Canonical source.** Contracts, docs, scripts, frontend. Slow to compile (Windows NTFS via WSL 9P). | Slow |
| `~/xythum-frontend/` | Working copy of `frontend/` only, on native ext4. Used to run `npm run dev` + `tsc --noEmit`. | Fast |

**Sync rule (run after every frontend edit):**

```bash
cd ~ && rsync -a --delete \
  --exclude=node_modules --exclude=.next --exclude=.turbo \
  "/mnt/e/github2/XYTHUM RWA PASSPORT/xythum-rwa/frontend/" ~/xythum-frontend/
```

Reverse-sync (when an edit happens directly in `~/xythum-frontend/`):

```bash
rsync -a --exclude=node_modules --exclude=.next --exclude=.turbo \
  ~/xythum-frontend/ \
  "/mnt/e/github2/XYTHUM RWA PASSPORT/xythum-rwa/frontend/"
```

### Key files added or changed in this session

#### New contracts
- `src/libraries/SignatureLib.sol` — shared ECDSA threshold-sig verification
- `src/libraries/ReceiptLib.sol` — `LockReceipt` + `UnlockReceipt` EIP-712 structs
- `src/escrow/RWALockEscrow.sol` — per-chain escrow holding original RWAs
- `src/interfaces/IRWALockEscrow.sol`

#### Modified contracts
- `src/core/XythumToken.sol` — added `burnForLock(amount, lockId)`, `bumpCapAndMint(to, amount, lockId)`, `burnedForLock` mapping, `BurnedForLock` event
- `src/core/CanonicalFactory.sol` — added `mintFromLock(receipt, sigs, bitmap)` with auto-deploy (CREATE2-creates the mirror if no mirror exists yet for the corridor), `mintedFromLock` mapping, `MintedFromLock` event, `_deployTokenForLock`, `_registerMirrorFromLock`
- `src/interfaces/IXythumToken.sol` — added `burnForLock`, `bumpCapAndMint`, `burnedForLock`

#### Tests (all passing under `--via-ir`)
- `test/unit/escrow/RWALockEscrow.t.sol` — 19 tests
- `test/unit/XythumTokenLock.t.sol` — 8 tests
- `test/unit/factory/CanonicalFactoryMintFromLock.t.sol` — 8 tests
- `test/integration/RoundTrip.t.sol` — 3 tests

#### Test helpers
- `test/helpers/ReceiptHelper.sol` — signs `LockReceipt`/`UnlockReceipt` with deterministic test keys

#### Pre-existing fix (compilation blocker)
- `test/unit/CanonicalFactory.t.sol` — renamed duplicate function `test_computeMirrorAddress_different_for_different_origins` (second occurrence) to `_different_for_different_targetChains`

#### Deploy script
- `script/DeployEscrow.s.sol` — runs per-chain, prints replay-domain audit warning + bytecode hash

#### Docs
- `docs/V2_ROADMAP.md` (new) — v2.1 self-rescue · v2.2 trustless burn-attestation · v2.3 signer bonding · v2.4 guardian multisig · v2.5 multi-RPC signer ops · v3 ZK migration
- `README.md` — added Trust Model section + `/lock` page row + V2_ROADMAP link

#### Frontend
- `src/lib/wagmi.ts` — RainbowKit `getDefaultConfig`, Alchemy primary + public RPC fallback for Fuji/BNB/Monad. Bad endpoints removed (`drpc.org` fails `eth_estimateGas` on Monad — known broken).
- `src/lib/chains.ts` — Fuji + BNB now have multi-RPC `default.http` arrays
- `src/lib/signing.ts` — added `signLockReceipt`, `signUnlockReceipt`, types `LockReceipt`, `UnlockReceipt`
- `src/lib/contracts.ts` — added `lockEscrow` field to `CONTRACTS` + 3 new ABIs (`RWA_LOCK_ESCROW_ABI`, `CANONICAL_FACTORY_MINT_FROM_LOCK_ABI`, `XYTHUM_TOKEN_BURN_FOR_LOCK_ABI`, `ERC20_APPROVE_ABI`)
- `src/app/lock/page.tsx` (new) — full lock → sign → mint → burn → sign → release flow
- `src/app/providers.tsx` — RainbowKit wrap
- `src/components/ConnectButton.tsx` — custom wallet picker dropdown (user replaced the RainbowKit stock with a styled one; keep as-is)
- `src/components/Navbar.tsx` — added `/lock` route
- `src/app/attest/page.tsx` — auto-runs deploy after `switchChain` success; pre-flight check for already-existing mirror with friendly error mapping (`MirrorAlreadyDeployed` → "use a different origin")

---

## Live testnet addresses

```
Avalanche Fuji (43113):
  signerRegistry:      0xF17BBD22D1d3De885d02E01805C01C0e43E64A2F
  attestationRegistry: 0xd0047E6F5281Ed7d04f2eAea216cB771b80f7104
  canonicalFactory:    0x0BA5bd535Ee071993643Cbb815368F55648B9365   ← REDEPLOYED 2026-04-28 (adds mintFromLock)
  ccipSender:          0x1062C2fBebd13862d4D503430E3E1A81907c2bD7
  ccipReceiver:        0xC740E9D56c126eb447f84404dDd9dffbB7AEd5F8
  mockRwa (mTBILL):    0xD52b37AD931F221A902fC7F43A9ed2D87Ce07C5F
  mirrorToken:         0x64D3c71cB8910553A55C143eC8d0f5900b70cFb5   ← Monad-mTBILL → Fuji canonical mirror
  ★ lockEscrow:        0x557474BEd7701ee5290CeB232DDa1Fa06799aA5F   ← NEW (M6)
  ★ xythumLend:        0xA1488D1063930947344305D851Ef90dF98944260   ← NEW (M7) demo lending market
  ★ mockUsdc:          0x3BeF60e85DA825AEe0449a8438FA8d943A07c848   ← NEW (M7) faucet + reserves

BNB Testnet (97):
  signerRegistry:      0xFA6aFAcfAA866Cf54aCCa0E23883a1597574206c
  attestationRegistry: 0xe27E5e2D924F6e42ffa90C6bE817AA030dE6f48D
  canonicalFactory:    0x4d0a5A6bf63a25bd6577Bdcda0f48e19843CacBC   ← REDEPLOYED 2026-04-28 (adds mintFromLock)
  ccipSender:          0x3823baE274eB188D3dF66D8bc4eAAaf0F050dAD6
  ccipReceiver:        0xDc1f35F18607c8ee5a823b1ebBc5eDFe0fb253F3
  mockRwa:             0x31004d16339C54f49FDb0dE061846268eE59B4af
  mirrorToken:         (orphaned by factory redeploy — re-attest on /attest to repopulate)
  ★ lockEscrow:        0x6BbD75e43Bb3515c54BeCAF6B17B69458A8201A3   ← NEW (M6)

Monad Testnet (10143):
  signerRegistry:      0x725cCe0916d2E8682438732fD9e79803B4fAB2BD
  attestationRegistry: 0xe27E5e2D924F6e42ffa90C6bE817AA030dE6f48D
  canonicalFactory:    0x27b678acD971f851Ce19751482371eC76b929B41   ← REDEPLOYED 2026-04-28 (adds mintFromLock)
  mockRwa:             0x430172985b21458d73576435D4aD4bEeA85F376C
  mirrorToken:         (orphaned by factory redeploy — re-attest on /attest to repopulate)
  ★ lockEscrow:        0xCe1D8aF9ae9039A12A157D6ec53eC87F906773C4   ← NEW (M6)

Deployer (funded on all 3 chains):
  0x72db032c0dFB6E7502e16A73fabdab31712dc706
```

---

## Env / secrets

Path: `/mnt/e/github2/XYTHUM RWA PASSPORT/xythum-rwa/.env`
Path: `/mnt/e/github2/XYTHUM RWA PASSPORT/xythum-rwa/frontend/.env.local` (and `~/xythum-frontend/.env.local`)

```bash
# Deployer (private key — testnet ONLY)
PRIVATE_KEY=0x6b85bf9aae2701fbd120a260b3198809a9219f1f54fc892230d768afca1dfb5a
DEPLOYER_ADDRESS=0x72db032c0dFB6E7502e16A73fabdab31712dc706

# RPCs (in repo .env)
RPC_AVALANCHE_FUJI=https://api.avax-test.network/ext/bc/C/rpc
RPC_BNB_TESTNET=https://data-seed-prebsc-1-s1.bnbchain.org:8545
RPC_MONAD_TESTNET=https://testnet-rpc.monad.xyz

# Frontend (.env.local)
NEXT_PUBLIC_ALCHEMY_API_KEY=im3woiuJhXEZW-Oo0fPJ8
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=8eb93a9f40d7e702a25e77322cf101c2

# SignerRegistry per chain (mirrors contracts.ts; in repo .env)
SIGNER_REGISTRY_FUJI=0xF17BBD22D1d3De885d02E01805C01C0e43E64A2F
SIGNER_REGISTRY_BNB=0xFA6aFAcfAA866Cf54aCCa0E23883a1597574206c
SIGNER_REGISTRY_MONAD=0x725cCe0916d2E8682438732fD9e79803B4fAB2BD

# RWALockEscrow per chain (M6)
LOCK_ESCROW_FUJI=0x557474BEd7701ee5290CeB232DDa1Fa06799aA5F
LOCK_ESCROW_BNB=0x6BbD75e43Bb3515c54BeCAF6B17B69458A8201A3
LOCK_ESCROW_MONAD=0xCe1D8aF9ae9039A12A157D6ec53eC87F906773C4
```

The 5 demo signer keys used by both attestations and receipts are derived
deterministically by `frontend/src/lib/signing.ts`:
`keccak256("xythum-demo-signer-1")` … `…-5`.

---

## How to run

### Tests (regression)

```bash
cd "/mnt/e/github2/XYTHUM RWA PASSPORT/xythum-rwa"
forge test --via-ir \
  --match-contract "RWALockEscrowTest|XythumTokenLockTest|CanonicalFactoryMintFromLockTest|RoundTripTest"
# expected: 38 passed; 0 failed
```

`forge build` on `/mnt/e/` may OOM-kill the default-profile compile; the
`--via-ir` profile compiles fine. Tests use that profile.

### Frontend dev server

```bash
cd ~/xythum-frontend
rm -rf .next                # only after env or wagmi changes
npm run dev                 # ~30-60s cold start on native fs
# → http://localhost:3000
```

If working from `/mnt/e/...` instead, expect 2+ minute cold starts. Always
prefer `~/xythum-frontend` for dev work.

### Deploying a new escrow on a 4th chain

```bash
cd "/mnt/e/github2/XYTHUM RWA PASSPORT/xythum-rwa"
set -a && . .env && set +a
forge script script/DeployEscrow.s.sol \
  --rpc-url $RPC_<CHAIN> --broadcast --via-ir --legacy \
  --sig "run(address)" $SIGNER_REGISTRY_<CHAIN>
# Then paste the printed address into frontend/src/lib/contracts.ts
# under that chain's `lockEscrow` field, and rsync to ~/xythum-frontend.
```

`--legacy` flag is required on BNB testnet (won't accept low EIP-1559 tips).

---

## Known gotchas the agent should remember

1. **WSL filesystem is the dominant performance bottleneck.** `/mnt/e/` ops are 10-50× slower than `~/`. ALWAYS work in `~/xythum-frontend` for `npm run dev` + `tsc`. Sync to `/mnt/e/` for git/canonical.
2. **`--via-ir` is required for `forge build`/`forge test`.** Without it: `Stack too deep` in `test/integration/FullFlow.t.sol`.
3. **BigInt literals (`0n`) are forbidden** in this frontend — tsconfig target is below ES2020. Use `BigInt(0)`.
4. **Don't pass `chainId:` directly to `useDeployContract` / `useWriteContract`.** Use `useSwitchChain` with chained `onSuccess` callbacks. The pattern that works is in `/attest`:
    ```ts
    if (chainId !== dir.sourceChain.id) {
      switchChain({ chainId: dir.sourceChain.id }, { onSuccess: () => doDeploy() });
      return;
    }
    doDeploy();
    ```
5. **`drpc.org` Monad RPC silently fails `eth_estimateGas`** even though `getBalance` works. Do NOT add it to fallback transports. Verified working endpoints for Monad: `testnet-rpc.monad.xyz`, `monad-testnet.g.alchemy.com`, `rpc-testnet.monadinfra.com`.
6. **`MirrorAlreadyDeployed` revert (selector `0x92f3fa7d`)** is the most common UI failure on `/attest`. CREATE2 = one mirror per `(originContract, originChainId, targetChainId)`. To deploy again to the same corridor, mint a fresh MockRWA first (different origin → different salt). The `/attest` page now pre-flights `factory.mirrors[salt]` and surfaces the existing mirror clearly.
7. **viem error "RPC endpoint returned too many errors"** is misleading — it usually wraps a contract revert that the wallet returned. Decode by selector, not by message.
8. **Custom `ConnectButton.tsx`** (not RainbowKit's stock). User picked a manual dropdown over RainbowKit's modal. Don't revert.
9. **Pre-deployed mirror tokens** in `contracts.ts` (`mirrorToken` field) come from prior `deployMirrorDirect` runs; they are NOT the mirrors that `mintFromLock` will create for the lock cycle. The lock-cycle mirror auto-deploys on first `mintFromLock` call for a fresh `(origin, src, dst)` triple — usually a different address than the existing `mirrorToken`. The `/lock` page accepts the user pasting the mirror address shown after a successful mint.
10. **`mintCap` is a cumulative high-water mark.** Each lock bumps cap by `receipt.amount`. Burns do NOT decrement it. This is intentional (matches existing `totalMinted` semantics).

---

## Trust model (one paragraph)

3-of-5 ECDSA threshold signers attest to lock + burn events off-chain.
Same trust model as wBTC's BitGo. If 3+ signers go offline, locked RWAs
are temporarily stuck (no fund loss). If 3+ collude, mirrors can be
minted without backing — this is the core v1 trust assumption. v2 adds
self-rescue + bonding + guardian pause; v3 replaces signers with ZK
proofs. See `docs/V2_ROADMAP.md` for sequencing.

**Source-of-truth hierarchy when state diverges:**
1. `RWALockEscrow.locks[lockId]` — what's actually escrowed
2. `XythumToken.burnedForLock[lockId]` — what's actually burned
3. `CanonicalFactory.mintedFromLock[lockId]` — derivative
4. Off-chain signer attestations — authorize actions, do not decide truth

---

## Two pages, two purposes (so the agent doesn't suggest deleting one)

- `/attest` — one-shot **issuance** (mirror is a synthetic; original RWA stays on origin, never escrowed). Cap = `att.lockedAmount`. CCIP available.
- `/lock` — full **collateral round-trip** (origin RWA escrowed; redeemable by burning the mirror). Cumulative cap. No CCIP — uses signer-relayed receipts (~60s round-trip).

Both ship; they solve different protocol primitives.

---

## What is explicitly NOT being built (don't propose these)

- An issuer (we mirror, we don't tokenize)
- A bridge (CCIP/LayerZero already exist; we use them when needed)
- A lending protocol (xRWA → Aave/Morpho as a normal ERC-20)
- A compliance/KYC layer (`ComplianceEngine` integrates external; we don't build the stack)
- A signer service (operators run their own; out of scope)
- A general cross-chain message protocol
- A governance token in v1

First customer is RWA issuers (Ondo, Centrifuge, Backed, Maple) — not DeFi
protocols, not traders.

---

## Open task list (where to pick up next session)

| Priority | Item | Why |
|---|---|---|
| ★ | Demo flow: lock 100k mTBILL on Fuji → mint xRWA on BNB → burn → release | Verify the full UI cycle on testnet end-to-end. CLI confirmed; UI not yet. |
| ★ | Add CLI smoke script `scripts/round-trip.mjs` | Reproducible CI check; auto-test all 3 corridors |
| MEDIUM | v2.1 — `cancelLock(lockId)` self-rescue after 24h | First gap to close before any production traffic |
| MEDIUM | Off-chain signer service (the protocol assumes one but ships none) | Right now the frontend signs in-browser with embedded keys — only OK for testnet demo. |
| LOW | Polish `/lock` page status pills (poll `Locked` + `MintedFromLock` + `BurnedForLock` + `Released` events to compute live status) | Better UX, not blocking |
| LOW | Remove `viaIR: false` workaround in `foundry.toml` once `FullFlow.t.sol` is refactored | Tech debt |

---

## Memory pointer

Project memory (`/root/.claude/projects/-mnt-e-github2-XYTHUM-RWA-PASSPORT/memory/`):
- `MEMORY.md` — index
- `project_xythum_rwa.md` — high-level description
- `feedback_no_coauthor.md` — user pref: no co-author trailers in commit messages

If a fresh session needs to know something not in this file, fall back to:
1. Code itself (always authoritative)
2. `/root/.claude/plans/giggly-crafting-crab.md` — the original M1-M6 plan
3. `git log` and `git diff main` — recent history

---

## How a fresh session should bootstrap after `/compact`

```
1. Read this file in full.
2. Read /root/.claude/plans/giggly-crafting-crab.md (the v1 plan).
3. Skim docs/V2_ROADMAP.md to see what's next.
4. Run `forge test --via-ir --match-contract "RWALockEscrowTest|XythumTokenLockTest|CanonicalFactoryMintFromLockTest|RoundTripTest"` to confirm 38/38.
5. Ask the user what they want to do next.
```

Do NOT re-explore the codebase blindly; this file already covers the durable
state. Re-explore only if the user's request implies something not covered
here.
