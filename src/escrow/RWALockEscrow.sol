// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IRWALockEscrow } from "../interfaces/IRWALockEscrow.sol";
import { ISignerRegistry } from "../interfaces/ISignerRegistry.sol";
import { ReceiptLib } from "../libraries/ReceiptLib.sol";
import { SignatureLib } from "../libraries/SignatureLib.sol";
import { AttestationLib } from "../libraries/AttestationLib.sol";

/// @title RWALockEscrow
/// @author Xythum Protocol
/// @notice Escrow that holds original RWA tokens on the origin chain while
///         their canonical mirror is alive on a target chain. Releases tokens
///         only when presented with a threshold-signed UnlockReceipt.
/// @dev One instance deployed per chain. Holds multiple RWA tokens.
contract RWALockEscrow is IRWALockEscrow, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Custom Errors ───────────────────────────────────────────────
    error ZeroAmount();
    error ZeroAddress();
    error TargetIsThisChain();
    error LockNotFound(bytes32 lockId);
    error LockAlreadyReleased(bytes32 lockId);
    error WrongOriginChain(uint256 provided, uint256 expected);
    error WrongOriginContract(address provided, address expected);
    error WrongAmount(uint256 provided, uint256 expected);
    error UnlockReceiptStale(uint256 receiptTimestamp, uint256 maxAge);
    error UnlockReceiptInFuture(uint256 receiptTimestamp);

    // ─── Storage ─────────────────────────────────────────────────────
    struct LockState {
        address rwaToken;
        address locker;
        uint256 amount;
        uint256 lockedAt;
        bool released;
    }

    // ─── Immutables ──────────────────────────────────────────────────
    /// @inheritdoc IRWALockEscrow
    address public immutable override signerRegistry;

    /// @inheritdoc IRWALockEscrow
    bytes32 public immutable override DOMAIN_SEPARATOR;

    /// @inheritdoc IRWALockEscrow
    uint256 public immutable override maxStaleness;

    // ─── Mutable storage ─────────────────────────────────────────────
    /// @notice Per-chain monotonically increasing nonce, mixed into lockId
    uint256 public lockNonce;

    /// @notice State for every lock created by this escrow
    mapping(bytes32 lockId => LockState) internal _locks;

    /// @dev Auxiliary index: original RWA balances locked under this escrow.
    ///      Used by `rescueStuckTokens` to ensure the owner cannot pull
    ///      escrowed funds.
    mapping(address rwaToken => uint256 totalLocked) public totalLocked;

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _signerRegistry Same SignerRegistry instance used by AttestationRegistry
    /// @param _maxStaleness Maximum age of a valid UnlockReceipt (e.g. 1 day)
    /// @param _initialOwner Address that can pause / rescue stuck tokens
    constructor(address _signerRegistry, uint256 _maxStaleness, address _initialOwner)
        Ownable(_initialOwner)
    {
        if (_signerRegistry == address(0) || _initialOwner == address(0)) {
            revert ZeroAddress();
        }
        signerRegistry = _signerRegistry;
        maxStaleness = _maxStaleness;
        // Reuse the protocol-wide EIP-712 domain (same name/version as
        // AttestationRegistry) so the same signer keys can sign both.
        DOMAIN_SEPARATOR = AttestationLib.domainSeparator(block.chainid, address(this));
    }

    // ─── External: lock ──────────────────────────────────────────────

    /// @inheritdoc IRWALockEscrow
    function lock(address rwaToken, uint256 amount, uint256 targetChainId)
        external
        override
        whenNotPaused
        nonReentrant
        returns (bytes32 lockId)
    {
        if (amount == 0) revert ZeroAmount();
        if (rwaToken == address(0)) revert ZeroAddress();
        if (targetChainId == block.chainid) revert TargetIsThisChain();

        uint256 nonce = lockNonce++;
        lockId = keccak256(abi.encode(address(this), msg.sender, rwaToken, amount, nonce));

        _locks[lockId] = LockState({
            rwaToken: rwaToken,
            locker: msg.sender,
            amount: amount,
            lockedAt: block.timestamp,
            released: false
        });
        totalLocked[rwaToken] += amount;

        IERC20(rwaToken).safeTransferFrom(msg.sender, address(this), amount);

        emit Locked(lockId, msg.sender, rwaToken, amount, targetChainId);
    }

    // ─── External: release ───────────────────────────────────────────

    /// @inheritdoc IRWALockEscrow
    function release(
        ReceiptLib.UnlockReceipt calldata receipt,
        bytes calldata signatures,
        uint256 signerBitmap
    ) external override whenNotPaused nonReentrant {
        // Receipt must target this chain.
        if (receipt.originChainId != block.chainid) {
            revert WrongOriginChain(receipt.originChainId, block.chainid);
        }

        // Receipt must be fresh.
        if (receipt.timestamp > block.timestamp) {
            revert UnlockReceiptInFuture(receipt.timestamp);
        }
        if (block.timestamp > receipt.timestamp + maxStaleness) {
            revert UnlockReceiptStale(receipt.timestamp, maxStaleness);
        }

        // Lock must exist and not yet be released.
        LockState storage L = _locks[receipt.lockId];
        if (L.amount == 0) revert LockNotFound(receipt.lockId);
        if (L.released) revert LockAlreadyReleased(receipt.lockId);

        // Receipt must match the on-chain lock exactly.
        if (L.rwaToken != receipt.originContract) {
            revert WrongOriginContract(receipt.originContract, L.rwaToken);
        }
        if (L.amount != receipt.amount) {
            revert WrongAmount(receipt.amount, L.amount);
        }

        // Verify 3-of-N threshold signatures.
        bytes32 digest = ReceiptLib.toTypedDataHash(receipt, DOMAIN_SEPARATOR);
        ISignerRegistry sr = ISignerRegistry(signerRegistry);
        SignatureLib.verifyThreshold(
            digest, signatures, signerBitmap, sr.getSignerSet(), sr.getThreshold()
        );

        // Effects.
        L.released = true;
        totalLocked[L.rwaToken] -= L.amount;

        // Interactions (last).
        IERC20(L.rwaToken).safeTransfer(receipt.recipient, L.amount);

        emit Released(receipt.lockId, receipt.recipient, L.amount);
    }

    // ─── External views ──────────────────────────────────────────────

    /// @inheritdoc IRWALockEscrow
    function lockState(bytes32 lockId)
        external
        view
        override
        returns (address rwaToken, address locker, uint256 amount, uint256 lockedAt, bool released)
    {
        LockState storage L = _locks[lockId];
        return (L.rwaToken, L.locker, L.amount, L.lockedAt, L.released);
    }

    // ─── Owner controls ──────────────────────────────────────────────

    /// @notice Pause new locks and releases (emergency)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume operations
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Rescue tokens sent to the escrow that are NOT locked under it
    ///         (e.g., someone transferred random tokens directly).
    /// @dev Cannot pull funds belonging to active locks; protected by
    ///      `totalLocked[token]` accounting.
    /// @param token ERC-20 token to rescue
    /// @param to Recipient
    function rescueStuckTokens(address token, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = IERC20(token).balanceOf(address(this));
        uint256 locked = totalLocked[token];
        if (bal > locked) {
            IERC20(token).safeTransfer(to, bal - locked);
        }
    }
}
