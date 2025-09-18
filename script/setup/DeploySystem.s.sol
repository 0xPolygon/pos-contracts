// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

// Don't import, wrong solidity version
// import {StakeManager} from "../../contracts/staking/stakeManager/StakeManager.sol";
// import {StakeManagerExtension} from "../../contracts/staking/stakeManager/StakeManagerExtension.sol";
// import {StakeManagerProxy} from "../../contracts/staking/stakeManager/StakeManagerProxy.sol";
// import {StakingNFT} from "../../contracts/staking/stakeManager/StakingNFT.sol";
// import {ValidatorShare} from "../../contracts/staking/validatorShare/ValidatorShare.sol";
// import {ValidatorShareFactory} from "../../contracts/staking/validatorShare/ValidatorShareFactory.sol";
// import {EventsHub} from "../../contracts/staking/EventsHub.sol";
// import {EventsHubProxy} from "../../contracts/staking/EventsHubProxy.sol";
// import {StakingInfo} from "../../contracts/staking/StakingInfo.sol";

// import {Registry} from "../../contracts/common/Registry.sol";
// import {Governance} from "../../contracts/common/Governance.sol";
// import {GovernanceProxy} from "../../contracts/common/GovernanceProxy.sol";
// import {PolygonMigration} from "../../contracts/common/misc/PolygonMigration.sol";
// import {ERC20Permit} from "../../contracts/common/tokens/ERC20Permit.sol";
// import {TestToken} from "../../contracts/common/tokens/TestToken.sol";

// import {RootChain} from "../../contracts/root/RootChain.sol";
// import {RootChainProxy} from "../../contracts/root/RootChainProxy.sol";
// import {StateSender} from "../../contracts/root/stateSyncer/StateSender.sol";

// Interfaces
import {StakeManager} from "../../scripts/helpers/interfaces/StakeManager.generated.sol";
import {StakeManagerExtension} from "../../scripts/helpers/interfaces/StakeManagerExtension.generated.sol";
import {StakeManagerProxy} from "../../scripts/helpers/interfaces/StakeManagerProxy.generated.sol";
import {StakingNFT} from "../../scripts/helpers/interfaces/StakingNFT.generated.sol";
import {ValidatorShare} from "../../scripts/helpers/interfaces/ValidatorShare.generated.sol";
import {ValidatorShareFactory} from "../../scripts/helpers/interfaces/ValidatorShareFactory.generated.sol";
import {EventsHub} from "../../scripts/helpers/interfaces/EventsHub.generated.sol";
import {EventsHubProxy} from "../../scripts/helpers/interfaces/EventsHubProxy.generated.sol";
import {StakingInfo} from "../../scripts/helpers/interfaces/StakingInfo.generated.sol";

import {Registry} from "../../scripts/helpers/interfaces/Registry.generated.sol";
import {Governance} from "../../scripts/helpers/interfaces/Governance.generated.sol";
import {GovernanceProxy} from "../../scripts/helpers/interfaces/GovernanceProxy.generated.sol";
import {PolygonMigration} from "../../scripts/helpers/interfaces/PolygonMigration.generated.sol";
import {ERC20Permit} from "../../scripts/helpers/interfaces/ERC20Permit.generated.sol";
import {TestToken} from "../../scripts/helpers/interfaces/TestToken.generated.sol";

import {RootChain} from "../../scripts/helpers/interfaces/RootChain.generated.sol";
import {RootChainProxy} from "../../scripts/helpers/interfaces/RootChainProxy.generated.sol";
import {StateSender} from "../../scripts/helpers/interfaces/StateSender.generated.sol";

import {ArtifactPath} from "./ArtifactPath.sol";

import "forge-std/Script.sol";

