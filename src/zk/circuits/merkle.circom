pragma circom 2.1.6;

include "../../../node_modules/circomlib/circuits/poseidon.circom";

// Merkle proof verification using Poseidon hash
// levels = depth of the tree
template MerkleProof(levels) {
    signal input leaf;
    signal input pathElements[levels];
    signal input pathIndices[levels];
    signal output root;

    component hashers[levels];
    signal hashes[levels + 1];
    hashes[0] <== leaf;

    for (var i = 0; i < levels; i++) {
        hashers[i] = Poseidon(2);

        // pathIndices[i] must be 0 or 1
        pathIndices[i] * (pathIndices[i] - 1) === 0;

        // if pathIndex == 0: hash(current, sibling)
        // if pathIndex == 1: hash(sibling, current)
        hashers[i].inputs[0] <== hashes[i] +
            (pathElements[i] - hashes[i]) * pathIndices[i];
        hashers[i].inputs[1] <== pathElements[i] +
            (hashes[i] - pathElements[i]) * pathIndices[i];

        hashes[i + 1] <== hashers[i].out;
    }

    root <== hashes[levels];
}
