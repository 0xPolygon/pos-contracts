pragma solidity 0.5.17;

import "./BaseERC20NoSig.sol";

/**
 * @title Polygon Network Token contract
 * @notice This contract is an ECR20 like wrapper over native gas token transfers on the Polygon PoS chain
 * @dev ERC20 methods have been made payable while keeping their method signature same as other ChildERC20s on PoS
 */
contract MRC20 is BaseERC20NoSig {
    event Transfer(address indexed from, address indexed to, uint256 value);

    uint256 public currentSupply = 0;
    uint8 private constant DECIMALS = 18;
    bool isInitialized;

    uint256 locked = 1; // append to storage layout
    modifier nonReentrant() {
        require(locked == 1, "reentrancy");
        locked = 2;
        _;
        locked = 1;
    }

    constructor() public {}

    function initialize(address _childChain, address _token) public {
        require(!isInitialized, "The contract is already initialized");
        isInitialized = true;
        token = _token;
        _transferOwnership(_childChain);
    }

    function setParent(address) public {
        revert("Disabled feature");
    }

    function deposit(address user, uint256 amount) public onlyOwner {
        // check for amount and user
        require(
            amount > 0 && user != address(0x0),
            "Insufficient amount or invalid user"
        );

        // input balance
        uint256 input1 = balanceOf(user);
        currentSupply = currentSupply.add(amount);

        // transfer amount to user
        // not reenterant since this method is only called by commitState on StateReceiver which is onlySystem
        _nativeTransfer(user, amount);

        // deposit events
        emit Deposit(token, user, amount, input1, balanceOf(user));
    }

    function withdraw(uint256 amount) public payable {
        address user = msg.sender;
        // input balance
        uint256 input = balanceOf(user);

        currentSupply = currentSupply.sub(amount);
        // check for amount
        require(
            amount > 0 && msg.value == amount,
            "Insufficient amount"
        );

        // withdraw event
        emit Withdraw(token, user, amount, input, balanceOf(user));
    }

    function name() public pure returns (string memory) {
        return "Polygon Network Token";
    }

    function symbol() public pure returns (string memory) {
        return "POL";
    }

    function decimals() public pure returns (uint8) {
        return DECIMALS;
    }

    function totalSupply() public pure returns (uint256) {
        return 10000000000 * 10**uint256(DECIMALS);
    }

    function balanceOf(address account) public view returns (uint256) {
        return account.balance;
    }

    /// @dev Function that is called when a user or another contract wants to transfer funds.
    /// @param to Address of token receiver.
    /// @param value Number of tokens to transfer.
    /// @return Returns success of function call.
    function transfer(address to, uint256 value) public payable returns (bool) {
        if (msg.value != value) {
            return false;
        }
        return _transferFrom(msg.sender, to, value);
    }

    /**
   * @dev _transfer is invoked by _transferFrom method that is inherited from BaseERC20.
   * This enables us to transfer Polygon ETH between users while keeping the interface same as that of an ERC20 Token.
   */
    function _transfer(address sender, address recipient, uint256 amount)
        internal
    {
        require(recipient != address(this), "can't send to MRC20");
        _nativeTransfer(recipient, amount);
        emit Transfer(sender, recipient, amount);
    }

    // @notice method to transfer native asset to receiver (nonReentrant)
    // @dev 5000 gas is forwarded in the call to receiver
    // @dev msg.value checks (if req), emitting logs are handled seperately
    // @param receiver address to transfer native token to
    // @param amount amount of native token to transfer
    function _nativeTransfer(address receiver, uint256 amount) internal nonReentrant {
        uint256 txGasLimit = 5000;
        (bool success, bytes memory ret) = receiver.call.value(amount).gas(txGasLimit)("");
        if (!success) {
            assembly {
                revert(add(ret, 0x20), mload(ret)) // bubble up revert
            }
        }
    }
}
