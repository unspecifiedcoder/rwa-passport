#!/usr/bin/env node
/**
 * Xythum round-trip smoke test (CLI).
 *
 * Walks the full Monad → Fuji round-trip:
 *   1. approve mTBILL → escrow on Monad
 *   2. lock 100k mTBILL on Monad
 *   3. sign LockReceipt with 3-of-5 demo keys (in-process)
 *   4. mintFromLock on Fuji factory (auto-deploys mirror)
 *   5. burnForLock on Fuji mirror
 *   6. sign UnlockReceipt
 *   7. release on Monad escrow
 *
 * No wallet popups, no chain switching — runs as the deployer EOA from .env.
 *
 * Run from repo root:  cd frontend && npm run round-trip
 * Or pin a corridor:   CORRIDOR=fuji-bnb npm run round-trip
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  formatEther,
  keccak256,
  toHex,
  encodePacked,
  parseEventLogs,
  getContract,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { avalancheFuji, bscTestnet } from "viem/chains";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// ─── env loading ─────────────────────────────────────────────────────
const __dirname = dirname(fileURLToPath(import.meta.url));
const ENV_CANDIDATES = [
  resolve(__dirname, "../../.env"), // frontend/scripts → repo root
  process.env.XYTHUM_ENV,
  "/mnt/e/github2/XYTHUM RWA PASSPORT/xythum-rwa/.env",
].filter(Boolean);
let envLoaded = null;
for (const envPath of ENV_CANDIDATES) {
  try {
    const env = readFileSync(envPath, "utf-8");
    for (const line of env.split("\n")) {
      const m = line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
    }
    envLoaded = envPath;
    break;
  } catch {
    /* try next */
  }
}
if (!envLoaded) console.warn("(no .env file found — using shell env only)");

const PRIVATE_KEY = process.env.PRIVATE_KEY;
if (!PRIVATE_KEY) {
  console.error("✗ PRIVATE_KEY missing in env");
  process.exit(1);
}
const account = privateKeyToAccount(PRIVATE_KEY.startsWith("0x") ? PRIVATE_KEY : `0x${PRIVATE_KEY}`);

// ─── chains ──────────────────────────────────────────────────────────
const monadTestnet = {
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "Monad", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: [process.env.RPC_MONAD_TESTNET || "https://testnet-rpc.monad.xyz"] } },
};

// Default corridor: Monad → Fuji. Override via CORRIDOR=fuji-bnb / fuji-monad / monad-fuji etc.
const CORRIDOR = process.env.CORRIDOR || "monad-fuji";
const CORRIDORS = {
  "monad-fuji": {
    origin: { ...monadTestnet, rpc: process.env.RPC_MONAD_TESTNET },
    target: { ...avalancheFuji, rpc: process.env.RPC_AVALANCHE_FUJI },
    rwaToken: "0x430172985b21458d73576435D4aD4bEeA85F376C",
    escrow: "0xCe1D8aF9ae9039A12A157D6ec53eC87F906773C4",
    factory: "0x0BA5bd535Ee071993643Cbb815368F55648B9365",
  },
  "fuji-monad": {
    origin: { ...avalancheFuji, rpc: process.env.RPC_AVALANCHE_FUJI },
    target: { ...monadTestnet, rpc: process.env.RPC_MONAD_TESTNET },
    rwaToken: "0xD52b37AD931F221A902fC7F43A9ed2D87Ce07C5F",
    escrow: "0x557474BEd7701ee5290CeB232DDa1Fa06799aA5F",
    factory: "0x27b678acD971f851Ce19751482371eC76b929B41",
  },
  "fuji-bnb": {
    origin: { ...avalancheFuji, rpc: process.env.RPC_AVALANCHE_FUJI },
    target: { ...bscTestnet, rpc: process.env.RPC_BNB_TESTNET },
    rwaToken: "0xD52b37AD931F221A902fC7F43A9ed2D87Ce07C5F",
    escrow: "0x557474BEd7701ee5290CeB232DDa1Fa06799aA5F",
    factory: "0x4d0a5A6bf63a25bd6577Bdcda0f48e19843CacBC",
  },
};
const dir = CORRIDORS[CORRIDOR];
if (!dir) {
  console.error(`✗ unknown CORRIDOR=${CORRIDOR}. Known: ${Object.keys(CORRIDORS).join(", ")}`);
  process.exit(1);
}

const AMOUNT = parseEther(process.env.AMOUNT || "100000");

// ─── 5 demo signer keys (must match SignerRegistry on chain) ────────
const SIGNER_KEYS = [1, 2, 3, 4, 5].map((i) => keccak256(toHex(`xythum-demo-signer-${i}`)));
const SIGNERS = SIGNER_KEYS.map(privateKeyToAccount);

// ─── ABIs (minimal) ─────────────────────────────────────────────────
const ERC20_ABI = [
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
];

