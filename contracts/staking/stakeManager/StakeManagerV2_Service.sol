// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import {StakeManager} from "./StakeManagerV2.sol";
import {IService} from "../../hub/IService.sol";
import {ISlasher} from "../../hub/ISlasher.sol";
import {ILocker} from "../../hub/ILocker.sol";
import {IStakingHub} from "../../hub/IStakingHub.sol";

/// @title ServicePoS
/// @author Polygon Labs
/// @notice Represents the Polygon PoS network
/// @notice Stakers can subscribe to this Service using the Staking Hub.
contract ServicePoS is StakeManager, IService {
    IStakingHub public stakingHub;
    ISlasher public slasher;
    ILocker public polLocker;

    struct RegisterParams {
        uint256 initalStake;
        uint256 heimdallFee;
        bool acceptDelegation;
        bytes signerPubKey;
    }
    mapping(address /*staker*/ => RegisterParams) public registerParams;

    function reinitializeV2(
        IStakingHub _stakingHub,
        IStakingHub.LockerSettings[] calldata _lockerSettings,
        uint40 _unsubNotice,
        ISlasher _slasher,
        ILocker _polLocker
    ) external onlyGovernance {
        stakingHub = _stakingHub;
        stakingHub.registerService(_lockerSettings, _unsubNotice, address(_slasher));
        slasher = _slasher;
        polLocker = _polLocker;
    }

    modifier onlyStakingHub() {
        require(msg.sender == address(stakingHub), "only StakingHub");
        _;
    }

    // ========== TRIGGERS ==========
    function onSubscribe(address staker, uint256 /*lockingInUntil*/) public onlyStakingHub onlyWhenUnlocked {
        RegisterParams memory params = registerParams[staker];
        delete registerParams[staker];

        require(params.initalStake != 0, "Staker not registered");
        require(currentValidatorSetSize() < validatorThreshold, "no more slots");
        // check if staker has enough locked funds, @todo heimdall fee needs to taken seperately? -> override claimfee
        require(
            polLocker.balanceOf(staker, stakingHub.serviceId(address(this))) >=
                params.initalStake.add(params.heimdallFee),
            "Insufficient funds (re)staked on locker"
        );

        _topUpFee(staker, params.heimdallFee);
        _stakeFor(staker, params.initalStake, params.acceptDelegation, params.signerPubKey);
    }

    function onInitiateUnsubscribe(address staker, bool isLockedIn) public onlyStakingHub {
        if (isLockedIn) revert("locked in");
        uint256 validatorId = NFTContract.tokenOfOwnerByIndex(staker, 0);
        require(validatorAuction[validatorId].amount == 0);

        Status status = validators[validatorId].status;
        require(
            validators[validatorId].activationEpoch > 0 &&
                validators[validatorId].deactivationEpoch == 0 &&
                (status == Status.Active || status == Status.Locked)
        );

        uint256 exitEpoch = currentEpoch.add(1); // notice period
        _unstake(validatorId, exitEpoch);
    }

    function onFinalizeUnsubscribe(address staker) public onlyStakingHub {
        uint256 validatorId = NFTContract.tokenOfOwnerByIndex(staker, 0);

        uint256 deactivationEpoch = validators[validatorId].deactivationEpoch;
        // can only claim stake back after WITHDRAWAL_DELAY
        require(
            deactivationEpoch > 0 &&
                deactivationEpoch.add(WITHDRAWAL_DELAY) <= currentEpoch &&
                validators[validatorId].status != Status.Unstaked
        );

        uint256 amount = validators[validatorId].amount;
        uint256 newTotalStaked = totalStaked.sub(amount);
        totalStaked = newTotalStaked;

        _liquidateRewards(validatorId, msg.sender);

        NFTContract.burn(validatorId);

        validators[validatorId].amount = 0;
        validators[validatorId].jailTime = 0;
        validators[validatorId].signer = address(0);

        signerToValidator[validators[validatorId].signer] = INCORRECT_VALIDATOR_ID;
        validators[validatorId].status = Status.Unstaked;

        _transferToken(msg.sender, amount);
        logger.logUnstaked(msg.sender, validatorId, amount, newTotalStaked);
    }

    // @notice registers staker params
    // @dev has to be called by staker, before subscribing to the service
    function registeOrModifyStakerParams(RegisterParams calldata params) external onlyWhenUnlocked {
        // validate params
        require(params.initalStake >= minDeposit, "Invalid stake");
        require(params.signerPubKey.length == 64, "not pub");
        address signer = address(uint160(uint256(keccak256(params.signerPubKey))));
        require(signer != address(0) && signerToValidator[signer] == 0, "Invalid signer");

        require(params.heimdallFee >= minHeimdallFee, "fee too small");

        registerParams[msg.sender] = params;
    }
}
