/**
 * EIP-712 signing utility for Xythum attestations.
 *
 * Uses 5 demo signer private keys (deterministic, testnet-only).
 * Signs with the first 3 of 5 (threshold 3/5).
 * In production, signatures would come from an off-chain signing service.
 */
import { keccak256, toHex, encodePacked, encodeAbiParameters, parseAbiParameters } from "viem";
import { privateKeyToAccount } from "viem/accounts";

// Demo signer keys — deterministic, testnet-only (5 signers, threshold 3)
// These are keccak256("xythum-demo-signer-1"), etc.
const SIGNER_KEYS = [
  keccak256(toHex("xythum-demo-signer-1")),
  keccak256(toHex("xythum-demo-signer-2")),
  keccak256(toHex("xythum-demo-signer-3")),
  keccak256(toHex("xythum-demo-signer-4")),
  keccak256(toHex("xythum-demo-signer-5")),
] as const;

// Number of signatures required (threshold)
const SIGNING_THRESHOLD = 3;

export const DEMO_SIGNER_ADDRESSES = SIGNER_KEYS.map(
  (key) => privateKeyToAccount(key).address
);

export interface Attestation {
  originContract: `0x${string}`;
  originChainId: bigint;
  targetChainId: bigint;
  navRoot: `0x${string}`;
  complianceRoot: `0x${string}`;
  lockedAmount: bigint;
  timestamp: bigint;
  nonce: bigint;
}

// EIP-712 domain for the TARGET chain's AttestationRegistry
const EIP712_DOMAIN = {
  name: "Xythum RWA Passport",
  version: "1",
} as const;

const ATTESTATION_TYPES = {
  Attestation: [
    { name: "originContract", type: "address" },
    { name: "originChainId", type: "uint256" },
    { name: "targetChainId", type: "uint256" },
    { name: "navRoot", type: "bytes32" },
    { name: "complianceRoot", type: "bytes32" },
    { name: "lockedAmount", type: "uint256" },
    { name: "timestamp", type: "uint256" },
    { name: "nonce", type: "uint256" },
  ],
} as const;

/**
 * Sign an attestation with the first 3 of 5 demo signer keys (threshold 3/5).
 * Produces packed signatures (65 bytes each, concatenated) and bitmap.
 *
 * @param att - The attestation to sign
 * @param targetChainId - Chain ID of the target (where AttestationRegistry lives)
 * @param attRegistryAddress - Address of AttestationRegistry on target chain
 * @param signerIndices - Which signer indices to use (default: [0,1,2] — first 3 of 5)
 * @returns { signatures, signerBitmap } ready for sendAttestation()
 */
export async function signAttestation(
  att: Attestation,
  targetChainId: number,
  attRegistryAddress: `0x${string}`,
  signerIndices: number[] = [0, 1, 2]
): Promise<{ signatures: `0x${string}`; signerBitmap: bigint }> {
  if (signerIndices.length < SIGNING_THRESHOLD) {
    throw new Error(`Need at least ${SIGNING_THRESHOLD} signers, got ${signerIndices.length}`);
  }

  const domain = {
    ...EIP712_DOMAIN,
    chainId: targetChainId,
    verifyingContract: attRegistryAddress,
  };

  // Sort indices so signatures are in bitmap order (required by contract)
  const sorted = [...signerIndices].sort((a, b) => a - b);

  // Sign with selected keys in order
  const sigParts: `0x${string}`[] = [];
  let signerBitmap = BigInt(0);

  for (const idx of sorted) {
    if (idx < 0 || idx >= SIGNER_KEYS.length) {
      throw new Error(`Signer index ${idx} out of range (0-${SIGNER_KEYS.length - 1})`);
    }

    const key = SIGNER_KEYS[idx];
    const account = privateKeyToAccount(key);
    const sig = await account.signTypedData({
      domain,
      types: ATTESTATION_TYPES,
      primaryType: "Attestation",
      message: {
        originContract: att.originContract,
        originChainId: att.originChainId,
        targetChainId: att.targetChainId,
        navRoot: att.navRoot,
        complianceRoot: att.complianceRoot,
        lockedAmount: att.lockedAmount,
        timestamp: att.timestamp,
        nonce: att.nonce,
      },
    });

    sigParts.push(sig);
    signerBitmap |= BigInt(1) << BigInt(idx);
  }

  // Pack signatures: concatenate raw bytes
  // Each sig is 65 bytes. Contract reads 65 bytes per signer.
  let packed: `0x${string}` = sigParts[0];
  for (let i = 1; i < sigParts.length; i++) {
    packed = encodePacked(["bytes", "bytes"], [packed, sigParts[i]]);
  }

  return { signatures: packed, signerBitmap };
}

// ────────────────────────────────────────────────────────────────────
// Lock-cycle receipts (mintFromLock + RWALockEscrow.release)
//
// Same EIP-712 domain as Attestation, same 5 demo keys, same threshold.
// The verifyingContract differs by direction:
//   - LockReceipt   → factory on TARGET chain
//   - UnlockReceipt → escrow on ORIGIN chain
// ────────────────────────────────────────────────────────────────────

export interface LockReceipt {
  originContract: `0x${string}`;
  originChainId: bigint;
  targetChainId: bigint;
  locker: `0x${string}`;
  amount: bigint;
  lockId: `0x${string}`;
  timestamp: bigint;
}

export interface UnlockReceipt {
  originContract: `0x${string}`;
  originChainId: bigint;
  targetChainId: bigint;
  recipient: `0x${string}`;
  amount: bigint;
  lockId: `0x${string}`;
  burnTxBlock: bigint;
  timestamp: bigint;
}

