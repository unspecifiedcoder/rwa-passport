"use client";

interface SignerHealthProps {
  activeSigners: number;
  totalSigners: number;
  threshold: number;
}

export function SignerHealth({
  activeSigners,
  totalSigners,
  threshold,
}: SignerHealthProps) {
  const healthPercent = totalSigners > 0 ? (activeSigners / totalSigners) * 100 : 0;
  const isHealthy = activeSigners >= threshold;

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-gray-400">Signer Health</h3>
        <span
          className={`text-xs font-medium px-2 py-0.5 rounded-full ${
            isHealthy
              ? "bg-green-500/20 text-green-400"
              : "bg-red-500/20 text-red-400"
          }`}
        >
          {isHealthy ? "Healthy" : "Degraded"}
        </span>
      </div>
      <p className="text-2xl font-bold text-white mb-1">
        {activeSigners}/{totalSigners}
      </p>
      <p className="text-xs text-gray-500 mb-3">
        Threshold: {threshold} signatures required
      </p>
      <div className="w-full bg-gray-800 rounded-full h-2">
        <div
          className={`h-2 rounded-full transition-all ${
            isHealthy ? "bg-green-500" : "bg-red-500"
          }`}
          style={{ width: `${healthPercent}%` }}
        />
      </div>
    </div>
  );
}
