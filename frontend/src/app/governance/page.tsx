"use client";

import { useState } from "react";
import { StatCard } from "@/components/StatCard";

const PROPOSAL_STATES = [
  "Pending",
  "Active",
  "Canceled",
  "Defeated",
  "Succeeded",
  "Queued",
  "Expired",
  "Executed",
];

interface MockProposal {
  id: string;
  title: string;
  description: string;
  state: number;
  forVotes: string;
  againstVotes: string;
  proposer: string;
  eta: string;
}

const MOCK_PROPOSALS: MockProposal[] = [
  {
    id: "1",
    title: "XIP-001: Increase Staking Rewards to 15% APY",
    description:
      "Proposal to increase the base staking reward rate from 10% to 15% APY to attract more XYT stakers and improve protocol security.",
    state: 1,
    forVotes: "42,500,000",
    againstVotes: "12,300,000",
    proposer: "0x742d...4fd8",
    eta: "Apr 15, 2026",
  },
  {
    id: "2",
    title: "XIP-002: Add Arbitrum Sepolia Chain Support",
    description:
      "Deploy CanonicalFactory and SignerRegistry on Arbitrum Sepolia to enable cross-chain RWA mirrors on Arbitrum L2.",
    state: 7,
    forVotes: "85,200,000",
    againstVotes: "3,100,000",
    proposer: "0x3fa1...9c22",
    eta: "Executed Mar 28",
  },
  {
    id: "3",
    title: "XIP-003: Update Fee Split to 50/25/15/10",
    description:
      "Adjust fee distribution: 50% treasury, 25% staking, 15% insurance, 10% burn for sustainable growth.",
    state: 5,
    forVotes: "62,800,000",
    againstVotes: "18,400,000",
    proposer: "0x9b3e...1a77",
    eta: "Queued - Execute Apr 10",
  },
];

function getStateColor(state: number): string {
  switch (state) {
    case 1:
      return "bg-green-500/20 text-green-400";
    case 5:
      return "bg-yellow-500/20 text-yellow-400";
    case 7:
      return "bg-blue-500/20 text-blue-400";
    case 3:
      return "bg-red-500/20 text-red-400";
    default:
      return "bg-gray-500/20 text-gray-400";
  }
}

export default function GovernancePage() {
  const [delegateAddress, setDelegateAddress] = useState("");

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold mb-2">Governance</h1>
        <p className="text-gray-400">
          XYT token holders govern the Xythum protocol through on-chain proposals
          and voting with timelock execution.
        </p>
      </div>

      {/* Governance Stats */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="XYT Total Supply"
          value="200M"
          subtitle="of 1B max supply"
          color="text-blue-400"
        />
        <StatCard
          title="Proposal Threshold"
          value="100K XYT"
          subtitle="0.01% of max supply"
          color="text-purple-400"
        />
        <StatCard
          title="Quorum"
          value="4%"
          subtitle="of total supply required"
          color="text-green-400"
        />
        <StatCard
          title="Timelock Delay"
          value="48h"
          subtitle="before execution"
          color="text-yellow-400"
        />
      </div>

      {/* Delegate Voting Power */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
        <h3 className="text-lg font-semibold mb-4">Delegate Voting Power</h3>
        <p className="text-sm text-gray-400 mb-4">
          Delegate your XYT voting power to yourself or another address.
          Delegating does not transfer tokens.
        </p>
        <div className="flex gap-3">
          <input
            type="text"
            placeholder="Delegate address (or self-delegate)"
            value={delegateAddress}
            onChange={(e) => setDelegateAddress(e.target.value)}
            className="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-blue-500"
          />
          <button className="px-6 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg text-sm font-medium transition-colors">
            Delegate
          </button>
          <button className="px-6 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg text-sm font-medium transition-colors">
            Self-Delegate
          </button>
        </div>
      </div>

      {/* Active Proposals */}
      <div>
        <h3 className="text-lg font-semibold mb-4">Proposals</h3>
        <div className="space-y-4">
          {MOCK_PROPOSALS.map((proposal) => (
            <div
              key={proposal.id}
              className="bg-gray-900 border border-gray-800 rounded-xl p-6 hover:border-gray-700 transition-colors"
            >
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1">
                  <div className="flex items-center gap-3 mb-2">
                    <span
                      className={`px-2 py-0.5 rounded text-xs font-medium ${getStateColor(proposal.state)}`}
                    >
                      {PROPOSAL_STATES[proposal.state]}
                    </span>
                    <span className="text-xs text-gray-500">{proposal.eta}</span>
                  </div>
                  <h4 className="text-white font-medium">{proposal.title}</h4>
                  <p className="text-sm text-gray-400 mt-1">
                    {proposal.description}
                  </p>
                </div>
              </div>

              {/* Voting bars */}
              <div className="mt-4 space-y-2">
                <div className="flex justify-between text-xs text-gray-400">
                  <span className="text-green-400">For: {proposal.forVotes} XYT</span>
                  <span className="text-red-400">Against: {proposal.againstVotes} XYT</span>
                </div>
                <div className="w-full h-2 bg-gray-800 rounded-full overflow-hidden flex">
                  <div
                    className="bg-green-500 h-full"
                    style={{
                      width: `${
                        (parseInt(proposal.forVotes.replace(/,/g, "")) /
                          (parseInt(proposal.forVotes.replace(/,/g, "")) +
                            parseInt(proposal.againstVotes.replace(/,/g, "")))) *
                        100
                      }%`,
                    }}
                  />
                  <div className="bg-red-500 h-full flex-1" />
                </div>
              </div>

              {/* Vote buttons */}
              {proposal.state === 1 && (
                <div className="flex gap-2 mt-4">
                  <button className="px-4 py-1.5 bg-green-600/20 text-green-400 hover:bg-green-600/30 rounded-lg text-xs font-medium transition-colors">
                    Vote For
                  </button>
                  <button className="px-4 py-1.5 bg-red-600/20 text-red-400 hover:bg-red-600/30 rounded-lg text-xs font-medium transition-colors">
                    Vote Against
                  </button>
                  <button className="px-4 py-1.5 bg-gray-700/50 text-gray-400 hover:bg-gray-700 rounded-lg text-xs font-medium transition-colors">
                    Abstain
                  </button>
                </div>
              )}

              <div className="mt-3 text-xs text-gray-500">
                Proposed by {proposal.proposer}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Governance Architecture */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
        <h3 className="text-sm font-medium text-gray-400 mb-4">
          Governance Architecture
        </h3>
        <pre className="text-xs text-gray-500 font-mono leading-relaxed">
{`XYT Token Holders
       |
  [Delegate Votes]
       |
       v
  XythumGovernor (OZ Governor)
  |-- Voting Delay: 1 day (7200 blocks)
  |-- Voting Period: 1 week (50400 blocks)
  |-- Proposal Threshold: 100K XYT
  |-- Quorum: 4% of total supply
       |
  [Queue Proposal]
       |
       v
  ProtocolTimelock (2-day delay)
       |
  [Execute]
       |
       v
  Protocol Contracts
  |-- ProtocolToken (mint, transfer limits)
  |-- StakingModule (reward rates, slashing)
  |-- FeeRouter (fee splits, recipients)
  |-- ProtocolTreasury (disbursements)
  |-- ComplianceEngine (tiers, rules)
  |-- EmergencyGuardian (circuit breakers)
  |-- OracleRouter (price feeds, thresholds)
  |-- MultiChainRegistry (chains, relayers)`}
        </pre>
      </div>
    </div>
  );
}
