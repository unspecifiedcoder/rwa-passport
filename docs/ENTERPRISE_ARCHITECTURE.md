# Enterprise Architecture

> Xythum RWA Passport - Billion-Dollar Protocol Design

## System Overview

The Xythum Enterprise platform extends the core RWA mirror protocol with a complete governance, DeFi, compliance, and security layer designed for institutional-grade operation at scale.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                     FRONTEND LAYER                              │
│  Next.js 15 + React 19 + wagmi + viem + Tailwind               │
│  Dashboard | Mirrors | Verify | Attest | Governance |           │
│  Staking | Analytics | Portfolio                                │
├─────────────────────────────────────────────────────────────────┤
│                   GOVERNANCE LAYER                              │
│  XythumGovernor (OZ Governor) ←→ ProtocolTimelock (2-day)       │
│  ProtocolToken (XYT) - ERC20Votes + Permit + Vesting           │
│  ProtocolTreasury - Multi-asset, epoch-limited disbursements    │
├─────────────────────────────────────────────────────────────────┤
│                     DEFI LAYER                                  │
│  StakingModule - Time-locked staking (1x-3x multipliers)       │
│  RWAYieldVault - ERC-4626 vaults with performance fees          │
│  FeeRouter - Dynamic fee split (treasury/staking/insurance/burn)│
├─────────────────────────────────────────────────────────────────┤
│                  COMPLIANCE LAYER                               │
│  ComplianceEngine - KYC/AML tiered credentials + blacklisting   │
│  OracleRouter - Chainlink price feeds + NAV validation          │
│  MultiChainRegistry - Unified cross-chain state tracking        │
├─────────────────────────────────────────────────────────────────┤
│                   SECURITY LAYER                                │
│  EmergencyGuardian - Circuit breakers + global emergency pause  │
│  Threshold Signatures - 3-of-5 ECDSA multi-sig attestations    │
│  Rate Limiting - Per-pair attestation cooldown                  │
├─────────────────────────────────────────────────────────────────┤
│                    CORE LAYER                                   │
│  CanonicalFactory - CREATE2 deterministic mirror deployment     │
│  AttestationRegistry - EIP-712 signature verification           │
│  SignerRegistry - k-of-n signer management                      │
│  XythumToken - ERC-20 mirror with mintCap + compliance          │
├─────────────────────────────────────────────────────────────────┤
│               CROSS-CHAIN TRANSPORT                             │
│  CCIPSender / CCIPReceiver - Chainlink CCIP v2.9.0              │
│  Direct Path - Instant attestation submission                   │
│  RWAHook - Uniswap V4 compliance + dynamic fees                │
│  CollateralVerifier - Groth16 ZK proof verification             │
└─────────────────────────────────────────────────────────────────┘
```

## Contract Directory

### Governance (`src/governance/`)
| Contract | Purpose |
|---|---|
| `ProtocolToken.sol` | XYT governance token - ERC20Votes, vesting, anti-whale |
| `XythumGovernor.sol` | OZ Governor with timelock - proposals, voting, execution |
| `ProtocolTimelock.sol` | TimelockController - 2-day execution delay |
| `ProtocolTreasury.sol` | Multi-asset treasury with spending limits |

### Staking (`src/staking/`)
| Contract | Purpose |
|---|---|
| `StakingModule.sol` | Synthetix-style staking with time-locked multipliers |

### Finance (`src/finance/`)
| Contract | Purpose |
|---|---|
| `FeeRouter.sol` | Dynamic fee collection and 4-way distribution |
| `RWAYieldVault.sol` | ERC-4626 yield vault with performance/management fees |

### Compliance (`src/compliance/`)
| Contract | Purpose |
|---|---|
| `ComplianceEngine.sol` | KYC/AML/accredited investor on-chain registry |

### Oracle (`src/oracle/`)
| Contract | Purpose |
|---|---|
| `OracleRouter.sol` | Chainlink price feeds, TWAP, NAV validation |

### Security (`src/security/`)
| Contract | Purpose |
|---|---|
| `EmergencyGuardian.sol` | Circuit breakers, multi-guardian emergency system |

### Registry (`src/registry/`)
| Contract | Purpose |
|---|---|
| `MultiChainRegistry.sol` | Unified cross-chain deployment tracking |

## Token Economics (XYT)

```
Maximum Supply:     1,000,000,000 XYT (1 billion)
Initial Mint:       200,000,000 XYT (20%) → Treasury

Allocation:
  Treasury:         200M (20%) - Liquidity, partnerships, ecosystem
  Team/Advisors:    150M (15%) - 6-month cliff, 2-year vest
  Investors:        100M (10%) - 3-month cliff, 18-month vest
  Staking Rewards:  250M (25%) - Emitted over 5 years
  Ecosystem:        200M (20%) - Grants, integrations, community
  Insurance Fund:   100M (10%) - Protocol safety net
```

## Fee Structure

```
Fee Collection Points:
  - Mirror Deployment Fee (ETH/native)
  - Attestation Submission Fee
  - Vault Performance Fee (10% on yield)
  - Vault Management Fee (0.5% annual)
  - Uniswap V4 Hook Dynamic Fees

Fee Distribution (configurable via governance):
  40% → Protocol Treasury
  30% → Staking Rewards Pool
  20% → Insurance Fund
  10% → XYT Token Burn (deflationary)
```

## Security Model

### Emergency Response
1. **Guardians** (2+) can activate global emergency instantly
2. **Emergency** pauses all registered contracts
3. **Governance** (timelock) required to deactivate
4. **Circuit Breakers** auto-trip on anomalous metrics

### Circuit Breakers
- TVL Drop (lower bound) - trips if TVL drops below threshold
- Volume Spike (upper bound) - trips on unusual volume
- Oracle Staleness - trips if price feeds go stale
- Cooldown periods prevent oscillation

## Governance Flow

```
1. Holder creates proposal (requires 100K XYT)
2. Voting delay: 1 day
3. Voting period: 1 week
4. Quorum: 4% of total supply
5. If passed → Queue in Timelock
6. Timelock delay: 2 days
7. Execute
```

## Deployment Order

```bash
1. ProtocolTimelock
2. ProtocolTreasury (owner: timelock)
3. ProtocolToken (initial mint → treasury)
4. XythumGovernor (token + timelock)
5. Grant Governor roles on Timelock
6. StakingModule
7. FeeRouter
8. ComplianceEngine
9. EmergencyGuardian
10. OracleRouter
11. MultiChainRegistry
12. Transfer ownership → Timelock (decentralize)
```
