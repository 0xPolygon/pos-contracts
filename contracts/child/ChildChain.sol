pragma solidity ^0.5.2;

import {Ownable} from "../common/oz/ownership/Ownable.sol";

import {StateSyncerVerifier} from "./bor/StateSyncerVerifier.sol";
import {StateReceiver} from "./bor/StateReceiver.sol";

// This is the immutable, non-upgradeable plasma ChildChain deployed at
// 0xD9c7C4ED4B66858301D0cb28Cc88bf655Fe34861 (solc 0.5.11, bor-chain-id 137).
// Its bytecode embeds the CREATION code of the child tokens it auto-deploys via
// `new ChildERC20(...)` / `new ChildERC721(...)`, so it must reference the
// PRE-REFACTOR token code (parentOwner ownership, "Matic Network"/v1 EIP712, no
// StateSyncer/onStateReceive) to reproduce byte-for-byte. That old token code
// lives in contracts/child/legacy/*. The modern ChildERC20/ChildERC721 in
// contracts/child/ are the base for the live proxified child-token path and
// must not be embedded here. Logic below is otherwise unchanged.
import {ChildTokenLegacy as ChildToken} from "./legacy/ChildTokenLegacy.sol";
import {ChildERC20Legacy as ChildERC20} from "./legacy/ChildERC20Legacy.sol";
import {ChildERC721Legacy as ChildERC721} from "./legacy/ChildERC721Legacy.sol";

contract ChildChain is Ownable, StateSyncerVerifier, StateReceiver {
    // mapping for (root token => child token)
    mapping(address => address) public tokens;
    mapping(address => bool) public isERC721;
    mapping(uint256 => bool) public deposits;
    mapping(uint256 => bool) public withdraws;

    event NewToken(address indexed rootToken, address indexed token, uint8 _decimals);

    event TokenDeposited(
        address indexed rootToken,
        address indexed childToken,
        address indexed user,
        uint256 amount,
        uint256 depositCount
    );

    event TokenWithdrawn(
        address indexed rootToken,
        address indexed childToken,
        address indexed user,
        uint256 amount,
        uint256 withrawCount
    );

    constructor() public {
        //Mapping matic Token
        tokens[0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0] = 0x0000000000000000000000000000000000001010;
    }

    function onStateReceive(uint256, /* id */ bytes calldata data) external onlyStateSyncer {
        (address user, address rootToken, uint256 amountOrTokenId, uint256 depositId) =
            abi.decode(data, (address, address, uint256, uint256));
        depositTokens(rootToken, user, amountOrTokenId, depositId);
    }

    function addToken(
        address _owner,
        address _rootToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        bool _isERC721
    ) public onlyOwner returns (address token) {
        // check if root token already exists
        require(tokens[_rootToken] == address(0x0), "Token already mapped");

        // create new token contract
        if (_isERC721) {
            token = address(new ChildERC721(_owner, _rootToken, _name, _symbol));
            isERC721[_rootToken] = true;
        } else {
            token = address(new ChildERC20(_owner, _rootToken, _name, _symbol, _decimals));
        }

        // add mapping with root token
        tokens[_rootToken] = token;

        // broadcast new token's event
        emit NewToken(_rootToken, token, _decimals);
    }

    // for testnet updates remove for mainnet
    function mapToken(address rootToken, address token, bool isErc721) public onlyOwner {
        tokens[rootToken] = token;
        isERC721[rootToken] = isErc721;
    }

    function withdrawTokens(
        address rootToken,
        address user,
        uint256 amountOrTokenId,
        uint256 withdrawCount
    ) public onlyOwner {
        // check if withdrawal happens only once
        require(withdraws[withdrawCount] == false);

        // set withdrawal flag
        withdraws[withdrawCount] = true;

        // retrieve child tokens
        address childToken = tokens[rootToken];

        // check if child token is mapped
        require(childToken != address(0x0), "child token is not mapped");

        ChildToken obj;

        if (isERC721[rootToken]) {
            obj = ChildERC721(childToken);
        } else {
            obj = ChildERC20(childToken);
        }
        // withdraw tokens
        obj.withdraw(amountOrTokenId);

        // Emit TokenWithdrawn event
        emit TokenWithdrawn(rootToken, childToken, user, amountOrTokenId, withdrawCount);
    }

    function depositTokens(address rootToken, address user, uint256 amountOrTokenId, uint256 depositId) internal {
        // check if deposit happens only once
        require(deposits[depositId] == false);

        // set deposit flag
        deposits[depositId] = true;

        // retrieve child tokens
        address childToken = tokens[rootToken];

        // check if child token is mapped
        require(childToken != address(0x0));

        ChildToken obj;

        if (isERC721[rootToken]) {
            obj = ChildERC721(childToken);
        } else {
            obj = ChildERC20(childToken);
        }

        // deposit tokens
        obj.deposit(user, amountOrTokenId);

        // Emit TokenDeposited event
        emit TokenDeposited(rootToken, childToken, user, amountOrTokenId, depositId);
    }
}
