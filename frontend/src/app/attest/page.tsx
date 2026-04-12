"use client";

import { useState, useEffect } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useDeployContract,
  useSwitchChain,
} from "wagmi";
import { parseEther, keccak256, toHex } from "viem";
import { avalancheFuji, bscTestnet } from "wagmi/chains";
import { ChainBadge } from "@/components/ChainBadge";
import {
  CCIP_SENDER_ABI,
  CCIP_CHAIN_SELECTORS,
  CONTRACTS,
  CANONICAL_FACTORY_ABI,
} from "@/lib/contracts";
import { MOCK_RWA_BYTECODE, MOCK_RWA_ABI } from "@/lib/mockrwa-bytecode";
import { signAttestation, type Attestation } from "@/lib/signing";
import { getChainName, monadTestnet } from "@/lib/chains";
import { PageHeader } from "@/components/primitives/PageHeader";
import { TerminalPanel } from "@/components/primitives/TerminalPanel";
import { PaperInput } from "@/components/primitives/PaperInput";
import { PaperButton } from "@/components/primitives/PaperButton";
import { Hash } from "@/components/primitives/Hash";
import { Pill } from "@/components/primitives/Pill";

// Direction configs — ccipSelector/ccipSender are optional (Monad has no CCIP)
interface Direction {
  id: string;
  label: string;
  sourceChain: { id: number; name: string };
  targetChain: { id: number; name: string };
  ccipSelector?: string;
  ccipSender?: string;
  targetFactory: string;
  targetAttReg: string;
  defaultRwa: string;
  hasCcip: boolean;
}

const DIRECTIONS: Direction[] = [
  {
    id: "fuji-to-bnb",
    label: "Fuji -> BNB",
    sourceChain: avalancheFuji,
    targetChain: bscTestnet,
    ccipSelector: CCIP_CHAIN_SELECTORS.bscTestnet,
    ccipSender: CONTRACTS.avalancheFuji.ccipSender!,
    targetFactory: CONTRACTS.bscTestnet.canonicalFactory,
    targetAttReg: CONTRACTS.bscTestnet.attestationRegistry,
    defaultRwa: CONTRACTS.avalancheFuji.mockRwa!,
    hasCcip: true,
  },
  {
    id: "bnb-to-fuji",
    label: "BNB -> Fuji",
    sourceChain: bscTestnet,
    targetChain: avalancheFuji,
    ccipSelector: CCIP_CHAIN_SELECTORS.avalancheFuji,
    ccipSender: CONTRACTS.bscTestnet.ccipSender!,
    targetFactory: CONTRACTS.avalancheFuji.canonicalFactory,
    targetAttReg: CONTRACTS.avalancheFuji.attestationRegistry,
    defaultRwa: CONTRACTS.bscTestnet.mockRwa!,
    hasCcip: true,
  },
  {
    id: "fuji-to-monad",
    label: "Fuji -> Monad",
    sourceChain: avalancheFuji,
    targetChain: monadTestnet,
    targetFactory: CONTRACTS.monadTestnet.canonicalFactory,
    targetAttReg: CONTRACTS.monadTestnet.attestationRegistry,
    defaultRwa: CONTRACTS.avalancheFuji.mockRwa!,
    hasCcip: false,
  },
  {
    id: "bnb-to-monad",
    label: "BNB -> Monad",
    sourceChain: bscTestnet,
    targetChain: monadTestnet,
    targetFactory: CONTRACTS.monadTestnet.canonicalFactory,
    targetAttReg: CONTRACTS.monadTestnet.attestationRegistry,
    defaultRwa: CONTRACTS.bscTestnet.mockRwa!,
    hasCcip: false,
  },
  {
    id: "monad-to-fuji",
    label: "Monad -> Fuji",
    sourceChain: monadTestnet,
    targetChain: avalancheFuji,
    targetFactory: CONTRACTS.avalancheFuji.canonicalFactory,
    targetAttReg: CONTRACTS.avalancheFuji.attestationRegistry,
    defaultRwa: CONTRACTS.monadTestnet.mockRwa!,
    hasCcip: false,
  },
  {
    id: "monad-to-bnb",
    label: "Monad -> BNB",
    sourceChain: monadTestnet,
    targetChain: bscTestnet,
    targetFactory: CONTRACTS.bscTestnet.canonicalFactory,
    targetAttReg: CONTRACTS.bscTestnet.attestationRegistry,
    defaultRwa: CONTRACTS.monadTestnet.mockRwa!,
    hasCcip: false,
  },
];

