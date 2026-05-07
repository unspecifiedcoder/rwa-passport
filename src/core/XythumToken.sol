// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IXythumToken } from "../interfaces/IXythumToken.sol";

/// @title ICompliance
/// @notice Minimal interface for transfer compliance checks
interface ICompliance {
    function isTransferCompliant(address from, address to, uint256 amount)
        external
        view
        returns (bool);
}

/// @title XythumToken
/// @author Xythum Protocol
/// @notice Canonical mirror of an RWA on a target chain. Deployed ONLY by
///         CanonicalFactory at a deterministic CREATE2 address.
/// @dev Embeds origin metadata as immutables for gas efficiency.
///      Enforces compliance on every transfer via a pluggable compliance contract.
///      TODO(upgrade): configurable decimals derived from origin token
contract XythumToken is ERC20, IXythumToken {
    // ─── Custom Errors ───────────────────────────────────────────────
    error Unauthorized(address caller);
    error TransferNotCompliant(address from, address to);
    error ZeroAddress();
    error MintCapExceeded(uint256 requested, uint256 remaining);
    error InvalidMintCap(uint256 newCap, uint256 currentSupply);
    error AlreadyBurnedForLock(bytes32 lockId);
    error InsufficientBalanceForBurn(address holder, uint256 requested, uint256 available);

    // ─── Events ──────────────────────────────────────────────────────
    /// @notice Emitted when a holder burns mirror tokens against a specific
    ///         lockId to signal "release my original RWA on the origin chain."
    ///         Watched by signers, who then issue an UnlockReceipt.
    event BurnedForLock(bytes32 indexed lockId, address indexed burner, uint256 amount);

    // ─── Immutables ──────────────────────────────────────────────────
    /// @notice The original RWA contract address on the source chain
    address public immutable override originContract;

    /// @notice The source chain ID where the original RWA lives
    uint256 public immutable override originChainId;

    /// @notice The CanonicalFactory that deployed this token
    address public immutable factory;

    /// @notice The compliance contract for transfer checks
    address public immutable compliance;

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Addresses authorized to mint/burn (factory + CCIP adapters)
    mapping(address => bool) public authorizedMinters;

    /// @notice Maximum total tokens that can be minted (from attestation lockedAmount)
    uint256 public mintCap;

    /// @notice Running total of all tokens ever minted (does not decrease on burn)
    uint256 public totalMinted;

    /// @notice Tracks which lockIds have already been burned-against on this chain.
    ///         A given lockId can be consumed at most once.
    mapping(bytes32 lockId => bool) public burnedForLock;

    // ─── Constructor ─────────────────────────────────────────────────
    /// @notice Deploy a new mirror token
    /// @param _name Token name (e.g. "Xythum Mirror")
    /// @param _symbol Token symbol (e.g. "xRWA")
    /// @param _originContract Address of the RWA on the source chain
    /// @param _originChainId Source chain ID
    /// @param _compliance Address of the compliance contract (address(0) to disable)
    /// @param _mintCap Maximum total supply (from attestation.lockedAmount)
    constructor(
        string memory _name,
        string memory _symbol,
        address _originContract,
        uint256 _originChainId,
        address _compliance,
        uint256 _mintCap
    ) ERC20(_name, _symbol) {
        originContract = _originContract;
        originChainId = _originChainId;
        factory = msg.sender;
        compliance = _compliance;
        authorizedMinters[msg.sender] = true;
        mintCap = _mintCap;
    }

    // ─── External Functions ──────────────────────────────────────────

    /// @inheritdoc IXythumToken
    function mint(address to, uint256 amount) external {
        if (!authorizedMinters[msg.sender]) revert Unauthorized(msg.sender);
        if (to == address(0)) revert ZeroAddress();
        if (totalMinted + amount > mintCap) {
            revert MintCapExceeded(amount, mintCap - totalMinted);
        }
        totalMinted += amount;
        _mint(to, amount);
    }

    /// @inheritdoc IXythumToken
    function burn(address from, uint256 amount) external {
        if (!authorizedMinters[msg.sender]) revert Unauthorized(msg.sender);
        _burn(from, amount);
    }

    /// @notice Burn `amount` of the caller's mirror tokens against a specific
    ///         `lockId`. The lockId is one-shot — a given lockId can only be
    ///         consumed once. Off-chain signers watch the `BurnedForLock`
    ///         event and issue an UnlockReceipt for the matching escrow.
    /// @dev    No `from` parameter — the caller burns their own tokens. This
    ///         intentionally avoids needing approvals / allowance management.
    /// @param amount Amount of xRWA to burn
    /// @param lockId Identifier matching an outstanding lock on the origin chain
    function burnForLock(uint256 amount, bytes32 lockId) external {
        if (burnedForLock[lockId]) revert AlreadyBurnedForLock(lockId);
        uint256 bal = balanceOf(msg.sender);
        if (bal < amount) revert InsufficientBalanceForBurn(msg.sender, amount, bal);
        burnedForLock[lockId] = true;
        _burn(msg.sender, amount);
        emit BurnedForLock(lockId, msg.sender, amount);
    }

    /// @notice Bump the mint cap by `amount` and mint to `to` in one call.
    ///         Used by `CanonicalFactory.mintFromLock` to grow supply when a
    ///         new lock arrives. The cap is a cumulative high-water mark and
    ///         never decreases (matches existing `totalMinted` semantics).
    /// @dev    Restricted to authorized minters (factory + adapters).
    /// @param to Recipient of the freshly minted xRWA
    /// @param amount Amount to mint AND amount to add to mintCap
    /// @param /* lockId */ Optional context (passed through for indexers; not stored)
    function bumpCapAndMint(
        address to,
        uint256 amount,
        bytes32 /* lockId */
    )
        external
    {
        if (!authorizedMinters[msg.sender]) revert Unauthorized(msg.sender);
        if (to == address(0)) revert ZeroAddress();
        // Cumulative high-water mark: cap can only grow.
        mintCap += amount;
        totalMinted += amount;
        _mint(to, amount);
    }

    /// @notice Set or revoke minter authorization
    /// @param minter Address to authorize or revoke
    /// @param authorized Whether the address should be authorized
    function setAuthorizedMinter(address minter, bool authorized) external {
        if (msg.sender != factory) revert Unauthorized(msg.sender);
        authorizedMinters[minter] = authorized;
    }

    /// @notice Update the mint cap (only callable by factory, e.g. via new attestation)
    /// @param newCap New maximum total supply
    function updateMintCap(uint256 newCap) external {
        if (msg.sender != factory) revert Unauthorized(msg.sender);
        if (newCap < totalSupply()) revert InvalidMintCap(newCap, totalSupply());
        mintCap = newCap;
    }

    /// @inheritdoc IXythumToken
    function isCompliant(address from, address to) public view returns (bool) {
        if (compliance == address(0)) return true;
        return ICompliance(compliance).isTransferCompliant(from, to, 0);
    }

    // ─── Internal Overrides ──────────────────────────────────────────

    /// @notice Override ERC20 _update to enforce compliance on transfers
    /// @dev Mint (from=0) and burn (to=0) bypass compliance checks
    function _update(address from, address to, uint256 amount) internal override {
        // Compliance check on transfers (not mint/burn)
        if (from != address(0) && to != address(0)) {
            if (!isCompliant(from, to)) {
                revert TransferNotCompliant(from, to);
            }
        }
        super._update(from, to, amount);
    }
}
