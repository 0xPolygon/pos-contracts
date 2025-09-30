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
    StakingInfo stakingInfo;
    EventsHub eventsHub;
    RootChain rootChain;
    address owner = makeAddr("owner");
    uint256 defaultStakeVS = 1000 * 10 ** 18;

    function run() public {}

    function deployAll() public {
        address governanceImpl = deployCode(GovernancePath);
        // Owner is msg.sender
        address governanceProxy = deployCode(GovernanceProxyPath, abi.encode(governanceImpl));
        governance = Governance(governanceProxy);

        registry = Registry(deployCode(RegistryPath, abi.encode(governanceProxy)));

        address eventsHubImpl = deployCode(EventsHubPath);
        // Not sure why, but that's how the old tests do it
        eventsHub = EventsHub(deployCode(EventsHubProxyPath, abi.encode(address(0))));

        EventsHubProxy(payable(address(eventsHub))).updateAndCall(
            eventsHubImpl, abi.encodeCall(EventsHub.initialize, (address(registry)))
        );

        updateRegistryContractMap("eventsHub", address(eventsHub));

        address validatorShareFactory = deployCode(ValidatorShareFactoryPath);
        address validatorShare = deployCode(ValidatorSharePath);
        updateRegistryContractMap("validatorShare", validatorShare);

        maticToken = TestToken(deployCode(TestTokenPath, abi.encode("Matic Token", "MT")));
        polToken = ERC20Permit(deployCode(ERC20PermitPath, abi.encode("Pol Token", "POL", "1.1.0")));
        updateRegistryContractMap("pol", address(polToken));

        polygonMigration =
            PolygonMigration(deployCode(PolygonMigrationPath, abi.encode(address(maticToken), address(polToken))));

        stakingInfo = StakingInfo(deployCode(StakingInfoPath, abi.encode(registry)));

        address stakingNFT = deployCode(StakingNFTPath, abi.encode("Matic Validator", "MV"));

        address rootChainImpl = deployCode(RootChainPath);
        rootChain = RootChain(deployCode(RootChainProxyPath, abi.encode(rootChainImpl, registry, "heimdall-P5rXwg")));

        address stakeManagerImpl = deployCode(StakeManagerPath);
        address stakeManagerProxy = deployCode(StakeManagerProxyPath, abi.encode(address(0)));
        stakeManager = StakeManager(stakeManagerProxy);
        updateRegistryContractMap("stakeManager", address(stakeManager));
        address stakeManagerExtension = deployCode(StakeManagerExtensionPath);

        StakeManagerProxy(payable(stakeManagerProxy)).updateAndCall(
            stakeManagerImpl,
            abi.encodeCall(
                StakeManager.initialize,
                (
                    address(registry),
                    address(rootChain),
                    address(maticToken),
                    stakingNFT,
                    address(stakingInfo),
                    validatorShareFactory,
                    governanceProxy,
                    owner,
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

        uint256 defaultTokenAmount = 5 * 10 ** 9 * 10 ** 18;
        maticToken.mint(address(polygonMigration), defaultTokenAmount);
        polToken.mint(address(polygonMigration), defaultTokenAmount);
        polToken.mint(address(stakeManager), defaultTokenAmount);
    }

    function governanceUpdateCall(address _target, bytes memory _callData) public {
        vm.prank(governance.owner());
        governance.update(_target, _callData);
    }

    function updateRegistryContractMap(string memory _key, address _value) public {
        governanceUpdateCall(
            address(registry), abi.encodeCall(Registry.updateContractMap, (keccak256(abi.encodePacked(_key)), _value))
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
        if (minDeposit > defaultStakeVS) {
            defaultStakeVS = minDeposit;
        }
        uint256 heimdallFee = stakeManager.minHeimdallFee();
        if (heimdallFee + defaultStakeVS > polToken.balanceOf(_validator.addr)) {
            fundAddr(_validator.addr, (heimdallFee + defaultStakeVS) - polToken.balanceOf(_validator.addr));
        }
        vm.prank(_validator.addr);
        polToken.approve(address(stakeManager), heimdallFee + defaultStakeVS);

        vm.prank(_validator.addr);
        stakeManager.stakeForPOL(_validator.addr, defaultStakeVS, heimdallFee, true, _validator.pubKey);
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

    function buyVouchersPOL(uint8 _validatorId, address _from, uint256 _amount) public {
        ValidatorShare validatorShare = ValidatorShare(stakeManager.getValidatorContract(_validatorId));
        fundAddr(_from, _amount);

        vm.prank(_from);
        polToken.approve(address(validatorShare), _amount);

        vm.prank(_from);
        validatorShare.buyVoucher(_amount, _amount);
    }

    function buyVouchersPOLPermit(uint8 _validatorId, address _from, uint256 _pk, uint256 _amount) public {
        ValidatorShare validatorShare = ValidatorShare(stakeManager.getValidatorContract(_validatorId));
        fundAddr(_from, _amount);

        // Generate permit signature for POL token
        uint256 _deadline = block.timestamp + 10;
        (uint8 _v, bytes32 _r, bytes32 _s) = createPermit(_from, address(stakeManager), _amount, _deadline, _pk);

        vm.prank(_from);
        validatorShare.buyVoucherWithPermit(_amount, _amount, _deadline, _v, _r, _s);
    }

    function createPermit(
        address _from,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint256 _pk
    ) public view returns (uint8, bytes32, bytes32) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _pk,
            keccak256(
                abi.encodePacked(
                    hex"1901",
                    polToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                            ),
                            _from,
                            _spender,
                            _value,
                            polToken.nonces(_from),
                            _deadline
                        )
                    )
                )
            )
        );
        return (v, r, s);
    }

    function sellVouchersPOL(uint8 _validatorId, address _from, uint256 _amount) public returns (uint256) {
        ValidatorShare validatorShare = getValidatorShareContract(_validatorId);

        vm.prank(_from);
        validatorShare.sellVoucher_newPOL(_amount, 0);

        return validatorShare.unbondNonces(_from);
    }

    function unstakeClaimPOL(uint8 _validatorId, address _from, uint256 _nonce) public {
        ValidatorShare validatorShare = getValidatorShareContract(_validatorId);

        vm.prank(_from);
        validatorShare.unstakeClaimTokens_newPOL(_nonce);
    }

    function getValidatorShareContract(uint8 _validatorId) public view returns (ValidatorShare) {
        return ValidatorShare(stakeManager.getValidatorContract(_validatorId));
    }

    function progressCheckpointWithRewards(
        Validator[] memory _validators,
        address _proposer
    ) public returns (uint256) {
        bytes32 voteHash = keccak256("voteData");
        bytes32 stateRootHash = keccak256("stateRoot");
        uint256[3][] memory sigs = signWithValidators(_validators, voteHash);

        vm.prank(address(rootChain));
        return stakeManager.checkSignatures(1, voteHash, stateRootHash, _proposer, sigs);
    }

    function signWithValidators(
        Validator[] memory _validators,
        bytes32 _data
    ) public pure returns (uint256[3][] memory sigs) {
        sigs = new uint256[3][](_validators.length);
        for (uint256 i = 0; i < _validators.length; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(_validators[i].pk, _data);
            sigs[i] = [uint256(r), uint256(s), uint256(v)];
        }
    }
}
