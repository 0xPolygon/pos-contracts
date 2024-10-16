pragma solidity ^0.5.2;

import {ERC721Holder} from "openzeppelin-solidity/contracts/token/ERC721/ERC721Holder.sol";
import {IERC20} from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import {SafeMath} from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import {SafeERC20} from "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";

import {Registry} from "../../common/Registry.sol";
import {WETH} from "../../common/tokens/WETH.sol";
import {IDepositManager} from "./IDepositManager.sol";
import {DepositManagerStorage} from "./DepositManagerStorage.sol";
import {StateSender} from "../stateSyncer/StateSender.sol";
import {GovernanceLockable} from "../../common/mixin/GovernanceLockable.sol";
import {RootChain} from "../RootChain.sol";

interface IPolygonMigration {
    function migrate(uint256 amount) external;
}


contract DepositManager is DepositManagerStorage, IDepositManager, ERC721Holder {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    modifier isTokenMapped(address _token) {
        require(
            registry.isTokenMapped(_token),
            "TOKEN_NOT_SUPPORTED"
        );
        _;
    }

    modifier isPredicateAuthorized() {
        require(uint8(registry.predicates(msg.sender)) != 0, "Not a valid predicate");
        _;
    }

    constructor() public GovernanceLockable(address(0x0)) {}

    // deposit ETH by sending to this contract
    function() external payable {
        depositEther();
    }

    // new: governance function to migrate MATIC to POL
    function migrateMatic() external onlyGovernance {
        IERC20 matic = IERC20(registry.contractMap(keccak256("matic")));
        _migrateMatic(matic.balanceOf(address(this)));
    }

    function _migrateMatic(uint256 _amount) private {
        IERC20 matic = IERC20(registry.contractMap(keccak256("matic")));
        address polygonMigration = registry.contractMap(keccak256("polygonMigration"));

        // check that _amount is not too high
        require(matic.balanceOf(address(this)) >= _amount, "amount exceeds this contract's MATIC balance");

        // approve
        matic.approve(polygonMigration, _amount);

        // call migrate function
        IPolygonMigration(polygonMigration).migrate(_amount);
    }

    function updateMaxErc20Deposit(uint256 maxDepositAmount) public onlyGovernance {
        require(maxDepositAmount != 0);
        emit MaxErc20DepositUpdate(maxErc20Deposit, maxDepositAmount);
        maxErc20Deposit = maxDepositAmount;
    }

    function transferAssets(address _token, address _user, uint256 _amountOrNFTId) external isPredicateAuthorized {
        address wethToken = registry.getWethTokenAddress();

        if (registry.isERC721(_token)) {
            IERC721(_token).transferFrom(address(this), _user, _amountOrNFTId);
        } else if (_token == wethToken) {
            WETH t = WETH(_token);
            t.withdraw(_amountOrNFTId, _user);
        } else {
            // new: pay out POL when MATIC is withdrawn
            if (_token == registry.contractMap(keccak256("matic"))) {
                require(
                    IERC20(registry.contractMap(keccak256("pol"))).transfer(_user, _amountOrNFTId),
                    "TRANSFER_FAILED"
                );
            } else {
                require(IERC20(_token).transfer(_user, _amountOrNFTId), "TRANSFER_FAILED");
            }
        }
    }

    function depositERC20(address _token, uint256 _amount) external {
        depositERC20ForUser(_token, msg.sender, _amount);
    }

    function depositERC721(address _token, uint256 _tokenId) external {
        depositERC721ForUser(_token, msg.sender, _tokenId);
    }

    function depositBulk(
        address[] calldata _tokens,
        uint256[] calldata _amountOrTokens,
        address _user
    )
        external
        onlyWhenUnlocked // unlike other deposit functions, depositBulk doesn't invoke _safeCreateDepositBlock
    {
        require(_tokens.length == _amountOrTokens.length, "Invalid Input");
        uint256 depositId = rootChain.updateDepositId(_tokens.length);
        Registry _registry = registry;

        for (uint256 i = 0; i < _tokens.length; i++) {
            // will revert if token is not mapped
            if (_registry.isTokenMappedAndIsErc721(_tokens[i])) {
                _safeTransferERC721(msg.sender, _tokens[i], _amountOrTokens[i]);
            } else {
                IERC20(_tokens[i]).safeTransferFrom(msg.sender, address(this), _amountOrTokens[i]);
            }

            _createDepositBlock(_user, _tokens[i], _amountOrTokens[i], depositId);
            depositId = depositId.add(1);
        }
    }

    /**
     * @dev Caches childChain and stateSender (frequently used variables) from registry
     */
    function updateChildChainAndStateSender() public {
        (address _childChain, address _stateSender) = registry.getChildChainAndStateSender();
        require(
            _stateSender != address(stateSender) || _childChain != childChain,
            "Atleast one of stateSender or childChain address should change"
        );
        childChain = _childChain;
        stateSender = StateSender(_stateSender);
    }

    function depositERC20ForUser(address _token, address _user, uint256 _amount) public {
        require(_amount <= maxErc20Deposit, "exceed maximum deposit amount");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        _safeCreateDepositBlock(_user, _token, _amount);
    }

    function depositERC721ForUser(address _token, address _user, uint256 _tokenId) public {
        require(registry.isTokenMappedAndIsErc721(_token), "not erc721");

        _safeTransferERC721(msg.sender, _token, _tokenId);
        _safeCreateDepositBlock(_user, _token, _tokenId);
    }

    // @todo: write depositEtherForUser
    function depositEther() public payable {
        address wethToken = registry.getWethTokenAddress();
        WETH t = WETH(wethToken);
        t.deposit.value(msg.value)();
        _safeCreateDepositBlock(msg.sender, wethToken, msg.value);
    }

    function _safeCreateDepositBlock(
        address _user,
        address _token,
        uint256 _amountOrToken
    ) internal onlyWhenUnlocked isTokenMapped(_token) {
        _createDepositBlock(_user, _token, _amountOrToken, rootChain.updateDepositId(1)); // returns _depositId
    }

    function _createDepositBlock(address _user, address _token, uint256 _amountOrToken, uint256 _depositId) internal {
        address matic = registry.contractMap(keccak256("matic"));

        // new: auto-migrate MATIC to POL
        if (_token == matic) {
            _migrateMatic(_amountOrToken);
        }
        // new: bridge POL as MATIC, child chain behaviour does not change
        else if (_token == registry.contractMap(keccak256("pol"))) {
            _token = matic;
        }

        deposits[_depositId] = DepositBlock(keccak256(abi.encodePacked(_user, _token, _amountOrToken)), now);
        stateSender.syncState(childChain, abi.encode(_user, _token, _amountOrToken, _depositId));
        emit NewDepositBlock(_user, _token, _amountOrToken, _depositId);
    }

    // Housekeeping function. @todo remove later
    function updateRootChain(address _rootChain) public onlyOwner {
        rootChain = RootChain(_rootChain);
    }

    function _safeTransferERC721(address _user, address _token, uint256 _tokenId) private {
        IERC721(_token).safeTransferFrom(_user, address(this), _tokenId);
    }
}
