// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {ChildERC20Proxified} from "../helpers/interfaces/ChildERC20Proxified.generated.sol";
import {ChildERC721Proxified} from "../helpers/interfaces/ChildERC721Proxified.generated.sol";
import {DepositManager} from "../helpers/interfaces/DepositManager.generated.sol";

contract MaticDeposit is Script {
    string path = "contractAddresses.json";
    string json = vm.readFile(path);

    function run(address addr, address rootToken, uint256 amount) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        depositERC20(addr, rootToken, amount);

        vm.stopBroadcast();
    }

    function checkDepositedERC20Balance(address addr, address token) public {
        ChildERC20Proxified childToken = ChildERC20Proxified(token);
        uint256 balance = childToken.balanceOf(addr);
        console.log("Balance of given address: ", balance);
    }

    function checkDepositedERC721Balance(address addr, address token, uint256 tokenID) public {
        ChildERC721Proxified childToken = ChildERC721Proxified(token);
        address owner = childToken.ownerOf(tokenID);
        console.log("Owner of given NFT: ", owner, ", but should be: ", addr);
    }

    function depositERC20(address addr, address rootToken, uint256 amount) public {
        console.log("Deposit ERC20: ");
        console.log("Token: ", rootToken);
        console.log("Amount: ", amount);
        ChildERC20Proxified childToken = ChildERC20Proxified(rootToken);
        uint256 b = childToken.balanceOf(addr);
        console.log("Balance of cuurent address: ", b);

        DepositManager depositManager = DepositManager(payable(vm.parseJsonAddress(json, ".root.DepositManagerProxy")));
        childToken.approve(address(depositManager), amount);
        console.log("Tokens Approved!");

        depositManager.depositERC20(rootToken, amount);
        console.log("Success!");
    }
}
