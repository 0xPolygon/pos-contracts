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

    Timelock timelock;
    Registry registry;
    StakeManager stakeManagerProxy;
    Governance governance;
    ERC20 polToken;
    address migrationAddress;
    DepositManager depositManagerProxy;
    ERC20 maticToken;
    address nativeGasTokenAddress;
    address gSafeAddress;

    function run() public {
        uint256 deployerPrivateKey = vm.promptSecretUint("Enter deployer private key: ");
        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        loadConfig();
        (StakeManager stakeManagerImpl, ValidatorShare validatorShareImpl, DepositManager depositManagerImpl) = deployImplementations(deployerPrivateKey);
        (bytes memory scheduleBatchPayload, bytes memory executeBatchPayload, bytes32 payloadId) =
            createPayload(stakeManagerImpl, validatorShareImpl, depositManagerImpl);

        console.log("Send scheduleBatchPayload to: ", address(timelock));
        console.logBytes(scheduleBatchPayload);

        console.log("----------------------");
        console.log("After at least 7 days send executeBatchPayload to: ", address(timelock));
        console.logBytes(executeBatchPayload);
    }

    function loadConfig() public {
        console.log("----------------------");
        console.log("Loading config \n");

        string memory input = vm.readFile("scripts/deployers/pol-upgrade/input.json");
        string memory chainIdSlug = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        registry = Registry(input.readAddress(string.concat(chainIdSlug, ".registry")));
        stakeManagerProxy = StakeManager(input.readAddress(string.concat(chainIdSlug, ".stakeManagerProxy")));
        governance = Governance(input.readAddress(string.concat(chainIdSlug, ".governance")));
        polToken = ERC20(input.readAddress(string.concat(chainIdSlug, ".polToken")));
        migrationAddress = input.readAddress(string.concat(chainIdSlug, ".migration"));
        timelock = Timelock(payable(input.readAddress(string.concat(chainIdSlug, ".timelock"))));
        depositManagerProxy = DepositManager(payable(input.readAddress(string.concat(chainIdSlug, ".depositManagerProxy"))));
        maticToken = ERC20(input.readAddress(string.concat(chainIdSlug, ".matic")));
        nativeGasTokenAddress = input.readAddress(string.concat(chainIdSlug, ".nativGasToken"));
        gSafeAddress = input.readAddress(string.concat(chainIdSlug, ".gSafe"));

        console.log("using Registry at: ", address(registry));
        console.log("using StakeManagerProxy at: ", address(stakeManagerProxy));
        console.log("using DepositManagerProxy at: ", address(depositManagerProxy));
        console.log("using Governance at: ", address(governance));
        console.log("using Timelock at: ", address(timelock));
        console.log("using Matic at: ", address(maticToken));
        console.log("using POL at: ", address(polToken));
        console.log("using PolygonMigration at: ", migrationAddress);
        console.log("using NativGasToken at: ", nativeGasTokenAddress);
        console.log("using gSafe at: ", gSafeAddress);
    }

    function deployImplementations(uint256 deployerPrivateKey)
        public
        returns (StakeManager stakeManagerImpl, ValidatorShare validatorShareImpl, DepositManager depositManagerImpl)
    {
        vm.startBroadcast(deployerPrivateKey);

        // deploy STEP 1
        // deploy new StakeManager version
        stakeManagerImpl = StakeManager(deployCode("out/StakeManager.sol/StakeManager.json"));

        console.log("deployed StakeManager implementation at: ", address(stakeManagerImpl));

        // deploy STEP 2
        // deploy new ValidatorShare version
        validatorShareImpl = ValidatorShare(deployCode("out/ValidatorShare.sol/ValidatorShare.json"));

        console.log("deployed ValidatorShare implementation at: ", address(validatorShareImpl));

        // deploy STEP 3
        // deploy new DepositManager version
        depositManagerImpl = DepositManager(payable(deployCode("out/DepositManager.sol/DepositManager.json")));

        console.log("deployed DepositManager implementation at: ", address(validatorShareImpl));

        vm.stopBroadcast();
    }

    function createPayload(StakeManager stakeManagerImpl, ValidatorShare validatorShareImpl, DepositManager depositManagerImpl)
        public
        returns (bytes memory scheduleBatchPayload, bytes memory executeBatchPayload, bytes32 payloadId)
    {
        console.log("----------------------");
        console.log("Generating payloads \n");

        // STEP 1
        // Update ValidatorShare registry entry
        bytes memory payloadRegistry1 = abi.encodeCall(
            governance.update, (address(registry), abi.encodeCall(registry.updateContractMap, (keccak256("validatorShare"), address(validatorShareImpl))))
        );

        console.log("Created payloadRegistry1 for: ", address(governance));
        console.logBytes(payloadRegistry1);

        // STEP 2
        // Update StakeManagerProxy implementation contract
        bytes memory payloadStakeManager2 = abi.encodeCall(StakeManagerProxy.updateImplementation, (address(stakeManagerImpl)));

        console.log("Created payloadStakeManager2 for: ", address(stakeManagerProxy));
        console.logBytes(payloadStakeManager2);

        // STEP 3
        // Call initializePOL
        bytes memory payloadInitializePol3 = abi.encodeCall(
            governance.update, (address(stakeManagerProxy), abi.encodeCall(stakeManagerProxy.initializePOL, (address(polToken), migrationAddress)))
        );

        console.log("Created payloadInitializePol3 for: ", address(governance));
        console.logBytes(payloadInitializePol3);

        // STEP 4
        // Call updateContractMap on registry to add "pol"
        bytes memory payloadContractMapPol4 =
            abi.encodeCall(governance.update, (address(registry), abi.encodeCall(registry.updateContractMap, (keccak256("pol"), address(polToken)))));

        console.log("Send payloadContractMapPol4 to: ", address(governance));
        console.logBytes(payloadContractMapPol4);

        // STEP 5
        // Call updateContractMap on registry to add "matic"
        bytes memory payloadContractMapMatic5 =
            abi.encodeCall(governance.update, (address(registry), abi.encodeCall(registry.updateContractMap, (keccak256("matic"), address(maticToken)))));

        console.log("Send payloadContractMapMatic5 to: ", address(governance));
        console.logBytes(payloadContractMapMatic5);

        // STEP 6
        // Call updateContractMap on registry to add "polygonMigration"
        bytes memory payloadContractMapMigration6 = abi.encodeCall(
            governance.update, (address(registry), abi.encodeCall(registry.updateContractMap, (keccak256("polygonMigration"), migrationAddress)))
        );

        console.log("Send payloadContractMapMigration6 to: ", address(governance));
        console.logBytes(payloadContractMapMigration6);

        // STEP 7
        // call mapToken on the Registry to map POL to the PoS native gas token address (1010)
        bytes memory payloadMapToken7 = abi.encodeCall(
            governance.update.selector, (address(registry), abi.encodeCall(registry.mapToken, (address(polToken), nativeGasTokenAddress, false)))
        );

        console.log("Send payloadMapToken7 to: ", address(governance));
        console.logBytes(payloadMapToken7);

        // STEP 8
        // update impl of proxy to DepositManager
        bytes memory payloadUpgradeDepositManager8 = abi.encodeCall(DepositManagerProxy.updateImplementation, (address(depositManagerImpl)));

        console.log();
        console.log("Send payloadUpgradeDepositManager8 to: ", address(depositManagerProxy));
        console.logBytes(payloadUpgradeDepositManager8);

        // STEP 9
        // call migrateMatic on the new DepositManager, migrating all MATIC
        uint256 amount = maticToken.balanceOf(address(depositManagerProxy));
        bytes memory payloadMigrateMatic9 =
            abi.encodeCall(governance.update, (address(depositManagerProxy), abi.encodeCall(depositManagerProxy.migrateMatic, (amount / 2))));

        console.log("Send payloadMigrateMatic9 to: ", address(governance));
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

        payloadId = timelock.hashOperationBatch(targets, values, payloads, "", "");
        console.log("Expected batch ID: %s", vm.toString(payloadId));

        // 172800 is minDelay
        scheduleBatchPayload = abi.encodeCall(Timelock.scheduleBatch, (targets, values, payloads, "", "", 172_800));
        executeBatchPayload = abi.encodeCall(Timelock.executeBatch, (targets, values, payloads, "", ""));
    }
}
