// SPDX-License-Identifier: MIT
pragma solidity 0.5.17;

import {ECVerify} from "../lib/ECVerify.sol";
import {ERC20} from "../oz/token/ERC20/ERC20.sol";
import {IERC20Permit} from "./../misc/IERC20Permit.sol";

// only meant for testing, adapted from:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/extensions/ERC20Permit.sol
// modifications:
// - check EIP712
// - replaced custom errors with strings
// - compress v,r,s for ECDSA.recover (redundant work, only meant for testing)

contract ERC20ValidatorShare is ERC20, IERC20Permit {
    // @todo put all of these into a slot to avoid storage collision
    mapping(address => uint256) private _nonces;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    // EIP712
    /* solhint-disable var-name-mixedcase */
    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private _CACHED_DOMAIN_SEPARATOR;
    uint256 private _CACHED_CHAIN_ID;

    bytes32 private _HASHED_NAME;
    bytes32 private _HASHED_VERSION;
    bytes32 private _TYPE_HASH;

    string private _VERSION = "1";
    /* solhint-enable var-name-mixedcase */


    // overriden in parent contract
    function name() public view returns (string memory) {}

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

        if (_chainId() != _CACHED_CHAIN_ID) {
            _cacheDomainSeparatorV4();
        }

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECVerify.ecrecovery(hash, v, r, s);
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
        return _CACHED_DOMAIN_SEPARATOR;
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

    function eip712Version() public view returns (string memory) {
        return _VERSION;
    }

    function _chainId() public pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    function _cacheDomainSeparatorV4() public returns (bytes32) {
        bytes32 hashedName = keccak256(bytes(name()));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));
        _TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = _chainId();
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator();
        return _CACHED_DOMAIN_SEPARATOR;
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION, _chainId(), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _toTypedDataHash(_CACHED_DOMAIN_SEPARATOR, structHash);
    }

    function _toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // utils
    function _toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 4;
        }
        bytes memory buffer = new bytes(length);
        for (uint256 i = length; i > 0; --i) {
            buffer[i - 1] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}
