// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Script, stdJson, console} from "forge-std/Script.sol";

import {TestToken} from "../helpers/interfaces/TestToken.generated.sol";
import {StakeManager} from "../helpers/interfaces/StakeManager.generated.sol";
import {IERC20} from "../helpers/interfaces/IERC20.generated.sol";

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
        TestToken maticToken = TestToken(vm.parseJsonAddress(json, ".root.tokens.MaticToken"));
        console.log("Sender account has a balance of: ", maticToken.balanceOf(validatorAccount));

        maticToken.approve(address(stakeManager), 10 ** 20);
        console.log("sent approve tx, staking now...");

        stakeManager.stakeForPOL(validatorAccount, stakeAmount, heimdallFee, true, pubkey);

        console.log("Validator set size: ", stakeManager.currentValidatorSetSize());
    }

    function topUpForFee() public {
        address stakeFor = vm.envAddress("VALIDATOR_1");
        uint256 amount = 10 ** 20;

        StakeManager stakeManager = StakeManager(vm.parseJsonAddress(json, ".stakeManager"));
        TestToken rootToken = TestToken(vm.parseJsonAddress(json, ".maticToken"));
        rootToken.approve(vm.parseJsonAddress(json, ".stakeManagerProxy"), amount);

        console.log("Approved!, staking now...");

        uint256 validatorId = stakeManager.signerToValidator(stakeFor);
        console.log("Validator ID : ", validatorId);
        stakeManager.topUpForFee(stakeFor, amount);

        console.log("Success!");
    }
}
