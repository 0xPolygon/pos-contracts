// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Script, stdJson, console} from "forge-std/Script.sol";

import {Registry} from "../helpers/interfaces/Registry.generated.sol";
import {Governance} from "../helpers/interfaces/Governance.generated.sol";

contract InitializeStateScript is Script {
    string path = "contractAddresses.json";
    string json = vm.readFile(path);

    address registryAddress = vm.parseJsonAddress(json, ".root.Registry");
    address governanceAddress = vm.parseJsonAddress(json, ".root.GovernanceProxy");

    Registry registry = Registry(registryAddress);
    Governance governance = Governance(governanceAddress);

    function updateContractMap(bytes32 nameHash, address value) internal {
        bytes memory callData = abi.encodeCall(registry.updateContractMap, (nameHash, value));

        governance.update(registryAddress, callData);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        updateContractMap(keccak256("validatorShare"), vm.parseJsonAddress(json, ".root.ValidatorShare"));
        updateContractMap(keccak256("depositManager"), vm.parseJsonAddress(json, ".root.DepositManagerProxy"));
        updateContractMap(keccak256("withdrawManager"), vm.parseJsonAddress(json, ".root.WithdrawManagerProxy"));
        updateContractMap(keccak256("stakeManager"), vm.parseJsonAddress(json, ".root.StakeManagerProxy"));
        updateContractMap(keccak256("stateSender"), vm.parseJsonAddress(json, ".root.StateSender"));
        updateContractMap(keccak256("pol"), vm.parseJsonAddress(json, ".root.tokens.PolToken"));
        updateContractMap(keccak256("wethToken"), vm.parseJsonAddress(json, ".root.tokens.MaticWeth"));
        updateContractMap(keccak256("eventsHub"), vm.parseJsonAddress(json, ".root.EventsHubProxy"));

        console.log("Success");

        bytes memory erc20PredicateData = abi.encodeCall(registry.addErc20Predicate, (vm.parseJsonAddress(json, ".root.predicates.ERC20Predicate")));
        governance.update(registryAddress, erc20PredicateData);

        bytes memory erc721PredicateData = abi.encodeCall(registry.addErc721Predicate, (vm.parseJsonAddress(json, ".root.predicates.ERC721Predicate")));
        governance.update(registryAddress, erc721PredicateData);

        // bytes memory marketPlacePredicateData = abi.encodeCall(registry.addPredicate, (vm.parseJsonAddress(json, ".root.predicates.MarketPlacePredicate"), 3));
        // governance.update(registryAddress, marketPlacePredicateData);

        vm.stopBroadcast();
    }
}
