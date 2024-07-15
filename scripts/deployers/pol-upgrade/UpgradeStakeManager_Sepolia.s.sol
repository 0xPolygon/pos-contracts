// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script, stdJson, console2 as console} from "forge-std/Script.sol";

import { StakeManager } from "../../helpers/interfaces/StakeManager.generated.sol";
import { StakeManagerProxy } from "../../helpers/interfaces/StakeManagerProxy.generated.sol";
import { ValidatorShare } from "../../helpers/interfaces/ValidatorShare.generated.sol";
import { Registry } from "../../helpers/interfaces/Registry.generated.sol";
import { Governance } from "../../helpers/interfaces/Governance.generated.sol";
import { ERC20 } from "../../helpers/interfaces/ERC20.generated.sol";

contract UpgradeEmissionManager is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.promptSecretUint("Enter deployer private key: ");

        string memory input = vm.readFile("scripts/deployers/pol-upgrade/input.json");
        string memory chainIdSlug = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));
        address registryAddress = input.readAddress(string.concat(chainIdSlug, ".registry"));
        address stakeManagerProxyAddress = input.readAddress(string.concat(chainIdSlug, ".stakeManagerProxy"));
        address governanceAddress = input.readAddress(string.concat(chainIdSlug, ".governance"));
        address polToken = input.readAddress(string.concat(chainIdSlug, ".polToken"));
        address migration = input.readAddress(string.concat(chainIdSlug, ".migration"));

        vm.startBroadcast(deployerPrivateKey);

        StakeManager stakeManagerImpl;
        stakeManagerImpl = StakeManager(deployCode("out/StakeManager.sol/StakeManager.json"));

        console.log("deployed StakeManager Implementation at: ", address(stakeManagerImpl));

        ValidatorShare validatorShareImpl;
        validatorShareImpl = ValidatorShare(deployCode("out/ValidatorShare.sol/ValidatorShare.json"));

        console.log("deployed ValidatorShare Implementation at: ", address(validatorShareImpl));

        Registry registry = Registry(registryAddress);
        console.log("found Registry at: ", address(registry));

        StakeManager stakeManager = StakeManager(stakeManagerProxyAddress);
        StakeManagerProxy stakeManagerProxy = StakeManagerProxy(payable(stakeManagerProxyAddress));
        console.log("found StakeManagerProxy at: ", address(stakeManagerProxy));

        vm.stopBroadcast();


        Governance governance = Governance(governanceAddress);

        bytes memory payloadRegistry = abi.encodeWithSelector(
            governance.update.selector,
            address(registry),
            abi.encodeWithSelector(
                registry.updateContractMap.selector,
                keccak256("validatorShare"),
                address(validatorShareImpl)
            )
        );

        console.log("Send payloadRegistry to: ", address(governance));
        console.logBytes(payloadRegistry);

        bytes memory payloadStakeManager = abi.encodeWithSelector(
            stakeManagerProxy.updateAndCall.selector,
            address(stakeManagerImpl),
            abi.encodeWithSelector(
                stakeManager.initializePOL.selector,
                address(polToken),
                migration
            )
        );
        
        console.log("Send payloadStakeManager to: ", address(stakeManagerProxy));
        console.logBytes(payloadStakeManager);
    }
}
