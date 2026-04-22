// CollateralProof in Noir
//
// Proves: "I control >= minimumValue of a registered asset"
// without revealing: actual balance, identity, or other positions.
//
// Public inputs: attestation_root, asset_id, minimum_value, nav_price
// Private inputs: balance, secret, path_elements, path_indices

global TREE_DEPTH: u32 = 10;

fn poseidon_hash_1(input: Field) -> Field {
    std::hash::pedersen_hash([input])
}

fn poseidon_hash_2(a: Field, b: Field) -> Field {
    std::hash::pedersen_hash([a, b])
}

fn poseidon_hash_3(a: Field, b: Field, c: Field) -> Field {
    std::hash::pedersen_hash([a, b, c])
}

fn main(
    attestation_root: pub Field,
    asset_id: pub Field,
    minimum_value: pub Field,
    nav_price: pub Field,
    balance: Field,
    secret: Field,
    path_elements: [Field; TREE_DEPTH],
    path_indices: [Field; TREE_DEPTH],
) {
    // 1. Compute owner commitment = Hash(secret)
    let commitment = poseidon_hash_1(secret);

    // 2. Compute leaf = Hash(commitment, balance, asset_id)
    let leaf = poseidon_hash_3(commitment, balance, asset_id);

    // 3. Verify Merkle inclusion
    let computed_root = compute_merkle_root(leaf, path_elements, path_indices);
    assert(computed_root == attestation_root, "Merkle proof invalid");

    // 4. balance >= minimum_value
    let balance_u64 = balance as u64;
    let min_u64 = minimum_value as u64;
    assert(balance_u64 >= min_u64, "Balance below minimum");

    // 5. nav_price must be non-zero
    assert(nav_price != 0, "NAV price cannot be zero");
}

fn compute_merkle_root(
    leaf: Field,
    path_elements: [Field; TREE_DEPTH],
    path_indices: [Field; TREE_DEPTH],
) -> Field {
    let mut current = leaf;
    for i in 0..TREE_DEPTH {
        let sibling = path_elements[i];
        let index = path_indices[i];
        assert((index == 0) | (index == 1), "Path index must be 0 or 1");
        if index == 0 {
            current = poseidon_hash_2(current, sibling);
        } else {
            current = poseidon_hash_2(sibling, current);
        }
    }
    current
}

#[test]
fn test_balance_above_minimum() {
    let secret = 12345;
    let balance: Field = 1000;
    let asset_id: Field = 42;
    let minimum_value: Field = 500;
    let nav_price: Field = 1;

    let commitment = poseidon_hash_1(secret);
    let leaf = poseidon_hash_3(commitment, balance, asset_id);
    let path_elements = [0; TREE_DEPTH];
    let path_indices = [0; TREE_DEPTH];
    let root = compute_merkle_root(leaf, path_elements, path_indices);

    main(root, asset_id, minimum_value, nav_price, balance, secret, path_elements, path_indices);
}

#[test]
fn test_exact_minimum() {
    let secret = 99999;
    let balance: Field = 500;
    let asset_id: Field = 1;
    let minimum_value: Field = 500;
    let nav_price: Field = 100;

    let commitment = poseidon_hash_1(secret);
    let leaf = poseidon_hash_3(commitment, balance, asset_id);
    let path_elements = [0; TREE_DEPTH];
    let path_indices = [0; TREE_DEPTH];
    let root = compute_merkle_root(leaf, path_elements, path_indices);

    main(root, asset_id, minimum_value, nav_price, balance, secret, path_elements, path_indices);
}

#[test(should_fail_with = "Balance below minimum")]
fn test_balance_below_minimum_fails() {
    let secret = 77777;
    let balance: Field = 100;
    let asset_id: Field = 1;
    let minimum_value: Field = 500;
    let nav_price: Field = 1;

    let commitment = poseidon_hash_1(secret);
    let leaf = poseidon_hash_3(commitment, balance, asset_id);
    let path_elements = [0; TREE_DEPTH];
    let path_indices = [0; TREE_DEPTH];
    let root = compute_merkle_root(leaf, path_elements, path_indices);

    main(root, asset_id, minimum_value, nav_price, balance, secret, path_elements, path_indices);
}

#[test(should_fail_with = "Merkle proof invalid")]
fn test_wrong_root_fails() {
    let secret = 55555;
    let balance: Field = 1000;
    let asset_id: Field = 42;
    let minimum_value: Field = 100;
    let nav_price: Field = 1;

    let commitment = poseidon_hash_1(secret);
    let leaf = poseidon_hash_3(commitment, balance, asset_id);
    let path_elements = [0; TREE_DEPTH];
    let path_indices = [0; TREE_DEPTH];

    let wrong_root: Field = 999;
    main(wrong_root, asset_id, minimum_value, nav_price, balance, secret, path_elements, path_indices);
}

#[test(should_fail_with = "NAV price cannot be zero")]
fn test_zero_nav_fails() {
    let secret = 11111;
    let balance: Field = 1000;
    let asset_id: Field = 42;
    let minimum_value: Field = 100;
    let nav_price: Field = 0;

    let commitment = poseidon_hash_1(secret);
    let leaf = poseidon_hash_3(commitment, balance, asset_id);
    let path_elements = [0; TREE_DEPTH];
    let path_indices = [0; TREE_DEPTH];
    let root = compute_merkle_root(leaf, path_elements, path_indices);

    main(root, asset_id, minimum_value, nav_price, balance, secret, path_elements, path_indices);
}
