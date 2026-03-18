// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Script, stdJson, console} from "forge-std/Script.sol";

import {ERC20Permit} from "../helpers/interfaces/ERC20Permit.generated.sol";
import {StakeManager} from "../helpers/interfaces/StakeManager.generated.sol";

contract MaticStake is Script {
    string path = "contractAddresses.json";
    string json = vm.readFile(path);

    function run(address validatorAccount, bytes memory pubkey, uint256 stakeAmount, uint256 heimdallFee) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        stake(validatorAccount, pubkey, stakeAmount, heimdallFee);

        vm.stopBroadcast();
    }

    function stake(address _validatorAccount, bytes memory _pubkey, uint256 _stakeAmount, uint256 _heimdallFee) public {
        address validatorAccount = _validatorAccount;
        bytes memory pubkey = _pubkey;
        uint256 stakeAmount = _stakeAmount;
        uint256 heimdallFee = _heimdallFee;

        console.log("StakeAmount: ", stakeAmount, " for validatorAccount: ", validatorAccount);

        StakeManager stakeManager = StakeManager(vm.parseJsonAddress(json, ".root.StakeManagerProxy"));
        console.log("StakeManager address: ", address(stakeManager));
        ERC20Permit polToken = ERC20Permit(vm.parseJsonAddress(json, ".root.tokens.PolToken"));
        console.log("Sender account POL balance: ", polToken.balanceOf(validatorAccount));

        polToken.approve(address(stakeManager), type(uint256).max);
        console.log("Sent approve tx, staking now...");

        console.log("Validator set size: ", stakeManager.currentValidatorSetSize());

        stakeManager.stakeForPOL(validatorAccount, stakeAmount, heimdallFee, true, pubkey);
        console.log("Staking successful!");
    }
}
