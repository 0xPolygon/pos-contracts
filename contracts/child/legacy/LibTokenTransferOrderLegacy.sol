// SPDX-License-Identifier: MIT
pragma solidity ^0.5.2;

import {LibEIP712DomainLegacy} from "./EIP712Legacy.sol";

// FROZEN. Reproduces the old on-chain child-token code embedded in the immutable
// plasma ChildChain 0xD9c7C4ED4B66858301D0cb28Cc88bf655Fe34861 (solc 0.5.11,
// bor-chain-id 137). Do not edit.
//
// The body is byte-identical to the modern misc/LibTokenTransferOrder.sol; the
// only reason a legacy copy exists is to re-parent onto LibEIP712DomainLegacy so
// the legacy token stack resolves the "Matic Network"/v1 domain instead of the
// modern one.
contract LibTokenTransferOrderLegacy is LibEIP712DomainLegacy {
    string internal constant EIP712_TOKEN_TRANSFER_ORDER_SCHEMA =
        "TokenTransferOrder(address spender,uint256 tokenIdOrAmount,bytes32 data,uint256 expiration)";
    bytes32 public constant EIP712_TOKEN_TRANSFER_ORDER_SCHEMA_HASH =
        keccak256(abi.encodePacked(EIP712_TOKEN_TRANSFER_ORDER_SCHEMA));

    struct TokenTransferOrder {
        address spender;
        uint256 tokenIdOrAmount;
        bytes32 data;
        uint256 expiration;
    }

    function getTokenTransferOrderHash(
        address spender,
        uint256 tokenIdOrAmount,
        bytes32 data,
        uint256 expiration
    ) public view returns (bytes32 orderHash) {
        orderHash = hashEIP712Message(hashTokenTransferOrder(spender, tokenIdOrAmount, data, expiration));
    }

    function hashTokenTransferOrder(
        address spender,
        uint256 tokenIdOrAmount,
        bytes32 data,
        uint256 expiration
    ) internal pure returns (bytes32 result) {
        bytes32 schemaHash = EIP712_TOKEN_TRANSFER_ORDER_SCHEMA_HASH;

        // Assembly for more efficiently computing:
        // return keccak256(abi.encode(
        //   schemaHash,
        //   spender,
        //   tokenIdOrAmount,
        //   data,
        //   expiration
        // ));

        assembly {
            // Load free memory pointer
            let memPtr := mload(64)

            mstore(memPtr, schemaHash) // hash of schema
            mstore(add(memPtr, 32), and(spender, 0xffffffffffffffffffffffffffffffffffffffff)) // spender
            mstore(add(memPtr, 64), tokenIdOrAmount) // tokenIdOrAmount
            mstore(add(memPtr, 96), data) // hash of data
            mstore(add(memPtr, 128), expiration) // expiration

            // Compute hash
            result := keccak256(memPtr, 160)
        }
        return result;
    }
}
