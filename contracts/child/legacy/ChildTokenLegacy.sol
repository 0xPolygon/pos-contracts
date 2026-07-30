// SPDX-License-Identifier: MIT
pragma solidity ^0.5.2;

import {SafeMath} from "../../common/oz/math/SafeMath.sol";
import {Ownable} from "../../common/oz/ownership/Ownable.sol";

import {LibTokenTransferOrderLegacy} from "./LibTokenTransferOrderLegacy.sol";

// FROZEN. Reproduces the old on-chain child-token code embedded in the immutable
// plasma ChildChain 0xD9c7C4ED4B66858301D0cb28Cc88bf655Fe34861 (solc 0.5.11,
// bor-chain-id 137). Do not edit.
//
// Old-code markers preserved vs the modern ChildToken.sol:
//   - `parentOwner` + `isParentOwner` modifier (modern uses `childChain` +
//     `onlyChildChain`)
//   - abstract `setParent(address)` (modern has a concrete setParent w/ event)
//   - NO StateSyncer/StateReceiver wiring, NO changeChildChain
contract ChildTokenLegacy is Ownable, LibTokenTransferOrderLegacy {
    using SafeMath for uint256;

    // ERC721/ERC20 contract token address on root chain
    address public token;
    address public parent;
    address public parentOwner;

    mapping(bytes32 => bool) public disabledHashes;

    modifier isParentOwner() {
        require(msg.sender == parentOwner);
        _;
    }

    function deposit(address user, uint256 amountOrTokenId) public;
    function withdraw(uint256 amountOrTokenId) public payable;
    function setParent(address _parent) public;

    event LogFeeTransfer(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 input1,
        uint256 input2,
        uint256 output1,
        uint256 output2
    );

    function ecrecovery(bytes32 hash, bytes memory sig) public pure returns (address result) {
        bytes32 r;
        bytes32 s;
        uint8 v;
        if (sig.length != 65) {
            return address(0x0);
        }
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := and(mload(add(sig, 65)), 255)
        }
        // https://github.com/ethereum/go-ethereum/issues/2053
        if (v < 27) {
            v += 27;
        }
        if (v != 27 && v != 28) {
            return address(0x0);
        }
        // get address out of hash and signature
        result = ecrecover(hash, v, r, s);
        // ecrecover returns zero on error
        require(result != address(0x0), "Error in ecrecover");
    }
}
