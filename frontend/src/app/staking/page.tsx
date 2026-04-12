"use client";

import { useState } from "react";
import { StatCard } from "@/components/StatCard";

const LOCK_OPTIONS = [
  { label: "Flexible", duration: 0, multiplier: "1.0x", apy: "8%" },
  { label: "30 Days", duration: 30, multiplier: "1.5x", apy: "12%" },
  { label: "90 Days", duration: 90, multiplier: "2.0x", apy: "16%" },
  { label: "180 Days", duration: 180, multiplier: "2.5x", apy: "20%" },
  { label: "365 Days", duration: 365, multiplier: "3.0x", apy: "24%" },
];

export default function StakingPage() {
  const [stakeAmount, setStakeAmount] = useState("");
  const [selectedLock, setSelectedLock] = useState(0);
  const [activeTab, setActiveTab] = useState<"stake" | "unstake">("stake");

  const selectedOption = LOCK_OPTIONS[selectedLock];

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold mb-2">XYT Staking</h1>
        <p className="text-gray-400">
          Stake XYT tokens to earn protocol rewards, secure the network, and
          participate in governance with boosted voting power.
        </p>
      </div>

      {/* Staking Stats */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
        <StatCard
          title="Total Staked"
          value="45.2M XYT"
          subtitle="$135.6M TVL"
          color="text-blue-400"
        />
        <StatCard
          title="Your Staked"
          value="0 XYT"
          subtitle="Connect wallet to view"
          color="text-purple-400"
        />
        <StatCard
          title="Pending Rewards"
          value="0 XYT"
          subtitle="Claimable now"
          color="text-green-400"
        />
        <StatCard
          title="Base APY"
          value="8-24%"
          subtitle="Based on lock duration"
          color="text-yellow-400"
        />
        <StatCard
          title="Total Slashed"
          value="0 XYT"
          subtitle="Insurance fund protected"
          color="text-red-400"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Stake/Unstake Panel */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          {/* Tab switcher */}
          <div className="flex gap-1 mb-6 bg-gray-800 rounded-lg p-1">
            <button
              onClick={() => setActiveTab("stake")}
              className={`flex-1 py-2 rounded-md text-sm font-medium transition-colors ${
                activeTab === "stake"
                  ? "bg-blue-600 text-white"
                  : "text-gray-400 hover:text-white"
              }`}
            >
              Stake
            </button>
            <button
              onClick={() => setActiveTab("unstake")}
              className={`flex-1 py-2 rounded-md text-sm font-medium transition-colors ${
                activeTab === "unstake"
                  ? "bg-blue-600 text-white"
                  : "text-gray-400 hover:text-white"
              }`}
            >
              Unstake
            </button>
          </div>

          {activeTab === "stake" ? (
            <>
              {/* Amount input */}
              <div className="mb-4">
                <label className="text-sm text-gray-400 mb-2 block">
                  Stake Amount
                </label>
                <div className="relative">
                  <input
                    type="number"
                    placeholder="0.00"
                    value={stakeAmount}
                    onChange={(e) => setStakeAmount(e.target.value)}
                    className="w-full bg-gray-800 border border-gray-700 rounded-lg px-4 py-3 text-lg text-white placeholder-gray-500 focus:outline-none focus:border-blue-500"
                  />
                  <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-2">
                    <span className="text-sm text-gray-400">XYT</span>
                    <button className="text-xs text-blue-400 hover:text-blue-300">
                      MAX
                    </button>
                  </div>
                </div>
                <p className="text-xs text-gray-500 mt-1">Balance: 0 XYT</p>
              </div>

              {/* Lock Duration Selector */}
              <div className="mb-6">
                <label className="text-sm text-gray-400 mb-2 block">
                  Lock Duration
                </label>
                <div className="grid grid-cols-5 gap-2">
                  {LOCK_OPTIONS.map((option, i) => (
                    <button
                      key={i}
                      onClick={() => setSelectedLock(i)}
                      className={`p-3 rounded-lg border text-center transition-colors ${
                        selectedLock === i
                          ? "border-blue-500 bg-blue-500/10 text-blue-400"
                          : "border-gray-700 bg-gray-800 text-gray-400 hover:border-gray-600"
                      }`}
                    >
                      <div className="text-xs font-medium">{option.label}</div>
                      <div className="text-lg font-bold mt-1">
                        {option.multiplier}
                      </div>
                      <div className="text-xs text-green-400 mt-1">
                        {option.apy}
                      </div>
                    </button>
                  ))}
                </div>
              </div>

              {/* Summary */}
              <div className="bg-gray-800 rounded-lg p-4 mb-4 space-y-2">
                <div className="flex justify-between text-sm">
                  <span className="text-gray-400">Lock Duration</span>
                  <span className="text-white">{selectedOption.label}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-400">Reward Multiplier</span>
                  <span className="text-blue-400">
                    {selectedOption.multiplier}
                  </span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-400">Estimated APY</span>
                  <span className="text-green-400">{selectedOption.apy}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-400">Weighted Stake</span>
                  <span className="text-white">
                    {stakeAmount
                      ? `${(parseFloat(stakeAmount || "0") * parseFloat(selectedOption.multiplier)).toFixed(2)} XYT`
                      : "0 XYT"}
                  </span>
                </div>
              </div>

              <button className="w-full py-3 bg-blue-600 hover:bg-blue-500 rounded-lg font-medium transition-colors">
                Stake XYT
              </button>
            </>
          ) : (
            <>
              <div className="text-center py-12 text-gray-500">
                <p className="text-lg mb-2">No active stakes</p>
                <p className="text-sm">
                  Connect your wallet and stake XYT to see your positions here.
                </p>
              </div>
            </>
          )}
        </div>

        {/* Rewards & Info Panel */}
        <div className="space-y-6">
          {/* Claim Rewards */}
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
            <h3 className="text-lg font-semibold mb-4">Rewards</h3>
            <div className="flex items-center justify-between mb-4">
              <div>
                <p className="text-2xl font-bold text-green-400">0.00 XYT</p>
                <p className="text-sm text-gray-400">Pending rewards</p>
              </div>
              <button className="px-6 py-2 bg-green-600 hover:bg-green-500 rounded-lg text-sm font-medium transition-colors">
                Claim Rewards
              </button>
            </div>
            <div className="border-t border-gray-800 pt-4 space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Total Earned (Lifetime)</span>
                <span className="text-white">0 XYT</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Reward Rate</span>
                <span className="text-white">0 XYT/day</span>
              </div>
            </div>
          </div>

          {/* Emergency Unstake */}
          <div className="bg-gray-900 border border-red-900/30 rounded-xl p-6">
            <h3 className="text-lg font-semibold mb-2 text-red-400">
              Emergency Unstake
            </h3>
            <p className="text-sm text-gray-400 mb-4">
              Withdraw staked XYT before the lock expires. A{" "}
              <span className="text-red-400 font-bold">10% penalty</span> is
              applied and sent to the insurance fund.
            </p>
            <button className="w-full py-2 bg-red-600/20 text-red-400 hover:bg-red-600/30 border border-red-900/50 rounded-lg text-sm font-medium transition-colors">
              Emergency Unstake (10% Penalty)
            </button>
          </div>

          {/* Staking Tiers Info */}
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
            <h3 className="text-sm font-medium text-gray-400 mb-3">
              Staking Multiplier Tiers
            </h3>
            <div className="space-y-2">
              {LOCK_OPTIONS.map((option, i) => (
                <div
                  key={i}
                  className="flex items-center justify-between text-sm"
                >
                  <div className="flex items-center gap-2">
                    <div
                      className={`w-2 h-2 rounded-full ${
                        i === 0
                          ? "bg-gray-400"
                          : i === 1
                            ? "bg-blue-400"
                            : i === 2
                              ? "bg-purple-400"
                              : i === 3
                                ? "bg-yellow-400"
                                : "bg-green-400"
                      }`}
                    />
                    <span className="text-gray-300">{option.label}</span>
                  </div>
                  <div className="flex gap-4">
                    <span className="text-blue-400">{option.multiplier}</span>
                    <span className="text-green-400 w-12 text-right">
                      {option.apy}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
