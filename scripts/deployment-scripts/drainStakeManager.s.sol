// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Script, stdJson, console} from "forge-std/Script.sol";

import {DrainStakeManager} from "../helpers/interfaces/DrainStakeManager.generated.sol";

contract DrainStakeManagerDeployment is Script {
    DrainStakeManager drainStakeManager;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // DrainStakeManager deployment:
        drainStakeManager = DrainStakeManager(payable(deployCode("out/DrainStakeManager.sol/DrainStakeManager.json")));
        console.log("DrainStakeManager address: ", address(drainStakeManager));

        vm.stopBroadcast();
    }
}
