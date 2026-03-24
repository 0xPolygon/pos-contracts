// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Script, stdJson, console} from "forge-std/Script.sol";

import {Registry} from "../helpers/interfaces/Registry.generated.sol";
import {Governance} from "../helpers/interfaces/Governance.generated.sol";
import {StateSender} from "../helpers/interfaces/StateSender.generated.sol";
import {DepositManager} from "../helpers/interfaces/DepositManager.generated.sol";

contract SyncChildStateToRootScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        string memory path = "contractAddresses.json";
        string memory json = vm.readFile(path);

        address registryAddress = vm.parseJsonAddress(json, ".root.Registry");

        Governance governance = Governance(vm.parseJsonAddress(json, ".root.GovernanceProxy"));
        Registry registry = Registry(registryAddress);

        bytes memory tokenData = abi.encodeWithSelector(
            bytes4(keccak256("mapToken(address,address,bool)")),
            vm.parseJsonAddress(json, ".root.tokens.MaticWeth"),
            vm.parseJsonAddress(json, ".child.tokens.MaticWeth"),
            false
        );
        governance.update(registryAddress, tokenData);

        console.log("Success!");

        tokenData = abi.encodeWithSelector(
            bytes4(keccak256("mapToken(address,address,bool)")),
            vm.parseJsonAddress(json, ".root.tokens.MaticToken"),
            vm.parseJsonAddress(json, ".child.tokens.MaticToken"),
            false
        );
        governance.update(registryAddress, tokenData);

        console.log("Success!");

        // Map PolToken to the same L2 native token (0x1010) so that POL can be deposited
        // directly via DepositManager.depositERC20. The DepositManager remaps POL→MATIC
        // internally before the state sync, so L2 behaviour is identical to bridging MATIC.
        tokenData = abi.encodeWithSelector(
            bytes4(keccak256("mapToken(address,address,bool)")),
            vm.parseJsonAddress(json, ".root.tokens.PolToken"),
            vm.parseJsonAddress(json, ".child.tokens.MaticToken"),
            false
        );
        governance.update(registryAddress, tokenData);

        console.log("Success!");

        tokenData = abi.encodeWithSelector(
            bytes4(keccak256("mapToken(address,address,bool)")),
            vm.parseJsonAddress(json, ".root.tokens.TestToken"),
            vm.parseJsonAddress(json, ".child.tokens.TestToken"),
            false
        );
        governance.update(registryAddress, tokenData);

        console.log("Success!");

        tokenData = abi.encodeWithSelector(
            bytes4(keccak256("mapToken(address,address,bool)")),
            vm.parseJsonAddress(json, ".root.tokens.RootERC721"),
            vm.parseJsonAddress(json, ".child.tokens.RootERC721"),
            true
        );
        governance.update(registryAddress, tokenData);

        bytes memory childChainData = abi.encodeWithSelector(
            bytes4(keccak256("updateContractMap(bytes32,address)")), keccak256(abi.encodePacked("childChain")), vm.parseJsonAddress(json, ".child.ChildChain")
        );
        governance.update(registryAddress, childChainData);

        StateSender stateSenderContract = StateSender(vm.parseJsonAddress(json, ".root.StateSender"));
        stateSenderContract.register(vm.parseJsonAddress(json, ".root.DepositManagerProxy"), vm.parseJsonAddress(json, ".child.ChildChain"));

        DepositManager depositManager = DepositManager(payable(vm.parseJsonAddress(json, ".root.DepositManagerProxy")));
        address currentChildChain = depositManager.childChain();
        address currentStateSender = depositManager.stateSender();
        (address newChildChain, address newStateSender) = registry.getChildChainAndStateSender();
        if (currentChildChain != newChildChain || currentStateSender != newStateSender) {
            depositManager.updateChildChainAndStateSender();
        }

        vm.stopBroadcast();
    }
}