const ESCROW_ABI = [
  { type: "function", name: "lock", stateMutability: "nonpayable", inputs: [{ name: "rwaToken", type: "address" }, { name: "amount", type: "uint256" }, { name: "targetChainId", type: "uint256" }], outputs: [{ name: "lockId", type: "bytes32" }] },
  { type: "function", name: "release", stateMutability: "nonpayable", inputs: [{ name: "receipt", type: "tuple", components: [{ name: "originContract", type: "address" }, { name: "originChainId", type: "uint256" }, { name: "targetChainId", type: "uint256" }, { name: "recipient", type: "address" }, { name: "amount", type: "uint256" }, { name: "lockId", type: "bytes32" }, { name: "burnTxBlock", type: "uint256" }, { name: "timestamp", type: "uint256" }] }, { name: "signatures", type: "bytes" }, { name: "signerBitmap", type: "uint256" }], outputs: [] },
  { type: "event", name: "Locked", inputs: [{ name: "lockId", type: "bytes32", indexed: true }, { name: "locker", type: "address", indexed: true }, { name: "rwaToken", type: "address", indexed: true }, { name: "amount", type: "uint256", indexed: false }, { name: "targetChainId", type: "uint256", indexed: false }] },
];

const FACTORY_ABI = [
  { type: "function", name: "mintFromLock", stateMutability: "nonpayable", inputs: [{ name: "receipt", type: "tuple", components: [{ name: "originContract", type: "address" }, { name: "originChainId", type: "uint256" }, { name: "targetChainId", type: "uint256" }, { name: "locker", type: "address" }, { name: "amount", type: "uint256" }, { name: "lockId", type: "bytes32" }, { name: "timestamp", type: "uint256" }] }, { name: "signatures", type: "bytes" }, { name: "signerBitmap", type: "uint256" }], outputs: [{ name: "mirror", type: "address" }] },
  { type: "event", name: "MintedFromLock", inputs: [{ name: "lockId", type: "bytes32", indexed: true }, { name: "mirror", type: "address", indexed: true }, { name: "locker", type: "address", indexed: true }, { name: "amount", type: "uint256", indexed: false }] },
];

const TOKEN_BURN_ABI = [
  { type: "function", name: "burnForLock", stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }, { name: "lockId", type: "bytes32" }], outputs: [] },
];

// ─── EIP-712 typed-data helpers ─────────────────────────────────────
const DOMAIN = { name: "Xythum RWA Passport", version: "1" };
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
};
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
};

async function signWithThree(domain, types, primaryType, message) {
  let packed = "0x";
  let bitmap = 0n;
  for (let i = 0; i < 3; i++) {
    const sig = await SIGNERS[i].signTypedData({ domain, types, primaryType, message });
    packed = packed === "0x" ? sig : encodePacked(["bytes", "bytes"], [packed, sig]);
    bitmap |= 1n << BigInt(i);
  }
  return { signatures: packed, signerBitmap: bitmap };
}

// ─── tiny pretty-print helpers ──────────────────────────────────────
const t0 = Date.now();
const elapsed = () => `${((Date.now() - t0) / 1000).toFixed(1)}s`;
const ok = (msg) => console.log(`  ✓ ${msg}  [${elapsed()}]`);
const step = (n, msg) => console.log(`\n[${n}] ${msg}`);

