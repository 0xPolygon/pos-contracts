pragma solidity 0.5.17;

import {SafeMath} from "../../common/oz/math/SafeMath.sol";
import {Registry} from "../../common/Registry.sol";
import {GovernanceLockable} from "../../common/mixin/GovernanceLockable.sol";
import {StakeManagerStorage} from "./StakeManagerStorage.sol";
import {StakeManagerStorageExtension} from "./StakeManagerStorageExtension.sol";
import {Initializable} from "../../common/mixin/Initializable.sol";
import {EventsHub} from "../EventsHub.sol";
import {ValidatorShare} from "../validatorShare/ValidatorShare.sol";

// DEPLOYMENT CONSTRAINT: a new version of this contract cannot be installed on the live system as
// things stand. `extensionCode` has no writer at all in the shipped StakeManager — the genesis
// initializer that used to set it is gone — so on the live proxy it is frozen at the extension
// deployed in 2021 (0xef49Ea6996073752b6840CDA34773FFA78F78166). A new extension can be deployed
// but never pointed at.
//
// The StakeManager upgrade itself is unaffected: it delegates only `migrateValidatorsData`,
// `updateCommissionRate` and `updateCheckpointRewardParams`, all three of which the deployed 2021
// extension already implements, so the StakeManager can ship on its own and keep using it.
//
// To actually replace this contract, one of:
//   1. fold it into StakeManager and drop `extensionCode` altogether — the intended direction; or
//   2. add a governance-gated reinitializer so `extensionCode` can be repointed at the new
//      deployment. Without that, changes here are dead code on mainnet.
//
// Note that the storage layouts must stay compatible either way: this contract and StakeManager
// share storage through the delegatecall.
contract StakeManagerExtension is StakeManagerStorage, Initializable, StakeManagerStorageExtension {
    using SafeMath for uint256;

    constructor() public GovernanceLockable(address(0x0)) {}

    function migrateValidatorsData(uint256 validatorIdFrom, uint256 validatorIdTo) external {       
        for (uint256 i = validatorIdFrom; i < validatorIdTo; ++i) {
            ValidatorShare contractAddress = ValidatorShare(validators[i].contractAddress);
            if (contractAddress != ValidatorShare(0)) {
                // move validator rewards out from ValidatorShare contract
                validators[i].reward = contractAddress.validatorRewards_deprecated().add(INITIALIZED_AMOUNT);
                validators[i].delegatedAmount = contractAddress.activeAmount();
                validators[i].commissionRate = contractAddress.commissionRate_deprecated();
            } else {
                validators[i].reward = validators[i].reward.add(INITIALIZED_AMOUNT);
            }

            validators[i].delegatorsReward = INITIALIZED_AMOUNT;
        }
    }

    function updateCheckpointRewardParams(
        uint256 _rewardDecreasePerCheckpoint,
        uint256 _maxRewardedCheckpoints,
        uint256 _checkpointRewardDelta
    ) external {
        require(_maxRewardedCheckpoints.mul(_rewardDecreasePerCheckpoint) <= CHK_REWARD_PRECISION);
        require(_checkpointRewardDelta <= CHK_REWARD_PRECISION);

        rewardDecreasePerCheckpoint = _rewardDecreasePerCheckpoint;
        maxRewardedCheckpoints = _maxRewardedCheckpoints;
        checkpointRewardDelta = _checkpointRewardDelta;

        _getOrCacheEventsHub().logRewardParams(_rewardDecreasePerCheckpoint, _maxRewardedCheckpoints, _checkpointRewardDelta);
    }

    function updateCommissionRate(uint256 validatorId, uint256 newCommissionRate) external {
        uint256 _epoch = currentEpoch;
        uint256 _lastCommissionUpdate = validators[validatorId].lastCommissionUpdate;

        require( // withdrawalDelay == dynasty
            (_lastCommissionUpdate.add(WITHDRAWAL_DELAY) <= _epoch) || _lastCommissionUpdate == 0, // For initial setting of commission rate
            "Cooldown"
        );

        require(newCommissionRate <= MAX_COMMISION_RATE, "Incorrect value");
        _getOrCacheEventsHub().logUpdateCommissionRate(validatorId, newCommissionRate, validators[validatorId].commissionRate);
        validators[validatorId].commissionRate = newCommissionRate;
        validators[validatorId].lastCommissionUpdate = _epoch;
    }

    function _getOrCacheEventsHub() private returns(EventsHub) {
        EventsHub _eventsHub = EventsHub(eventsHub);
        if (_eventsHub == EventsHub(0x0)) {
            _eventsHub = EventsHub(Registry(registry).contractMap(keccak256("eventsHub")));
            eventsHub = address(_eventsHub);
        }
        return _eventsHub;
    }
}
