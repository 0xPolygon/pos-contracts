pragma solidity ^0.5.2;

import "../oz/token/ERC20/ERC20.sol";

contract WETH is ERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    function deposit() public payable;

    function withdraw(uint256 wad) public;

    function withdraw(uint256 wad, address user) public;
}
