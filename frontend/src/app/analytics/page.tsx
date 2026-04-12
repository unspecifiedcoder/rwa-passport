"use client";

import { StatCard } from "@/components/StatCard";

const PROTOCOL_METRICS = [
  { label: "Total Value Locked", value: "$2.4B", change: "+12.3%", positive: true },
  { label: "24h Volume", value: "$89.2M", change: "+5.7%", positive: true },
  { label: "Total Mirrors Deployed", value: "1,247", change: "+23", positive: true },
  { label: "Active Chains", value: "6", change: "+1", positive: true },
  { label: "Unique Holders", value: "42,891", change: "+1,203", positive: true },
  { label: "Protocol Revenue (30d)", value: "$4.2M", change: "+18.5%", positive: true },
];

const CHAIN_TVL = [
  { chain: "Ethereum", tvl: "$1.2B", share: "50%", color: "bg-blue-500", mirrors: 312 },
  { chain: "Arbitrum", tvl: "$480M", share: "20%", color: "bg-cyan-500", mirrors: 289 },
  { chain: "BNB Chain", tvl: "$360M", share: "15%", color: "bg-yellow-500", mirrors: 256 },
  { chain: "Avalanche", tvl: "$192M", share: "8%", color: "bg-red-500", mirrors: 198 },
  { chain: "Base", tvl: "$120M", share: "5%", color: "bg-blue-400", mirrors: 112 },
  { chain: "Monad", tvl: "$48M", share: "2%", color: "bg-violet-500", mirrors: 80 },
];

const TOP_MIRRORS = [
  { name: "xTBILL", origin: "US Treasury Bill Token", tvl: "$420M", apy: "5.2%", chains: 6 },
  { name: "xGOLD", origin: "Tokenized Gold (PAXG)", tvl: "$310M", apy: "0.5%", chains: 4 },
  { name: "xREIT", origin: "Real Estate Index Token", tvl: "$185M", apy: "7.8%", chains: 5 },
  { name: "xBOND", origin: "Corporate Bond Token", tvl: "$142M", apy: "4.1%", chains: 3 },
  { name: "xAGRI", origin: "Agricultural Commodity", tvl: "$98M", apy: "3.2%", chains: 3 },
];

const FEE_REVENUE = [
  { period: "Today", collected: "$142K", distributed: "$128K" },
  { period: "This Week", collected: "$980K", distributed: "$882K" },
  { period: "This Month", collected: "$4.2M", distributed: "$3.78M" },
  { period: "All Time", collected: "$28.5M", distributed: "$25.65M" },
];