const LOCK_RECEIPT_TYPES = {
  LockReceipt: [
    { name: "originContract", type: "address" },
    { name: "originChainId", type: "uint256" },
    { name: "targetChainId", type: "uint256" },
    { name: "locker", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "lockId", type: "bytes32" },
    { name: "timestamp", type: "uint256" },
  ],
} as const;

const UNLOCK_RECEIPT_TYPES = {
  UnlockReceipt: [
    { name: "originContract", type: "address" },
    { name: "originChainId", type: "uint256" },
    { name: "targetChainId", type: "uint256" },
    { name: "recipient", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "lockId", type: "bytes32" },
    { name: "burnTxBlock", type: "uint256" },
    { name: "timestamp", type: "uint256" },
  ],
} as const;

async function signWithDemoKeys<T extends Record<string, unknown>>(
  domain: { name: string; version: string; chainId: number; verifyingContract: `0x${string}` },
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  types: any,
  primaryType: string,
  message: T,
  signerIndices: number[],
): Promise<{ signatures: `0x${string}`; signerBitmap: bigint }> {
  if (signerIndices.length < SIGNING_THRESHOLD) {
    throw new Error(`Need at least ${SIGNING_THRESHOLD} signers, got ${signerIndices.length}`);
  }
  const sorted = [...signerIndices].sort((a, b) => a - b);
  const sigParts: `0x${string}`[] = [];
  let signerBitmap = BigInt(0);
  for (const idx of sorted) {
    if (idx < 0 || idx >= SIGNER_KEYS.length) {
      throw new Error(`Signer index ${idx} out of range (0-${SIGNER_KEYS.length - 1})`);
    }
    const account = privateKeyToAccount(SIGNER_KEYS[idx]);
    // viem's signTypedData accepts arbitrary typed-data shapes
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const sig = await account.signTypedData({ domain, types, primaryType, message } as any);
    sigParts.push(sig);
    signerBitmap |= BigInt(1) << BigInt(idx);
  }
  let packed: `0x${string}` = sigParts[0];
  for (let i = 1; i < sigParts.length; i++) {
    packed = encodePacked(["bytes", "bytes"], [packed, sigParts[i]]);
  }
  return { signatures: packed, signerBitmap };
}

/**
 * Sign a LockReceipt with the first 3 of 5 demo signer keys.
 *
 * @param r - The LockReceipt to sign
 * @param targetChainId - The chain where the factory will verify (typically `r.targetChainId` as number)
 * @param factoryAddress - The CanonicalFactory address on the target chain
 * @param signerIndices - Which signer indices to use (default: [0, 1, 2])
 */
export async function signLockReceipt(
  r: LockReceipt,
  targetChainId: number,
  factoryAddress: `0x${string}`,
  signerIndices: number[] = [0, 1, 2],
): Promise<{ signatures: `0x${string}`; signerBitmap: bigint }> {
  return signWithDemoKeys(
    { ...EIP712_DOMAIN, chainId: targetChainId, verifyingContract: factoryAddress },
    LOCK_RECEIPT_TYPES,
    "LockReceipt",
    {
      originContract: r.originContract,
      originChainId: r.originChainId,
      targetChainId: r.targetChainId,
      locker: r.locker,
      amount: r.amount,
      lockId: r.lockId,
      timestamp: r.timestamp,
    },
    signerIndices,
  );
}

/**
 * Sign an UnlockReceipt with the first 3 of 5 demo signer keys.
 *
 * @param r - The UnlockReceipt to sign
 * @param originChainId - The chain where the escrow will verify (typically `r.originChainId` as number)
 * @param escrowAddress - The RWALockEscrow address on the origin chain
 * @param signerIndices - Which signer indices to use (default: [0, 1, 2])
 */
export async function signUnlockReceipt(
  r: UnlockReceipt,
  originChainId: number,
  escrowAddress: `0x${string}`,
  signerIndices: number[] = [0, 1, 2],
): Promise<{ signatures: `0x${string}`; signerBitmap: bigint }> {
  return signWithDemoKeys(
    { ...EIP712_DOMAIN, chainId: originChainId, verifyingContract: escrowAddress },
    UNLOCK_RECEIPT_TYPES,
    "UnlockReceipt",
    {
      originContract: r.originContract,
      originChainId: r.originChainId,
      targetChainId: r.targetChainId,
      recipient: r.recipient,
      amount: r.amount,
      lockId: r.lockId,
      burnTxBlock: r.burnTxBlock,
      timestamp: r.timestamp,
    },
    signerIndices,
  );
}

/**
 * Build the encoded payload for fee estimation.
 * Mirrors CCIPSender._sendMessage encoding:
 *   abi.encode(messageType, abi.encode(att), signatures, signerBitmap)
 */
export function buildPayload(
  att: Attestation,
  signatures: `0x${string}`,
  signerBitmap: bigint
): `0x${string}` {
  // First encode the attestation struct
  const encodedAtt = encodeAbiParameters(
    parseAbiParameters(
      "address originContract, uint256 originChainId, uint256 targetChainId, bytes32 navRoot, bytes32 complianceRoot, uint256 lockedAmount, uint256 timestamp, uint256 nonce"
    ),
    [
      att.originContract,
      att.originChainId,
      att.targetChainId,
      att.navRoot,
      att.complianceRoot,
      att.lockedAmount,
      att.timestamp,
      att.nonce,
    ]
  );

  // Then encode the full payload
  const payload = encodeAbiParameters(
    parseAbiParameters("uint8 messageType, bytes attEncoded, bytes signatures, uint256 signerBitmap"),
    [1, encodedAtt, signatures, signerBitmap]
  );

  return payload;
}
