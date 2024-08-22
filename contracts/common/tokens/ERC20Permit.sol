// SPDX-License-Identifier: MIT
pragma solidity 0.5.17;

import {ECDSA} from "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";
import {TestToken} from "./TestToken.sol";
import {EIP712} from "./../misc/EIP712.sol";
import {IERC20Permit} from "./../misc/IERC20Permit.sol";

// only meant for testing, adapted from: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/extensions/ERC20Permit.sol
// modifications:
// - check EIP712
// - replaced custom errors with strings
// - compress v,r,s for ECDSA.recover (redundant work, only meant for testing)

contract ERC20Permit is TestToken, IERC20Permit, EIP712 {
    mapping(address => uint256) private _nonces;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _version
    ) public TestToken(_name, _symbol) EIP712(_name, _version) {}

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        if (block.timestamp > deadline) {
            revert("ERC2612ExpiredSignature");
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, _compress(v, r, s));
        if (signer != owner) {
            revert("ERC2612InvalidSigner");
        }

        _approve(owner, spender, value);
    }

    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _useNonce(address owner) private returns (uint256 current) {
        current = _nonces[owner];
        _nonces[owner] = current + 1;
    }

    function _compress(uint8 v, bytes32 r, bytes32 s) private pure returns (bytes memory) {
        bytes memory signature = new bytes(65);

        assembly {
            mstore(add(signature, 0x20), r)
            mstore(add(signature, 0x40), s)
            mstore8(add(signature, 0x60), v)
        }

        return signature;
    }
}
