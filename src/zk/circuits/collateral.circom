pragma circom 2.1.6;

include "./merkle.circom";
include "../../../node_modules/circomlib/circuits/poseidon.circom";
include "../../../node_modules/circomlib/circuits/comparators.circom";

// CollateralProof: Prove "I control >= minimumValue of an asset"
// without revealing actual balance, identity, or other positions.
//
// Public inputs:
//   attestationRoot — Merkle root binding proof to on-chain state
//   assetId         — Which asset (field element derived from address)
//   minimumValue    — The minimum value being claimed
//
// Private inputs:
//   balance         — Actual token balance
//   secret          — Owner's secret (preimage of commitment)
//   pathElements[]  — Merkle proof siblings
//   pathIndices[]   — Merkle proof path bits

template CollateralProof(merkleDepth) {
    // PUBLIC
    signal input attestationRoot;
    signal input assetId;
    signal input minimumValue;

    // PRIVATE
    signal input balance;
    signal input secret;
    signal input pathElements[merkleDepth];
    signal input pathIndices[merkleDepth];

    // CONSTRAINT 1: Compute owner commitment
    // commitment = Poseidon(secret)
    component commitHash = Poseidon(1);
    commitHash.inputs[0] <== secret;
    signal commitment;
    commitment <== commitHash.out;

    // CONSTRAINT 2: Compute leaf = Poseidon(commitment, balance, assetId)
    component leafHash = Poseidon(3);
    leafHash.inputs[0] <== commitment;
    leafHash.inputs[1] <== balance;
    leafHash.inputs[2] <== assetId;

    // CONSTRAINT 3: Verify Merkle inclusion
    component merkle = MerkleProof(merkleDepth);
    merkle.leaf <== leafHash.out;
    for (var i = 0; i < merkleDepth; i++) {
        merkle.pathElements[i] <== pathElements[i];
        merkle.pathIndices[i] <== pathIndices[i];
    }
    merkle.root === attestationRoot;

    // CONSTRAINT 4: balance >= minimumValue
    component gte = GreaterEqThan(252);
    gte.in[0] <== balance;
    gte.in[1] <== minimumValue;
    gte.out === 1;
}

component main {public [attestationRoot, assetId, minimumValue]}
    = CollateralProof(10);  // 10-level tree = 1024 leaves (sufficient for MVP)
