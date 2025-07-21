// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.28;

import "lib/forge-std/src/Script.sol";
import "../../helpers/interfaces/Governance.generated.sol";
import "../../helpers/interfaces/Timelock.generated.sol";
import "../../helpers/interfaces/Registry.generated.sol";
import "../../helpers/interfaces/ERC20PredicateBurnOnlyOneExit.generated.sol";

contract LogLimit is Script {
    bytes scheduleCallData;
    bytes executeCallData;
    address newPredicate;
    address currentPredicate;

    address posMultisig = 0xFa7D2a996aC6350f4b56C043112Da0366a59b74c;
    Registry registry = Registry(0x33a02E6cC863D393d6Bf231B697b82F6e499cA71);
    Timelock timelock = Timelock(payable(0xCaf0aa768A3AE1297DF20072419Db8Bb8b5C8cEf));
    Governance governanceProxy = Governance(0x6e7a5820baD6cebA8Ef5ea69c0C92EbbDAc9CE48);
    address maticToken = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;

    function run() public {
        currentPredicate = registry.erc20Predicate();
        address withdrawManager = registry.getWithdrawManagerAddress();
        address depositManager = registry.getDepositManagerAddress();
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        // deploy predicate
        newPredicate = deployCode("out/ERC20PredicateBurnOnlyOneExit.sol/ERC20PredicateBurnOnlyOneExit.json", abi.encode(withdrawManager, depositManager));
        vm.stopBroadcast();

        console.log("New predicate: ", newPredicate);

        bytes memory updateCall1 = abi.encodeCall(Governance.update, (address(registry), abi.encodeCall(Registry.removePredicate, (currentPredicate))));
        bytes memory updateCall2 = abi.encodeCall(Governance.update, (address(registry), abi.encodeCall(Registry.addErc20Predicate, (newPredicate))));

        bytes memory exitCall = abi.encodeCall(ERC20PredicateBurnOnlyOneExit.releaseFunds, ());

        bytes memory rollbackCall1 = abi.encodeCall(Governance.update, (address(registry), abi.encodeCall(Registry.removePredicate, (newPredicate))));
        bytes memory rollbackCall2 = abi.encodeCall(Governance.update, (address(registry), abi.encodeCall(Registry.addErc20Predicate, (currentPredicate))));

        address[] memory targets = new address[](5);
        targets[0] = address(governanceProxy);
        targets[1] = address(governanceProxy);
        targets[2] = address(newPredicate);
        targets[3] = address(governanceProxy);
        targets[4] = address(governanceProxy);

        uint256[] memory values = new uint256[](5);
        bytes[] memory callData = new bytes[](5);
        callData[0] = updateCall1;
        callData[1] = updateCall2;
        callData[2] = exitCall;
        callData[3] = rollbackCall1;
        callData[4] = rollbackCall2;

        scheduleCallData = abi.encodeCall(Timelock.scheduleBatch, (targets, values, callData, bytes32(""), bytes32(""), 0));
        executeCallData = abi.encodeCall(Timelock.executeBatch, (targets, values, callData, bytes32(""), bytes32("")));

        console.log("Schedule batch 1.");
        console.logBytes(scheduleCallData);

        console.log("Execute batch 1.");
        console.logBytes(executeCallData);
    }
}
