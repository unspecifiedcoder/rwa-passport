"use client";

import { useState, useEffect } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useDeployContract,
  useSwitchChain,
} from "wagmi";
import { parseEther, keccak256, toHex, decodeEventLog } from "viem";
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
import { getChainName } from "@/lib/chains";

// Direction configs
const DIRECTIONS = [
  {
    id: "fuji-to-bnb",
    label: "Avalanche Fuji -> BNB Testnet",
    sourceChain: avalancheFuji,
    targetChain: bscTestnet,
    ccipSelector: CCIP_CHAIN_SELECTORS.bscTestnet,
    ccipSender: CONTRACTS.avalancheFuji.ccipSender!,
    targetFactory: CONTRACTS.bscTestnet.canonicalFactory,
    targetAttReg: CONTRACTS.bscTestnet.attestationRegistry,
    defaultRwa: CONTRACTS.avalancheFuji.mockRwa!,
  },
  {
    id: "bnb-to-fuji",
    label: "BNB Testnet -> Avalanche Fuji",
    sourceChain: bscTestnet,
    targetChain: avalancheFuji,
    ccipSelector: CCIP_CHAIN_SELECTORS.avalancheFuji,
    ccipSender: CONTRACTS.bscTestnet.ccipSender!,
    targetFactory: CONTRACTS.avalancheFuji.canonicalFactory,
    targetAttReg: CONTRACTS.avalancheFuji.attestationRegistry,
    defaultRwa: CONTRACTS.bscTestnet.mockRwa!,
  },
] as const;

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

  // Deploy method
  const [deployMethod, setDeployMethod] = useState<DeployMethod>("direct");

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
    if (!signatures || !signedAtt || !isConnected) return;

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
      args: [BigInt(dir.ccipSelector), signedAtt, signatures, signerBitmap],
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
        <h1 className="text-2xl font-bold">Cross-Chain RWA Attestation</h1>
        <p className="text-gray-400 text-sm">Loading...</p>
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <h1 className="text-2xl font-bold mb-2">Cross-Chain RWA Attestation</h1>
        <p className="text-gray-400 text-sm">
          Deploy an RWA, sign an attestation with the demo signer network, and deploy a canonical mirror.
        </p>
        <p className="text-xs text-yellow-500 mt-1">
          TESTNET DEMO: Uses deterministic signer keys. Not for production.
        </p>
      </div>

      {/* ── Direction Selector ── */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-4">
        <label className="block text-sm font-medium text-gray-400 mb-2">Direction</label>
        <div className="flex gap-2">
          {DIRECTIONS.map((d, i) => (
            <button
              key={d.id}
              onClick={() => setDirIdx(i)}
              className={`flex-1 px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                dirIdx === i
                  ? "bg-brand-600 text-white"
                  : "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
              }`}
            >
              {d.label}
            </button>
          ))}
        </div>
      </div>

      {/* ── Step 1: Deploy MockRWA (optional) ── */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold text-white">
            Step 1: Origin RWA Token
          </h3>
          <ChainBadge chainId={dir.sourceChain.id} />
        </div>

        <div>
          <label className="block text-xs text-gray-400 mb-1">Origin Contract Address</label>
          <input
            type="text"
            value={originAddress}
            onChange={(e) => setOriginAddress(e.target.value)}
            placeholder="0x... (ERC-20 on source chain)"
            className="w-full bg-gray-800 border border-gray-700 rounded-md px-3 py-2 text-sm font-mono text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
          <p className="text-xs text-gray-500 mt-1">
            Default: pre-deployed MockRWA on {getChainName(dir.sourceChain.id)}
          </p>
        </div>

        <div className="border-t border-gray-800 pt-3">
          <p className="text-xs text-gray-400 mb-2">
            Or deploy a fresh MockRWA (ERC-20 mTBILL, 1M tokens):
          </p>
          <button
            onClick={handleDeployRwa}
            disabled={!isConnected || deployPending || deployConfirming}
            className="px-4 py-2 text-sm font-medium bg-gray-700 hover:bg-gray-600 disabled:bg-gray-800 disabled:text-gray-600 rounded-md transition-colors"
          >
            {deployPending
              ? "Confirm in wallet..."
              : deployConfirming
              ? "Deploying..."
              : !isConnected
              ? "Connect wallet first"
              : !isOnSourceChain
              ? `Switch to ${getChainName(dir.sourceChain.id)}`
              : "Deploy New MockRWA"}
          </button>
          {deployReceipt?.contractAddress && (
            <p className="text-xs text-green-400 mt-2">
              Deployed: <code className="bg-gray-800 px-1 rounded">{deployReceipt.contractAddress}</code>
            </p>
          )}
        </div>
      </div>

      {/* ── Step 2: Configure Attestation ── */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 space-y-4">
        <h3 className="text-sm font-semibold text-white">Step 2: Configure Attestation</h3>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-xs text-gray-400 mb-1">Locked Amount (tokens)</label>
            <input
              type="text"
              value={lockedAmount}
              onChange={(e) => setLockedAmount(e.target.value)}
              className="w-full bg-gray-800 border border-gray-700 rounded-md px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>
          <div>
            <label className="block text-xs text-gray-400 mb-1">Nonce</label>
            <input
              type="text"
              value={nonce}
              onChange={(e) => setNonce(e.target.value)}
              className="w-full bg-gray-800 border border-gray-700 rounded-md px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
            <p className="text-xs text-gray-500 mt-1">
              Must be unique per origin/target pair. Fuji-BNB nonce 1&amp;2 used.
            </p>
          </div>
        </div>

        <div className="bg-gray-800/50 rounded-md p-3 text-xs space-y-1">
          <div className="flex justify-between text-gray-400">
            <span>Source Chain</span>
            <span className="text-white">{getChainName(dir.sourceChain.id)} ({dir.sourceChain.id})</span>
          </div>
          <div className="flex justify-between text-gray-400">
            <span>Target Chain</span>
            <span className="text-white">{getChainName(dir.targetChain.id)} ({dir.targetChain.id})</span>
          </div>
          <div className="flex justify-between text-gray-400">
            <span>Target Factory</span>
            <span className="font-mono text-white">{dir.targetFactory.slice(0, 14)}...</span>
          </div>
          <div className="flex justify-between text-gray-400">
            <span>Target AttReg (EIP-712 domain)</span>
            <span className="font-mono text-white">{dir.targetAttReg.slice(0, 14)}...</span>
          </div>
        </div>
      </div>

      {/* ── Step 3: Sign with Demo Signers ── */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 space-y-4">
        <h3 className="text-sm font-semibold text-white">Step 3: Sign Attestation (3/5 Demo Signers)</h3>
        <p className="text-xs text-gray-400">
          Signs the EIP-712 typed data with 3 deterministic testnet signer keys.
          The signatures are verified on-chain by the target chain&apos;s AttestationRegistry.
        </p>

        <button
          onClick={handleSign}
          disabled={signing || !originAddress}
          className="w-full px-4 py-3 text-sm font-medium bg-purple-600 hover:bg-purple-700 disabled:bg-gray-700 disabled:text-gray-500 rounded-md transition-colors"
        >
          {signing ? "Signing with 3 demo keys..." : signatures ? "Re-sign Attestation" : "Sign Attestation"}
        </button>

        {signatures && (
          <div className="bg-green-500/10 border border-green-500/30 rounded-md p-3">
            <p className="text-green-400 text-sm font-medium">Attestation Signed</p>
            <p className="text-xs text-green-300/70 mt-1">
              3/5 signatures packed ({signatures.length / 2 - 1} bytes). Bitmap: {signerBitmap.toString()}.
            </p>
            <p className="text-xs font-mono text-green-300/50 mt-1 break-all">
              {signatures.slice(0, 40)}...{signatures.slice(-20)}
            </p>
          </div>
        )}
      </div>

      {/* ── Step 4: Deploy Mirror (Direct or CCIP) ── */}
      {signatures && (
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 space-y-4">
          <h3 className="text-sm font-semibold text-white">Step 4: Deploy Mirror</h3>

          {/* Method selector */}
          <div>
            <label className="block text-xs text-gray-400 mb-2">Deployment Method</label>
            <div className="flex gap-2">
              <button
                onClick={() => setDeployMethod("direct")}
                className={`flex-1 px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                  deployMethod === "direct"
                    ? "bg-green-600 text-white"
                    : "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                }`}
              >
                Direct (Instant)
              </button>
              <button
                onClick={() => setDeployMethod("ccip")}
                className={`flex-1 px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                  deployMethod === "ccip"
                    ? "bg-brand-600 text-white"
                    : "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                }`}
              >
                CCIP (~20 min)
              </button>
            </div>
          </div>

          {/* Method explanation */}
          <div className="bg-gray-800/50 rounded-md p-3 text-xs space-y-1">
            {deployMethod === "direct" ? (
              <>
                <p className="text-green-400 font-medium">Direct Deploy</p>
                <p className="text-gray-400">
                  Your wallet submits the attestation + signatures directly to{" "}
                  <code className="bg-gray-800 px-1 rounded">CanonicalFactory.deployMirrorDirect()</code> on the{" "}
                  <span className="text-white font-medium">target chain</span>.
                  Mirror deployed in ~5 seconds. Wallet must be on {getChainName(dir.targetChain.id)}.
                </p>
              </>
            ) : (
              <>
                <p className="text-brand-400 font-medium">CCIP Relay</p>
                <p className="text-gray-400">
                  Calls <code className="bg-gray-800 px-1 rounded">CCIPSender.sendAttestation()</code> on the{" "}
                  <span className="text-white font-medium">source chain</span>.
                  CCIP relays the message (~20-35 min). No target chain tx needed.
                  Wallet must be on {getChainName(dir.sourceChain.id)}.
                </p>
              </>
            )}
          </div>

          {/* Action button */}
          {deployMethod === "direct" ? (
            <button
              onClick={handleDirectDeploy}
              disabled={!isConnected || directPending || directConfirming}
              className="w-full px-4 py-3 text-sm font-medium bg-green-600 hover:bg-green-700 disabled:bg-gray-700 disabled:text-gray-500 rounded-md transition-colors"
            >
              {directPending
                ? "Confirm in wallet..."
                : directConfirming
                ? "Deploying mirror..."
                : !isConnected
                ? "Connect wallet first"
                : !isOnTargetChain
                ? `Switch to ${getChainName(dir.targetChain.id)}`
                : "Deploy Mirror Direct (Instant)"}
            </button>
          ) : (
            <button
              onClick={handleSendCCIP}
              disabled={!isConnected || ccipPending || ccipConfirming}
              className="w-full px-4 py-3 text-sm font-medium bg-brand-600 hover:bg-brand-700 disabled:bg-gray-700 disabled:text-gray-500 rounded-md transition-colors"
            >
              {ccipPending
                ? "Confirm in wallet..."
                : ccipConfirming
                ? "Waiting for confirmation..."
                : !isConnected
                ? "Connect wallet first"
                : !isOnSourceChain
                ? `Switch to ${getChainName(dir.sourceChain.id)}`
                : `Send via CCIP (${dir.sourceChain.id === avalancheFuji.id ? "~0.2 AVAX" : "~0.01 BNB"})`}
            </button>
          )}

          {/* Direct deploy TX feedback */}
          {directHash && (
            <div className="bg-green-500/10 border border-green-500/30 rounded-md p-3 text-sm">
              <p className="text-green-400 font-medium">Transaction sent!</p>
              <p className="text-xs font-mono text-green-300/70 mt-1 break-all">
                TX: {directHash}
              </p>
            </div>
          )}

          {/* CCIP TX feedback */}
          {ccipHash && (
            <div className="bg-blue-500/10 border border-blue-500/30 rounded-md p-3 text-sm">
              <p className="text-blue-400 font-medium">Transaction sent!</p>
              <p className="text-xs font-mono text-blue-300/70 mt-1 break-all">
                TX: {ccipHash}
              </p>
            </div>
          )}
        </div>
      )}

      {/* ── Direct Deploy Success ── */}
      {directMirrorAddr && (
        <div className="bg-green-500/10 border border-green-500/30 rounded-xl p-6 space-y-3">
          <h3 className="text-green-400 font-semibold">Mirror Deployed Instantly!</h3>
          <p className="text-sm text-green-300/70">
            Canonical mirror token deployed on {getChainName(dir.targetChain.id)}:
          </p>
          <p className="text-xs font-mono text-green-300 break-all bg-green-500/5 rounded-md p-2">
            {directMirrorAddr}
          </p>
          <div className="text-sm text-gray-300 space-y-1 mt-2">
            <p>The mirror is now live. You can:</p>
            <ul className="text-xs text-gray-400 space-y-1 ml-4 list-disc">
              <li>Go to the <a href="/verify" className="text-brand-400 underline">Verify</a> page to confirm canonical status</li>
              <li>Go to the <a href="/mirrors" className="text-brand-400 underline">Mirrors</a> page to see all deployed mirrors</li>
            </ul>
          </div>
        </div>
      )}

      {/* ── CCIP Tracking ── */}
      {ccipMsgId && (
        <div className="bg-yellow-500/10 border border-yellow-500/30 rounded-xl p-6 space-y-3">
          <h3 className="text-yellow-400 font-semibold">CCIP Message Sent!</h3>
          <p className="text-sm text-yellow-300/70">
            Message ID:
          </p>
          <p className="text-xs font-mono text-yellow-300/50 break-all">{ccipMsgId}</p>
          <a
            href={`https://ccip.chain.link/msg/${ccipMsgId}`}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-block px-4 py-2 text-sm bg-yellow-600 hover:bg-yellow-700 rounded-md text-white transition-colors"
          >
            Track on CCIP Explorer
          </a>
          <div className="text-sm text-gray-300 space-y-1 mt-2">
            <p>What happens next:</p>
            <ol className="list-decimal list-inside text-xs text-gray-400 space-y-1 ml-2">
              <li>CCIP routes the message (~20-35 min for testnet)</li>
              <li>CCIPReceiver on {getChainName(dir.targetChain.id)} receives it</li>
              <li>AttestationRegistry verifies the 3/5 signatures</li>
              <li>CanonicalFactory deploys an XythumToken mirror via CREATE2</li>
              <li>Go to the <a href="/verify" className="text-brand-400 underline">Verify</a> page to check!</li>
            </ol>
          </div>
        </div>
      )}

      {/* ── Error display ── */}
      {error && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-xl p-4">
          <p className="text-red-400 text-sm">{error}</p>
        </div>
      )}

      {/* ── How it works ── */}
      <div className="bg-gray-900/50 border border-gray-800 rounded-xl p-6">
        <h3 className="text-sm font-medium text-gray-400 mb-2">How It Works</h3>
        <ol className="text-sm text-gray-500 space-y-2 list-decimal list-inside">
          <li>Deploy or pick an ERC-20 RWA token on the source chain</li>
          <li>Build an attestation (origin, target, locked amount, nonce)</li>
          <li>Sign the attestation with the demo signer network (3/5 threshold, EIP-712)</li>
          <li>Choose deployment path:
            <ul className="ml-6 mt-1 space-y-1 list-disc text-xs">
              <li><span className="text-green-400">Direct</span>: Submit to target chain instantly (~5 sec)</li>
              <li><span className="text-brand-400">CCIP</span>: Relay via Chainlink CCIP (~20-35 min, automated)</li>
            </ul>
          </li>
          <li>Both paths verify the same threshold signatures on-chain</li>
          <li>CanonicalFactory deploys a canonical XythumToken mirror at a deterministic CREATE2 address</li>
        </ol>
      </div>
    </div>
  );
}
