"use client";

import { useAccount } from "wagmi";
import { StatCard } from "@/components/StatCard";

const MOCK_POSITIONS = [
  {
    token: "XYT",
    type: "Governance Token",
    balance: "250,000",
    value: "$750,000",
    change: "+4.2%",
  },
  {
    token: "xTBILL",
    type: "Mirror Token (US Treasury)",
    balance: "1,000,000",
    value: "$1,005,000",
    change: "+0.5%",
  },
  {
    token: "xVault-TBILL",
    type: "Yield Vault Shares",
    balance: "500,000",
    value: "$525,000",
    change: "+5.0%",
  },
  {
    token: "xGOLD",
    type: "Mirror Token (Gold)",
    balance: "100",
    value: "$230,000",
    change: "+1.8%",
  },
];

const MOCK_STAKING = {
  stakedAmount: "200,000 XYT",
  stakedValue: "$600,000",
  lockDuration: "365 Days",
  multiplier: "3.0x",
  weightedStake: "600,000 XYT",
  unlockDate: "Apr 7, 2027",
  pendingRewards: "12,450 XYT",
  rewardsValue: "$37,350",
};

const MOCK_VESTING = {
  totalGrant: "1,000,000 XYT",
  vested: "370,000 XYT",
  released: "250,000 XYT",
  claimable: "120,000 XYT",
  cliffDate: "Oct 7, 2026",
  fullVestDate: "Apr 7, 2028",
};

const MOCK_HISTORY = [
  { action: "Staked", amount: "200,000 XYT", date: "Apr 7, 2026", tx: "0x1a2b...3c4d" },
  { action: "Claimed Rewards", amount: "5,200 XYT", date: "Apr 1, 2026", tx: "0x5e6f...7g8h" },
  { action: "Deposited to Vault", amount: "500,000 xTBILL", date: "Mar 28, 2026", tx: "0x9i0j...1k2l" },
  { action: "Received Mirror", amount: "1,000,000 xTBILL", date: "Mar 25, 2026", tx: "0x3m4n...5o6p" },
  { action: "Vesting Release", amount: "120,000 XYT", date: "Mar 15, 2026", tx: "0x7q8r...9s0t" },
];

export default function PortfolioPage() {
  const { address, isConnected } = useAccount();

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold mb-2">Portfolio</h1>
        <p className="text-gray-400">
          {isConnected
            ? `Viewing portfolio for ${address?.slice(0, 6)}...${address?.slice(-4)}`
            : "Connect your wallet to view your portfolio."}
        </p>
      </div>

      {/* Portfolio Value */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Total Portfolio"
          value="$2.51M"
          subtitle="+3.2% (30d)"
          color="text-green-400"
        />
        <StatCard
          title="Staked Value"
          value="$600K"
          subtitle="200K XYT locked"
          color="text-blue-400"
        />
        <StatCard
          title="Vault Deposits"
          value="$525K"
          subtitle="xTBILL Yield Vault"
          color="text-purple-400"
        />
        <StatCard
          title="Voting Power"
          value="600K XYT"
          subtitle="3.0x multiplier"
          color="text-yellow-400"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Token Positions */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 className="text-lg font-semibold mb-4">Token Positions</h3>
          <div className="space-y-3">
            {MOCK_POSITIONS.map((pos) => (
              <div
                key={pos.token}
                className="flex items-center justify-between p-3 bg-gray-800 rounded-lg hover:bg-gray-750 transition-colors"
              >
                <div>
                  <p className="text-white font-medium">{pos.token}</p>
                  <p className="text-xs text-gray-500">{pos.type}</p>
                </div>
                <div className="text-right">
                  <p className="text-white font-medium">{pos.value}</p>
                  <p className="text-xs text-gray-400">
                    {pos.balance}{" "}
                    <span className="text-green-400">{pos.change}</span>
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Staking Position */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 className="text-lg font-semibold mb-4">Staking Position</h3>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div className="p-3 bg-gray-800 rounded-lg">
                <p className="text-xs text-gray-400">Staked Amount</p>
                <p className="text-lg font-bold text-white">
                  {MOCK_STAKING.stakedAmount}
                </p>
              </div>
              <div className="p-3 bg-gray-800 rounded-lg">
                <p className="text-xs text-gray-400">Value</p>
                <p className="text-lg font-bold text-white">
                  {MOCK_STAKING.stakedValue}
                </p>
              </div>
              <div className="p-3 bg-gray-800 rounded-lg">
                <p className="text-xs text-gray-400">Lock / Multiplier</p>
                <p className="text-sm text-blue-400">
                  {MOCK_STAKING.lockDuration} ({MOCK_STAKING.multiplier})
                </p>
              </div>
              <div className="p-3 bg-gray-800 rounded-lg">
                <p className="text-xs text-gray-400">Unlock Date</p>
                <p className="text-sm text-gray-300">
                  {MOCK_STAKING.unlockDate}
                </p>
              </div>
            </div>

            {/* Pending Rewards */}
            <div className="flex items-center justify-between p-3 bg-green-900/20 border border-green-900/30 rounded-lg">
              <div>
                <p className="text-sm text-green-400">Pending Rewards</p>
                <p className="text-lg font-bold text-green-400">
                  {MOCK_STAKING.pendingRewards}
                </p>
              </div>
              <button className="px-4 py-2 bg-green-600 hover:bg-green-500 rounded-lg text-sm font-medium transition-colors">
                Claim
              </button>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Vesting Schedule */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 className="text-lg font-semibold mb-4">Vesting Schedule</h3>
          <div className="space-y-3">
            <div className="flex justify-between text-sm">
              <span className="text-gray-400">Total Grant</span>
              <span className="text-white">{MOCK_VESTING.totalGrant}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-gray-400">Vested</span>
              <span className="text-blue-400">{MOCK_VESTING.vested}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-gray-400">Released</span>
              <span className="text-green-400">{MOCK_VESTING.released}</span>
            </div>

            {/* Progress bar */}
            <div className="w-full h-3 bg-gray-800 rounded-full overflow-hidden mt-2">
              <div
                className="h-full bg-gradient-to-r from-blue-500 to-green-500 rounded-full"
                style={{ width: "37%" }}
              />
            </div>
            <div className="flex justify-between text-xs text-gray-500">
              <span>0%</span>
              <span>37% vested</span>
              <span>100%</span>
            </div>

            {/* Claimable */}
            <div className="flex items-center justify-between p-3 bg-blue-900/20 border border-blue-900/30 rounded-lg mt-2">
              <div>
                <p className="text-sm text-blue-400">Claimable Now</p>
                <p className="text-lg font-bold text-blue-400">
                  {MOCK_VESTING.claimable}
                </p>
              </div>
              <button className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg text-sm font-medium transition-colors">
                Release
              </button>
            </div>

            <div className="text-xs text-gray-500 space-y-1">
              <p>Cliff ends: {MOCK_VESTING.cliffDate}</p>
              <p>Fully vested: {MOCK_VESTING.fullVestDate}</p>
            </div>
          </div>
        </div>

        {/* Transaction History */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 className="text-lg font-semibold mb-4">Recent Activity</h3>
          <div className="space-y-3">
            {MOCK_HISTORY.map((tx, i) => (
              <div
                key={i}
                className="flex items-center justify-between p-3 bg-gray-800 rounded-lg"
              >
                <div>
                  <p className="text-sm text-white">{tx.action}</p>
                  <p className="text-xs text-gray-500">{tx.date}</p>
                </div>
                <div className="text-right">
                  <p className="text-sm text-white">{tx.amount}</p>
                  <p className="text-xs text-gray-500 font-mono">{tx.tx}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
