import { CanonicalVerifier } from "@/components/CanonicalVerifier";

export default function VerifyPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold mb-2">Canonical Verification</h1>
        <p className="text-gray-400 text-sm">
          Verify that a token address is an official Xythum canonical mirror.
        </p>
      </div>

      <CanonicalVerifier />

      <div className="bg-gray-900/50 border border-gray-800 rounded-xl p-6 max-w-xl">
        <h3 className="text-sm font-medium text-gray-400 mb-2">
          For Integrators
        </h3>
        <p className="text-sm text-gray-500 mb-3">
          You can verify canonical status on-chain by calling:
        </p>
        <pre className="bg-gray-800 rounded-md p-3 text-xs font-mono text-gray-300 overflow-x-auto">
{`// Solidity
bool canonical = ICanonicalFactory(factory).isCanonical(tokenAddress);

// TypeScript (viem)
const result = await publicClient.readContract({
  address: factoryAddress,
  abi: canonicalFactoryAbi,
  functionName: 'isCanonical',
  args: [tokenAddress],
});`}
        </pre>
      </div>
    </div>
  );
}
