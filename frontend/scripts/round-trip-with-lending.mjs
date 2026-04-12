#!/usr/bin/env node
/**
 * Xythum round-trip + lending smoke test (CLI).
 *
 * Walks the full Monad → Fuji round-trip with a lending detour on Fuji:
 *   [1]  approve mTBILL on Monad
 *   [2]  lock 100k mTBILL on Monad
 *   [3]  sign LockReceipt
 *   [4]  mintFromLock on Fuji          → 100k xRWA at <mirror>
 *   [5]  faucet 10k MockUSDC on Fuji
 *   [6]  approve xRWA → XythumLend
 *   [7]  supply 100k xRWA
 *   [8]  borrow 5k USDC
 *   [9]  approve USDC → XythumLend
 *   [10] repay 5k USDC
 *   [11] withdraw 100k xRWA
 *   [12] burnForLock on Fuji
 *   [13] sign UnlockReceipt
 *   [14] release on Monad
 *
 * No wallet popups — runs as the deployer EOA from .env.
 *
 * Run:  cd frontend && npm run round-trip-lending
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  parseUnits,
  formatUnits,
  keccak256,
  toHex,
  encodePacked,
  parseEventLogs,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { avalancheFuji } from "viem/chains";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// ─── env loading ─────────────────────────────────────────────────────
const __dirname = dirname(fileURLToPath(import.meta.url));
const ENV_CANDIDATES = [
  resolve(__dirname, "../../.env"),
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

// Lending lives on Fuji — the only supported corridor here is monad-fuji.
const CORRIDOR = process.env.CORRIDOR || "monad-fuji";
const CORRIDORS = {
  "monad-fuji": {
    origin: { ...monadTestnet, rpc: process.env.RPC_MONAD_TESTNET },
    target: { ...avalancheFuji, rpc: process.env.RPC_AVALANCHE_FUJI },
    rwaToken: "0x430172985b21458d73576435D4aD4bEeA85F376C",
    escrow: "0xCe1D8aF9ae9039A12A157D6ec53eC87F906773C4",
    factory: "0x0BA5bd535Ee071993643Cbb815368F55648B9365",
    // Lending contracts live on the target chain (Fuji). Live addresses below.
    xythumLend: process.env.XYTHUM_LEND_ADDR || "0xA1488D1063930947344305D851Ef90dF98944260",
    mockUsdc: process.env.MOCK_USDC_ADDR || "0x3BeF60e85DA825AEe0449a8438FA8d943A07c848",
  },
};
const dir = CORRIDORS[CORRIDOR];
if (!dir) {
  console.error(`✗ unknown CORRIDOR=${CORRIDOR}. Known: ${Object.keys(CORRIDORS).join(", ")}`);
  process.exit(1);
}

const ZERO = "0x0000000000000000000000000000000000000000";
if (dir.xythumLend === ZERO || dir.mockUsdc === ZERO) {
  console.error(
    "✗ XYTHUM_LEND_ADDR / MOCK_USDC_ADDR not set. Deploy the lending contracts on Fuji and " +
      "export both env vars (or hardcode them in this script's CORRIDORS table).",
  );
  process.exit(1);
}

const AMOUNT = parseUnits(process.env.AMOUNT || "100000", 18);
const BORROW_AMOUNT = parseUnits(process.env.BORROW_AMOUNT || "5000", 6);
const REPAY_AMOUNT = parseUnits(process.env.REPAY_AMOUNT || "5000", 6);

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

const MOCK_USDC_ABI = [
  { type: "function", name: "faucet", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
];

const LEND_ABI = [
  { type: "function", name: "supply", stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "withdraw", stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "borrow", stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "repay", stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "positionOf", stateMutability: "view", inputs: [{ name: "user", type: "address" }], outputs: [{ name: "collateral", type: "uint256" }, { name: "debt", type: "uint256" }, { name: "healthBps", type: "uint256" }] },
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
  console.log(`\nXYTHUM ROUND-TRIP + LENDING SMOKE TEST · corridor: ${CORRIDOR}`);
  console.log(`  amount: ${formatUnits(AMOUNT, 18)} mTBILL → xRWA`);
  console.log(`  borrow: ${formatUnits(BORROW_AMOUNT, 6)} USDC`);
  console.log(`  account: ${account.address}`);
  console.log(`  origin: ${dir.origin.name} (${dir.origin.id})`);
  console.log(`  target: ${dir.target.name} (${dir.target.id})`);
  console.log(`  xythumLend: ${dir.xythumLend}`);
  console.log(`  mockUsdc:   ${dir.mockUsdc}`);

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
    ok(`already approved (${formatUnits(allowance, 18)} mTBILL)`);
  }

  // ─── 2. lock ───────────────────────────────────────────────────
  step(2, `Lock ${formatUnits(AMOUNT, 18)} mTBILL into escrow`);
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
  ok(`minted ${formatUnits(AMOUNT, 18)} xRWA · mirror=${mirror} (tx ${mintHash.slice(0, 10)}…)`);

  // ─── 5. faucet USDC ────────────────────────────────────────────
  step(5, "Faucet 10,000 mock USDC on Fuji");
  const faucetHash = await targetWallet.writeContract({
    address: dir.mockUsdc,
    abi: MOCK_USDC_ABI,
    functionName: "faucet",
    args: [],
  });
  await targetPub.waitForTransactionReceipt({ hash: faucetHash });
  const usdcBal = await targetPub.readContract({ address: dir.mockUsdc, abi: MOCK_USDC_ABI, functionName: "balanceOf", args: [account.address] });
  ok(`faucet drawn · wallet USDC=${formatUnits(usdcBal, 6)} (tx ${faucetHash.slice(0, 10)}…)`);

  // ─── 6. approve xRWA → XythumLend ──────────────────────────────
  step(6, "Approve xRWA to XythumLend");
  const approveLendHash = await targetWallet.writeContract({
    address: mirror,
    abi: ERC20_ABI,
    functionName: "approve",
    args: [dir.xythumLend, AMOUNT],
  });
  await targetPub.waitForTransactionReceipt({ hash: approveLendHash });
  ok(`approved (tx ${approveLendHash.slice(0, 10)}…)`);

  // ─── 7. supply ─────────────────────────────────────────────────
  step(7, `Supply ${formatUnits(AMOUNT, 18)} xRWA to XythumLend`);
  const supplyHash = await targetWallet.writeContract({
    address: dir.xythumLend,
    abi: LEND_ABI,
    functionName: "supply",
    args: [AMOUNT],
  });
  await targetPub.waitForTransactionReceipt({ hash: supplyHash });
  ok(`supplied (tx ${supplyHash.slice(0, 10)}…)`);

  // ─── 8. borrow ─────────────────────────────────────────────────
  step(8, `Borrow ${formatUnits(BORROW_AMOUNT, 6)} USDC from XythumLend`);
  const borrowHash = await targetWallet.writeContract({
    address: dir.xythumLend,
    abi: LEND_ABI,
    functionName: "borrow",
    args: [BORROW_AMOUNT],
  });
  await targetPub.waitForTransactionReceipt({ hash: borrowHash });
  const pos = await targetPub.readContract({ address: dir.xythumLend, abi: LEND_ABI, functionName: "positionOf", args: [account.address] });
  ok(`borrowed · debt=${formatUnits(pos[1], 6)} USDC · healthBps=${pos[2].toString()} (tx ${borrowHash.slice(0, 10)}…)`);

  // ─── 9. approve USDC → XythumLend ──────────────────────────────
  step(9, "Approve USDC to XythumLend");
  const approveUsdcHash = await targetWallet.writeContract({
    address: dir.mockUsdc,
    abi: MOCK_USDC_ABI,
    functionName: "approve",
    args: [dir.xythumLend, REPAY_AMOUNT],
  });
  await targetPub.waitForTransactionReceipt({ hash: approveUsdcHash });
  ok(`approved (tx ${approveUsdcHash.slice(0, 10)}…)`);

  // ─── 10. repay ─────────────────────────────────────────────────
  step(10, `Repay ${formatUnits(REPAY_AMOUNT, 6)} USDC`);
  const repayHash = await targetWallet.writeContract({
    address: dir.xythumLend,
    abi: LEND_ABI,
    functionName: "repay",
    args: [REPAY_AMOUNT],
  });
  await targetPub.waitForTransactionReceipt({ hash: repayHash });
  ok(`repaid (tx ${repayHash.slice(0, 10)}…)`);

  // ─── 11. withdraw ──────────────────────────────────────────────
  step(11, `Withdraw ${formatUnits(AMOUNT, 18)} xRWA`);
  const withdrawHash = await targetWallet.writeContract({
    address: dir.xythumLend,
    abi: LEND_ABI,
    functionName: "withdraw",
    args: [AMOUNT],
  });
  await targetPub.waitForTransactionReceipt({ hash: withdrawHash });
  ok(`withdrew (tx ${withdrawHash.slice(0, 10)}…)`);

  // ─── 12. burnForLock ───────────────────────────────────────────
  step(12, "burnForLock on target mirror");
  const burnHash = await targetWallet.writeContract({
    address: mirror,
    abi: TOKEN_BURN_ABI,
    functionName: "burnForLock",
    args: [AMOUNT, lockId],
  });
  const burnRcpt = await targetPub.waitForTransactionReceipt({ hash: burnHash });
  ok(`burned · block ${burnRcpt.blockNumber} (tx ${burnHash.slice(0, 10)}…)`);

  // ─── 13. sign UnlockReceipt ────────────────────────────────────
  step(13, "Sign UnlockReceipt with 3-of-5 demo signers");
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

  // ─── 14. release ───────────────────────────────────────────────
  step(14, "release on origin escrow → original mTBILL back to wallet");
  const releaseHash = await originWallet.writeContract({
    address: dir.escrow,
    abi: ESCROW_ABI,
    functionName: "release",
    args: [unlockReceipt, unlockSig.signatures, unlockSig.signerBitmap],
  });
  await originPub.waitForTransactionReceipt({ hash: releaseHash });
  ok(`released · tx ${releaseHash.slice(0, 10)}…`);

  console.log(`\n  ROUND-TRIP + LENDING COMPLETE in ${elapsed()}\n`);
}

main().catch((err) => {
  console.error("\n✗ round-trip-with-lending failed:", err.shortMessage || err.message);
  if (err.cause) console.error("  cause:", err.cause.shortMessage || err.cause.message);
  process.exit(1);
});
