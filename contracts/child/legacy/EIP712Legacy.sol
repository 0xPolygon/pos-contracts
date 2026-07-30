// SPDX-License-Identifier: MIT
pragma solidity ^0.5.2;

import {ChainIdMixin} from "../../common/mixin/ChainIdMixin.sol";

// FROZEN. Reproduces the old on-chain child-token EIP712 base embedded in the
// immutable plasma ChildChain 0xD9c7C4ED4B66858301D0cb28Cc88bf655Fe34861
// (solc 0.5.11, bor-chain-id 137). Do not edit.
//
// Old-code markers preserved vs the modern misc/EIP712.sol:
//   - domain name "Matic Network" / version "1" (modern is "Polygon Ecosystem
//     Token" / "2")
//   - hashEIP712Message with the domain hash cached in EIP712_DOMAIN_HASH
//   - NO hashEIP712MessageWithAddress helper (added in the modern refactor)
contract LibEIP712DomainLegacy is ChainIdMixin {
    string internal constant EIP712_DOMAIN_SCHEMA =
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    bytes32 public constant EIP712_DOMAIN_SCHEMA_HASH = keccak256(abi.encodePacked(EIP712_DOMAIN_SCHEMA));

    string internal constant EIP712_DOMAIN_NAME = "Matic Network";
    string internal constant EIP712_DOMAIN_VERSION = "1";
    uint256 internal constant EIP712_DOMAIN_CHAINID = CHAINID;

    bytes32 public EIP712_DOMAIN_HASH;

    constructor() public {
        EIP712_DOMAIN_HASH = keccak256(
            abi.encode(
                EIP712_DOMAIN_SCHEMA_HASH,
                keccak256(bytes(EIP712_DOMAIN_NAME)),
                keccak256(bytes(EIP712_DOMAIN_VERSION)),
                EIP712_DOMAIN_CHAINID,
                address(this)
            )
        );
    }

    function hashEIP712Message(bytes32 hashStruct) internal view returns (bytes32 result) {
        bytes32 domainHash = EIP712_DOMAIN_HASH;

        // Assembly for more efficient computing:
        // keccak256(abi.encode(
        //     EIP191_HEADER,
        //     domainHash,
        //     hashStruct
        // ));

        assembly {
            // Load free memory pointer
            let memPtr := mload(64)

            mstore(memPtr, 0x1901000000000000000000000000000000000000000000000000000000000000) // EIP191 header
            mstore(add(memPtr, 2), domainHash) // EIP712 domain hash
            mstore(add(memPtr, 34), hashStruct) // Hash of struct

            // Compute hash
            result := keccak256(memPtr, 66)
        }
        return result;
    }
}
