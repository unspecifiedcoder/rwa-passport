"use client";

import { truncateAddress } from "@/lib/utils";
import { ChainBadge } from "./ChainBadge";

export interface MirrorEntry {
  address: string;
  originContract: string;
  originChainId: number;
  targetChainId: number;
  symbol: string;
  status: "active" | "paused";
}

interface MirrorTableProps {
  mirrors: MirrorEntry[];
}

export function MirrorTable({ mirrors }: MirrorTableProps) {
  if (mirrors.length === 0) {
    return (
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-8 text-center text-gray-500">
        No mirrors deployed yet. Deploy contracts to testnet to see data.
      </div>
    );
  }

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
      <table className="w-full">
        <thead>
          <tr className="border-b border-gray-800">
            <th className="text-left text-xs font-medium text-gray-400 px-4 py-3">
              Symbol
            </th>
            <th className="text-left text-xs font-medium text-gray-400 px-4 py-3">
              Origin Chain
            </th>
            <th className="text-left text-xs font-medium text-gray-400 px-4 py-3">
              Target Chain
            </th>
            <th className="text-left text-xs font-medium text-gray-400 px-4 py-3">
              Status
            </th>
            <th className="text-left text-xs font-medium text-gray-400 px-4 py-3">
              Address
            </th>
          </tr>
        </thead>
        <tbody>
          {mirrors.map((mirror) => (
            <tr
              key={mirror.address}
              className="border-b border-gray-800/50 hover:bg-gray-800/30 transition-colors"
            >
              <td className="px-4 py-3 font-mono text-sm font-medium text-white">
                {mirror.symbol}
              </td>
              <td className="px-4 py-3">
                <ChainBadge chainId={mirror.originChainId} />
              </td>
              <td className="px-4 py-3">
                <ChainBadge chainId={mirror.targetChainId} />
              </td>
              <td className="px-4 py-3">
                <span
                  className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                    mirror.status === "active"
                      ? "bg-green-500/20 text-green-400"
                      : "bg-yellow-500/20 text-yellow-400"
                  }`}
                >
                  {mirror.status === "active" ? "Active" : "Paused"}
                </span>
              </td>
              <td className="px-4 py-3">
                <button
                  onClick={() => navigator.clipboard.writeText(mirror.address)}
                  className="font-mono text-sm text-gray-400 hover:text-white transition-colors cursor-pointer"
                  title="Click to copy"
                >
                  {truncateAddress(mirror.address)}
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
