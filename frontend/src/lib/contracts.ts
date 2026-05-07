// ABI fragments for the Xythum protocol contracts
// Full ABIs are in xythum-rwa/out/ after forge build

// Attestation tuple type (reused across multiple ABIs)
const ATTESTATION_TUPLE = {
  name: "att",
  type: "tuple" as const,
  components: [
    { name: "originContract", type: "address" as const },
    { name: "originChainId", type: "uint256" as const },
    { name: "targetChainId", type: "uint256" as const },
    { name: "navRoot", type: "bytes32" as const },
    { name: "complianceRoot", type: "bytes32" as const },
    { name: "lockedAmount", type: "uint256" as const },
    { name: "timestamp", type: "uint256" as const },
    { name: "nonce", type: "uint256" as const },
  ],
} as const;

export const CANONICAL_FACTORY_ABI = [
  {
    type: "function",
    name: "isCanonical",
    inputs: [{ name: "mirror", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "computeMirrorAddress",
    inputs: [ATTESTATION_TUPLE],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "deployMirrorDirect",
    inputs: [
      ATTESTATION_TUPLE,
      { name: "signatures", type: "bytes" },
      { name: "signerBitmap", type: "uint256" },
    ],
    outputs: [{ name: "mirror", type: "address" }],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "getMirrorCount",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getAllMirrors",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getMirrors",
    inputs: [
      { name: "offset", type: "uint256" },
      { name: "limit", type: "uint256" },
    ],
    outputs: [{ name: "result", type: "address[]" }],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "MirrorDeployed",
    inputs: [
      { name: "mirror", type: "address", indexed: true },
      { name: "originContract", type: "address", indexed: true },
      { name: "originChainId", type: "uint256", indexed: false },
      { name: "targetChainId", type: "uint256", indexed: false },
      { name: "salt", type: "bytes32", indexed: false },
    ],
  },
] as const;

export const SIGNER_REGISTRY_ABI = [
  {
    type: "function",
    name: "getSignerCount",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "threshold",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getSignerSet",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
    stateMutability: "view",
  },
] as const;

export const ATTESTATION_REGISTRY_ABI = [
  {
    type: "event",
    name: "AttestationVerified",
    inputs: [
      { name: "pairKey", type: "bytes32", indexed: true },
      { name: "originContract", type: "address", indexed: true },
      { name: "originChainId", type: "uint256", indexed: false },
      { name: "targetChainId", type: "uint256", indexed: false },
      { name: "nonce", type: "uint256", indexed: false },
    ],
  },
] as const;

export const XYTHUM_TOKEN_ABI = [
  {
    type: "function",
    name: "name",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "symbol",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "originContract",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "originChainId",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "totalSupply",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
] as const;

export const CCIP_SENDER_ABI = [
  {
    type: "function",
    name: "sendAttestation",
    inputs: [
      { name: "destinationChainSelector", type: "uint64" },
      {
        name: "att",
        type: "tuple",
        components: [
          { name: "originContract", type: "address" },
          { name: "originChainId", type: "uint256" },
          { name: "targetChainId", type: "uint256" },
          { name: "navRoot", type: "bytes32" },
          { name: "complianceRoot", type: "bytes32" },
          { name: "lockedAmount", type: "uint256" },
          { name: "timestamp", type: "uint256" },
          { name: "nonce", type: "uint256" },
        ],
      },
      { name: "signatures", type: "bytes" },
      { name: "signerBitmap", type: "uint256" },
    ],
    outputs: [{ name: "messageId", type: "bytes32" }],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "estimateFee",
    inputs: [
      { name: "destinationChainSelector", type: "uint64" },
      { name: "payload", type: "bytes" },
    ],
    outputs: [{ name: "fee", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "supportedChains",
    inputs: [{ name: "", type: "uint64" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "allowedReceivers",
    inputs: [{ name: "", type: "uint64" }],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "AttestationSent",
    inputs: [
      { name: "messageId", type: "bytes32", indexed: false },
      { name: "destinationChainSelector", type: "uint64", indexed: false },
      { name: "originContract", type: "address", indexed: false },
      { name: "nonce", type: "uint256", indexed: false },
    ],
  },
] as const;

// CCIP chain selectors
export const CCIP_CHAIN_SELECTORS = {
  avalancheFuji: "14767482510784806043" as const,
  bscTestnet: "13264668187771770619" as const,
} as const;

// Deployed contract addresses (update after deployment)
export const CONTRACTS: Record<
  string,
  {
    signerRegistry: `0x${string}`;
    attestationRegistry: `0x${string}`;
    canonicalFactory: `0x${string}`;
    ccipSender?: `0x${string}`;
    ccipReceiver?: `0x${string}`;
    mockRwa?: `0x${string}`;
    mockGroth16Verifier?: `0x${string}`;
    collateralVerifier?: `0x${string}`;
    aaveAdapter?: `0x${string}`;
    mirrorToken?: `0x${string}`;
    lockEscrow?: `0x${string}`;
    xythumLend?: `0x${string}`;
    mockUsdc?: `0x${string}`;
  }
> = {
  // ── Bidirectional: Fuji ↔ BNB Testnet ──
  avalancheFuji: {
    signerRegistry: "0xF17BBD22D1d3De885d02E01805C01C0e43E64A2F",
    attestationRegistry: "0xd0047E6F5281Ed7d04f2eAea216cB771b80f7104",
    canonicalFactory: "0x0BA5bd535Ee071993643Cbb815368F55648B9365",
    ccipSender: "0x1062C2fBebd13862d4D503430E3E1A81907c2bD7",
    ccipReceiver: "0xC740E9D56c126eb447f84404dDd9dffbB7AEd5F8",
    mockRwa: "0xD52b37AD931F221A902fC7F43A9ed2D87Ce07C5F",
    mirrorToken: "0x64D3c71cB8910553A55C143eC8d0f5900b70cFb5",
    lockEscrow: "0x557474BEd7701ee5290CeB232DDa1Fa06799aA5F",
    xythumLend: "0xA1488D1063930947344305D851Ef90dF98944260",
    mockUsdc: "0x3BeF60e85DA825AEe0449a8438FA8d943A07c848",
  },
  bscTestnet: {
    signerRegistry: "0xFA6aFAcfAA866Cf54aCCa0E23883a1597574206c",
    attestationRegistry: "0xe27E5e2D924F6e42ffa90C6bE817AA030dE6f48D",
    canonicalFactory: "0x4d0a5A6bf63a25bd6577Bdcda0f48e19843CacBC",
    lockEscrow: "0x6BbD75e43Bb3515c54BeCAF6B17B69458A8201A3",
    ccipSender: "0x3823baE274eB188D3dF66D8bc4eAAaf0F050dAD6",
    ccipReceiver: "0xDc1f35F18607c8ee5a823b1ebBc5eDFe0fb253F3",
    mockRwa: "0x31004d16339C54f49FDb0dE061846268eE59B4af",
    mirrorToken: "0xD8885030b36DDDf303A8F6Eb3A78A5609432f209",
    mockGroth16Verifier: "0x93fb227eD3087f6E4506e2fDCec2aC528b9a430d",
    collateralVerifier: "0x8590e66Fd2110455995E80042399e77751e01291",
    aaveAdapter: "0x6b8a2a79794251c6E9e23E36142277210EF6A717",
  },
  // ── Monad Testnet (direct deploy only, no CCIP) ──
  monadTestnet: {
    signerRegistry: "0x725cCe0916d2E8682438732fD9e79803B4fAB2BD",
    attestationRegistry: "0xe27E5e2D924F6e42ffa90C6bE817AA030dE6f48D",
    canonicalFactory: "0x27b678acD971f851Ce19751482371eC76b929B41",
    mockRwa: "0x430172985b21458d73576435D4aD4bEeA85F376C",
    mirrorToken: "0x4f01a5d71a6B83D0B74ff7262D6114bc6E933EE3",
    lockEscrow: "0xCe1D8aF9ae9039A12A157D6ec53eC87F906773C4",
  },
  // ── Sepolia chains (placeholder, not deployed yet) ──
  sepolia: {
    signerRegistry: "0x0000000000000000000000000000000000000000",
    attestationRegistry: "0x0000000000000000000000000000000000000000",
    canonicalFactory: "0x0000000000000000000000000000000000000000",
  },
  arbitrumSepolia: {
    signerRegistry: "0x0000000000000000000000000000000000000000",
    attestationRegistry: "0x0000000000000000000000000000000000000000",
    canonicalFactory: "0x0000000000000000000000000000000000000000",
  },
  baseSepolia: {
    signerRegistry: "0x0000000000000000000000000000000000000000",
    attestationRegistry: "0x0000000000000000000000000000000000000000",
    canonicalFactory: "0x0000000000000000000000000000000000000000",
  },
};

// ─── ERC-20 minimal ABIs (approve / balance / allowance) ────────────
export const ERC20_APPROVE_ABI = [
  {
    type: "function",
    name: "approve",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "allowance",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
] as const;

export const ERC20_BALANCE_ABI = ERC20_APPROVE_ABI;

// ─── RWALockEscrow ABI (lock-mint-burn-unlock round-trip) ───────────
export const RWA_LOCK_ESCROW_ABI = [
  {
    type: "function",
    name: "lock",
    stateMutability: "nonpayable",
    inputs: [
      { name: "rwaToken", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "targetChainId", type: "uint256" },
    ],
    outputs: [{ name: "lockId", type: "bytes32" }],
  },
  {
    type: "function",
    name: "release",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "receipt",
        type: "tuple",
        components: [
          { name: "originContract", type: "address" },
          { name: "originChainId", type: "uint256" },
          { name: "targetChainId", type: "uint256" },
          { name: "recipient", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "lockId", type: "bytes32" },
          { name: "burnTxBlock", type: "uint256" },
          { name: "timestamp", type: "uint256" },
        ],
      },
      { name: "signatures", type: "bytes" },
      { name: "signerBitmap", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "lockState",
    stateMutability: "view",
    inputs: [{ name: "lockId", type: "bytes32" }],
    outputs: [
      { name: "rwaToken", type: "address" },
      { name: "locker", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "lockedAt", type: "uint256" },
      { name: "released", type: "bool" },
    ],
  },
  {
    type: "function",
    name: "totalLocked",
    stateMutability: "view",
    inputs: [{ name: "rwaToken", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "event",
    name: "Locked",
    inputs: [
      { name: "lockId", type: "bytes32", indexed: true },
      { name: "locker", type: "address", indexed: true },
      { name: "rwaToken", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "targetChainId", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Released",
    inputs: [
      { name: "lockId", type: "bytes32", indexed: true },
      { name: "recipient", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;

// ─── CanonicalFactory.mintFromLock ABI ──────────────────────────────
export const CANONICAL_FACTORY_MINT_FROM_LOCK_ABI = [
  {
    type: "function",
    name: "mintFromLock",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "receipt",
        type: "tuple",
        components: [
          { name: "originContract", type: "address" },
          { name: "originChainId", type: "uint256" },
          { name: "targetChainId", type: "uint256" },
          { name: "locker", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "lockId", type: "bytes32" },
          { name: "timestamp", type: "uint256" },
        ],
      },
      { name: "signatures", type: "bytes" },
      { name: "signerBitmap", type: "uint256" },
    ],
    outputs: [{ name: "mirror", type: "address" }],
  },
  {
    type: "function",
    name: "mintedFromLock",
    stateMutability: "view",
    inputs: [{ name: "lockId", type: "bytes32" }],
    outputs: [{ type: "bool" }],
  },
  {
    type: "event",
    name: "MintedFromLock",
    inputs: [
      { name: "lockId", type: "bytes32", indexed: true },
      { name: "mirror", type: "address", indexed: true },
      { name: "locker", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;

// ─── XythumToken.burnForLock ABI ────────────────────────────────────
export const XYTHUM_TOKEN_BURN_FOR_LOCK_ABI = [
  {
    type: "function",
    name: "burnForLock",
    stateMutability: "nonpayable",
    inputs: [
      { name: "amount", type: "uint256" },
      { name: "lockId", type: "bytes32" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "burnedForLock",
    stateMutability: "view",
    inputs: [{ name: "lockId", type: "bytes32" }],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "BurnedForLock",
    inputs: [
      { name: "lockId", type: "bytes32", indexed: true },
      { name: "burner", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;

// ─── MockUSDC ABI (faucet + standard ERC-20 ops) ─────────────────────
export const MOCK_USDC_ABI = [
  ...ERC20_APPROVE_ABI,
  {
    type: "function",
    name: "faucet",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
] as const;

// ─── XythumLend ABI (single-pair demo lending market) ───────────────
export const XYTHUM_LEND_ABI = [
  {
    type: "function",
    name: "supply",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "withdraw",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "borrow",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "repay",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "positionOf",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      { name: "collateral", type: "uint256" },
      { name: "debt", type: "uint256" },
      { name: "healthBps", type: "uint256" },
    ],
  },
  {
    type: "function",
    name: "maxBorrow",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "maxWithdraw",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "reservesBalance",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
] as const;
