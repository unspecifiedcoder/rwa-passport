# Xythum RWA Passport - Integration Guide

## For Protocols Integrating Xythum Mirror Tokens

### 1. Verifying Canonical Tokens

Before accepting any token claiming to be an Xythum mirror, verify it on-chain:

```solidity
// Solidity
import {ICanonicalFactory} from "xythum/interfaces/ICanonicalFactory.sol";

ICanonicalFactory factory = ICanonicalFactory(FACTORY_ADDRESS);

// Returns true only for tokens deployed by the official factory
bool isReal = factory.isCanonical(tokenAddress);
```

```typescript
// TypeScript (viem)
import { createPublicClient, http } from 'viem';
import { sepolia } from 'viem/chains';

const client = createPublicClient({ chain: sepolia, transport: http() });

const isCanonical = await client.readContract({
  address: FACTORY_ADDRESS,
  abi: [{
    type: 'function',
    name: 'isCanonical',
    inputs: [{ name: 'mirror', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
  }],
  functionName: 'isCanonical',
  args: [tokenAddress],
});
```

### 2. Computing Expected Addresses

Predict the mirror address before deployment:

```solidity
// Build attestation struct
AttestationLib.Attestation memory att = AttestationLib.Attestation({
    originContract: 0xOriginalRWA,
    originChainId: 1,         // Ethereum mainnet
    targetChainId: 42161,     // Arbitrum
    navRoot: bytes32(0),      // NAV merkle root
    complianceRoot: bytes32(0),
    lockedAmount: 1_000_000e18,
    timestamp: block.timestamp,
    nonce: 1
});

// This address is deterministic and identical pre/post deployment
address predictedMirror = factory.computeMirrorAddress(att);
```

### 3. Reading Mirror Metadata

Every XythumToken stores immutable origin metadata:

```solidity
IXythumToken mirror = IXythumToken(mirrorAddress);

address origin = mirror.originContract();    // RWA on source chain
uint256 chainId = mirror.originChainId();    // Source chain ID
string memory name = mirror.name();          // "Xythum Mirror"
string memory symbol = mirror.symbol();      // "xRWA"
```

### 4. Using ZK Collateral Proofs

Accept ZK-verified collateral for lending:

```solidity
import {IZKCollateral} from "xythum/interfaces/IZKCollateral.sol";

IZKCollateral verifier = IZKCollateral(VERIFIER_ADDRESS);

// User submits proof
bytes32 proofId = verifier.verifyCollateralProof(proof, publicInputs);

// Read verified collateral value
(uint256 minValue, address asset, uint256 timestamp) =
    verifier.getCollateralValue(proofId);

// Check freshness
require(block.timestamp - timestamp < 1 hours, "Proof too old");

// Check asset is canonical
require(factory.isCanonical(asset), "Not canonical");

// Safe to use minValue as collateral amount
```

### 5. Listening for Events

Monitor protocol activity:

```typescript
// Mirror deployments
const mirrorEvents = await client.getLogs({
  address: FACTORY_ADDRESS,
  event: {
    type: 'event',
    name: 'MirrorDeployed',
    inputs: [
      { name: 'mirror', type: 'address', indexed: true },
      { name: 'originContract', type: 'address', indexed: true },
      { name: 'originChainId', type: 'uint256', indexed: false },
      { name: 'targetChainId', type: 'uint256', indexed: false },
      { name: 'salt', type: 'bytes32', indexed: false },
    ],
  },
  fromBlock: 'earliest',
});

// ZK proof verifications
const proofEvents = await client.getLogs({
  address: VERIFIER_ADDRESS,
  event: {
    type: 'event',
    name: 'CollateralProofVerified',
    inputs: [
      { name: 'proofId', type: 'bytes32', indexed: true },
      { name: 'asset', type: 'address', indexed: true },
      { name: 'minimumValue', type: 'uint256', indexed: false },
      { name: 'timestamp', type: 'uint256', indexed: false },
    ],
  },
  fromBlock: 'earliest',
});
```

### 6. Compliance Checks

Before interacting with mirror tokens, check compliance:

```solidity
IXythumToken mirror = IXythumToken(mirrorAddress);

// Check if a transfer would be compliant
bool allowed = mirror.isCompliant(sender, receiver);
```

Note: Compliance is enforced automatically on every `transfer()` and `transferFrom()`. Non-compliant transfers revert with `TransferNotCompliant(from, to)`.

## Deployed Contract Addresses

| Chain | Contract | Address |
|-------|----------|---------|
| Sepolia | CanonicalFactory | _Deploy to get address_ |
| Sepolia | SignerRegistry | _Deploy to get address_ |
| Sepolia | AttestationRegistry | _Deploy to get address_ |

Run the deploy script to get addresses:
```bash
cd xythum-rwa
source .env
forge script script/Deploy.s.sol --fork-url $RPC_ETHEREUM_SEPOLIA --broadcast
```

## Gas Costs (Approximate)

| Operation | Gas |
|-----------|-----|
| `deployMirror` | ~1,380,000 |
| `computeMirrorAddress` | ~5,600 |
| `isCanonical` | ~2,500 |
| `verifyAttestation` | ~310,000 |
| `XythumToken.transfer` | ~45,000 (with compliance) |
| `verifyCollateralProof` | ~217,000 |
| `AaveAdapter.depositWithProof` | ~118,000 |
