// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title ProtocolToken (XYT)
/// @author Xythum Protocol
/// @notice The governance and utility token for the Xythum RWA Passport protocol.
///         - ERC20Votes for on-chain governance (Governor compatible)
///         - ERC20Permit for gasless approvals
///         - Vesting schedules for team, investors, ecosystem
///         - Anti-whale transfer limits
///         - Hard supply cap of 1 billion tokens
/// @dev Follows OpenZeppelin v5 patterns. Designed as the economic backbone of
///      a billion-dollar RWA tokenization protocol.
contract ProtocolToken is ERC20, ERC20Permit, ERC20Votes, Ownable2Step {
    // ─── Custom Errors ───────────────────────────────────────────────
    error MaxSupplyExceeded(uint256 requested, uint256 remaining);
    error TransferLimitExceeded(uint256 amount, uint256 limit);
    error UnauthorizedMinter(address caller);
    error VestingAlreadyExists(address beneficiary);
    error NoVestingSchedule(address beneficiary);
    error NothingToRelease(address beneficiary);
    error ZeroAddress();
    error ZeroAmount();

    // ─── Constants ───────────────────────────────────────────────────
    /// @notice Maximum total supply: 1 billion XYT (18 decimals)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    // ─── Structs ─────────────────────────────────────────────────────
    /// @notice Vesting schedule for a beneficiary
    struct VestingSchedule {
        uint256 totalAmount; // Total tokens to vest
        uint256 released; // Tokens already released
        uint256 startTime; // Vesting start timestamp
        uint256 cliffEnd; // Cliff end timestamp
        uint256 vestingEnd; // Full vesting end timestamp
        bool revocable; // Whether the schedule can be revoked
    }

    // ─── Storage ─────────────────────────────────────────────────────
    /// @notice Addresses authorized to mint (staking rewards, governance)
    mapping(address => bool) public authorizedMinters;

    /// @notice Vesting schedules per beneficiary
    mapping(address => VestingSchedule) public vestingSchedules;

    /// @notice Anti-whale: maximum transfer amount (0 = unlimited)
    uint256 public transferLimit;

    /// @notice Addresses exempt from transfer limit (DEXes, staking, governance)
    mapping(address => bool) public transferLimitExempt;

    /// @notice Total tokens allocated to vesting (not yet released)
    uint256 public totalVestingReserved;

    // ─── Events ──────────────────────────────────────────────────────
    event MinterUpdated(address indexed minter, bool authorized);
    event TransferLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event TransferLimitExemptUpdated(address indexed account, bool exempt);
    event VestingCreated(
        address indexed beneficiary, uint256 amount, uint256 cliffEnd, uint256 vestingEnd
    );
    event VestingReleased(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary, uint256 unvested);

    // ─── Constructor ─────────────────────────────────────────────────
    /// @notice Deploy the XYT governance token
    /// @param _owner Protocol multisig / timelock controller
    /// @param _initialMint Initial mint for treasury (e.g., 100M for liquidity bootstrapping)
    /// @param _treasury Treasury address to receive initial mint
    constructor(address _owner, uint256 _initialMint, address _treasury)
        ERC20("Xythum Protocol", "XYT")
        ERC20Permit("Xythum Protocol")
        Ownable(_owner)
    {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_initialMint > MAX_SUPPLY) revert MaxSupplyExceeded(_initialMint, MAX_SUPPLY);

        // Initial treasury mint
        if (_initialMint > 0) {
            _mint(_treasury, _initialMint);
        }

        // Owner and treasury are exempt from transfer limits
        transferLimitExempt[_owner] = true;
        transferLimitExempt[_treasury] = true;
    }

    // ─── Minting ─────────────────────────────────────────────────────

    /// @notice Mint new tokens (staking rewards, governance emissions)
    function mint(address to, uint256 amount) external {
        if (!authorizedMinters[msg.sender]) revert UnauthorizedMinter(msg.sender);
        if (to == address(0)) revert ZeroAddress();
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert MaxSupplyExceeded(amount, MAX_SUPPLY - totalSupply());
        }
        _mint(to, amount);
    }

    /// @notice Burn tokens from caller's balance
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // ─── Vesting ─────────────────────────────────────────────────────

    /// @notice Create a vesting schedule
    /// @param beneficiary Address to receive vested tokens
    /// @param amount Total tokens to vest
    /// @param cliffDuration Cliff period in seconds
    /// @param vestingDuration Total vesting duration in seconds (including cliff)
    /// @param revocable Whether the owner can revoke unvested tokens
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    ) external onlyOwner {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (vestingSchedules[beneficiary].totalAmount != 0) {
            revert VestingAlreadyExists(beneficiary);
        }

        // Ensure we have enough supply for this vesting
        if (totalSupply() + totalVestingReserved + amount > MAX_SUPPLY) {
            revert MaxSupplyExceeded(amount, MAX_SUPPLY - totalSupply() - totalVestingReserved);
        }

        uint256 start = block.timestamp;
        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            released: 0,
            startTime: start,
            cliffEnd: start + cliffDuration,
            vestingEnd: start + vestingDuration,
            revocable: revocable
        });

        totalVestingReserved += amount;

        emit VestingCreated(beneficiary, amount, start + cliffDuration, start + vestingDuration);
    }

    /// @notice Release vested tokens to the beneficiary
    function releaseVestedTokens(address beneficiary) external {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        if (schedule.totalAmount == 0) revert NoVestingSchedule(beneficiary);

        uint256 releasable = _computeReleasable(schedule);
        if (releasable == 0) revert NothingToRelease(beneficiary);

        schedule.released += releasable;
        totalVestingReserved -= releasable;
        _mint(beneficiary, releasable);

        emit VestingReleased(beneficiary, releasable);
    }

    /// @notice Revoke a vesting schedule (only if revocable)
    function revokeVesting(address beneficiary) external onlyOwner {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        if (schedule.totalAmount == 0) revert NoVestingSchedule(beneficiary);

        // Release any vested but unclaimed tokens first
        uint256 releasable = _computeReleasable(schedule);
        if (releasable > 0) {
            schedule.released += releasable;
            _mint(beneficiary, releasable);
            emit VestingReleased(beneficiary, releasable);
        }

        uint256 unvested = schedule.totalAmount - schedule.released;
        totalVestingReserved -= unvested;

        delete vestingSchedules[beneficiary];
        emit VestingRevoked(beneficiary, unvested);
    }

    /// @notice Get the releasable amount for a beneficiary
    function getReleasableAmount(address beneficiary) external view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        if (schedule.totalAmount == 0) return 0;
        return _computeReleasable(schedule);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    /// @notice Set authorized minter status
    function setMinter(address minter, bool authorized) external onlyOwner {
        authorizedMinters[minter] = authorized;
        emit MinterUpdated(minter, authorized);
    }

    /// @notice Set anti-whale transfer limit (0 = unlimited)
    function setTransferLimit(uint256 limit) external onlyOwner {
        uint256 oldLimit = transferLimit;
        transferLimit = limit;
        emit TransferLimitUpdated(oldLimit, limit);
    }

    /// @notice Set transfer limit exemption for an address
    function setTransferLimitExempt(address account, bool exempt) external onlyOwner {
        transferLimitExempt[account] = exempt;
        emit TransferLimitExemptUpdated(account, exempt);
    }

    // ─── View ────────────────────────────────────────────────────────

    /// @notice Maximum supply cap
    function maxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    // ─── Internal Overrides ──────────────────────────────────────────

    /// @dev Override _update for anti-whale + ERC20Votes bookkeeping
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        // Anti-whale check on transfers (not mint/burn)
        if (from != address(0) && to != address(0) && transferLimit > 0) {
            if (!transferLimitExempt[from] && !transferLimitExempt[to]) {
                if (value > transferLimit) {
                    revert TransferLimitExceeded(value, transferLimit);
                }
            }
        }

        super._update(from, to, value);
    }

    /// @dev Required override for ERC20Permit + ERC20Votes
    function nonces(address owner_) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner_);
    }

    // ─── Internal ────────────────────────────────────────────────────

    /// @notice Compute releasable amount for a vesting schedule
    function _computeReleasable(VestingSchedule storage schedule)
        internal
        view
        returns (uint256)
    {
        if (block.timestamp < schedule.cliffEnd) return 0;

        uint256 vested;
        if (block.timestamp >= schedule.vestingEnd) {
            vested = schedule.totalAmount;
        } else {
            uint256 elapsed = block.timestamp - schedule.startTime;
            uint256 duration = schedule.vestingEnd - schedule.startTime;
            vested = (schedule.totalAmount * elapsed) / duration;
        }

        return vested - schedule.released;
    }
}
