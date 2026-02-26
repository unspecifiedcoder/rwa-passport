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
  }
> = {
  // ── Bidirectional: Fuji ↔ BNB Testnet ──
  avalancheFuji: {
    signerRegistry: "0xF17BBD22D1d3De885d02E01805C01C0e43E64A2F",
    attestationRegistry: "0xd0047E6F5281Ed7d04f2eAea216cB771b80f7104",
    canonicalFactory: "0x4934985287C28e647ecF38d485E448ac4A4A4Ab7",
    ccipSender: "0x1062C2fBebd13862d4D503430E3E1A81907c2bD7",
    ccipReceiver: "0xC740E9D56c126eb447f84404dDd9dffbB7AEd5F8",
    mockRwa: "0xD52b37AD931F221A902fC7F43A9ed2D87Ce07C5F",
    mirrorToken: "0x50Cef4543E676089F9C1D66851F1F6bAb269CEfC",
  },
  bscTestnet: {
    signerRegistry: "0xFA6aFAcfAA866Cf54aCCa0E23883a1597574206c",
    attestationRegistry: "0xe27E5e2D924F6e42ffa90C6bE817AA030dE6f48D",
    canonicalFactory: "0x99AB8C07C0082CBdD0306B30BC52eA15e6dB2521",
    ccipSender: "0x3823baE274eB188D3dF66D8bc4eAAaf0F050dAD6",
    ccipReceiver: "0xDc1f35F18607c8ee5a823b1ebBc5eDFe0fb253F3",
    mockRwa: "0x31004d16339C54f49FDb0dE061846268eE59B4af",
    mirrorToken: "0xD8885030b36DDDf303A8F6Eb3A78A5609432f209",
    mockGroth16Verifier: "0x93fb227eD3087f6E4506e2fDCec2aC528b9a430d",
    collateralVerifier: "0x8590e66Fd2110455995E80042399e77751e01291",
    aaveAdapter: "0x6b8a2a79794251c6E9e23E36142277210EF6A717",
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
