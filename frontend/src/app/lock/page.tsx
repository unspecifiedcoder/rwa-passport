"use client";

import { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { avalancheFuji, bscTestnet } from "wagmi/chains";
import { parseEther, formatEther, getAddress, parseEventLogs } from "viem";

import { CONTRACTS, RWA_LOCK_ESCROW_ABI, CANONICAL_FACTORY_MINT_FROM_LOCK_ABI, XYTHUM_TOKEN_BURN_FOR_LOCK_ABI, ERC20_APPROVE_ABI } from "@/lib/contracts";
import { getChainName, monadTestnet } from "@/lib/chains";
import { signLockReceipt, signUnlockReceipt, type LockReceipt, type UnlockReceipt } from "@/lib/signing";

import { PageHeader } from "@/components/primitives/PageHeader";
import { TerminalPanel } from "@/components/primitives/TerminalPanel";
import { PaperButton } from "@/components/primitives/PaperButton";
import { PaperInput } from "@/components/primitives/PaperInput";
import { Hash } from "@/components/primitives/Hash";
import { Pill } from "@/components/primitives/Pill";
import { ChainBadge } from "@/components/ChainBadge";
import { MyLocks, appendLock, loadLockHistory, setMirrorForLock } from "@/components/MyLocks";

interface Corridor {
  id: string;
  label: string;
  origin: { id: number; name: string };
  target: { id: number; name: string };
  rwaToken: `0x${string}` | undefined;
  escrow: `0x${string}` | undefined;
  factory: `0x${string}` | undefined;
}

const CORRIDORS: Corridor[] = [
  {
    id: "fuji-to-bnb",
    label: "Fuji → BNB",
    origin: avalancheFuji,
    target: bscTestnet,
    rwaToken: CONTRACTS.avalancheFuji.mockRwa,
    escrow: CONTRACTS.avalancheFuji.lockEscrow,
    factory: CONTRACTS.bscTestnet.canonicalFactory,
  },
  {
    id: "bnb-to-fuji",
    label: "BNB → Fuji",
    origin: bscTestnet,
    target: avalancheFuji,
    rwaToken: CONTRACTS.bscTestnet.mockRwa,
    escrow: CONTRACTS.bscTestnet.lockEscrow,
    factory: CONTRACTS.avalancheFuji.canonicalFactory,
  },
  {
    id: "fuji-to-monad",
    label: "Fuji → Monad",
    origin: avalancheFuji,
    target: monadTestnet,
    rwaToken: CONTRACTS.avalancheFuji.mockRwa,
    escrow: CONTRACTS.avalancheFuji.lockEscrow,
    factory: CONTRACTS.monadTestnet.canonicalFactory,
  },
  {
    id: "bnb-to-monad",
    label: "BNB → Monad",
    origin: bscTestnet,
    target: monadTestnet,
    rwaToken: CONTRACTS.bscTestnet.mockRwa,
    escrow: CONTRACTS.bscTestnet.lockEscrow,
    factory: CONTRACTS.monadTestnet.canonicalFactory,
  },
  {
    id: "monad-to-fuji",
    label: "Monad → Fuji",
    origin: monadTestnet,
    target: avalancheFuji,
    rwaToken: CONTRACTS.monadTestnet.mockRwa,
    escrow: CONTRACTS.monadTestnet.lockEscrow,
    factory: CONTRACTS.avalancheFuji.canonicalFactory,
  },
  {
    id: "monad-to-bnb",
    label: "Monad → BNB",
    origin: monadTestnet,
    target: bscTestnet,
    rwaToken: CONTRACTS.monadTestnet.mockRwa,
    escrow: CONTRACTS.monadTestnet.lockEscrow,
    factory: CONTRACTS.bscTestnet.canonicalFactory,
  },
];

type LockStatus = "ACTIVE" | "MINTED" | "BURNED" | "RELEASED";

interface LockEntry {
  lockId: `0x${string}`;
  amount: bigint;
  corridor: string;
  status: LockStatus;
  mirror?: `0x${string}`;
}

export default function LockPage() {
  const { address, isConnected, chainId } = useAccount();
  const { switchChain } = useSwitchChain();

  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const [corridorIdx, setCorridorIdx] = useState(0);
  const dir = CORRIDORS[corridorIdx];

  // ─── lock + mint state ────────────────────────────────────────────
  const [lockAmount, setLockAmount] = useState("100000");
  const [error, setError] = useState("");
  const [lastLockId, setLastLockId] = useState<`0x${string}` | null>(null);
  const [signedLockReceipt, setSignedLockReceipt] = useState<{
    receipt: LockReceipt;
    signatures: `0x${string}`;
    signerBitmap: bigint;
  } | null>(null);

  const escrowReady = !!dir.escrow && dir.escrow !== "0x0000000000000000000000000000000000000000";

  // ─── on-chain reads ───────────────────────────────────────────────
  const { data: rwaBalance } = useReadContract({
    address: dir.rwaToken,
    abi: ERC20_APPROVE_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: dir.origin.id,
    query: { enabled: !!address && !!dir.rwaToken },
  });

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: dir.rwaToken,
    abi: ERC20_APPROVE_ABI,
    functionName: "allowance",
    args: address && dir.escrow ? [address, dir.escrow] : undefined,
    chainId: dir.origin.id,
    query: { enabled: !!address && !!dir.escrow && !!dir.rwaToken },
  });

  // ─── tx hooks ─────────────────────────────────────────────────────
  const { writeContract: approve, data: approveHash, isPending: approvePending } =
    useWriteContract();
  const { isLoading: approveConfirming, isSuccess: approveDone } = useWaitForTransactionReceipt({
    hash: approveHash,
  });
  useEffect(() => {
    if (approveDone) refetchAllowance();
  }, [approveDone, refetchAllowance]);

  const {
    writeContract: lockWrite,
    data: lockHash,
    isPending: lockPending,
  } = useWriteContract();
  const { data: lockReceipt, isLoading: lockConfirming } = useWaitForTransactionReceipt({
    hash: lockHash,
  });

  // Pull lockId out of the Locked event in the lock tx receipt.
  useEffect(() => {
    if (!lockReceipt) return;
    // event Locked(bytes32 indexed lockId, address indexed locker, address indexed rwaToken, uint256 amount, uint256 targetChainId)
    const LOCKED_TOPIC = "0x" + "Locked(bytes32,address,address,uint256,uint256)" // we'll match by structure
      .padEnd(64, "0"); // not used — fallback below
    // Simpler: any log emitted by the escrow whose first topic is the Locked event.
    // We don't have the topic precomputed; viem doesn't compute it for us inline here.
    // The Locked event's first non-anonymous indexed param is lockId in topics[1].
    const fromEscrow = lockReceipt.logs.find(
      (l) => l.address.toLowerCase() === (dir.escrow ?? "").toLowerCase(),
    );
    if (fromEscrow?.topics?.[1]) {
      const newLockId = fromEscrow.topics[1] as `0x${string}`;
      setLastLockId(newLockId);
      if (dir.rwaToken) {
        appendLock({
          lockId: newLockId,
          amount: parseEther(lockAmount || "0").toString(),
          rwaToken: dir.rwaToken,
          originChainId: dir.origin.id,
          targetChainId: dir.target.id,
          createdAt: Math.floor(Date.now() / 1000),
        });
      }
    }
  }, [lockReceipt, dir.escrow, dir.origin.id, dir.target.id, dir.rwaToken, lockAmount]);

  const {
    writeContract: mintFromLock,
    data: mintHash,
    isPending: mintPending,
  } = useWriteContract();
  const {
    data: mintReceiptData,
    isLoading: mintConfirming,
    isSuccess: mintDone,
  } = useWaitForTransactionReceipt({ hash: mintHash });

  // ─── burn + release state ─────────────────────────────────────────
  const [burnLockId, setBurnLockId] = useState("");
  const [burnAmount, setBurnAmount] = useState("");
  const [signedUnlockReceipt, setSignedUnlockReceipt] = useState<{
    receipt: UnlockReceipt;
    signatures: `0x${string}`;
    signerBitmap: bigint;
  } | null>(null);

  // Find the canonical mirror for this corridor (auto-deployed by mintFromLock).
  // We can derive it via factory.computeMirrorAddress, but for the burn UI we
  // accept the user pasting the mirror address shown after a successful mint,
  // OR fall back to looking up CONTRACTS[<targetSlug>].mirrorToken.
  const targetSlug =
    dir.target.id === avalancheFuji.id
      ? "avalancheFuji"
      : dir.target.id === bscTestnet.id
        ? "bscTestnet"
        : "monadTestnet";
  const fallbackMirror = CONTRACTS[targetSlug]?.mirrorToken;
  const [mirrorAddrInput, setMirrorAddrInput] = useState(fallbackMirror ?? "");
  useEffect(() => {
    setMirrorAddrInput(fallbackMirror ?? "");
  }, [fallbackMirror]);

  // Auto-fill mirror + lockId from the mint tx's MintedFromLock event.
  useEffect(() => {
    if (!mintReceiptData) return;
    const events = parseEventLogs({
      abi: CANONICAL_FACTORY_MINT_FROM_LOCK_ABI,
      logs: mintReceiptData.logs,
      eventName: "MintedFromLock",
    });
    const evt = events[0];
    if (!evt) return;
    const mirror = getAddress(evt.args.mirror as `0x${string}`);
    const id = evt.args.lockId as `0x${string}`;
    setMirrorAddrInput(mirror);
    setBurnLockId(id);
    setBurnAmount(formatEther(evt.args.amount as bigint));
    setMirrorForLock(id, mirror);
  }, [mintReceiptData]);

  // Fallback: on mount (and on corridor change), if the burn fields are empty,
  // populate them from the most recent matching entry in MY LOCKS localStorage.
  // This handles the case where the user navigated /lock → /lend → /lock and
  // lost the in-memory mint receipt.
  useEffect(() => {
    if (burnLockId) return;
    const history = loadLockHistory();
    const match = history.find(
      (e) =>
        e.originChainId === dir.origin.id &&
        e.targetChainId === dir.target.id,
    );
    if (!match) return;
    setBurnLockId(match.lockId);
    setBurnAmount(formatEther(BigInt(match.amount)));
    if (match.mirror) setMirrorAddrInput(match.mirror);
  }, [dir.origin.id, dir.target.id, burnLockId]);

  const {
    writeContract: burnWrite,
    data: burnHash,
    isPending: burnPending,
  } = useWriteContract();
  const { data: burnReceiptData, isLoading: burnConfirming } = useWaitForTransactionReceipt({
    hash: burnHash,
  });

  const {
    writeContract: releaseWrite,
    data: releaseHash,
    isPending: releasePending,
  } = useWriteContract();
  const { isLoading: releaseConfirming, isSuccess: releaseDone } = useWaitForTransactionReceipt({
    hash: releaseHash,
  });

  // ─── handlers (NO chainId param — relies on switchChain like /attest) ──

  const onSourceChain = chainId === dir.origin.id;
  const onTargetChain = chainId === dir.target.id;

  const doApprove = () => {
    if (!dir.rwaToken || !dir.escrow) return;
    setError("");
    approve(
      {
        address: dir.rwaToken,
        abi: ERC20_APPROVE_ABI,
        functionName: "approve",
        args: [dir.escrow, parseEther(lockAmount || "0")],
      },
      { onError: (e) => setError(`Approve failed: ${e.message}`) },
    );
  };

  const doLock = () => {
    if (!dir.rwaToken || !dir.escrow) return;
    setError("");
    lockWrite(
      {
        address: dir.escrow,
        abi: RWA_LOCK_ESCROW_ABI,
        functionName: "lock",
        args: [dir.rwaToken, parseEther(lockAmount || "0"), BigInt(dir.target.id)],
      },
      { onError: (e) => setError(`Lock failed: ${e.message}`) },
    );
  };

  const handleApproveOrLock = () => {
    if (!isConnected) {
      setError("Connect a wallet first.");
      return;
    }
    if (!escrowReady) {
      setError("Escrow not deployed on this chain yet — see contracts.ts.");
      return;
    }
    if (!onSourceChain) {
      switchChain(
        { chainId: dir.origin.id },
        {
          onSuccess: () => {
            // After switch, decide approve vs lock based on allowance.
            const need = parseEther(lockAmount || "0");
            const have = (allowance as bigint | undefined) ?? BigInt(0);
            if (have < need) {
              doApprove();
            } else {
              doLock();
            }
          },
          onError: (e) => setError(`Could not switch chain: ${e.message}`),
        },
      );
      return;
    }
    const need = parseEther(lockAmount || "0");
    if (((allowance as bigint | undefined) ?? BigInt(0)) < need) {
      doApprove();
    } else {
      doLock();
    }
  };

  const handleSignLock = async () => {
    if (!lastLockId || !address || !dir.rwaToken || !dir.factory) {
      setError("Lock first, then sign.");
      return;
    }
    setError("");
    try {
      const receipt: LockReceipt = {
        originContract: dir.rwaToken,
        originChainId: BigInt(dir.origin.id),
        targetChainId: BigInt(dir.target.id),
        locker: address,
        amount: parseEther(lockAmount || "0"),
        lockId: lastLockId,
        // -60s for cross-chain clock skew (verifying chain block.timestamp can lag local clock).
        timestamp: BigInt(Math.floor(Date.now() / 1000) - 60),
      };
      const { signatures, signerBitmap } = await signLockReceipt(
        receipt,
        dir.target.id,
        dir.factory,
      );
      setSignedLockReceipt({ receipt, signatures, signerBitmap });
    } catch (e: unknown) {
      setError(`Signing failed: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const doMint = () => {
    if (!signedLockReceipt || !dir.factory) return;
    setError("");
    mintFromLock(
      {
        address: dir.factory,
        abi: CANONICAL_FACTORY_MINT_FROM_LOCK_ABI,
        functionName: "mintFromLock",
        args: [
          signedLockReceipt.receipt,
          signedLockReceipt.signatures,
          signedLockReceipt.signerBitmap,
        ],
      },
      { onError: (e) => setError(`Mint failed: ${e.message}`) },
    );
  };

  const handleMint = () => {
    if (!signedLockReceipt) {
      setError("Sign the lock receipt first.");
      return;
    }
    if (!isConnected) {
      setError("Connect a wallet first.");
      return;
    }
    if (!onTargetChain) {
      switchChain(
        { chainId: dir.target.id },
        {
          onSuccess: () => doMint(),
          onError: (e) => setError(`Could not switch chain: ${e.message}`),
        },
      );
      return;
    }
    doMint();
  };

  // ─── burn handlers ───────────────────────────────────────────────
  const doBurn = () => {
    if (!mirrorAddrInput || !burnLockId) return;
    setError("");
    burnWrite(
      {
        address: mirrorAddrInput as `0x${string}`,
        abi: XYTHUM_TOKEN_BURN_FOR_LOCK_ABI,
        functionName: "burnForLock",
        args: [parseEther(burnAmount || "0"), burnLockId as `0x${string}`],
      },
      { onError: (e) => setError(`Burn failed: ${e.message}`) },
    );
  };

  const handleBurn = () => {
    if (!isConnected) return setError("Connect a wallet first.");
    if (!burnLockId || !mirrorAddrInput) return setError("Need lockId + mirror address.");
    if (!onTargetChain) {
      switchChain(
        { chainId: dir.target.id },
        {
          onSuccess: () => doBurn(),
          onError: (e) => setError(`Could not switch chain: ${e.message}`),
        },
      );
      return;
    }
    doBurn();
  };

  const handleSignUnlock = async () => {
    if (!burnLockId || !address || !dir.rwaToken || !dir.escrow) {
      setError("Burn must complete first, then sign.");
      return;
    }
    setError("");
    try {
      const receipt: UnlockReceipt = {
        originContract: dir.rwaToken,
        originChainId: BigInt(dir.origin.id),
        targetChainId: BigInt(dir.target.id),
        recipient: address,
        amount: parseEther(burnAmount || "0"),
        lockId: burnLockId as `0x${string}`,
        burnTxBlock: burnReceiptData?.blockNumber ?? BigInt(0),
        // -60s for cross-chain clock skew (verifying chain block.timestamp can lag local clock).
        timestamp: BigInt(Math.floor(Date.now() / 1000) - 60),
      };
      const { signatures, signerBitmap } = await signUnlockReceipt(
        receipt,
        dir.origin.id,
        dir.escrow,
      );
      setSignedUnlockReceipt({ receipt, signatures, signerBitmap });
    } catch (e: unknown) {
      setError(`Signing failed: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  const doRelease = () => {
    if (!signedUnlockReceipt || !dir.escrow) return;
    setError("");
    releaseWrite(
      {
        address: dir.escrow,
        abi: RWA_LOCK_ESCROW_ABI,
        functionName: "release",
        args: [
          signedUnlockReceipt.receipt,
          signedUnlockReceipt.signatures,
          signedUnlockReceipt.signerBitmap,
        ],
      },
      { onError: (e) => setError(`Release failed: ${e.message}`) },
    );
  };

  const handleRelease = () => {
    if (!signedUnlockReceipt) return setError("Sign the unlock receipt first.");
    if (!onSourceChain) {
      switchChain(
        { chainId: dir.origin.id },
        {
          onSuccess: () => doRelease(),
          onError: (e) => setError(`Could not switch chain: ${e.message}`),
        },
      );
      return;
    }
    doRelease();
  };

  // ─── derived UI state ─────────────────────────────────────────────
  const lockAmtBigInt = useMemo(() => {
    try {
      return parseEther(lockAmount || "0");
    } catch {
      return BigInt(0);
    }
  }, [lockAmount]);
  const needsApprove = ((allowance as bigint | undefined) ?? BigInt(0)) < lockAmtBigInt;

  if (!mounted) {
    return (
      <div className="space-y-6">
        <PageHeader
          article="ARTICLE VIII"
          kicker="VAULT OF ESCROW"
          title="The lock chamber"
          lede="Loading…"
        />
      </div>
    );
  }

  return (
    <div className="space-y-10">
      <PageHeader
        article="ARTICLE VIII"
        kicker="VAULT OF ESCROW"
        title={
          <>
            Lock the <em className="italic">original</em>. Mint the mirror.
          </>
        }
        lede={
          <>
            Lock your RWA in escrow on the origin chain, mint a canonical xRWA
            mirror on the target chain, use it freely, and redeem for the
            original whenever you burn the mirror. ~30 seconds end-to-end —
            no CCIP wait.
          </>
        }
        stamp={{ text: "ROUND-TRIP", meta: "LOCK · MINT · BURN · UNLOCK", tone: "wax" }}
        meta={<>SIGNERS · 3 / 5 ECDSA THRESHOLD</>}
      />

      {/* ── Corridor selector ────────────────────────────────────── */}
      <TerminalPanel label="STEP 0 · CORRIDOR" status="idle" meta="ORIGIN → TARGET">
        <div className="p-4 grid grid-cols-2 md:grid-cols-3 gap-2">
          {CORRIDORS.map((c, i) => {
            const active = corridorIdx === i;
            const hasEscrow =
              !!c.escrow && c.escrow !== "0x0000000000000000000000000000000000000000";
            return (
              <button
                key={c.id}
                onClick={() => {
                  setCorridorIdx(i);
                  setLastLockId(null);
                  setSignedLockReceipt(null);
                }}
                className={`px-3 py-3 font-mono text-[11px] uppercase tracking-stamp transition-all border ${
                  active
                    ? "border-leaf-0 bg-leaf-0/10 text-leaf-0"
                    : "border-cover-3 bg-cover-2 text-ink-muted hover:border-leaf-2 hover:text-ink-page"
                }`}
              >
                <span className="block">{c.label}</span>
                <span className="block text-[8px] text-ink-faint mt-1">
                  {hasEscrow ? "READY" : "ESCROW PENDING"}
                </span>
              </button>
            );
          })}
        </div>
      </TerminalPanel>

      {!escrowReady && (
        <div className="bg-wax-0/10 border-2 border-wax-0 px-5 py-4 font-mono text-[11px] text-wax-0">
          ⚠ ESCROW NOT DEPLOYED on {getChainName(dir.origin.id).toUpperCase()} yet.
          Run <code className="text-ink-page">script/DeployEscrow.s.sol</code> and
          update <code className="text-ink-page">contracts.ts</code> with the new address.
        </div>
      )}

      <MyLocks />

      {/* ── STEP 1: Lock ─────────────────────────────────────────── */}
      <TerminalPanel
        label="STEP 1 · LOCK ORIGINAL RWA"
        status="idle"
        meta={`ORIGIN · ${getChainName(dir.origin.id).toUpperCase()}`}
      >
        <div className="p-6 space-y-5">
          <div className="flex items-center justify-between">
            <ChainBadge chainId={dir.origin.id} />
            <Pill label="MTBILL · ERC-20" tone="leaf" />
          </div>
          <PaperInput
            label="Amount to lock"
            type="number"
            placeholder="100000"
            value={lockAmount}
            onChange={(e) => setLockAmount(e.target.value)}
            suffix="MTBILL"
            hint={
              rwaBalance !== undefined
                ? `WALLET BALANCE · ${formatEther(rwaBalance as bigint)} MTBILL`
                : "WALLET BALANCE · —"
            }
          />
          <div className="grid grid-cols-2 gap-2 bg-cover-0 border border-cover-3 p-4 font-mono text-[11px]">
            <Row label="ORIGIN" value={`${getChainName(dir.origin.id)} · ${dir.origin.id}`} />
            <Row label="TARGET" value={`${getChainName(dir.target.id)} · ${dir.target.id}`} />
            <Row label="ESCROW" value={dir.escrow ?? "—"} />
            <Row label="RWA TOKEN" value={dir.rwaToken ?? "—"} />
          </div>
          <PaperButton
            tone="leaf"
            size="lg"
            fullWidth
            disabled={
              !escrowReady ||
              approvePending ||
              approveConfirming ||
              lockPending ||
              lockConfirming ||
              !lockAmount
            }
            onClick={handleApproveOrLock}
          >
            {approvePending || approveConfirming
              ? "Confirming approve…"
              : lockPending || lockConfirming
                ? "Locking…"
                : !isConnected
                  ? "Connect wallet"
                  : !onSourceChain
                    ? `Switch to ${getChainName(dir.origin.id)}`
                    : needsApprove
                      ? `▶ Approve ${lockAmount} mTBILL`
                      : `▶ Lock ${lockAmount} mTBILL`}
          </PaperButton>
          {lastLockId && (
            <div className="bg-verde-0/10 border border-verde-0/40 px-3 py-2 font-mono text-[11px] text-verde-0">
              ✓ LOCKED · lockId = <Hash addr={lastLockId} chainId={dir.origin.id} kind="tx" />
            </div>
          )}
        </div>
      </TerminalPanel>

      {/* ── STEP 2: Sign LockReceipt ─────────────────────────────── */}
      <TerminalPanel
        label="STEP 2 · ENDORSE LOCK"
        status={signedLockReceipt ? "live" : "idle"}
        meta="3 / 5 ECDSA THRESHOLD"
      >
        <div className="p-6 space-y-5">
          <p className="font-body text-[13px] text-ink-muted leading-relaxed max-w-2xl">
            The same 3-of-5 demo signers that sign attestations now also sign a{" "}
            <em className="italic">LockReceipt</em> binding{" "}
            <code className="text-ink-page">lockId → amount → corridor</code>. This is what the
            target factory verifies before minting.
          </p>
          <PaperButton
            tone="leaf"
            size="lg"
            fullWidth
            disabled={!lastLockId}
            onClick={handleSignLock}
          >
            {signedLockReceipt ? "Re-endorse" : lastLockId ? "▶ Endorse with 3 / 5 signers" : "Lock first"}
          </PaperButton>
          {signedLockReceipt && (
            <div className="parchment passport-corner p-5 relative">
              <div className="absolute -top-3 right-4">
                <div className="stamp stamp-fresh text-verde-0 text-[10px] tracking-stamp bg-parchment-0">
                  <span className="block leading-tight">ENDORSED</span>
                  <span className="block leading-none text-[7px] mt-0.5">
                    LOCK · BITMAP {signedLockReceipt.signerBitmap.toString()}
                  </span>
                </div>
              </div>
              <div className="font-mono text-[10px] uppercase tracking-stamp text-ink-deep/55 mb-2">
                LOCK RECEIPT · SIGNED
              </div>
              <div className="font-mono text-[11px] text-ink-deep break-all">
                {signedLockReceipt.signatures.slice(0, 64)}
                <span className="text-ink-deep/40"> … </span>
                {signedLockReceipt.signatures.slice(-16)}
              </div>
            </div>
          )}
        </div>
      </TerminalPanel>

      {/* ── STEP 3: Mint mirror on target ────────────────────────── */}
      {signedLockReceipt && (
        <TerminalPanel
          label="STEP 3 · MINT MIRROR"
          status="idle"
          meta={`TARGET · ${getChainName(dir.target.id).toUpperCase()}`}
        >
          <div className="p-6 space-y-5">
            <div className="bg-cover-0 border border-cover-3 p-4 font-body text-[12px] text-ink-muted leading-relaxed">
              <span className="text-leaf-0 font-mono uppercase tracking-stamp text-[10px]">
                AUTO-DEPLOY
              </span>{" "}
              · If no mirror exists for this corridor yet, the factory will
              CREATE2-deploy one in the same tx. Otherwise it bumps the
              existing mirror&apos;s mintCap. One transaction either way.
            </div>
            <PaperButton
              tone="leaf"
              size="lg"
              fullWidth
              disabled={mintPending || mintConfirming}
              onClick={handleMint}
            >
              {mintPending || mintConfirming
                ? "Minting…"
                : !isConnected
                  ? "Connect wallet"
                  : !onTargetChain
                    ? `Switch to ${getChainName(dir.target.id)}`
                    : "▶ mintFromLock on target"}
            </PaperButton>
            {mintDone && mintHash && (
              <div className="bg-verde-0/10 border border-verde-0/40 p-4 font-mono text-[11px] text-verde-0">
                ✓ MIRROR MINTED · TX <Hash addr={mintHash} chainId={dir.target.id} kind="tx" />
                {mintReceiptData && (() => {
                  const transferLog = mintReceiptData.logs.find((l) =>
                    l.topics?.[0] === "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
                  );
                  const mirror = transferLog?.address as `0x${string}` | undefined;
                  return mirror ? (
                    <div className="mt-2">
                      Mirror token <Hash addr={mirror} chainId={dir.target.id} kind="address" />
                    </div>
                  ) : null;
                })()}
              </div>
            )}
          </div>
        </TerminalPanel>
      )}

      {/* ── BURN + UNLOCK section ────────────────────────────────── */}
      <TerminalPanel
        label="ARTICLE IX · REDEEM"
        status="idle"
        meta="BURN ON TARGET · UNLOCK ON ORIGIN"
      >
        <div className="p-6 space-y-5">
          <p className="font-body text-[13px] text-ink-muted leading-relaxed max-w-2xl">
            When you&apos;re done with the mirror, burn it against the original
            lockId. The signers see the burn, sign an{" "}
            <em className="italic">UnlockReceipt</em>, and you redeem the
            original RWA on the origin chain.
          </p>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            <PaperInput
              label="Mirror token address (target chain)"
              placeholder="0x…"
              value={mirrorAddrInput}
              onChange={(e) => setMirrorAddrInput(e.target.value)}
              hint="AUTO-FILLED FROM MINT TX · OVERRIDE IF NEEDED"
            />
            <PaperInput
              label="lockId"
              placeholder="0x…"
              value={burnLockId}
              onChange={(e) => setBurnLockId(e.target.value)}
              hint="AUTO-FILLED FROM MINT TX · OVERRIDE IF NEEDED"
            />
            <PaperInput
              label="Amount to burn"
              type="number"
              value={burnAmount}
              onChange={(e) => setBurnAmount(e.target.value)}
              suffix="XRWA"
              hint="MUST EQUAL THE ORIGINAL LOCK AMOUNT"
            />
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <PaperButton
              tone="wax"
              size="md"
              fullWidth
              disabled={burnPending || burnConfirming || !burnLockId || !mirrorAddrInput}
              onClick={handleBurn}
            >
              {burnPending || burnConfirming
                ? "Burning…"
                : !onTargetChain
                  ? `Switch to ${getChainName(dir.target.id)}`
                  : "1 · burnForLock"}
            </PaperButton>
            <PaperButton
              tone="leaf"
              size="md"
              fullWidth
              disabled={!burnReceiptData || !burnLockId}
              onClick={handleSignUnlock}
            >
              {signedUnlockReceipt ? "Re-endorse" : "2 · Endorse unlock"}
            </PaperButton>
            <PaperButton
              tone="verde"
              size="md"
              fullWidth
              disabled={!signedUnlockReceipt || releasePending || releaseConfirming}
              onClick={handleRelease}
            >
              {releasePending || releaseConfirming
                ? "Releasing…"
                : !onSourceChain
                  ? `Switch to ${getChainName(dir.origin.id)}`
                  : "3 · release on origin"}
            </PaperButton>
          </div>
          {releaseDone && (
            <div className="parchment passport-corner-tr p-6 relative">
              <div className="absolute -top-4 right-4">
                <div className="stamp stamp-fresh text-verde-0 text-[12px] tracking-stamp bg-parchment-0">
                  <span className="block leading-tight">REDEEMED</span>
                  <span className="block leading-none text-[7px] mt-0.5">
                    ORIGINAL · BACK ON {getChainName(dir.origin.id)}
                  </span>
                </div>
              </div>
              <div className="font-display italic text-3xl text-verde-1 mb-2">Round-trip complete.</div>
              <div className="font-body text-[14px] text-ink-deep/70 mb-3">
                The original RWA has been transferred back from escrow to your wallet on{" "}
                {getChainName(dir.origin.id)}.
              </div>
              <div className="font-mono text-[11px] text-ink-deep/60 space-y-1">
                {burnHash && (
                  <div>BURN TX <Hash addr={burnHash} chainId={dir.target.id} kind="tx" /></div>
                )}
                {releaseHash && (
                  <div>RELEASE TX <Hash addr={releaseHash} chainId={dir.origin.id} kind="tx" /></div>
                )}
              </div>
            </div>
          )}
        </div>
      </TerminalPanel>

      {error && (
        <div className="bg-wax-0/10 border-2 border-wax-0 p-5 font-mono text-[12px] text-wax-0">
          {error}
        </div>
      )}
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className="text-ink-faint text-[9px] uppercase tracking-stamp">{label}</span>
      <span className="text-ink-page text-right truncate">{value}</span>
    </div>
  );
}