type DeployMethod = "direct" | "ccip";

export default function AttestPage() {
  const { address, isConnected, chainId } = useAccount();
  const { switchChain } = useSwitchChain();
  const [mounted, setMounted] = useState(false);
  useEffect(() => { setMounted(true); }, []);

  // ── State ──
  const [dirIdx, setDirIdx] = useState(0);
  const dir = DIRECTIONS[dirIdx];

  const [originAddress, setOriginAddress] = useState<string>(dir.defaultRwa);
  const [lockedAmount, setLockedAmount] = useState("1000000");
  const [nonce, setNonce] = useState("3");
  const [error, setError] = useState("");

  // Signing state
  const [signing, setSigning] = useState(false);
  const [signatures, setSignatures] = useState<`0x${string}` | null>(null);
  const [signerBitmap, setSignerBitmap] = useState<bigint>(BigInt(0));
  const [signedAtt, setSignedAtt] = useState<Attestation | null>(null);

  // Deploy method — default to direct for chains without CCIP
  const [deployMethod, setDeployMethod] = useState<DeployMethod>("direct");

  // Force direct deploy for directions without CCIP
  useEffect(() => {
    if (!DIRECTIONS[dirIdx].hasCcip) {
      setDeployMethod("direct");
    }
  }, [dirIdx]);

  // TX state
  const [ccipMsgId, setCcipMsgId] = useState<string>("");
  const [directMirrorAddr, setDirectMirrorAddr] = useState<string>("");

  // ── Deploy MockRWA ──
  const { deployContract, data: deployHash, isPending: deployPending } = useDeployContract();
  const { data: deployReceipt, isLoading: deployConfirming } = useWaitForTransactionReceipt({ hash: deployHash });

  // ── Send via CCIP TX ──
  const { writeContract: sendCCIP, data: ccipHash, isPending: ccipPending } = useWriteContract();
  const { data: ccipReceipt, isLoading: ccipConfirming } = useWaitForTransactionReceipt({ hash: ccipHash });

  // ── Direct Deploy TX ──
  const { writeContract: deployDirect, data: directHash, isPending: directPending } = useWriteContract();
  const { data: directReceipt, isLoading: directConfirming } = useWaitForTransactionReceipt({ hash: directHash });

  // When direction changes, reset state
  useEffect(() => {
    setOriginAddress(DIRECTIONS[dirIdx].defaultRwa);
    setSignatures(null);
    setSignedAtt(null);
    setError("");
    setCcipMsgId("");
    setDirectMirrorAddr("");
  }, [dirIdx]);

  // When deploy receipt arrives, set the origin address
  useEffect(() => {
    if (deployReceipt?.contractAddress) {
      setOriginAddress(deployReceipt.contractAddress);
    }
  }, [deployReceipt]);

  // When CCIP send receipt arrives, extract CCIP message ID from logs
  useEffect(() => {
    if (ccipReceipt) {
      const log = ccipReceipt.logs.find(
        (l) => l.topics[0] === "0x5cc25302c2f18447d84e2df490a816ed05b21da5297eab7c9f1a7628a3ce4e83"
      );
      if (log && log.data) {
        const msgId = "0x" + log.data.slice(2, 66);
        setCcipMsgId(msgId);
      }
    }
  }, [ccipReceipt]);

  // When direct deploy receipt arrives, extract mirror address from MirrorDeployed event
  useEffect(() => {
    if (directReceipt) {
      // MirrorDeployed(address indexed mirror, address indexed originContract, uint256, uint256, bytes32)
      // Event topic0 = keccak256("MirrorDeployed(address,address,uint256,uint256,bytes32)")
      const MIRROR_DEPLOYED_TOPIC = "0xd7a30203c37d4b3c6805e8e080de0879218289cb99c74869910cb8ca31de4801";
      const mirrorLog = directReceipt.logs.find(
        (l) => l.topics[0] === MIRROR_DEPLOYED_TOPIC
      );
      if (mirrorLog && mirrorLog.topics[1]) {
        // First indexed param is mirror address (padded to 32 bytes)
        const mirrorAddr = "0x" + mirrorLog.topics[1].slice(26);
        setDirectMirrorAddr(mirrorAddr);
      }
    }
  }, [directReceipt]);

  // ── Handlers ──
  const handleDeployRwa = () => {
    if (!isConnected) return;
    if (chainId !== dir.sourceChain.id) {
      switchChain({ chainId: dir.sourceChain.id });
      return;
    }
    setError("");
    deployContract({
      bytecode: MOCK_RWA_BYTECODE,
      abi: MOCK_RWA_ABI,
    });
  };

  const handleSign = async () => {
    setError("");
    setSigning(true);
    try {
      const att: Attestation = {
        originContract: originAddress as `0x${string}`,
        originChainId: BigInt(dir.sourceChain.id),
        targetChainId: BigInt(dir.targetChain.id),
        navRoot: keccak256(toHex("demo-nav-data")),
        complianceRoot: keccak256(toHex("demo-compliance")),
        lockedAmount: parseEther(lockedAmount),
        timestamp: BigInt(Math.floor(Date.now() / 1000)),
        nonce: BigInt(nonce),
      };

      const result = await signAttestation(
        att,
        dir.targetChain.id,
        dir.targetAttReg as `0x${string}`
      );

      setSignatures(result.signatures);
      setSignerBitmap(result.signerBitmap);
      setSignedAtt(att);
    } catch (e: unknown) {
      setError(`Signing failed: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setSigning(false);
    }
  };

  const handleSendCCIP = () => {
    if (!signatures || !signedAtt || !isConnected || !dir.hasCcip) return;

    if (chainId !== dir.sourceChain.id) {
      switchChain({ chainId: dir.sourceChain.id });
      return;
    }

    setError("");
    const fee = dir.sourceChain.id === avalancheFuji.id ? "0.2" : "0.01";

    sendCCIP({
      address: dir.ccipSender as `0x${string}`,
      abi: CCIP_SENDER_ABI,
      functionName: "sendAttestation",
      args: [BigInt(dir.ccipSelector!), signedAtt, signatures, signerBitmap],
      value: parseEther(fee),
    });
  };

  const handleDirectDeploy = () => {
    if (!signatures || !signedAtt || !isConnected) return;

    // Direct deploy: wallet must be on TARGET chain
    if (chainId !== dir.targetChain.id) {
      switchChain({ chainId: dir.targetChain.id });
      return;
    }

    setError("");

    deployDirect({
      address: dir.targetFactory as `0x${string}`,
      abi: CANONICAL_FACTORY_ABI,
      functionName: "deployMirrorDirect",
      args: [signedAtt, signatures, signerBitmap],
    });
  };

  const isOnSourceChain = chainId === dir.sourceChain.id;
  const isOnTargetChain = chainId === dir.targetChain.id;

  if (!mounted) {
    return (
      <div className="space-y-6">
        <PageHeader
          article="ARTICLE VII"
          kicker="ATTESTATION DESK"
          title="Issuing chamber"
          lede="Loading…"
        />
      </div>
    );
  }

  return (
    <div className="space-y-10">
      <PageHeader
        article="ARTICLE VII"
        kicker="ATTESTATION DESK"
        title={
          <>
            Issue a <em className="italic">canonical mirror</em>.
          </>
        }
        lede={
          <>
            Four steps. Pick a corridor, sign the attestation with three of five
            authorized signers, and dispatch — instantly to the target chain or
            via Chainlink CCIP relay. Same outcome, same predictable address.
          </>
        }
        stamp={{ text: "TESTNET", meta: "DETERMINISTIC SIGNERS", tone: "wax" }}
        meta={<>DEMO SIGNERS · NOT FOR PRODUCTION</>}
      />

      {/* ── Corridor selector ── */}
      <TerminalPanel label="STEP 0 · CORRIDOR" status="idle" meta="SOURCE → TARGET">
        <div className="p-4 grid grid-cols-2 md:grid-cols-3 gap-2">
          {DIRECTIONS.map((d, i) => {
            const active = dirIdx === i;
            return (
              <button
                key={d.id}
                onClick={() => setDirIdx(i)}
                className={`px-3 py-3 font-mono text-[11px] uppercase tracking-stamp transition-all border ${
                  active
                    ? "border-leaf-0 bg-leaf-0/10 text-leaf-0"
                    : "border-cover-3 bg-cover-2 text-ink-muted hover:border-leaf-2 hover:text-ink-page"
                }`}
              >
                <span className="block">{d.label}</span>
                <span className="block text-[8px] text-ink-faint mt-1">
                  {d.hasCcip ? "CCIP + DIRECT" : "DIRECT ONLY"}
                </span>
              </button>
            );
          })}
        </div>
      </TerminalPanel>

      {/* ── Step 1: Origin ── */}
      <TerminalPanel
        label="STEP 1 · ORIGIN ASSET"
        status="idle"
        meta={`SOURCE · ${getChainName(dir.sourceChain.id).toUpperCase()}`}
      >
        <div className="p-6 space-y-5">
          <div className="flex items-center justify-between">
            <ChainBadge chainId={dir.sourceChain.id} />
            <Pill label="ERC-20" tone="leaf" />
          </div>
          <PaperInput
            label="Origin contract address"
            placeholder="0x… (ERC-20 on source chain)"
            value={originAddress}
            onChange={(e) => setOriginAddress(e.target.value)}
            hint={`DEFAULT · PRE-DEPLOYED MOCKRWA ON ${getChainName(dir.sourceChain.id).toUpperCase()}`}
          />
          <div className="pt-3 border-t border-cover-3 flex items-center justify-between gap-3">
            <span className="font-mono text-[10px] uppercase tracking-stamp text-ink-muted">
              OR · MINT A FRESH MOCKRWA (mTBILL · 1M tokens)
            </span>
            <PaperButton
              tone="ghost"
              size="sm"
              disabled={!isConnected || deployPending || deployConfirming}
              onClick={handleDeployRwa}
            >
              {deployPending
                ? "Confirm in wallet…"
                : deployConfirming
                  ? "Deploying…"
                  : !isConnected
                    ? "Connect wallet"
                    : !isOnSourceChain
                      ? `Switch to ${getChainName(dir.sourceChain.id)}`
                      : "Mint MockRWA"}
            </PaperButton>
          </div>
          {deployReceipt?.contractAddress && (
            <div className="bg-verde-0/10 border border-verde-0/40 px-3 py-2 font-mono text-[11px] text-verde-0">
              ✓ DEPLOYED · <Hash addr={deployReceipt.contractAddress} />
            </div>
          )}
        </div>
      </TerminalPanel>

      {/* ── Step 2: Configure ── */}
      <TerminalPanel
        label="STEP 2 · ATTESTATION FIELDS"
        status="idle"
        meta="EIP-712 PAYLOAD"
      >
        <div className="p-6 grid grid-cols-1 md:grid-cols-2 gap-5">
          <PaperInput
            label="Locked amount (tokens)"
            value={lockedAmount}
            onChange={(e) => setLockedAmount(e.target.value)}
            hint="BECOMES THE MIRROR'S MINTCAP"
          />
          <PaperInput
            label="Nonce"
            value={nonce}
            onChange={(e) => setNonce(e.target.value)}
            hint="UNIQUE PER (ORIGIN · TARGET) PAIR"
          />
          <div className="md:col-span-2 mt-2 grid grid-cols-2 gap-2 bg-cover-0 border border-cover-3 p-4 font-mono text-[11px]">
            <SchemaRow label="SOURCE" value={`${getChainName(dir.sourceChain.id)} · ${dir.sourceChain.id}`} />
            <SchemaRow label="TARGET" value={`${getChainName(dir.targetChain.id)} · ${dir.targetChain.id}`} />
            <SchemaRow label="TARGET FACTORY" value={dir.targetFactory.slice(0, 14) + "…"} />
            <SchemaRow label="TARGET ATT.REG (DOMAIN)" value={dir.targetAttReg.slice(0, 14) + "…"} />
          </div>
        </div>
      </TerminalPanel>

      {/* ── Step 3: Sign ── */}
      <TerminalPanel
        label="STEP 3 · ENDORSEMENT"
        status={signatures ? "live" : "idle"}
        meta="3 / 5 ECDSA THRESHOLD"
      >
        <div className="p-6 space-y-5">
          <p className="font-body text-[13px] text-ink-muted leading-relaxed max-w-2xl">
            Three deterministic testnet signer keys produce ECDSA signatures
            over the EIP-712 typed data. The target chain&apos;s
            AttestationRegistry verifies the bitmap on-chain.
          </p>
          <PaperButton
            tone="leaf"
            size="lg"
            fullWidth
            disabled={signing || !originAddress}
            onClick={handleSign}
          >
            {signing
              ? "Signing with three keys…"
              : signatures
                ? "Re-endorse"
                : "▶ Endorse with 3 / 5 signers"}
          </PaperButton>
          {signatures && (
            <div className="parchment passport-corner p-5 relative">
              <div className="absolute -top-3 right-4">
                <div className="stamp stamp-fresh text-verde-0 text-[10px] tracking-stamp bg-parchment-0">
                  <span className="block leading-tight">ENDORSED</span>
                  <span className="block leading-none text-[7px] mt-0.5">
                    BITMAP · {signerBitmap.toString()}
                  </span>
                </div>
              </div>
              <div className="font-mono text-[10px] uppercase tracking-stamp text-ink-deep/55 mb-2">
                ATTESTATION · SIGNED &amp; PACKED
              </div>
              <div className="font-mono text-[11px] text-ink-deep break-all">
                {signatures.slice(0, 64)}
                <span className="text-ink-deep/40"> … </span>
                {signatures.slice(-16)}
              </div>
              <div className="mt-3 pt-3 border-t border-ink-deep/20 flex items-center justify-between font-mono text-[9px] uppercase tracking-stamp text-ink-deep/60">
                <span>{signatures.length / 2 - 1} BYTES</span>
                <span>BITMAP {signerBitmap.toString()}</span>
              </div>
            </div>
          )}
        </div>
      </TerminalPanel>

      {/* ── Step 4: Deploy ── */}
      {signatures && (
        <TerminalPanel
          label="STEP 4 · DISPATCH"
          status="idle"
          meta="CHOOSE PATH"
        >
          <div className="p-6 space-y-5">
            <div className="grid grid-cols-2 gap-2">
              <PathTab
                label="DIRECT"
                sub="~5 sec · target gas"
                active={deployMethod === "direct"}
                onClick={() => setDeployMethod("direct")}
                tone="leaf"
              />
              <PathTab
                label={dir.hasCcip ? "CCIP RELAY" : "CCIP · N/A"}
                sub={dir.hasCcip ? "~20-35 min · source gas" : "MONAD HAS NO CCIP"}
                active={deployMethod === "ccip"}
                onClick={() => dir.hasCcip && setDeployMethod("ccip")}
                tone="wax"
                disabled={!dir.hasCcip}
              />
            </div>

            <div className="bg-cover-0 border border-cover-3 p-4 font-body text-[12px] text-ink-muted leading-relaxed">
              {deployMethod === "direct" ? (
                <>
                  <span className="text-leaf-0 font-mono uppercase tracking-stamp text-[10px]">
                    DIRECT
                  </span>{" "}
                  · Wallet submits attestation + signatures to{" "}
                  <code className="text-ink-page">deployMirrorDirect()</code>{" "}
                  on the <em className="italic text-ink-page">target chain</em>.
                  Mirror appears in ~5 seconds.
                </>
              ) : (
                <>
                  <span className="text-wax-0 font-mono uppercase tracking-stamp text-[10px]">
                    CCIP RELAY
                  </span>{" "}
                  · Wallet calls{" "}
                  <code className="text-ink-page">CCIPSender.sendAttestation()</code>{" "}
                  on the <em className="italic text-ink-page">source chain</em>.
                  Chainlink relays it; no target chain tx required.
                </>
              )}
            </div>

            {deployMethod === "direct" ? (
              <PaperButton
                tone="leaf"
                size="lg"
                fullWidth
                disabled={!isConnected || directPending || directConfirming}
                onClick={handleDirectDeploy}
              >
                {directPending
                  ? "Confirm in wallet…"
                  : directConfirming
                    ? "Deploying mirror…"
                    : !isConnected
                      ? "Connect wallet"
                      : !isOnTargetChain
                        ? `Switch to ${getChainName(dir.targetChain.id)}`
                        : "▶ Deploy mirror · DIRECT"}
              </PaperButton>
            ) : (
              <PaperButton
                tone="wax"
                size="lg"
                fullWidth
                disabled={!isConnected || ccipPending || ccipConfirming}
                onClick={handleSendCCIP}
              >
                {ccipPending
                  ? "Confirm in wallet…"
                  : ccipConfirming
                    ? "Awaiting confirmation…"
                    : !isConnected
                      ? "Connect wallet"
                      : !isOnSourceChain
                        ? `Switch to ${getChainName(dir.sourceChain.id)}`
                        : `▶ Send via CCIP (${dir.sourceChain.id === avalancheFuji.id ? "~0.2 AVAX" : "~0.01 BNB"})`}
              </PaperButton>
            )}

            {directHash && (
              <div className="bg-verde-0/10 border border-verde-0/40 p-4 font-mono text-[11px] text-verde-0">
                ✓ TX SUBMITTED · {directHash.slice(0, 24)}…
              </div>
            )}
            {ccipHash && (
              <div className="bg-leaf-0/10 border border-leaf-0/40 p-4 font-mono text-[11px] text-leaf-0">
                ✓ TX SUBMITTED · {ccipHash.slice(0, 24)}…
              </div>
            )}
          </div>
        </TerminalPanel>
      )}

      {/* ── Direct deploy success ── */}
      {directMirrorAddr && (
        <div className="parchment passport-corner-tr p-8 relative">
          <div className="absolute -top-4 right-6">
            <div className="stamp stamp-fresh text-verde-0 text-[12px] tracking-stamp bg-parchment-0">
              <span className="block leading-tight">ISSUED</span>
              <span className="block leading-none text-[7px] mt-0.5">
                MIRROR · DIRECT · {getChainName(dir.targetChain.id)}
              </span>
            </div>
          </div>
          <div className="font-display italic text-4xl text-verde-1 mb-2">
            Mirror minted.
          </div>
          <div className="font-body text-[14px] text-ink-deep/70 mb-4">
            A canonical xRWA mirror is live on {getChainName(dir.targetChain.id)}.
          </div>
          <div className="bg-cover-0 border-2 border-verde-0 px-5 py-4 font-mono text-base text-leaf-0 break-all">
            {directMirrorAddr}
          </div>
          <div className="mt-4 flex gap-2">
            <a href="/verify" className="inline-block">
              <PaperButton tone="leaf" size="sm">↪ Verify canonical</PaperButton>
            </a>
            <a href="/mirrors" className="inline-block">
              <PaperButton tone="ghost" size="sm">↪ See registry</PaperButton>
            </a>
          </div>
        </div>
      )}

      {/* ── CCIP tracking ── */}
      {ccipMsgId && (
        <div className="parchment passport-corner-tr p-8 relative">
          <div className="absolute -top-4 right-6">
            <div className="stamp stamp-fresh text-leaf-1 text-[12px] tracking-stamp bg-parchment-0">
              <span className="block leading-tight">IN TRANSIT</span>
              <span className="block leading-none text-[7px] mt-0.5">
                CHAINLINK CCIP RELAY
              </span>
            </div>
          </div>
          <div className="font-display italic text-4xl text-wax-1 mb-2">
            Dispatched.
          </div>
          <div className="font-body text-[13px] text-ink-deep/70 mb-3">
            CCIP message ID:
          </div>
          <div className="bg-cover-0 border border-cover-3 px-4 py-3 font-mono text-[11px] text-leaf-0 break-all">
            {ccipMsgId}
          </div>
          <a
            href={`https://ccip.chain.link/msg/${ccipMsgId}`}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-block mt-4"
          >
            <PaperButton tone="wax" size="sm">↗ Track on CCIP Explorer</PaperButton>
          </a>
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

function SchemaRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className="text-ink-faint text-[9px] uppercase tracking-stamp">{label}</span>
      <span className="text-ink-page text-right">{value}</span>
    </div>
  );
}

function PathTab({
  label,
  sub,
  active,
  onClick,
  tone,
  disabled,
}: {
  label: string;
  sub: string;
  active: boolean;
  onClick: () => void;
  tone: "leaf" | "wax";
  disabled?: boolean;
}) {
  const accent =
    tone === "leaf"
      ? active
        ? "border-leaf-0 bg-leaf-0/15 text-leaf-0"
        : "border-cover-3 bg-cover-2 text-ink-muted"
      : active
        ? "border-wax-0 bg-wax-0/15 text-wax-0"
        : "border-cover-3 bg-cover-2 text-ink-muted";
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`px-4 py-3 text-left transition-all border ${accent} ${disabled ? "opacity-40 cursor-not-allowed" : "hover:border-leaf-2"}`}
    >
      <div className="font-mono text-[11px] uppercase tracking-stamp font-semibold">
        {label}
      </div>
      <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint mt-1">
        {sub}
      </div>
    </button>
  );
}
