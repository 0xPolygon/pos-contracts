// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Script, stdJson, console} from "forge-std/Script.sol";

import {TestToken} from "../helpers/interfaces/TestToken.generated.sol";
import {StakeManager} from "../helpers/interfaces/StakeManager.generated.sol";
import {IERC20} from "../helpers/interfaces/IERC20.generated.sol";

contract MaticStakeTest is Script {
    string path = "contractAddresses.json";
    string json = vm.readFile(path);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        stake();

        vm.stopBroadcast();
    }

    function stake() public {
        address validatorAccount = vm.envAddress("VALIDATOR");
        bytes memory pubkey = vm.envBytes("VALIDATOR_PUB_KEY");
        uint256 stakeAmount = vm.envUint("STAKE_AMOUNT");
        uint256 heimdallFee = vm.envUint("HEIMDALL_FEE");

        console.log("StakeAmount: ", stakeAmount, " for validatorAccount: ", validatorAccount);

        StakeManager stakeManager = StakeManager(0x4AE8f648B1Ec892B6cc68C89cc088583964d08bE);
        console.log("StakeManager address: ", address(stakeManager));
        TestToken maticToken = TestToken(0x3fd0A53F4Bf853985a95F4Eb3F9C9FDE1F8e2b53);
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
