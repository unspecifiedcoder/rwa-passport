// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IMultiChainRegistry } from "../interfaces/IMultiChainRegistry.sol";

/// @title MultiChainRegistry
/// @author Xythum Protocol
/// @notice Unified cross-chain state registry for tracking all RWA mirror deployments
///         across supported chains. Acts as the canonical source of truth for
///         aggregate supply, deployment locations, and chain health.
/// @dev Updated via CCIP messages or direct calls from authorized relayers.
///      Provides the data layer for the protocol dashboard and compliance reporting.
contract MultiChainRegistry is IMultiChainRegistry, Ownable2Step {
    // ─── Custom Errors ───────────────────────────────────────────────
    error OnlyRelayer();
    error ChainNotSupported(uint256 chainId);
    error DeploymentAlreadyExists(address originContract, uint256 chainId);
    error ZeroAddress();

    // ─── Structs ─────────────────────────────────────────────────────
    struct ChainInfo {
        string name;
        bool active;
        uint256 registeredAt;
    }

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Supported chain configurations
    mapping(uint256 => ChainInfo) public chainInfos;

    /// @notice All supported chain IDs
    uint256[] public supportedChainIds;

    /// @notice Deployments: keccak256(originContract, originChainId) => chainId => deployment
    mapping(bytes32 => mapping(uint256 => ChainDeployment)) public deploymentMap;

    /// @notice Chain IDs where an asset is deployed: keccak256(originContract, originChainId) => chainId[]
    mapping(bytes32 => uint256[]) public deploymentChains;

    /// @notice Authorized cross-chain relayers
    mapping(address => bool) public relayers;

    /// @notice Total deployments across all chains
    uint256 public totalDeployments;

    /// @notice Aggregate minted supply per origin asset
    mapping(bytes32 => uint256) public aggregateSupplyMap;

    // ─── Events ──────────────────────────────────────────────────────
    event RelayerUpdated(address indexed relayer, bool active);
    event ChainStatusUpdated(uint256 indexed chainId, bool active);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(address _owner) Ownable(_owner) {
        relayers[_owner] = true;
    }

    // ─── Modifiers ───────────────────────────────────────────────────
    modifier onlyRelayer() {
        if (!relayers[msg.sender] && msg.sender != owner()) revert OnlyRelayer();
        _;
    }

    // ─── Chain Management ────────────────────────────────────────────

    /// @notice Add a supported chain
    function addChain(uint256 chainId, string calldata name) external onlyOwner {
        if (!chainInfos[chainId].active) {
            supportedChainIds.push(chainId);
        }

        chainInfos[chainId] = ChainInfo({
            name: name,
            active: true,
            registeredAt: block.timestamp
        });

        emit ChainAdded(chainId, name);
    }

    /// @notice Deactivate a chain
    function setChainStatus(uint256 chainId, bool active) external onlyOwner {
        chainInfos[chainId].active = active;
        emit ChainStatusUpdated(chainId, active);
    }

    // ─── Deployment Registration ─────────────────────────────────────

    /// @inheritdoc IMultiChainRegistry
    function registerDeployment(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        address mirrorAddress
    ) external onlyRelayer {
        if (mirrorAddress == address(0)) revert ZeroAddress();
        if (!chainInfos[targetChainId].active) revert ChainNotSupported(targetChainId);

        bytes32 assetKey = _assetKey(originContract, originChainId);

        // Check not already registered
        if (deploymentMap[assetKey][targetChainId].mirrorAddress != address(0)) {
            revert DeploymentAlreadyExists(originContract, targetChainId);
        }

        deploymentMap[assetKey][targetChainId] = ChainDeployment({
            chainId: targetChainId,
            mirrorAddress: mirrorAddress,
            factory: msg.sender,
            deployedAt: block.timestamp,
            totalMinted: 0,
            active: true
        });

        deploymentChains[assetKey].push(targetChainId);
        totalDeployments++;

        emit CrossChainDeploymentRegistered(originContract, targetChainId, mirrorAddress);
    }

    /// @inheritdoc IMultiChainRegistry
    function syncSupply(address originContract, uint256 chainId, uint256 totalMinted)
        external
        onlyRelayer
    {
        bytes32 assetKey = _assetKey(originContract, chainId);
        deploymentMap[assetKey][chainId].totalMinted = totalMinted;

        // Recalculate aggregate supply
        _recalculateAggregateSupply(originContract, chainId);

        emit SupplySynced(originContract, chainId, totalMinted);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @inheritdoc IMultiChainRegistry
    function getDeployments(address originContract, uint256 originChainId)
        external
        view
        returns (ChainDeployment[] memory)
    {
        bytes32 assetKey = _assetKey(originContract, originChainId);
        uint256[] storage chains = deploymentChains[assetKey];

        ChainDeployment[] memory result = new ChainDeployment[](chains.length);
        for (uint256 i = 0; i < chains.length; i++) {
            result[i] = deploymentMap[assetKey][chains[i]];
        }
        return result;
    }

    /// @inheritdoc IMultiChainRegistry
    function getAggregateSupply(address originContract, uint256 originChainId)
        external
        view
        returns (uint256)
    {
        bytes32 assetKey = _assetKey(originContract, originChainId);
        return aggregateSupplyMap[assetKey];
    }

    /// @inheritdoc IMultiChainRegistry
    function getSupportedChains() external view returns (uint256[] memory) {
        return supportedChainIds;
    }

    /// @notice Get deployment count for an origin asset
    function getDeploymentCount(address originContract, uint256 originChainId)
        external
        view
        returns (uint256)
    {
        bytes32 assetKey = _assetKey(originContract, originChainId);
        return deploymentChains[assetKey].length;
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function setRelayer(address relayer, bool active) external onlyOwner {
        relayers[relayer] = active;
        emit RelayerUpdated(relayer, active);
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _assetKey(address originContract, uint256 originChainId)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(originContract, originChainId));
    }

    function _recalculateAggregateSupply(address originContract, uint256 originChainId) internal {
        bytes32 assetKey = _assetKey(originContract, originChainId);
        uint256[] storage chains = deploymentChains[assetKey];

        uint256 total;
        for (uint256 i = 0; i < chains.length; i++) {
            total += deploymentMap[assetKey][chains[i]].totalMinted;
        }

        aggregateSupplyMap[assetKey] = total;
    }
}
