address SFC {
module EthStateVerifier {
    use SFC::RLP;
    use StarcoinFramework::Vector;
    use StarcoinFramework::Hash;
    use SFC::Bytes;

    const INVALID_PROOF: u64 = 400;

    public fun to_nibble(b: u8): (u8, u8) {
        let n1 = b >> 4;
        let n2 = (b << 4) >> 4;
        (n1, n2)
    }
    public fun to_nibbles(bytes: &vector<u8>): vector<u8> {
        let result = Vector::empty<u8>();
        let i = 0;
        let data_len = Vector::length(bytes);
        while (i < data_len) {
            let (a, b) = to_nibble(*Vector::borrow(bytes, i));
            Vector::push_back(&mut result, a);
            Vector::push_back(&mut result, b);
            i = i + 1;
        };

        result
    }

    fun verify_inner(
        expected_root: vector<u8>,
        key: vector<u8>,
        proof: vector<vector<u8>>,
        expected_value: vector<u8>,
        key_index: u64,
        proof_index: u64,
    ): bool {
        if (proof_index >= Vector::length(&proof)) {
            return false
        };

        let node = Vector::borrow(&proof, proof_index);
        let dec = RLP::decode_list(node);
        // trie root is always a hash
        if (key_index == 0 || Vector::length(node) >= 32u64) {
            if (Hash::keccak_256(*node) != expected_root) {
                return false
            }
        } else {
            // and if rlp < 32 bytes, then it is not hashed
            let root = Vector::borrow(&dec, 0);
            if (root != &expected_root) {
                return false
            }
        };
        let rlp_len = Vector::length(&dec);
        // branch node.
        if (rlp_len == 17) {
            if (key_index >= Vector::length(&key)) {
                // value stored in the branch
                let item = Vector::borrow(&dec, 16);
                if (item == &expected_value) {
                    return true
                }
            } else {
                // down the rabbit hole.
                let index = Vector::borrow(&key, key_index);
                let new_expected_root = Vector::borrow(&dec, (*index as u64));
                if (Vector::length(new_expected_root) != 0) {
                    return verify_inner(*new_expected_root, key, proof, expected_value, key_index + 1, proof_index + 1)
                }
            };
        } else if (rlp_len == 2) {
            let node_key = Vector::borrow(&dec, 0);
            let node_value = Vector::borrow(&dec, 1);
            let (prefix, nibble) = to_nibble(*Vector::borrow(node_key, 0));

            if (prefix == 0) {
                // even extension node
                let shared_nibbles = to_nibbles(&Bytes::slice(node_key, 1, Vector::length(node_key)));
                let extension_length = Vector::length(&shared_nibbles);
                if (shared_nibbles ==
                    Bytes::slice(&key, key_index, key_index + extension_length)) {
                        return verify_inner(*node_value, key, proof, expected_value, key_index + extension_length, proof_index + 1)
                }
            } else if (prefix == 1) {
                // odd extension node
                let shared_nibbles = to_nibbles(&Bytes::slice(node_key, 1, Vector::length(node_key)));
                let extension_length = Vector::length(&shared_nibbles);
                if (nibble == *Vector::borrow(&key, key_index) &&
                    shared_nibbles ==
                        Bytes::slice(
                            &key,
                            key_index + 1,
                            key_index + 1 + extension_length,
                        )) {
                    return verify_inner(*node_value, key, proof, expected_value, key_index + 1 + extension_length, proof_index + 1)
                };
            } else if (prefix == 2) {
                // even leaf node
                let shared_nibbles = to_nibbles(&Bytes::slice(node_key, 1, Vector::length(node_key)));
                return shared_nibbles == Bytes::slice(&key, key_index, Vector::length(&key)) && &expected_value == node_value
            } else if (prefix == 3) {
                // odd leaf node
                let shared_nibbles = to_nibbles(&Bytes::slice(node_key, 1, Vector::length(node_key)));
                return &expected_value == node_value &&
                    nibble == *Vector::borrow(&key, key_index) &&
                     shared_nibbles ==
                        Bytes::slice(&key, key_index + 1, Vector::length(&key))
            } else {
                // invalid proof
                abort INVALID_PROOF
            };
        };
        return Vector::length(&expected_value) == 0
    }

    public fun verify(
        expected_root: vector<u8>,
        key: vector<u8>,
        proof: vector<vector<u8>>,
        expected_value: vector<u8>,
    ): bool {
        let hashed_key = Hash::keccak_256(key);
        let key = to_nibbles(&hashed_key);
        return verify_inner(expected_root, key, proof, expected_value, 0, 0)
    }
}
}