contract DeploySystem is Script, ArtifactPath {
    Governance governance;
    StakeManager stakeManager;
    Registry registry;
    ERC20Permit polToken;
    TestToken maticToken;
    PolygonMigration polygonMigration;

    function run() public {
        vm.startBroadcast();
    }

    function deployAll(address _owner) public {
        address governanceImpl = deployCode(GovernancePath);
        // Owner is msg.sender
        address governanceProxy = deployCode(GovernanceProxyPath, abi.encode(governanceImpl));
        governance = Governance(governanceProxy);

        registry = Registry(deployCode(RegistryPath, abi.encode(governanceProxy)));

        address eventsHub = deployCode(EventsHubPath);
        // Not sure why, but that's how the old tests do it
        address eventsHubProxy = deployCode(EventsHubProxyPath, abi.encode(address(0)));

        EventsHubProxy(payable(eventsHubProxy)).updateAndCall(
            eventsHub, abi.encodeCall(EventsHub.initialize, (address(registry)))
        );

        updateRegistryContractMap("eventsHub", eventsHubProxy);

        address validatorShareFactory = deployCode(ValidatorShareFactoryPath);
        address validatorShare = deployCode(ValidatorSharePath);
        updateRegistryContractMap("validatorShare", validatorShare);

        maticToken = TestToken(deployCode(TestTokenPath, abi.encode("Matic Token", "MT")));
        polToken = ERC20Permit(deployCode(ERC20PermitPath, abi.encode("Pol Token", "POL", "1.1.0")));
        updateRegistryContractMap("pol", address(polToken));

        polygonMigration =
            PolygonMigration(deployCode(PolygonMigrationPath, abi.encode(address(maticToken), address(polToken))));

        address stakingInfo = deployCode(StakingInfoPath, abi.encode(registry));

        address stakingNFT = deployCode(StakingNFTPath, abi.encode("Matic Validator", "MV"));

        address rootChain = deployCode(RootChainPath);
        address rootChainProxy = deployCode(RootChainProxyPath, abi.encode(rootChain, registry, "heimdall-P5rXwg"));

        address stakeManagerImpl = deployCode(StakeManagerPath, abi.encode(address(0)));
        address stakeManagerProxy = deployCode(StakeManagerProxyPath);
        stakeManager = StakeManager(stakeManagerProxy);
        updateRegistryContractMap("stakeManager", address(stakeManager));
        address stakeManagerExtension = deployCode(StakeManagerExtensionPath);

        StakeManagerProxy(payable(stakeManagerProxy)).updateAndCall(
            stakeManagerImpl,
            abi.encodeCall(
                StakeManager.initialize,
                (
                    address(registry),
                    rootChainProxy,
                    address(maticToken),
                    stakingNFT,
                    stakingInfo,
                    validatorShareFactory,
                    governanceProxy,
                    _owner,
                    stakeManagerExtension,
                    address(polToken),
                    address(polygonMigration)
                )
            )
        );

        StakingNFT(stakingNFT).transferOwnership(address(stakeManager));

        address stateSender = deployCode(StateSenderPath);
        updateRegistryContractMap("stateSender", stateSender);
    }

    function setTestConfig() public {
        governanceUpdateCall(address(stakeManager), abi.encodeCall(StakeManager.updateCheckPointBlockInterval, (1)));
        maticToken.mint(address(polygonMigration), 5 * 10 ^ 9 * 10 ^ 18);
        polToken.mint(address(polygonMigration), 5 * 10 ^ 9 * 10 ^ 18);
    }

    function governanceUpdateCall(address target, bytes memory callData) public {
        vm.prank(governance.owner());
        governance.update(target, callData);
    }

    function updateRegistryContractMap(string memory key, address value) public {
        governanceUpdateCall(
            address(registry), abi.encodeCall(Registry.updateContractMap, (keccak256(abi.encode(key)), value))
        );
    }

    // Helper that should always add a validator, this is not testing the adding itself
    function addValidator(Validator memory _validator) public {
        uint256 currentValidators = stakeManager.currentValidatorSetSize();
        uint256 validatorLimit = stakeManager.validatorThreshold();

        if (currentValidators >= validatorLimit) {
            vm.prank(address(governance));
            stakeManager.updateValidatorThreshold(currentValidators + 1);
        }

        uint256 minDeposit = stakeManager.minDeposit();
        uint256 customMinDeposit = 1000 * 10 ^ 18;
        if (minDeposit < customMinDeposit) {
            minDeposit = customMinDeposit;
        }
        uint256 heimdallFee = stakeManager.minHeimdallFee();
        if (heimdallFee + minDeposit > polToken.balanceOf(_validator.addr)) {
            fundAddr(_validator.addr, (heimdallFee + minDeposit) - polToken.balanceOf(_validator.addr));
        }
        stakeManager.stakeForPOL(_validator.addr, minDeposit, heimdallFee, true, _validator.pubKey);
    }

    function removeValidator(uint8 _id) public {
        vm.prank(address(governance));
        stakeManager.forceUnstakePOL(_id);
    }

    function skipFoundationValidators() public {
        require(stakeManager.NFTCounter() == 1, "Some validators already exist");
        for (uint8 id = 1; id < 8; id++) {
            Validator memory currentVal = createValidator(id);
            addValidator(currentVal);
            removeValidator(id);
        }
    }

    struct Validator {
        uint8 id;
        address addr;
        uint256 pk;
        bytes pubKey;
    }

    function createValidator(uint8 _id) public returns (Validator memory) {
        VmSafe.Wallet memory wallet = vm.createWallet(_id);
        Validator memory validator;
        validator.addr = wallet.addr;
        validator.pk = wallet.privateKey;
        validator.pubKey = bytes.concat(bytes32(wallet.publicKeyX), bytes32(wallet.publicKeyY));
        validator.id = _id;
        return validator;
    }

    function fundAddr(address _address, uint256 _amount) public {
        polToken.mint(_address, _amount);
    }

    function fundAddrMatic(address _address, uint256 _amount) public {
        maticToken.mint(_address, _amount);
    }
}