export default function AnalyticsPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold mb-2">Protocol Analytics</h1>
        <p className="text-gray-400">
          Real-time metrics, TVL breakdown, and revenue analytics for the
          Xythum RWA Passport protocol.
        </p>
      </div>

      {/* Key Metrics */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {PROTOCOL_METRICS.map((metric) => (
          <div
            key={metric.label}
            className="bg-gray-900 border border-gray-800 rounded-xl p-5"
          >
            <p className="text-sm text-gray-400">{metric.label}</p>
            <div className="flex items-end justify-between mt-2">
              <p className="text-2xl font-bold text-white">{metric.value}</p>
              <span
                className={`text-sm font-medium ${
                  metric.positive ? "text-green-400" : "text-red-400"
                }`}
              >
                {metric.change}
              </span>
            </div>
          </div>
        ))}
      </div>

      {/* TVL by Chain */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
        <h3 className="text-lg font-semibold mb-4">TVL by Chain</h3>
        <div className="space-y-3">
          {CHAIN_TVL.map((chain) => (
            <div key={chain.chain} className="flex items-center gap-4">
              <div className="w-24 text-sm text-gray-300">{chain.chain}</div>
              <div className="flex-1">
                <div className="w-full h-6 bg-gray-800 rounded-full overflow-hidden">
                  <div
                    className={`h-full ${chain.color} rounded-full flex items-center justify-end pr-2`}
                    style={{ width: chain.share }}
                  >
                    <span className="text-xs font-medium text-white">
                      {chain.share}
                    </span>
                  </div>
                </div>
              </div>
              <div className="w-24 text-right text-sm text-white font-medium">
                {chain.tvl}
              </div>
              <div className="w-20 text-right text-xs text-gray-400">
                {chain.mirrors} mirrors
              </div>
            </div>
          ))}
        </div>
        <div className="mt-4 pt-4 border-t border-gray-800 flex justify-between text-sm">
          <span className="text-gray-400">Total TVL</span>
          <span className="text-white font-bold">$2.4B</span>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Top Mirrors */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 className="text-lg font-semibold mb-4">Top Mirror Tokens</h3>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-gray-400 border-b border-gray-800">
                  <th className="text-left pb-3 font-medium">Token</th>
                  <th className="text-right pb-3 font-medium">TVL</th>
                  <th className="text-right pb-3 font-medium">APY</th>
                  <th className="text-right pb-3 font-medium">Chains</th>
                </tr>
              </thead>
              <tbody>
                {TOP_MIRRORS.map((mirror) => (
                  <tr
                    key={mirror.name}
                    className="border-b border-gray-800/50 hover:bg-gray-800/30"
                  >
                    <td className="py-3">
                      <div>
                        <span className="text-white font-medium">
                          {mirror.name}
                        </span>
                        <p className="text-xs text-gray-500">{mirror.origin}</p>
                      </div>
                    </td>
                    <td className="text-right text-white">{mirror.tvl}</td>
                    <td className="text-right text-green-400">{mirror.apy}</td>
                    <td className="text-right text-gray-300">{mirror.chains}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Fee Revenue */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 className="text-lg font-semibold mb-4">Protocol Revenue</h3>
          <div className="space-y-3">
            {FEE_REVENUE.map((period) => (
              <div
                key={period.period}
                className="flex items-center justify-between p-3 bg-gray-800 rounded-lg"
              >
                <span className="text-sm text-gray-300">{period.period}</span>
                <div className="text-right">
                  <p className="text-sm text-white font-medium">
                    {period.collected}
                  </p>
                  <p className="text-xs text-gray-500">
                    {period.distributed} distributed
                  </p>
                </div>
              </div>
            ))}
          </div>

          {/* Fee Split Visualization */}
          <div className="mt-4 pt-4 border-t border-gray-800">
            <h4 className="text-sm text-gray-400 mb-3">
              Fee Distribution Split
            </h4>
            <div className="flex h-4 rounded-full overflow-hidden">
              <div className="bg-blue-500 w-[40%]" title="Treasury 40%" />
              <div className="bg-purple-500 w-[30%]" title="Staking 30%" />
              <div className="bg-yellow-500 w-[20%]" title="Insurance 20%" />
              <div className="bg-red-500 w-[10%]" title="Burn 10%" />
            </div>
            <div className="flex justify-between mt-2 text-xs text-gray-400">
              <span className="flex items-center gap-1">
                <span className="w-2 h-2 bg-blue-500 rounded-full" /> Treasury
                40%
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2 h-2 bg-purple-500 rounded-full" /> Staking
                30%
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2 h-2 bg-yellow-500 rounded-full" />{" "}
                Insurance 20%
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2 h-2 bg-red-500 rounded-full" /> Burn 10%
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Protocol Security Status */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
        <h3 className="text-lg font-semibold mb-4">Security Status</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="flex items-center gap-3 p-3 bg-gray-800 rounded-lg">
            <div className="w-3 h-3 rounded-full bg-green-400 animate-pulse" />
            <div>
              <p className="text-sm text-white">Emergency Status</p>
              <p className="text-xs text-green-400">All Clear</p>
            </div>
          </div>
          <div className="flex items-center gap-3 p-3 bg-gray-800 rounded-lg">
            <div className="w-3 h-3 rounded-full bg-green-400" />
            <div>
              <p className="text-sm text-white">Circuit Breakers</p>
              <p className="text-xs text-green-400">0/5 Tripped</p>
            </div>
          </div>
          <div className="flex items-center gap-3 p-3 bg-gray-800 rounded-lg">
            <div className="w-3 h-3 rounded-full bg-green-400" />
            <div>
              <p className="text-sm text-white">Oracle Health</p>
              <p className="text-xs text-green-400">All Feeds Fresh</p>
            </div>
          </div>
          <div className="flex items-center gap-3 p-3 bg-gray-800 rounded-lg">
            <div className="w-3 h-3 rounded-full bg-green-400" />
            <div>
              <p className="text-sm text-white">Signer Network</p>
              <p className="text-xs text-green-400">5/5 Active (3/5 threshold)</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
