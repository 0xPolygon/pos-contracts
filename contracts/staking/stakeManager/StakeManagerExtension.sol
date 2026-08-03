pragma solidity 0.5.17;

import {SafeMath} from "../../common/oz/math/SafeMath.sol";
import {Registry} from "../../common/Registry.sol";
import {GovernanceLockable} from "../../common/mixin/GovernanceLockable.sol";
import {StakeManagerStorage} from "./StakeManagerStorage.sol";
import {StakeManagerStorageExtension} from "./StakeManagerStorageExtension.sol";
import {Initializable} from "../../common/mixin/Initializable.sol";
import {EventsHub} from "../EventsHub.sol";

contract StakeManagerExtension is StakeManagerStorage, Initializable, StakeManagerStorageExtension {
    using SafeMath for uint256;

    constructor() public GovernanceLockable(address(0x0)) {}

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

        _getOrCacheEventsHub().logRewardParams(
            _rewardDecreasePerCheckpoint, _maxRewardedCheckpoints, _checkpointRewardDelta
        );
    }

    function updateCommissionRate(uint256 validatorId, uint256 newCommissionRate) external {
        uint256 _epoch = currentEpoch;
        uint256 _lastCommissionUpdate = validators[validatorId].lastCommissionUpdate;

        require( // withdrawalDelay == dynasty
            (_lastCommissionUpdate.add(WITHDRAWAL_DELAY) <= _epoch) || _lastCommissionUpdate == 0, // For initial
                // setting of commission rate
            "Cooldown"
        );

        require(newCommissionRate <= MAX_COMMISION_RATE, "Incorrect value");
        _getOrCacheEventsHub().logUpdateCommissionRate(
            validatorId, newCommissionRate, validators[validatorId].commissionRate
        );
        validators[validatorId].commissionRate = newCommissionRate;
        validators[validatorId].lastCommissionUpdate = _epoch;
    }

    function _getOrCacheEventsHub() private returns (EventsHub) {
        EventsHub _eventsHub = EventsHub(eventsHub);
        if (_eventsHub == EventsHub(0x0)) {
            _eventsHub = EventsHub(Registry(registry).contractMap(keccak256("eventsHub")));
            eventsHub = address(_eventsHub);
        }
        return _eventsHub;
    }
}
