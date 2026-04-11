// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMultiChainRegistry
/// @author Xythum Protocol
/// @notice Interface for unified cross-chain state tracking
interface IMultiChainRegistry {
    /// @notice Cross-chain deployment record
    struct ChainDeployment {
        uint256 chainId;
        address mirrorAddress;
        address factory;
        uint256 deployedAt;
        uint256 totalMinted;
        bool active;
    }

    /// @notice Emitted when a cross-chain deployment is registered
    event CrossChainDeploymentRegistered(
        address indexed originContract, uint256 indexed chainId, address mirrorAddress
    );

    /// @notice Emitted when cross-chain supply is synced
    event SupplySynced(
        address indexed originContract, uint256 indexed chainId, uint256 totalMinted
    );

    /// @notice Emitted when a new chain is supported
    event ChainAdded(uint256 indexed chainId, string name);

    /// @notice Register a deployment on another chain
    function registerDeployment(
        address originContract,
        uint256 originChainId,
        uint256 targetChainId,
        address mirrorAddress
    ) external;

    /// @notice Sync total minted supply from another chain
    function syncSupply(address originContract, uint256 chainId, uint256 totalMinted) external;

    /// @notice Get all chain deployments for an origin asset
    function getDeployments(address originContract, uint256 originChainId)
        external
        view
        returns (ChainDeployment[] memory);

    /// @notice Get aggregate supply across all chains for an asset
    function getAggregateSupply(address originContract, uint256 originChainId)
        external
        view
        returns (uint256);

    /// @notice Get all supported chain IDs
    function getSupportedChains() external view returns (uint256[] memory);
}
