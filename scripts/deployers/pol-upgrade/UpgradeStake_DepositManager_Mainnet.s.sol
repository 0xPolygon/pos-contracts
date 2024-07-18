// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script, stdJson, console} from "forge-std/Script.sol";

import {StakeManager} from "../../helpers/interfaces/StakeManager.generated.sol";
import {StakeManagerProxy} from "../../helpers/interfaces/StakeManagerProxy.generated.sol";
import {ValidatorShare} from "../../helpers/interfaces/ValidatorShare.generated.sol";
import {Registry} from "../../helpers/interfaces/Registry.generated.sol";
import {Governance} from "../../helpers/interfaces/Governance.generated.sol";
import {DepositManager} from "../../helpers/interfaces/DepositManager.generated.sol";
import {DepositManagerProxy} from "../../helpers/interfaces/DepositManagerProxy.generated.sol";
import {ERC20} from "../../helpers/interfaces/ERC20.generated.sol";

import {Timelock} from "../../../contracts/common/misc/ITimelock.sol";

contract UpgradeStake_DepositManager_Mainnet is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.promptSecretUint("Enter deployer private key: ");

        string memory input = vm.readFile("scripts/deployers/pol-upgrade/input.json");
        string memory chainIdSlug = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));
        address registryAddress = input.readAddress(string.concat(chainIdSlug, ".registry"));
        address stakeManagerProxyAddress = input.readAddress(string.concat(chainIdSlug, ".stakeManagerProxy"));
        address governanceAddress = input.readAddress(string.concat(chainIdSlug, ".governance"));
        address polTokenAddress = input.readAddress(string.concat(chainIdSlug, ".polToken"));
        address migrationAddress = input.readAddress(string.concat(chainIdSlug, ".migration"));
        address timelockAddress = input.readAddress(string.concat(chainIdSlug, ".timelock"));
        address payable depositManagerProxyAddress = payable(input.readAddress(string.concat(chainIdSlug, ".depositManagerProxy")));
        address maticAddress = input.readAddress(string.concat(chainIdSlug, ".matic"));
        address nativeGasTokenAddress = address(0x0000000000000000000000000000000000001010);

        vm.startBroadcast(deployerPrivateKey);

        // deploy STEP 1
        // deploy new StakeManager version
        StakeManager stakeManagerImpl;
        stakeManagerImpl = StakeManager(deployCode("out/StakeManager.sol/StakeManager.json"));

        console.log("deployed StakeManager implementation at: ", address(stakeManagerImpl));

        // deploy STEP 2
        // deploy new ValidatorShare version
        ValidatorShare validatorShareImpl;
        validatorShareImpl = ValidatorShare(deployCode("out/ValidatorShare.sol/ValidatorShare.json"));

        console.log("deployed ValidatorShare implementation at: ", address(validatorShareImpl));

        // deploy STEP 3
        // deploy new DepositManager version 
        DepositManager depositManagerImpl;
        depositManagerImpl = DepositManager(payable(deployCode("out/DepositManager.sol/DepositManager.json")));

        console.log("deployed DepositManager implementation at: ", address(validatorShareImpl));

        vm.stopBroadcast();

        Registry registry = Registry(registryAddress);
        console.log("using Registry at: ", address(registry));

        StakeManager stakeManager = StakeManager(stakeManagerProxyAddress);
        StakeManagerProxy stakeManagerProxy = StakeManagerProxy(payable(stakeManagerProxyAddress));
        console.log("using StakeManagerProxy at: ", address(stakeManagerProxy));

        DepositManager depositManager = DepositManager(depositManagerProxyAddress);
        DepositManagerProxy depositManagerProxy = DepositManagerProxy(depositManagerProxyAddress);
        console.log("using DepositManagerProxy at: ", address(depositManagerProxy));

        Governance governance = Governance(governanceAddress);
        console.log("using Governance at: ", address(governanceAddress));

        Timelock timelock = Timelock(payable(timelockAddress));
        console.log("using Timelock at: ", address(timelockAddress));

        ERC20 maticToken = ERC20(maticAddress);
        console.log("using Matic at: ", address(maticAddress));

        console.log("----------------------");
        console.log("Generating payloads \n");

        // STEP 1 
        // Update ValidatorShare registry entry
        bytes memory payloadRegistry1 = abi.encodeWithSelector(
            governance.update.selector,
            address(registry),
            abi.encodeWithSelector(registry.updateContractMap.selector, keccak256("validatorShare"), address(validatorShareImpl))
        );

        console.log("Created payloadRegistry1 for: ", address(governance));
        console.logBytes(payloadRegistry1);


        // STEP 2
        // Update StakeManagerProxy implementation contract
        bytes memory payloadStakeManager2 = abi.encodeWithSelector(stakeManagerProxy.updateImplementation.selector, address(stakeManagerImpl));

        console.log("Created payloadStakeManager2 for: ", address(stakeManagerProxy));
        console.logBytes(payloadStakeManager2);

        // STEP 3
        // Call initializePOL
        bytes memory payloadInitializePol3 = abi.encodeWithSelector(
            governance.update.selector, address(stakeManagerProxy), abi.encodeWithSelector(stakeManager.initializePOL.selector, polTokenAddress, migrationAddress)
        );

        console.log("Created payloadInitializePol3 for: ", address(governance));
        console.logBytes(payloadInitializePol3);

        // STEP 4
        // Call updateContractMap on registry to add "pol"
        bytes memory payloadContractMapPol4 = abi.encodeWithSelector(
            governance.update.selector, address(registry), abi.encodeWithSelector(registry.updateContractMap.selector, keccak256("pol"), polTokenAddress)
        );

        console.log("Send payloadContractMapPol4 to: ", address(governance));
        console.logBytes(payloadContractMapPol4);

        // STEP 5
        // Call updateContractMap on registry to add "matic"
        bytes memory payloadContractMapMatic5 = abi.encodeWithSelector(
            governance.update.selector, address(registry), abi.encodeWithSelector(registry.updateContractMap.selector, keccak256("matic"), maticAddress)
        );

        console.log("\n Send payloadContractMapMatic5 to: ", address(governance));
        console.logBytes(payloadContractMapMatic5);

        // STEP 6
        // Call updateContractMap on registry to add "polygonMigration"
        bytes memory payloadContractMapMigration6 = abi.encodeWithSelector(
            governance.update.selector, address(registry), abi.encodeWithSelector(registry.updateContractMap.selector, keccak256("polygonMigration"), migrationAddress)
        );

        console.log("Send payloadContractMapMigration6 to: ", address(governance));
        console.logBytes(payloadContractMapMigration6);

        // STEP 7
        // call mapToken on the Registry to map POL to the PoS native gas token address (1010)
        bytes memory payloadMapToken7 = abi.encodeWithSelector(
            governance.update.selector, address(registry), abi.encodeWithSelector(registry.mapToken.selector, polTokenAddress, nativeGasTokenAddress, false)
        );

        console.log("Send payloadMapToken7 to: ", address(governance));
        console.logBytes(payloadMapToken7);

        // STEP 8
        // update impl of proxy to DepositManager
        bytes memory payloadUpgradeDepositManager8 = abi.encodeWithSelector(depositManagerProxy.updateImplementation.selector, address(depositManagerImpl));

        console.log();
        console.log("Send payloadUpgradeDepositManager8 to: ", address(depositManagerProxy));
        console.logBytes(payloadUpgradeDepositManager8);

        // STEP 9
        // call migrateMatic on the new DepositManager, migrating all MATIC
        uint256 amount = maticToken.balanceOf(address(depositManagerProxy));
        bytes memory payloadMigrateMatic9 = abi.encodeWithSelector(
            governance.update.selector, address(depositManagerProxy), abi.encodeWithSelector(depositManager.migrateMatic.selector, amount)
        );

        console.log("\n Send payloadMigrateMatic9 to: ", address(governance));
        console.logBytes(payloadMigrateMatic9);

        console.log("----------------------");
        console.log("Batching payloads \n");

        address[] memory targets = new address[](9);
        targets[0] = address(governance);
        targets[1] = address(stakeManagerProxy);
        targets[2] = address(governance);
        targets[3] = address(governance);
        targets[4] = address(governance);
        targets[5] = address(governance);
        targets[6] = address(governance);
        targets[7] = address(depositManagerProxy);
        targets[8] = address(governance);

        // Inits to 0
        uint256[] memory values = new uint256[](9);

        bytes[] memory payloads = new bytes[](9);
        payloads[0] = payloadRegistry1;
        payloads[1] = payloadStakeManager2;
        payloads[2] = payloadInitializePol3;
        payloads[3] = payloadContractMapPol4;
        payloads[4] = payloadContractMapMatic5;
        payloads[5] = payloadContractMapMigration6;
        payloads[6] = payloadMapToken7;
        payloads[7] = payloadUpgradeDepositManager8;
        payloads[8] = payloadMigrateMatic9;

        bytes memory batchPayload = abi.encodeWithSelector(Timelock.scheduleBatch.selector, targets, values, payloads, "", "");
        bytes32 payloadId = timelock.hashOperationBatch(targets, values, payloads, "", "");

        console.log("Expected batch ID: %s", vm.toString(payloadId));
        console.log("Send batchPayload to: ", address(timelock));
        console.logBytes(batchPayload);

        bytes memory executePayload = abi.encodeWithSelector(Timelock.executeBatch.selector, targets, values, payloads, "", "");

        console.log("----------------------");
        console.log("After at least 7 days send executePayload to: ", address(timelock));
        console.logBytes(executePayload);

    }
}
