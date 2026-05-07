"use client";

import { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { avalancheFuji } from "wagmi/chains";
import { formatUnits, getAddress, parseUnits } from "viem";

import {
  CONTRACTS,
  ERC20_BALANCE_ABI,
  MOCK_USDC_ABI,
  XYTHUM_LEND_ABI,
} from "@/lib/contracts";
import { getChainName } from "@/lib/chains";

import { PageHeader } from "@/components/primitives/PageHeader";
import { TerminalPanel } from "@/components/primitives/TerminalPanel";
import { PaperButton } from "@/components/primitives/PaperButton";
import { PaperInput } from "@/components/primitives/PaperInput";
import { Hash } from "@/components/primitives/Hash";
import { Pill } from "@/components/primitives/Pill";
import { ChainBadge } from "@/components/ChainBadge";

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";
const FUJI_ID = avalancheFuji.id;

function safeParseUnits(value: string, decimals: number): bigint {
  try {
    if (!value || value.trim() === "") return BigInt(0);
    return parseUnits(value, decimals);
  } catch {
    return BigInt(0);
  }
}

function fmtBigInt(value: bigint | undefined, decimals: number, fractionDigits = 2): string {
  if (value === undefined) return "—";
  const f = formatUnits(value, decimals);
  const [whole, frac = ""] = f.split(".");
  const wholeFormatted = BigInt(whole).toLocaleString("en-US");
  if (fractionDigits === 0) return wholeFormatted;
  const fracPad = (frac + "0".repeat(fractionDigits)).slice(0, fractionDigits);
  return `${wholeFormatted}.${fracPad}`;
}

type HealthTone = "verde" | "leaf" | "wax";

function classifyHealth(healthBps: bigint, debt: bigint): { label: string; tone: HealthTone; display: string } {
  if (debt === BigInt(0)) {
    return { label: "NO DEBT", tone: "verde", display: "∞" };
  }
  // healthBps = collateralValueUsd6 × 10000 / debt
  // 14285 ≈ 100 / 70 (the 70% LTV ceiling)
  const display = (Number(healthBps) / 10000).toFixed(2);
  if (healthBps >= BigInt(14285)) return { label: "SAFE", tone: "verde", display };
  if (healthBps >= BigInt(10000)) return { label: "WARN", tone: "leaf", display };
  return { label: "UNHEALTHY", tone: "wax", display };
}

export default function LendPage() {
  const { address, isConnected, chainId } = useAccount();
  const { switchChain } = useSwitchChain();

  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const lendAddr = CONTRACTS.avalancheFuji.xythumLend;
  const usdcAddr = CONTRACTS.avalancheFuji.mockUsdc;
  const fallbackMirror = CONTRACTS.avalancheFuji.mirrorToken;

  const lendDeployed = !!lendAddr && lendAddr !== ZERO_ADDR;
  const usdcDeployed = !!usdcAddr && usdcAddr !== ZERO_ADDR;
  const deploymentReady = lendDeployed && usdcDeployed;

  const [mirrorInput, setMirrorInput] = useState<string>(fallbackMirror ?? "");
  useEffect(() => {
    if (!mirrorInput && fallbackMirror) setMirrorInput(fallbackMirror);
  }, [fallbackMirror, mirrorInput]);

  const mirrorAddr = useMemo<`0x${string}` | undefined>(() => {
    if (!mirrorInput) return undefined;
    try {
      return getAddress(mirrorInput);
    } catch {
      return undefined;
    }
  }, [mirrorInput]);
  const mirrorOk = !!mirrorAddr && mirrorAddr !== ZERO_ADDR;

  const [supplyAmount, setSupplyAmount] = useState("");
  const [borrowAmount, setBorrowAmount] = useState("");
  const [repayAmount, setRepayAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [error, setError] = useState("");
  const [lastTxHash, setLastTxHash] = useState<`0x${string}` | null>(null);

  const onFuji = chainId === FUJI_ID;

  // ─── reads ───────────────────────────────────────────────────────────
  const { data: xrwaBalance, refetch: refetchXrwaBalance } = useReadContract({
    address: mirrorAddr,
    abi: ERC20_BALANCE_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: FUJI_ID,
    query: { enabled: !!address && mirrorOk, refetchInterval: 5000 },
  });

  const { data: xrwaAllowance, refetch: refetchXrwaAllowance } = useReadContract({
    address: mirrorAddr,
    abi: ERC20_BALANCE_ABI,
    functionName: "allowance",
    args: address && lendAddr ? [address, lendAddr] : undefined,
    chainId: FUJI_ID,
    query: { enabled: !!address && mirrorOk && lendDeployed, refetchInterval: 5000 },
  });

  const { data: usdcBalance, refetch: refetchUsdcBalance } = useReadContract({
    address: usdcAddr,
    abi: MOCK_USDC_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: FUJI_ID,
    query: { enabled: !!address && usdcDeployed, refetchInterval: 5000 },
  });

  const { data: usdcAllowance, refetch: refetchUsdcAllowance } = useReadContract({
    address: usdcAddr,
    abi: MOCK_USDC_ABI,
    functionName: "allowance",
    args: address && lendAddr ? [address, lendAddr] : undefined,
    chainId: FUJI_ID,
    query: { enabled: !!address && usdcDeployed && lendDeployed, refetchInterval: 5000 },
  });

  const { data: positionData, refetch: refetchPosition } = useReadContract({
    address: lendAddr,
    abi: XYTHUM_LEND_ABI,
    functionName: "positionOf",
    args: address ? [address] : undefined,
    chainId: FUJI_ID,
    query: { enabled: !!address && lendDeployed, refetchInterval: 5000 },
  });

  const { data: maxBorrowData, refetch: refetchMaxBorrow } = useReadContract({
    address: lendAddr,
    abi: XYTHUM_LEND_ABI,
    functionName: "maxBorrow",
    args: address ? [address] : undefined,
    chainId: FUJI_ID,
    query: { enabled: !!address && lendDeployed, refetchInterval: 5000 },
  });

  const { data: maxWithdrawData, refetch: refetchMaxWithdraw } = useReadContract({
    address: lendAddr,
    abi: XYTHUM_LEND_ABI,
    functionName: "maxWithdraw",
    args: address ? [address] : undefined,
    chainId: FUJI_ID,
    query: { enabled: !!address && lendDeployed, refetchInterval: 5000 },
  });

  const { data: reservesData, refetch: refetchReserves } = useReadContract({
    address: lendAddr,
    abi: XYTHUM_LEND_ABI,
    functionName: "reservesBalance",
    chainId: FUJI_ID,
    query: { enabled: lendDeployed, refetchInterval: 5000 },
  });

  const collateral = positionData ? (positionData as readonly [bigint, bigint, bigint])[0] : BigInt(0);
  const debt = positionData ? (positionData as readonly [bigint, bigint, bigint])[1] : BigInt(0);
  const healthBps = positionData ? (positionData as readonly [bigint, bigint, bigint])[2] : BigInt(0);

  // ─── tx hooks ────────────────────────────────────────────────────────
  const {
    writeContract: faucetWrite,
    data: faucetHash,
    isPending: faucetPending,
  } = useWriteContract();
  const { isLoading: faucetConfirming, isSuccess: faucetDone } = useWaitForTransactionReceipt({
    hash: faucetHash,
  });
  useEffect(() => {
    if (faucetHash) setLastTxHash(faucetHash);
  }, [faucetHash]);
  useEffect(() => {
    if (faucetDone) refetchUsdcBalance();
  }, [faucetDone, refetchUsdcBalance]);

  const {
    writeContract: approveXrwaWrite,
    data: approveXrwaHash,
    isPending: approveXrwaPending,
  } = useWriteContract();
  const { isLoading: approveXrwaConfirming, isSuccess: approveXrwaDone } = useWaitForTransactionReceipt({
    hash: approveXrwaHash,
  });
  useEffect(() => {
    if (approveXrwaHash) setLastTxHash(approveXrwaHash);
  }, [approveXrwaHash]);
  useEffect(() => {
    if (approveXrwaDone) refetchXrwaAllowance();
  }, [approveXrwaDone, refetchXrwaAllowance]);

  const {
    writeContract: supplyWrite,
    data: supplyHash,
    isPending: supplyPending,
  } = useWriteContract();
  const { isLoading: supplyConfirming, isSuccess: supplyDone } = useWaitForTransactionReceipt({
    hash: supplyHash,
  });
  useEffect(() => {
    if (supplyHash) setLastTxHash(supplyHash);
  }, [supplyHash]);
  useEffect(() => {
    if (supplyDone) {
      refetchXrwaBalance();
      refetchXrwaAllowance();
      refetchPosition();
      refetchMaxBorrow();
      refetchMaxWithdraw();
    }
  }, [supplyDone, refetchXrwaBalance, refetchXrwaAllowance, refetchPosition, refetchMaxBorrow, refetchMaxWithdraw]);

  const {
    writeContract: borrowWrite,
    data: borrowHash,
    isPending: borrowPending,
  } = useWriteContract();
  const { isLoading: borrowConfirming, isSuccess: borrowDone } = useWaitForTransactionReceipt({
    hash: borrowHash,
  });
  useEffect(() => {
    if (borrowHash) setLastTxHash(borrowHash);
  }, [borrowHash]);
  useEffect(() => {
    if (borrowDone) {
      refetchUsdcBalance();
      refetchPosition();
      refetchMaxBorrow();
      refetchMaxWithdraw();
      refetchReserves();
    }
  }, [borrowDone, refetchUsdcBalance, refetchPosition, refetchMaxBorrow, refetchMaxWithdraw, refetchReserves]);

  const {
    writeContract: approveUsdcWrite,
    data: approveUsdcHash,
    isPending: approveUsdcPending,
  } = useWriteContract();
  const { isLoading: approveUsdcConfirming, isSuccess: approveUsdcDone } = useWaitForTransactionReceipt({
    hash: approveUsdcHash,
  });
  useEffect(() => {
    if (approveUsdcHash) setLastTxHash(approveUsdcHash);
  }, [approveUsdcHash]);
  useEffect(() => {
    if (approveUsdcDone) refetchUsdcAllowance();
  }, [approveUsdcDone, refetchUsdcAllowance]);

  const {
    writeContract: repayWrite,
    data: repayHash,
    isPending: repayPending,
  } = useWriteContract();
  const { isLoading: repayConfirming, isSuccess: repayDone } = useWaitForTransactionReceipt({
    hash: repayHash,
  });
  useEffect(() => {
    if (repayHash) setLastTxHash(repayHash);
  }, [repayHash]);
  useEffect(() => {
    if (repayDone) {
      refetchUsdcBalance();
      refetchUsdcAllowance();
      refetchPosition();
      refetchMaxBorrow();
      refetchMaxWithdraw();
      refetchReserves();
    }
  }, [repayDone, refetchUsdcBalance, refetchUsdcAllowance, refetchPosition, refetchMaxBorrow, refetchMaxWithdraw, refetchReserves]);

  const {
    writeContract: withdrawWrite,
    data: withdrawHash,
    isPending: withdrawPending,
  } = useWriteContract();
  const { isLoading: withdrawConfirming, isSuccess: withdrawDone } = useWaitForTransactionReceipt({
    hash: withdrawHash,
  });
  useEffect(() => {
    if (withdrawHash) setLastTxHash(withdrawHash);
  }, [withdrawHash]);
  useEffect(() => {
    if (withdrawDone) {
      refetchXrwaBalance();
      refetchPosition();
      refetchMaxBorrow();
      refetchMaxWithdraw();
    }
  }, [withdrawDone, refetchXrwaBalance, refetchPosition, refetchMaxBorrow, refetchMaxWithdraw]);

  // ─── handlers ────────────────────────────────────────────────────────
  const guard = (): boolean => {
    if (!isConnected) {
      setError("Connect a wallet first.");
      return false;
    }
    if (!deploymentReady) {
      setError("Lending contracts not deployed yet on Fuji.");
      return false;
    }
    return true;
  };

  const ensureFuji = (then: () => void) => {
    if (onFuji) {
      then();
      return;
    }
    switchChain(
      { chainId: FUJI_ID },
      {
        onSuccess: () => then(),
        onError: (e) => setError(`Could not switch chain: ${e.message}`),
      },
    );
  };

  const doFaucet = () => {
    if (!usdcAddr) return;
    faucetWrite(
      {
        address: usdcAddr,
        abi: MOCK_USDC_ABI,
        functionName: "faucet",
        args: [],
      },
      { onError: (e) => setError(`Faucet failed: ${e.message}`) },
    );
  };

  const handleFaucet = () => {
    if (!guard()) return;
    setError("");
    ensureFuji(doFaucet);
  };

  const supplyBigInt = safeParseUnits(supplyAmount, 18);
  const borrowBigInt = safeParseUnits(borrowAmount, 6);
  const repayBigInt = safeParseUnits(repayAmount, 6);
  const withdrawBigInt = safeParseUnits(withdrawAmount, 18);

  const xrwaAllowanceBI = (xrwaAllowance as bigint | undefined) ?? BigInt(0);
  const usdcAllowanceBI = (usdcAllowance as bigint | undefined) ?? BigInt(0);
  const needsXrwaApprove = xrwaAllowanceBI < supplyBigInt;
  const needsUsdcApprove = usdcAllowanceBI < repayBigInt;

  const doApproveXrwa = () => {
    if (!mirrorAddr || !lendAddr) return;
    approveXrwaWrite(
      {
        address: mirrorAddr,
        abi: ERC20_BALANCE_ABI,
        functionName: "approve",
        args: [lendAddr, supplyBigInt],
      },
      { onError: (e) => setError(`Approve failed: ${e.message}`) },
    );
  };

  const doSupply = () => {
    if (!lendAddr) return;
    supplyWrite(
      {
        address: lendAddr,
        abi: XYTHUM_LEND_ABI,
        functionName: "supply",
        args: [supplyBigInt],
      },
      { onError: (e) => setError(`Supply failed: ${e.message}`) },
    );
  };

  const handleApproveOrSupply = () => {
    if (!guard()) return;
    if (!mirrorOk) {
      setError("Paste a valid mirror token address.");
      return;
    }
    if (supplyBigInt === BigInt(0)) {
      setError("Enter a non-zero supply amount.");
      return;
    }
    setError("");
    ensureFuji(() => {
      if (needsXrwaApprove) doApproveXrwa();
      else doSupply();
    });
  };

  const doBorrow = () => {
    if (!lendAddr) return;
    borrowWrite(
      {
        address: lendAddr,
        abi: XYTHUM_LEND_ABI,
        functionName: "borrow",
        args: [borrowBigInt],
      },
      { onError: (e) => setError(`Borrow failed: ${e.message}`) },
    );
  };

  const handleBorrow = () => {
    if (!guard()) return;
    if (borrowBigInt === BigInt(0)) {
      setError("Enter a non-zero borrow amount.");
      return;
    }
    setError("");
    ensureFuji(doBorrow);
  };

  const doApproveUsdc = () => {
    if (!usdcAddr || !lendAddr) return;
    approveUsdcWrite(
      {
        address: usdcAddr,
        abi: MOCK_USDC_ABI,
        functionName: "approve",
        args: [lendAddr, repayBigInt],
      },
      { onError: (e) => setError(`Approve failed: ${e.message}`) },
    );
  };

  const doRepay = () => {
    if (!lendAddr) return;
    repayWrite(
      {
        address: lendAddr,
        abi: XYTHUM_LEND_ABI,
        functionName: "repay",
        args: [repayBigInt],
      },
      { onError: (e) => setError(`Repay failed: ${e.message}`) },
    );
  };

  const handleApproveOrRepay = () => {
    if (!guard()) return;
    if (repayBigInt === BigInt(0)) {
      setError("Enter a non-zero repay amount.");
      return;
    }
    setError("");
    ensureFuji(() => {
      if (needsUsdcApprove) doApproveUsdc();
      else doRepay();
    });
  };

  const doWithdraw = () => {
    if (!lendAddr) return;
    withdrawWrite(
      {
        address: lendAddr,
        abi: XYTHUM_LEND_ABI,
        functionName: "withdraw",
        args: [withdrawBigInt],
      },
      { onError: (e) => setError(`Withdraw failed: ${e.message}`) },
    );
  };

  const handleWithdraw = () => {
    if (!guard()) return;
    if (withdrawBigInt === BigInt(0)) {
      setError("Enter a non-zero withdraw amount.");
      return;
    }
    setError("");
    ensureFuji(doWithdraw);
  };

  const health = classifyHealth(healthBps, debt);

  if (!mounted) {
    return (
      <div className="space-y-6">
        <PageHeader
          article="ARTICLE X"
          kicker="VAULT OF LENDING"
          title="The mirror, lent."
          lede="Loading…"
        />
      </div>
    );
  }

  return (
    <div className="space-y-10">
      <PageHeader
        article="ARTICLE X"
        kicker="VAULT OF LENDING"
        title={
          <>
            Use the <em className="italic">mirror</em> as collateral on its target chain.
          </>
        }
        lede={
          <>
            Supply your xRWA mirror tokens on Fuji as collateral and borrow mock
            USDC against them. A demo market with a hardcoded $1 oracle and a
            fixed 70% LTV — no liquidation engine, no interest. Production
            hardening on V2 roadmap.
          </>
        }
        stamp={{ text: "DEMO MARKET", meta: "FUJI · 70% LTV", tone: "wax" }}
        meta={<>SINGLE PAIR · XRWA / USDC</>}
      />

      <div className="bg-wax-0/10 border-2 border-wax-0 px-5 py-4 font-mono text-[11px] text-wax-0 flex items-start gap-3">
        <div className="stamp text-wax-0 text-[9px] tracking-stamp shrink-0">
          <span className="block leading-tight">DEMO</span>
          <span className="block leading-none text-[7px] mt-0.5 opacity-80">MARKET</span>
        </div>
        <div className="leading-relaxed">
          Hardcoded $1 oracle · 70% LTV · No liquidation engine.
          <br />
          Production hardening (real oracle, interest, liquidations, multi-pair) is on the V2 roadmap.
        </div>
      </div>

      {!deploymentReady && (
        <div className="bg-wax-0/10 border-2 border-wax-0 px-5 py-4 font-mono text-[11px] text-wax-0">
          ⚠ DEPLOYMENT PENDING · XythumLend or MockUSDC not yet deployed on{" "}
          {getChainName(FUJI_ID).toUpperCase()}. Deploy the contracts and update{" "}
          <code className="text-ink-page">contracts.ts</code>. All actions are disabled.
        </div>
      )}

      {/* ── STEP 0 · MIRROR TOKEN ────────────────────────────────────── */}
      <TerminalPanel label="STEP 0 · MIRROR TOKEN (FUJI)" status="idle" meta="COLLATERAL ASSET">
        <div className="p-6 space-y-5">
          <div className="flex items-center justify-between">
            <ChainBadge chainId={FUJI_ID} />
            <Pill label="XRWA · 18 DEC" tone="leaf" />
          </div>
          <PaperInput
            label="Mirror token address"
            placeholder="0x…"
            value={mirrorInput}
            onChange={(e) => setMirrorInput(e.target.value)}
            hint="AUTO-FILLED IF A MIRROR WAS MINTED RECENTLY · OTHERWISE PASTE FROM /LOCK"
          />
          <div className="grid grid-cols-2 gap-2 bg-cover-0 border border-cover-3 p-4 font-mono text-[11px]">
            <Row label="LEND VAULT" value={lendDeployed ? (lendAddr as string) : "DEPLOYMENT PENDING"} />
            <Row label="MOCK USDC" value={usdcDeployed ? (usdcAddr as string) : "DEPLOYMENT PENDING"} />
            <Row
              label="RESERVES AVAILABLE"
              value={
                reservesData !== undefined
                  ? `${fmtBigInt(reservesData as bigint, 6, 2)} USDC`
                  : "—"
              }
            />
            <Row label="MARKET LTV" value="70.00%" />
          </div>
        </div>
      </TerminalPanel>

      {/* ── STEP 1 · USDC FAUCET ─────────────────────────────────────── */}
      <TerminalPanel label="STEP 1 · USDC FAUCET" status="idle" meta="MOCK USDC · OPEN FAUCET">
        <div className="p-6 space-y-5">
          <div className="flex items-center justify-between">
            <div className="font-mono text-[11px] text-ink-muted">
              <span className="text-ink-faint text-[9px] uppercase tracking-stamp mr-2">
                WALLET USDC
              </span>
              <span className="text-ink-page">
                {usdcBalance !== undefined ? fmtBigInt(usdcBalance as bigint, 6, 2) : "—"} USDC
              </span>
            </div>
            <Pill label="USDC · 6 DEC" tone="verde" />
          </div>
          <PaperButton
            tone="verde"
            size="lg"
            fullWidth
            disabled={!deploymentReady || faucetPending || faucetConfirming}
            onClick={handleFaucet}
          >
            {faucetPending || faucetConfirming
              ? "Faucet pending…"
              : !isConnected
                ? "Connect wallet"
                : !onFuji
                  ? `Switch to ${getChainName(FUJI_ID)}`
                  : "▶ Faucet 10,000 USDC"}
          </PaperButton>
        </div>
      </TerminalPanel>

      {/* ── STEP 2 · SUPPLY xRWA ─────────────────────────────────────── */}
      <TerminalPanel label="STEP 2 · SUPPLY XRWA" status="idle" meta="COLLATERAL DEPOSIT">
        <div className="p-6 space-y-5">
          <div className="flex items-center justify-between">
            <div className="font-mono text-[11px] text-ink-muted">
              <span className="text-ink-faint text-[9px] uppercase tracking-stamp mr-2">
                WALLET XRWA
              </span>
              <span className="text-ink-page">
                {xrwaBalance !== undefined ? fmtBigInt(xrwaBalance as bigint, 18, 2) : "—"} xRWA
              </span>
            </div>
            <Pill label="XRWA · 18 DEC" tone="leaf" />
          </div>
          <PaperInput
            label="Amount to supply"
            type="number"
            placeholder="100000"
            value={supplyAmount}
            onChange={(e) => setSupplyAmount(e.target.value)}
            suffix="XRWA"
            hint={
              xrwaAllowance !== undefined
                ? `ALLOWANCE · ${fmtBigInt(xrwaAllowance as bigint, 18, 2)} XRWA`
                : "ALLOWANCE · —"
            }
          />
          <PaperButton
            tone="leaf"
            size="lg"
            fullWidth
            disabled={
              !deploymentReady ||
              !mirrorOk ||
              approveXrwaPending ||
              approveXrwaConfirming ||
              supplyPending ||
              supplyConfirming ||
              !supplyAmount
            }
            onClick={handleApproveOrSupply}
          >
            {approveXrwaPending || approveXrwaConfirming
              ? "Confirming approve…"
              : supplyPending || supplyConfirming
                ? "Supplying…"
                : !isConnected
                  ? "Connect wallet"
                  : !onFuji
                    ? `Switch to ${getChainName(FUJI_ID)}`
                    : needsXrwaApprove
                      ? `▶ Approve ${supplyAmount} xRWA`
                      : `▶ Supply ${supplyAmount} xRWA`}
          </PaperButton>
        </div>
      </TerminalPanel>

      {/* ── STEP 3 · BORROW USDC ─────────────────────────────────────── */}
      <TerminalPanel label="STEP 3 · BORROW USDC" status="idle" meta="DEBT ISSUE">
        <div className="p-6 space-y-5">
          <PaperInput
            label="Amount to borrow"
            type="number"
            placeholder="5000"
            value={borrowAmount}
            onChange={(e) => setBorrowAmount(e.target.value)}
            suffix="USDC"
            hint={
              maxBorrowData !== undefined
                ? `MAX BORROW · ${fmtBigInt(maxBorrowData as bigint, 6, 2)} USDC (70% LTV CAP)`
                : "MAX BORROW · —"
            }
          />
          <PaperButton
            tone="leaf"
            size="lg"
            fullWidth
            disabled={
              !deploymentReady ||
              borrowPending ||
              borrowConfirming ||
              !borrowAmount
            }
            onClick={handleBorrow}
          >
            {borrowPending || borrowConfirming
              ? "Borrowing…"
              : !isConnected
                ? "Connect wallet"
                : !onFuji
                  ? `Switch to ${getChainName(FUJI_ID)}`
                  : `▶ Borrow ${borrowAmount} USDC`}
          </PaperButton>
        </div>
      </TerminalPanel>

      {/* ── POSITION SUMMARY ─────────────────────────────────────────── */}
      <TerminalPanel label="POSITION SUMMARY" status="live" meta="POLLING · 5s">
        <div className="p-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="bg-cover-0 border border-cover-3 p-5">
              <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint mb-2">
                COLLATERAL
              </div>
              <div className="font-mono tabular-nums text-2xl text-ink-page">
                {fmtBigInt(collateral, 18, 2)}
              </div>
              <div className="font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mt-1">
                XRWA
              </div>
            </div>
            <div className="bg-cover-0 border border-cover-3 p-5">
              <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint mb-2">
                DEBT
              </div>
              <div className="font-mono tabular-nums text-2xl text-ink-page">
                {fmtBigInt(debt, 6, 2)}
              </div>
              <div className="font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mt-1">
                USDC
              </div>
            </div>
            <div className="bg-cover-0 border border-cover-3 p-5">
              <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint mb-2">
                HEALTH FACTOR
              </div>
              <div className="font-mono tabular-nums text-2xl text-ink-page">
                {health.display}
              </div>
              <div className="mt-2">
                <Pill label={health.label} tone={health.tone} />
              </div>
            </div>
          </div>
        </div>
      </TerminalPanel>

      {/* ── STEP 4 · REPAY + WITHDRAW ───────────────────────────────── */}
      <TerminalPanel label="STEP 4 · REPAY + WITHDRAW" status="idle" meta="UNWIND">
        <div className="p-6 space-y-6">
          <div className="space-y-3">
            <PaperInput
              label="Amount to repay"
              type="number"
              placeholder="5000"
              value={repayAmount}
              onChange={(e) => setRepayAmount(e.target.value)}
              suffix="USDC"
              hint={
                usdcAllowance !== undefined
                  ? `ALLOWANCE · ${fmtBigInt(usdcAllowance as bigint, 6, 2)} USDC · CURRENT DEBT · ${fmtBigInt(debt, 6, 2)} USDC`
                  : "ALLOWANCE · —"
              }
            />
            <PaperButton
              tone="wax"
              size="lg"
              fullWidth
              disabled={
                !deploymentReady ||
                approveUsdcPending ||
                approveUsdcConfirming ||
                repayPending ||
                repayConfirming ||
                !repayAmount
              }
              onClick={handleApproveOrRepay}
            >
              {approveUsdcPending || approveUsdcConfirming
                ? "Confirming approve…"
                : repayPending || repayConfirming
                  ? "Repaying…"
                  : !isConnected
                    ? "Connect wallet"
                    : !onFuji
                      ? `Switch to ${getChainName(FUJI_ID)}`
                      : needsUsdcApprove
                        ? `▶ Approve ${repayAmount} USDC`
                        : `▶ Repay ${repayAmount} USDC`}
            </PaperButton>
          </div>
          <div className="space-y-3">
            <PaperInput
              label="Amount to withdraw"
              type="number"
              placeholder="100000"
              value={withdrawAmount}
              onChange={(e) => setWithdrawAmount(e.target.value)}
              suffix="XRWA"
              hint={
                maxWithdrawData !== undefined
                  ? `MAX WITHDRAW · ${fmtBigInt(maxWithdrawData as bigint, 18, 2)} XRWA (LTV-CONSTRAINED)`
                  : "MAX WITHDRAW · —"
              }
            />
            <PaperButton
              tone="verde"
              size="lg"
              fullWidth
              disabled={
                !deploymentReady ||
                withdrawPending ||
                withdrawConfirming ||
                !withdrawAmount
              }
              onClick={handleWithdraw}
            >
              {withdrawPending || withdrawConfirming
                ? "Withdrawing…"
                : !isConnected
                  ? "Connect wallet"
                  : !onFuji
                    ? `Switch to ${getChainName(FUJI_ID)}`
                    : `▶ Withdraw ${withdrawAmount} xRWA`}
            </PaperButton>
          </div>
        </div>
      </TerminalPanel>

      {lastTxHash && (
        <div className="bg-verde-0/10 border border-verde-0/40 px-5 py-4 font-mono text-[11px] text-verde-0">
          ✓ RECENT TX · <Hash addr={lastTxHash} chainId={FUJI_ID} kind="tx" />
        </div>
      )}

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
