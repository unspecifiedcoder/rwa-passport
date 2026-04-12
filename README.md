# XYTHUM RWA PASSPORT

> Cross-chain canonical RWA mirror protocol -- deterministic CREATE2 token deployment with threshold ECDSA attestations, dual-path delivery (instant direct + Chainlink CCIP), Uniswap V4 hooks, and ZK collateral proofs. Foundry + Next.js.

[![Tests](https://img.shields.io/badge/tests-214%20passing-brightgreen)]()
[![Solidity](https://img.shields.io/badge/solidity-0.8.26-blue)]()
[![Foundry](https://img.shields.io/badge/foundry-v1.2.3-orange)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

## What is this?

XYTHUM RWA PASSPORT creates **canonical mirror tokens** for Real-World Assets across multiple blockchains. When an RWA exists on Chain A, this protocol deploys an official, verifiable mirror on Chain B at a **deterministic address** -- so the same asset always lives at the same address on every chain.

The system ensures authenticity through **3-of-5 threshold ECDSA signatures**, preventing unauthorized or counterfeit mirrors. Two delivery paths are supported: **instant direct deployment** (~5 seconds) and **Chainlink CCIP relay** (~20-35 minutes).

### Key Properties

- **Deterministic**: Same CREATE2 address for the same asset across all chains
- **Canonical**: `isCanonical(address)` -- one on-chain call to verify authenticity
- **Threshold-signed**: 3-of-5 multi-sig attestation required for every mirror
- **Dual-path**: Instant direct deploy OR async CCIP relay
- **Composable**: Uniswap V4 hooks enforce compliance at the AMM level
- **Verifiable**: ZK Groth16 proofs for collateral ratios without revealing positions

## Architecture

```
  Source Chain (Fuji / BNB)                    Target Chain (BNB / Fuji)
 +--------------------------+                +--------------------------+
 |                          |                |                          |
 |  MockRWA (origin ERC-20) |                |  SignerRegistry (3/5)    |
 |          |               |                |          |               |
 |          v               |                |  AttestationRegistry     |
 |  CCIPSender -------------|--- CCIP ------>|--- CCIPReceiver          |
 |                          |                |          |               |
 |                          |                |          v               |
 |                          |    Direct ---->|  CanonicalFactory        |
 |                          |   (instant)    |   |-- deployMirrorDirect |
 |                          |                |   |-- deployMirror (CCIP)|
 |                          |                |   |-- mintMirror         |
 |                          |                |   '-- computeMirrorAddr  |
 |                          |                |          |               |
 |                          |                |  XythumToken (xRWA)     |
 |                          |                |   |-- ERC-20 mirror      |
 |                          |                |   |-- mintCap enforced   |
 |                          |                |   '-- compliance hook    |
 |                          |                |          |               |
 |                          |                |  RWAHook (Uniswap V4)   |
 |                          |                |   |-- beforeSwap check   |
 |                          |                |   '-- dynamic fees       |
 |                          |                |                          |
 |                          |                |  CollateralVerifier (ZK) |
 |                          |                |   '-- AaveAdapter        |
 +--------------------------+                +--------------------------+
```

**Bidirectional**: Both Fuji->BNB and BNB->Fuji are fully deployed and tested.

## Contracts

| Contract | Path | Description |
|---|---|---|
| `SignerRegistry` | `src/core/SignerRegistry.sol` | k-of-n threshold signer management with rotation cooldowns |
| `AttestationRegistry` | `src/core/AttestationRegistry.sol` | EIP-712 multi-sig attestation verification, rate limiting, nonce tracking |
| `CanonicalFactory` | `src/core/CanonicalFactory.sol` | Deterministic CREATE2 mirror deployment, dual-path (direct + CCIP), mint/minter management |
| `XythumToken` | `src/core/XythumToken.sol` | ERC-20 mirror with mint cap, authorized minters, pause, compliance hooks |
| `CCIPSender` | `src/ccip/CCIPSender.sol` | Sends cross-chain attestations via Chainlink CCIP |
| `CCIPReceiver` | `src/ccip/CCIPReceiver.sol` | Receives CCIP messages and triggers mirror deployment |
| `RWAHook` | `src/hooks/RWAHook.sol` | Uniswap V4 hook: compliance whitelist/blacklist + dynamic fees via hookData |
| `LiquidityBootstrap` | `src/hooks/LiquidityBootstrap.sol` | Time-weighted fee decay for bootstrapping new mirror liquidity |
| `CollateralVerifier` | `src/zk/CollateralVerifier.sol` | ZK Groth16 proof verification for collateral ratios |
| `AaveAdapter` | `src/adapters/AaveAdapter.sol` | Supplies verified collateral to Aave V3 |

## Live Testnet Deployment

Deployed and verified on **Avalanche Fuji** and **BNB Chain Testnet** with full bidirectional CCIP wiring.

| Contract | Fuji (43113) | BNB Testnet (97) |
|---|---|---|
| SignerRegistry | `0xF17BBD22D1d3De885d02E01805C01C0e43E64A2F` | `0xFA6aFAcfAA866Cf54aCCa0E23883a1597574206c` |
| AttestationRegistry | `0xd0047E6F5281Ed7d04f2eAea216cB771b80f7104` | `0xe27E5e2D924F6e42ffa90C6bE817AA030dE6f48D` |
| CanonicalFactory | `0x4934985287C28e647ecF38d485E448ac4A4A4Ab7` | `0x99AB8C07C0082CBdD0306B30BC52eA15e6dB2521` |
| CCIPSender | `0x1062C2fBebd13862d4D503430E3E1A81907c2bD7` | `0x3823baE274eB188D3dF66D8bc4eAAaf0F050dAD6` |
| CCIPReceiver | `0xC740E9D56c126eb447f84404dDd9dffbB7AEd5F8` | `0xDc1f35F18607c8ee5a823b1ebBc5eDFe0fb253F3` |

**E2E verified**: Factory deploy -> attestation signing -> mirror deployment -> mint 10,000 xRWA -> transfer 2,500 -> authorize minter -> direct mint 1,000. All on-chain on Fuji.

## Test Suite

**214 tests, 0 failures** across unit, integration, invariant, and attack scenario tests.

```
forge test
```

| Test File | Count | Type |
|---|---|---|
| `CanonicalFactory.t.sol` | 41 | Unit (incl. 8 direct path, 4 enumeration, 4 invariant) |
| `XythumToken.t.sol` | 32 | Unit (incl. mintCap tests) |
| `SignerRegistry.t.sol` | 21 | Unit |
| `AttestationRegistry.t.sol` | 19 | Unit (incl. submitAttestation) |
| `RWAHook.t.sol` | 17 | Unit (incl. hookData compliance) |
| `CollateralVerifier.t.sol` | 15 | Unit |
| `CCIPSender.t.sol` | 12 | Unit |
| `AaveAdapter.t.sol` | 11 | Unit |
| `CCIPReceiver.t.sol` | 10 | Unit |
| `AttackScenarios.t.sol` | 10 | Integration (replay, front-run, collusion, flash loan) |
| `LiquidityFlow.t.sol` | 5 | Integration |
| `Create2Verification.t.sol` | 4 | Unit |
| `ZKCollateral.t.sol` | 4 | Integration |
| `FullFlow.t.sol` | 3 | Integration |
| `DualPath.t.sol` | 2 | Integration (direct + CCIP coexistence) |
| `SignerInvariant.t.sol` | 4 | Invariant |
| `CanonicalInvariant.t.sol` | 4 | Invariant |

## Frontend

A Next.js 15 dashboard with wallet connection (wagmi + viem) for interacting with the protocol.

```bash
cd frontend
npm install
npm run dev      # http://localhost:3000
```

### Pages

| Page | Description |
|---|---|
| **Dashboard** (`/`) | Protocol stats, signer health on both chains, deployed contract addresses, architecture diagram |
| **Attest** (`/attest`) | Full cross-chain workflow: deploy origin RWA -> sign 3/5 attestation -> deploy mirror (direct or CCIP) |
| **Lock** (`/lock`) | Full lock-mint-burn-unlock round-trip: lock RWA on origin -> mint xRWA on target -> use in DeFi -> burn -> redeem original |
| **Mirrors** (`/mirrors`) | Browse deployed canonical mirror tokens with on-chain metadata |
| **Verify** (`/verify`) | Paste any address to check `isCanonical()` on BNB Testnet or Avalanche Fuji |

### Features

- **Deploy new RWAs** directly from the UI (deploys fresh MockRWA ERC-20)
- **Bidirectional**: Fuji -> BNB and BNB -> Fuji, selectable via toggle
- **Dual-path deploy**: Instant direct (~5s) or CCIP relay (~20-35min)
- **Client-side EIP-712 signing** with demo signer keys (testnet only)
- **Live on-chain reads** for signer health, canonical verification, token metadata

## Quick Start

### Prerequisites

- [Foundry](https://getfoundry.sh/) v1.2+
- Node.js v18+

### Build & Test

```bash
# Clone
git clone https://github.com/unspecifiedcoder/rwa-passport.git
cd rwa-passport

# Install Foundry dependencies
forge install

# Build contracts
forge build

# Run all 214 tests
forge test

# Run with gas report
forge test --gas-report

# Run specific test
forge test --match-path test/unit/CanonicalFactory.t.sol -vvv
```

### Deploy (Testnet)

```bash
# Copy and configure environment
cp .env.example .env
# Edit .env with your PRIVATE_KEY and RPC URLs

# Deploy source chain (Fuji)
forge script script/DeploySource.s.sol:DeploySource \
  --rpc-url $RPC_AVALANCHE_FUJI --broadcast -vv

# Deploy target chain (BNB Testnet)
forge script script/DeployTarget.s.sol:DeployTarget \
  --rpc-url $RPC_BNB_TESTNET --broadcast -vv

# Wire CCIP (connect sender <-> receiver across chains)
forge script script/WireChains.s.sol:WireChains \
  --rpc-url $RPC_AVALANCHE_FUJI --broadcast -vv

# Deploy mirror via direct attestation
forge script script/DirectMirrorDeploy.s.sol:DirectMirrorDeploy \
  --rpc-url $RPC_BNB_TESTNET --broadcast -vv
```

### Frontend

```bash
cd frontend
npm install
npm run dev      # Development at http://localhost:3000
npm run build    # Production build
```

## How It Works

### 1. Origin Asset Exists

An ERC-20 token exists on the source chain (e.g., a tokenized bond on Fuji).

### 2. Signers Attest

3 of 5 authorized signers produce EIP-712 typed-data signatures over an `Attestation` struct:

```solidity
struct Attestation {
    address originContract;   // The RWA token on source chain
    uint256 originChainId;    // Source chain ID
    uint256 targetChainId;    // Where to deploy the mirror
    bytes32 navRoot;          // Merkle root of NAV data
    bytes32 complianceRoot;   // Merkle root of compliance data
    uint256 lockedAmount;     // Collateral locked (becomes mintCap)
    uint256 timestamp;        // Attestation time (must be within 24h)
    uint256 nonce;            // Unique per origin/chain pair
}
```

### 3. Mirror Deployed

The attestation + signatures are submitted to `CanonicalFactory` on the target chain. The factory:
- Verifies 3/5 threshold signatures via `AttestationRegistry`
- Computes a deterministic CREATE2 address using `canonicalSalt(originContract, originChainId, targetChainId)`
- Deploys `XythumToken` at that exact address
- Marks it as canonical: `isCanonical(mirrorAddress) == true`

### 4. Two Delivery Paths

| Path | Method | Speed | Cost |
|---|---|---|---|
| **Direct** | User calls `deployMirrorDirect()` on target chain | ~5 seconds | Gas only |
| **CCIP** | User calls `CCIPSender.sendAttestation()` on source chain, Chainlink relays | ~20-35 min | Gas + CCIP fee (~0.13 AVAX) |

### 5. Tokens Are Usable

The mirror token is a standard ERC-20 with:
- **Mint cap** enforcement (cannot exceed attested `lockedAmount`)
- **Authorized minters** (factory + owner-delegated addresses)
- **Compliance hooks** (optional whitelist/blacklist per transfer)
- **Uniswap V4 integration** via `RWAHook` (compliance checks + dynamic fees on swaps)

## Security

- **Threshold signatures**: 3-of-5 ECDSA multi-sig for all attestations
- **CREATE2 determinism**: Same address on every chain for the same asset
- **Mint cap**: Mirror supply cannot exceed attested locked amount
- **Rate limiting**: 1 attestation per hour per origin/chain pair
- **Nonce tracking**: Prevents replay of attestations
- **Timestamp expiry**: Attestations expire after 24 hours
- **Compliance hooks**: Uniswap V4 hooks enforce whitelist/blacklist per swap
- **ZK collateral proofs**: Groth16 verification without revealing positions
- **Attack tests**: Replay, front-running, signer collusion, flash loan, grief scenarios
- **Pause/emergency**: Owner can pause tokens and factory

### Trust Model (read this if you're considering using the protocol)

The protocol's security ultimately reduces to **the 3-of-5 ECDSA signer set** registered in `SignerRegistry`. Mirrors are deployed and locks are released against threshold-signed receipts produced by this set off-chain. This is the same trust model as wBTC's BitGo custodian — a known multi-party authority, not trustless cryptography.

**What "honest signers" guarantees you:**
- One canonical mirror per `(origin, srcChain, dstChain)` triple
- Mirror supply is bounded by escrowed origin supply (`mintCap` is a cumulative high-water mark)
- Replay across chains is impossible (EIP-712 domain pins `chainId` + `verifyingContract`)
- Replay across receipts is impossible (one-shot `lockId` mappings on all three contracts)

**Failure modes you must accept in v1:**

| Scenario | What happens | Recovery |
|---|---|---|
| All 3+ signers go **offline** | Locked RWAs are **temporarily stuck**. No fund loss. | Manual intervention by signer ops, or wait for them to come back. v2: 24h self-rescue (`cancelLock`). |
| 3+ signers **collude maliciously** | Mirrors can be **minted without backing**, draining the target chain. **This is the core trust assumption.** | Same as wBTC. v2: signer bonding + slashing + guardian-multisig pause. v3: replace signers with ZK proofs. |
| Signers sign correctly, user **never submits** the receipt | LockReceipt expires after `LOCK_RECEIPT_MAX_STALENESS` (1 day) | User asks signers to re-issue. |
| Burn succeeds on target → signers don't sign UnlockReceipt | Mirror burned, **original RWA stuck in escrow** until signers act | v2: Merkle-proof of the `BurnedForLock` event from target → trustless `release` after timeout. v1: signers must intervene. |
| Anyone front-runs a LockReceipt to call `mintFromLock` first | The receipt names `locker` as recipient, so the front-runner pays gas but the locker still receives the mirror. **Useless attack.** | None needed. |

**Source-of-truth hierarchy** (when state across contracts disagrees):

1. `RWALockEscrow.locks[lockId]` — the only ground truth for "what is escrowed"
2. `XythumToken.burnedForLock[lockId]` — ground truth for "did the burn happen"
3. `CanonicalFactory.mintedFromLock[lockId]` — derivative; minting requires (1)
4. Off-chain signer attestations — **authorize actions, but never decide truth.** Signers must read (1) and (2) before signing.

**Worst-case attack surface (ranked by severity):**

| # | Attack | Status |
|---|---|---|
| 1 | Signer collusion (3-of-5 sign a fake LockReceipt) | **OPEN — core v1 trust assumption.** Mitigation in v2 (bonding + slashing + guardian pause). |
| 2 | Replay LockReceipt across chains | **CLOSED.** EIP-712 domain pins chainId + verifyingContract. Sigs valid for one factory only. |
| 3 | Burn-amount mismatch | **CLOSED.** Escrow re-checks `locks[id].amount == receipt.amount` on release. |
| 4 | Front-run a signed receipt | **CLOSED.** Receipts name `locker`/`recipient`; griefer just pays gas. |
| 5 | Signer software trusts a single RPC for lock-event existence | **OPEN — operational.** Production signer stack must read from N independent RPCs and require quorum before signing. Out of scope for contract layer. |

If any of these change your mind about deploying, see the v2 plan in [`docs/V2_ROADMAP.md`](docs/V2_ROADMAP.md).

See [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) for the full threat model.

## Documentation

| Document | Description |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | System architecture and design decisions |
| [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) | Threat model and mitigation strategies |
| [`docs/INTEGRATION_GUIDE.md`](docs/INTEGRATION_GUIDE.md) | Integration guide for downstream protocols |
| [`docs/RWA_MOVEMENT_FLOW.md`](docs/RWA_MOVEMENT_FLOW.md) | Complete RWA movement flow (12 sections) |
| [`docs/V2_ROADMAP.md`](docs/V2_ROADMAP.md) | v2 plan: self-rescue, trustless burn-attestation, signer bonding, ZK migration |
| [`security/gas-report.txt`](security/gas-report.txt) | Gas usage report |

## Project Structure

```
xythum-rwa/
  src/
    core/           # SignerRegistry, AttestationRegistry, CanonicalFactory, XythumToken
    ccip/           # CCIPSender, CCIPReceiver
    hooks/          # RWAHook, LiquidityBootstrap
    zk/             # CollateralVerifier, circom circuits
    adapters/       # AaveAdapter
    interfaces/     # ISignerRegistry, ICanonicalFactory, IXythumToken, etc.
    libraries/      # AttestationLib, MerkleLib
    mocks/          # MockRWA, MockGroth16Verifier
  test/
    unit/           # 155 unit tests
    integration/    # 24 integration tests (FullFlow, DualPath, Attack, ZK, Liquidity)
    invariant/      # 8 invariant/fuzz tests
    helpers/        # Test utilities (AttestationHelper, HookMiner, MockCCIPRouter, etc.)
  script/           # Deployment and testing scripts for Fuji + BNB Testnet
  frontend/         # Next.js 15 + wagmi + viem dashboard
  docs/             # Architecture, threat model, integration guide, flow docs
  security/         # Gas reports
```

## Tech Stack

| Layer | Technology |
|---|---|
| Smart Contracts | Solidity 0.8.26, OpenZeppelin v5.1.0 |
| Framework | Foundry (forge, cast, anvil) |
| Cross-Chain | Chainlink CCIP v2.9.0 |
| AMM Hooks | Uniswap V4 Core |
| ZK Proofs | Groth16 (circom circuits, snarkjs) |
| Frontend | Next.js 15, React 19, wagmi, viem, Tailwind CSS |
| Testnets | Avalanche Fuji (43113), BNB Chain Testnet (97) |

## License

MIT