// ─── main ───────────────────────────────────────────────────────────
async function main() {
  console.log(`\nXYTHUM ROUND-TRIP SMOKE TEST · corridor: ${CORRIDOR}`);
  console.log(`  amount: ${formatEther(AMOUNT)} mTBILL`);
  console.log(`  account: ${account.address}`);
  console.log(`  origin: ${dir.origin.name} (${dir.origin.id})`);
  console.log(`  target: ${dir.target.name} (${dir.target.id})`);

  const originPub = createPublicClient({ chain: dir.origin, transport: http(dir.origin.rpc) });
  const targetPub = createPublicClient({ chain: dir.target, transport: http(dir.target.rpc) });
  const originWallet = createWalletClient({ chain: dir.origin, transport: http(dir.origin.rpc), account });
  const targetWallet = createWalletClient({ chain: dir.target, transport: http(dir.target.rpc), account });

  // ─── 1. approve ────────────────────────────────────────────────
  step(1, "Approve escrow to pull mTBILL on origin");
  const allowance = await originPub.readContract({ address: dir.rwaToken, abi: ERC20_ABI, functionName: "allowance", args: [account.address, dir.escrow] });
  if (allowance < AMOUNT) {
    const approveHash = await originWallet.writeContract({ address: dir.rwaToken, abi: ERC20_ABI, functionName: "approve", args: [dir.escrow, AMOUNT] });
    await originPub.waitForTransactionReceipt({ hash: approveHash });
    ok(`approved (tx ${approveHash.slice(0, 10)}…)`);
  } else {
    ok(`already approved (${formatEther(allowance)} mTBILL)`);
  }

  // ─── 2. lock ───────────────────────────────────────────────────
  step(2, `Lock ${formatEther(AMOUNT)} mTBILL into escrow`);
  const lockHash = await originWallet.writeContract({ address: dir.escrow, abi: ESCROW_ABI, functionName: "lock", args: [dir.rwaToken, AMOUNT, BigInt(dir.target.id)] });
  const lockRcpt = await originPub.waitForTransactionReceipt({ hash: lockHash });
  const lockedEvents = parseEventLogs({ abi: ESCROW_ABI, logs: lockRcpt.logs, eventName: "Locked" });
  const lockId = lockedEvents[0]?.args.lockId;
  if (!lockId) throw new Error("no Locked event in tx receipt");
  ok(`locked · lockId ${lockId.slice(0, 10)}… (tx ${lockHash.slice(0, 10)}…)`);

  // ─── 3. sign LockReceipt ───────────────────────────────────────
  step(3, "Sign LockReceipt with 3-of-5 demo signers");
  const lockReceipt = {
    originContract: dir.rwaToken,
    originChainId: BigInt(dir.origin.id),
    targetChainId: BigInt(dir.target.id),
    locker: account.address,
    amount: AMOUNT,
    lockId,
    // -60s to absorb cross-chain clock skew (target chain timestamp can lag).
    timestamp: BigInt(Math.floor(Date.now() / 1000) - 60),
  };
  const lockSig = await signWithThree(
    { ...DOMAIN, chainId: dir.target.id, verifyingContract: dir.factory },
    LOCK_RECEIPT_TYPES,
    "LockReceipt",
    lockReceipt,
  );
  ok(`signed · bitmap=${lockSig.signerBitmap.toString()}`);

  // ─── 4. mintFromLock ───────────────────────────────────────────
  step(4, "mintFromLock on target factory (auto-deploys mirror if needed)");
  const mintHash = await targetWallet.writeContract({
    address: dir.factory,
    abi: FACTORY_ABI,
    functionName: "mintFromLock",
    args: [lockReceipt, lockSig.signatures, lockSig.signerBitmap],
  });
  const mintRcpt = await targetPub.waitForTransactionReceipt({ hash: mintHash });
  const mintEvents = parseEventLogs({ abi: FACTORY_ABI, logs: mintRcpt.logs, eventName: "MintedFromLock" });
  const mirror = mintEvents[0]?.args.mirror;
  if (!mirror) throw new Error("no MintedFromLock event in tx receipt");
  ok(`minted ${formatEther(AMOUNT)} xRWA · mirror=${mirror} (tx ${mintHash.slice(0, 10)}…)`);

  // ─── 5. burnForLock ────────────────────────────────────────────
  step(5, "burnForLock on target mirror");
  const burnHash = await targetWallet.writeContract({
    address: mirror,
    abi: TOKEN_BURN_ABI,
    functionName: "burnForLock",
    args: [AMOUNT, lockId],
  });
  const burnRcpt = await targetPub.waitForTransactionReceipt({ hash: burnHash });
  ok(`burned · block ${burnRcpt.blockNumber} (tx ${burnHash.slice(0, 10)}…)`);

  // ─── 6. sign UnlockReceipt ─────────────────────────────────────
  step(6, "Sign UnlockReceipt with 3-of-5 demo signers");
  const unlockReceipt = {
    originContract: dir.rwaToken,
    originChainId: BigInt(dir.origin.id),
    targetChainId: BigInt(dir.target.id),
    recipient: account.address,
    amount: AMOUNT,
    lockId,
    burnTxBlock: burnRcpt.blockNumber,
    timestamp: BigInt(Math.floor(Date.now() / 1000) - 60),
  };
  const unlockSig = await signWithThree(
    { ...DOMAIN, chainId: dir.origin.id, verifyingContract: dir.escrow },
    UNLOCK_RECEIPT_TYPES,
    "UnlockReceipt",
    unlockReceipt,
  );
  ok(`signed · bitmap=${unlockSig.signerBitmap.toString()}`);

  // ─── 7. release ────────────────────────────────────────────────
  step(7, "release on origin escrow → original mTBILL back to wallet");
  const releaseHash = await originWallet.writeContract({
    address: dir.escrow,
    abi: ESCROW_ABI,
    functionName: "release",
    args: [unlockReceipt, unlockSig.signatures, unlockSig.signerBitmap],
  });
  await originPub.waitForTransactionReceipt({ hash: releaseHash });
  ok(`released · tx ${releaseHash.slice(0, 10)}…`);

  console.log(`\n  ROUND-TRIP COMPLETE in ${elapsed()}\n`);
}

main().catch((err) => {
  console.error("\n✗ round-trip failed:", err.shortMessage || err.message);
  if (err.cause) console.error("  cause:", err.cause.shortMessage || err.cause.message);
  process.exit(1);
});
