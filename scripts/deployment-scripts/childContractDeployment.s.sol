// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Script, stdJson, console} from "forge-std/Script.sol";

import {ChildChain} from "../helpers/interfaces/ChildChain.generated.sol";
import {ChildERC20Proxified} from "../helpers/interfaces/ChildERC20Proxified.generated.sol";
import {ChildTokenProxy} from "../helpers/interfaces/ChildTokenProxy.generated.sol";
import {ChildERC721Proxified} from "../helpers/interfaces/ChildERC721Proxified.generated.sol";
import {MRC20} from "../helpers/interfaces/MRC20.generated.sol";

contract ChildContractDeploymentScript is Script {
    ChildChain childChain;
    ChildERC20Proxified childMaticWethPRoxified;
    ChildTokenProxy childMaticWethProxy;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        string memory path = "contractAddresses.json";
        string memory json = vm.readFile(path);
        string memory childJson = "child";
        string memory childTokenJson = "child_token";

        address maticWethAddress = vm.parseJsonAddress(json, ".root.tokens.MaticWeth");
        address maticRootAddress = vm.parseJsonAddress(json, ".root.tokens.MaticToken");

        childChain = ChildChain(payable(deployCode("out/ChildChain.sol/ChildChain.json")));
        vm.serializeAddress(childJson, "ChildChain", address(childChain));

        console.log("childChain address: ", address(childChain));

        // Deploy MaticWeth (ERC20) child contract and its proxy.
        // Initialize the contract, update the child chain contracts and map the token with its root contract.

        childMaticWethPRoxified = ChildERC20Proxified(payable(deployCode("out/ChildERC20Proxified.sol/ChildERC20Proxified.json")));
        console.log("Child MaticWethProxified deployed at: ", address(childMaticWethPRoxified));

        childMaticWethProxy = ChildTokenProxy(payable(deployCode("out/ChildTokenProxy.sol/ChildTokenProxy.json", abi.encode(address(childMaticWethPRoxified)))));
        console.log("Child MaticWethProxy deployed at: ", address(childMaticWethProxy));

        ChildERC20Proxified childMaticWeth = ChildERC20Proxified(address(childMaticWethProxy));
        console.log("Abstraction successful!");

        MRC20 childMatic = MRC20(0x0000000000000000000000000000000000001010);
        vm.serializeAddress(childTokenJson, "MaticWeth", address(childMaticWeth));
        vm.serializeAddress(childTokenJson, "MaticToken", address(childMatic));

        // Init genesis matic.
        childMatic.initialize(address(childChain), maticRootAddress);

        // First parameter should be MaticWeth Address.
        childMaticWeth.initialize(maticWethAddress, "Eth on Matic", "ETH", 18);
        console.log("Child MaticWeth contract initialized");

        childMaticWeth.changeChildChain(address(childChain));
        console.log("Child MaticWeth child chain updated");

        childChain.mapToken(maticRootAddress, address(childMatic), false);
        console.log("Root and child Matic contracts mapped");

        // First address should be MaticWeth address.
        childChain.mapToken(maticWethAddress, address(childMaticWeth), false);
        console.log("Root and child MaticWeth contracts mapped");

        // Same thing for TestToken(ERC20).
        // BUG FIX: Use proper TestToken root address instead of maticWethAddress
        // From test/helpers/deployer.js:299-321 - deployChildErc20() shows correct pattern:
        // const rootERC20 = await this.deployTestErc20({ mapToken: false })
        // await childToken.initialize(rootERC20.address, 'ChildToken', 'CTOK', 18)
        // await this.childChain.mapToken(rootERC20.address, childToken.address, false)
        address testTokenRootAddress = vm.parseJsonAddress(json, ".root.tokens.TestToken");
        ChildERC20Proxified childTestTokenProxified = ChildERC20Proxified(payable(deployCode("out/ChildERC20Proxified.sol/ChildERC20Proxified.json")));
        console.log("Child TestTokenProxified contract deployed");
        ChildTokenProxy childTestTokenProxy =
            ChildTokenProxy(payable(deployCode("out/ChildTokenProxy.sol/ChildTokenProxy.json", abi.encode(address(childTestTokenProxified)))));
        console.log("Child TestToken proxy contract deployed");
        ChildERC20Proxified childTestToken = ChildERC20Proxified(address(childTestTokenProxy));

        vm.serializeAddress(childTokenJson, "TestToken", address(childTestToken));

        childTestToken.initialize(testTokenRootAddress, "Test Token", "TST", 18);
        console.log("Child TestToken contract initialized");
        childTestToken.changeChildChain(address(childChain));
        console.log("Child TestToken child chain updated");
        childChain.mapToken(testTokenRootAddress, address(childTestToken), false);
        console.log("Root and child TestToken contracts mapped");

        // Same thing for RootERC721.
        // BUG FIX: Use proper RootERC721 address instead of maticWethAddress for mapping
        // From test/helpers/deployer.js:341-355 - deployChildErc721() shows correct pattern:
        // const rootERC721 = await this.deployTestErc721({ mapToken: false })
        // await childErc721.initialize(rootERC721.address, 'ChildERC721', 'C721')
        // await this.childChain.mapToken(rootERC721.address, childErc721.address, true)
        address rootERC721Address = vm.parseJsonAddress(json, ".root.tokens.RootERC721");
        ChildERC721Proxified childTestERC721Proxified = ChildERC721Proxified(payable(deployCode("out/ChildERC721Proxified.sol/ChildERC721Proxified.json")));
        console.log("Child TestERC721Proxified contract deployed");
        ChildTokenProxy childTestERC721Proxy =
            ChildTokenProxy(payable(deployCode("out/ChildTokenProxy.sol/ChildTokenProxy.json", abi.encode(address(childTestERC721Proxified)))));
        console.log("Child TestERC721 proxy contract deployed");
        ChildERC721Proxified childTestERC721 = ChildERC721Proxified(payable(address(childTestERC721Proxy)));
        string memory outChildToken = vm.serializeAddress(childTokenJson, "RootERC721", address(childTestERC721));

        childTestERC721.initialize(rootERC721Address, "Test ERC721", "TST721");

        console.log("Child TestERC721 contract initialized");
        childTestERC721.changeChildChain(address(childChain));
        console.log("Child TestERC721 child chain updated");
        childChain.mapToken(rootERC721Address, address(childTestERC721), true);
        console.log("Root and child testERC721 contracts mapped");

        string memory tempJson = "tempJson";
        string memory outChild = vm.serializeString(childJson, "tokens", outChildToken);

        vm.serializeJson(tempJson, json);
        string memory fJson = vm.serializeString(tempJson, "child", outChild);
        vm.writeJson(fJson, path);

        vm.stopBroadcast();
    }
}
