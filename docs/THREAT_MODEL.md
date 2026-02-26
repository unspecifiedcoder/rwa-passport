# Xythum RWA Passport - Threat Model

## Trust Assumptions

| Component | Trust Level | Assumption |
|-----------|------------|------------|
| Signer Network | Threshold trust | At least `threshold` out of N signers are honest |
| Chainlink CCIP | Infrastructure trust | CCIP delivers messages correctly and with finality |
| Uniswap V4 | Protocol trust | PoolManager executes hooks correctly per spec |
| Compliance Contract | Configurable | Owner-controlled allowlist (MVP); ERC-3643 in v2 |
| ZK Verifier | Cryptographic | Groth16 proof system is sound (mock in MVP) |

## Attack Vectors and Mitigations

### 1. Signer Collusion Below Threshold

**Threat**: A subset of signers (below threshold) collude to forge an attestation.

**Mitigation**: `AttestationRegistry.verifyAttestation()` counts recovered signers against the threshold. If fewer than `threshold` valid signatures are provided, the transaction reverts with `InsufficientSignatures`.

**Test**: `test_attack_signer_collusion_below_threshold` (AttackScenarios.t.sol)

---

### 2. Attestation Replay

**Threat**: An attacker replays a previously valid attestation to trigger duplicate deployment.

**Mitigation**: `CanonicalFactory` stores deployed mirrors by CREATE2 salt. Deploying the same attestation twice reverts with `MirrorAlreadyDeployed`. Additionally, `AttestationRegistry` stores attested nonces and rejects duplicates.

**Test**: `test_attack_replay_attestation` (AttackScenarios.t.sol)

---

### 3. Cross-Chain Replay (Same Origin, Different Target)

**Threat**: An attestation for chain A is replayed on chain B.

**Analysis**: This is **intended behavior**. Different target chains produce different CREATE2 salts (`keccak256(origin, originChain, targetChain)`), so each target gets a unique mirror address. This is not an attack.

**Test**: `test_attack_replay_different_chain` (AttackScenarios.t.sol)

---

### 4. Frontrunning Mirror Deployment

**Threat**: An attacker predicts the CREATE2 address and deploys a fake contract there first.

**Mitigation**: CREATE2 address includes the factory address as deployer: `keccak256(0xff ++ factory ++ salt ++ initCodeHash)`. Only the factory contract can deploy at that address. A different deployer produces a completely different address. `isCanonical()` checks the factory's internal mapping, not just bytecode.

**Test**: `test_attack_frontrun_mirror_deployment` (AttackScenarios.t.sol)

---

### 5. Stale NAV Exploitation

**Threat**: An attacker uses a stale NAV attestation (>24h old) to get favorable prices or cheap collateral.

**Mitigation**:
- **RWAHook**: Dynamic fees increase linearly as NAV ages. Fresh (<1hr): 5 bps. Stale (>6hr): 50 bps. This makes trading on stale data expensive.
- **AaveAdapter**: `maxProofAge` (default 1hr) rejects proofs older than the threshold.
- **AttestationRegistry**: `maxStaleness` (24hr) rejects attestations with old timestamps.

**Test**: `test_attack_stale_nav_exploitation` (AttackScenarios.t.sol)

---

### 6. Compliance Bypass via Intermediary

**Threat**: Non-compliant user B receives tokens through compliant intermediary C (A -> C -> B).

**Mitigation**: `XythumToken._update()` checks compliance on EVERY transfer, not just the first hop. The transfer from C to B will revert with `TransferNotCompliant` because B is not whitelisted.

**Test**: `test_attack_compliance_bypass_via_intermediate` (AttackScenarios.t.sol)

---

### 7. Unauthorized Minting

**Threat**: An attacker directly calls `XythumToken.mint()` to create tokens without attestation.

**Mitigation**: Only addresses in the `authorizedMinters` mapping can mint. This is set by the factory (which is the initial minter) and can only be modified by the factory via `setAuthorizedMinter()`.

**Test**: `test_attack_unauthorized_mint` (AttackScenarios.t.sol)

---

### 8. Unauthorized CCIP Messages

**Threat**: An attacker sends a CCIP message to `XythumCCIPReceiver` from an unregistered source.

**Mitigation**: `XythumCCIPReceiver._ccipReceive()` checks the `allowedSenders` mapping for the source chain selector + sender address combination. Unauthorized sources revert with `UnauthorizedSender`.

**Test**: `test_attack_ccip_message_from_unauthorized_source` (AttackScenarios.t.sol)

---

### 9. Double-Spend ZK Proof

**Threat**: An attacker submits the same ZK proof twice to get double receipt tokens.

**Mitigation**: Two layers of protection:
1. `CollateralVerifier.usedNullifiers`: `keccak256(proof)` is stored after first use; replay reverts with `NullifierAlreadyUsed`
2. `AaveAdapter.usedProofs`: `proofId` is stored after first deposit; replay reverts with `ProofAlreadyUsed`

**Test**: `test_attack_double_spend_zk_proof` (AttackScenarios.t.sol)

---

### 10. Protocol Pause

**Threat**: Protocol must be pausable for emergency response.

**Mitigation**: `CanonicalFactory` inherits OpenZeppelin `Pausable`. Owner can call `pause()` to halt all mirror deployments. `RWAHook` has per-pool pause via `pausePool(poolId)`. Both are only callable by owner (governance multisig in production).

**Test**: `test_attack_paused_protocol` (AttackScenarios.t.sol)

---

## Access Control Matrix

| Function | Who Can Call | State Changed |
|----------|-------------|---------------|
| `SignerRegistry.registerSigner` | Owner only | Adds signer to active set |
| `SignerRegistry.removeSigner` | Owner only | Initiates cooldown, then removes |
| `AttestationRegistry.verifyAttestation` | Anyone | Stores verified attestation |
| `CanonicalFactory.deployMirror` | Anyone | Deploys mirror token |
| `CanonicalFactory.pause/unpause` | Owner only | Halts/resumes deployments |
| `XythumToken.mint/burn` | Authorized minters only | Changes token supply |
| `XythumToken.setAuthorizedMinter` | Factory only | Modifies minter set |
| `RWAHook.pausePool/unpausePool` | Owner only | Halts/resumes pool |
| `RWAHook.updateNAV` | Anyone (MVP) | Resets NAV timestamp |
| `CollateralVerifier.verifyCollateralProof` | Anyone | Stores proof record |
| `CollateralVerifier.registerAsset` | Owner only | Maps asset to circuit ID |
| `CollateralVerifier.invalidateProof` | Owner only | Deactivates proof |
| `AaveAdapter.depositWithProof` | Anyone | Mints receipt tokens |
| `AaveAdapter.setMaxProofAge` | Owner only | Changes proof validity window |

## Emergency Procedures

1. **Pause factory**: `factory.pause()` -- stops all mirror deployments
2. **Pause pool**: `hook.pausePool(poolId)` -- stops trading on specific pool
3. **Invalidate proof**: `verifier.invalidateProof(proofId)` -- deactivates a compromised proof
4. **Remove signer**: `signerRegistry.removeSigner(addr)` -- removes compromised signer (after cooldown)

## Known Limitations (MVP)

- ECDSA multi-sig instead of BLS aggregation (higher gas, no aggregation)
- `tx.origin` used for compliance in V4 hooks (can be spoofed by meta-tx relayers)
- MockVerifier instead of real Groth16 (circom tooling not available)
- Manual LP seeding (no auto-liquidity from treasury)
- Simple allowlist compliance (not full ERC-3643 T-REX)
- `updateNAV()` callable by anyone (should be restricted to AttestationRegistry in v2)
