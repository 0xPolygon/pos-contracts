pragma solidity ^0.8.4;

import { StakeManager } from "../scripts/helpers/interfaces/StakeManager.generated.sol";
import { StakeManagerProxy } from "../scripts/helpers/interfaces/StakeManagerProxy.generated.sol";
import { ValidatorShare } from "../scripts/helpers/interfaces/ValidatorShare.generated.sol";
import { Registry } from "../scripts/helpers/interfaces/Registry.generated.sol";
import { ERC20 } from "../scripts/helpers/interfaces/ERC20.generated.sol";

import "forge-std/Test.sol";

contract ForkupgradeStakeManagerTest is Test {
    uint256 mainnetFork;

    function setUp() public {
        string memory MAINNET_RPC_URL = string.concat("https://mainnet.infura.io/v3/", vm.envString("INFURA_TOKEN"));
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
    }

    function test_UpgradeStakeManager() public {
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        StakeManager stakeManagerImpl;
        stakeManagerImpl = StakeManager(deployCode("out/StakeManager.sol/StakeManager.json"));

        console.log("deployed StakeManager Implementation at: ", address(stakeManagerImpl));

        ValidatorShare validatorShareImpl;
        validatorShareImpl = ValidatorShare(deployCode("out/ValidatorShare.sol/ValidatorShare.json"));

        console.log("deployed ValidatorShare Implementation at: ", address(validatorShareImpl));

        Registry registry = Registry(0x33a02E6cC863D393d6Bf231B697b82F6e499cA71);
        console.log("found Registry at: ", address(registry));

        StakeManager stakeManager = StakeManager(0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908);
        StakeManagerProxy stakeManagerProxy = StakeManagerProxy(payable(0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908));
        console.log("found StakeManagerProxy at: ", address(stakeManagerProxy));

        address governance = 0x6e7a5820baD6cebA8Ef5ea69c0C92EbbDAc9CE48;
        address timelock = 0xCaf0aa768A3AE1297DF20072419Db8Bb8b5C8cEf;
        ERC20 polToken = ERC20(0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6);
        ERC20 maticToken = ERC20(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0);
        address migration = 0x29e7DF7b6A1B2b07b731457f499E1696c60E2C4e;

        uint256 balance = maticToken.balanceOf(address(stakeManagerProxy));
        console.log("Matic balance: ", balance);

        // prank set registry as 0x6e7a5820baD6cebA8Ef5ea69c0C92EbbDAc9CE48
        vm.prank(governance);
        registry.updateContractMap(keccak256("validatorShare"), address(validatorShareImpl));

        // prank set proxyImpl as 0xCaf0aa768A3AE1297DF20072419Db8Bb8b5C8cEf
        vm.prank(timelock);
        stakeManagerProxy.updateImplementation(address(stakeManagerImpl));
        // prank call initPol with pol 0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6 mig 0x29e7DF7b6A1B2b07b731457f499E1696c60E2C4e as 0x6e7a5820baD6cebA8Ef5ea69c0C92EbbDAc9CE48

        vm.prank(governance);
        stakeManager.initializePOL(address(polToken), migration);

        assertEq(maticToken.balanceOf(address(stakeManagerProxy)), 0);
        assertEq(polToken.balanceOf(address(stakeManagerProxy)), balance);
    }
}