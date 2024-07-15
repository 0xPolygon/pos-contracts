// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script, stdJson, console2 as console} from "forge-std/Script.sol";

//cast interface path/to/artifact/file.json
// import {
//     ProxyAdmin,
//     TransparentUpgradeableProxy,
//     ITransparentUpgradeableProxy
// } from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import { StakeManager } from "../helpers/interfaces/StakeManager.generated.sol";
import { StakeManagerProxy } from "../helpers/interfaces/StakeManagerProxy.generated.sol";
import { ValidatorShare } from "../helpers/interfaces/ValidatorShare.generated.sol";
import { Registry } from "../helpers/interfaces/Registry.generated.sol";

contract UpgradeStakeManager is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory input = vm.readFile("scripts/deployers/input.json");
        string memory chainIdSlug = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));
        address emProxyAddress = input.readAddress(string.concat(chainIdSlug, ".emissionManagerProxy"));
        address emProxyAdmin = input.readAddress(string.concat(chainIdSlug, ".emProxyAdmin"));
        address newTreasury = input.readAddress(string.concat(chainIdSlug, ".treasury"));

        vm.startBroadcast(deployerPrivateKey);

        StakeManager stakeManagerImpl;
        stakeManagerImpl = StakeManager(deployCode("out/StakeManager.sol/StakeManager.json"));

        console.log("deployed StakeManager Implementation at: ", address(stakeManagerImpl));

        ValidatorShare validatorShareImpl;
        validatorShareImpl = ValidatorShare(deployCode("out/ValidatorShare.sol/ValidatorShare.json"));


        console.log("deployed ValidatorShare Implementation at: ", address(validatorShareImpl));
        
        vm.stopBroadcast();

        Registry registry = Registry(0x33a02E6cC863D393d6Bf231B697b82F6e499cA71);
        console.log("found Registry at: ", address(registry));

        StakeManagerProxy stakeManagerProxy = StakeManagerProxy(0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908);
        console.log("found StakeManagerProxy at: ", address(stakeManagerProxy));



        // set registry valshare value
        // set proxy impl
        // call initLegacy

        // bytes memory payloadReg = abi.encodeWithSelector(
        //     ProxyAdmin.upgradeAndCall.selector,
        //     ITransparentUpgradeableProxy(address(emProxy)),
        //     address(newEmImpl),
        //     abi.encodeWithSelector(DefaultEmissionManager.reinitialize.selector)
        // );

        // console.log("Send this payload to: ", emProxyAdmin);
        // console.logBytes(payload);
    }
}