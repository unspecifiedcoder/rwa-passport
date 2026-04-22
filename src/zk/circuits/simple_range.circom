pragma circom 2.1.6;

// SimpleRangeProof: Prove "I know a secret number >= minimumValue"
// without revealing the actual number.
//
// Public inputs:
//   minimumValue — The minimum value being claimed
//
// Private inputs:
//   actualValue  — The secret value

include "../../../node_modules/circomlib/circuits/comparators.circom";

template SimpleRangeProof() {
    signal input minimumValue;
    signal input actualValue;

    // actualValue >= minimumValue
    component gte = GreaterEqThan(252);
    gte.in[0] <== actualValue;
    gte.in[1] <== minimumValue;
    gte.out === 1;
}

component main {public [minimumValue]} = SimpleRangeProof();
