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
    ILocker[] public lockerContracts;

    struct RegisterParams {
        uint256 initalStake;
        uint256 heimdallFee;
        bool acceptDelegation;
        bytes signerPubKey;
    }
    mapping(address => RegisterParams) public registerParams;

    // self-registers as Service, @todo set msg.sender as owner ?
    // @todo make this reinitialize(2)
    constructor(
        address _stakingHub,
        IStakingHub.LockerSettings[] memory _lockers,
        uint40 _unsubNotice,
        address _slasher
    ) public {
        stakingHub = IStakingHub(_stakingHub);
        stakingHub.registerService(_lockers, _unsubNotice, _slasher);
        slasher = ISlasher(_slasher);
        // lockerContracts = _lockerContracts; // @todo
    }

    modifier onlyStakingHub() {
        require(msg.sender == address(stakingHub), "only StakingHub");
        _;
    }

    function initiateSlasherUpdate(address _slasher) public onlyOwner {
        stakingHub.initiateSlasherUpdate(_slasher);
    }

    function finalizeSlasherUpdate() public onlyOwner {
        stakingHub.finalizeSlasherUpdate();
    }

    function freeze(address staker, bytes calldata proof) external onlyOwner {
        slasher.freeze(staker, proof);
    }

    function slash(address staker, uint8[] calldata percentages) external {
        slasher.slash(staker, percentages);
    }

    /// @notice services monitor
    function terminateStaker(address staker) public onlyOwner {
        stakingHub.terminate(staker);
        //@todo _unstake(staker, 0, true);
    }

    // ========== TRIGGERS ==========
    function onSubscribe(address staker, uint256 lockingInUntil) public onlyStakingHub onlyWhenUnlocked {
        RegisterParams memory params = registerParams[staker];
        require(params.initalStake != 0, "Staker not registered");
        require(currentValidatorSetSize() < validatorThreshold, "no more slots");

        delete registerParams[staker];
    }

    // function stakeFor() external {}

    // function onInitiateUnsubscribe(address staker, bool) public onlyStakingHub {}

    function onFinalizeUnsubscribe(address staker) public onlyStakingHub {}

    function registeOrModifyStakerParams(address staker, RegisterParams calldata params) external onlyWhenUnlocked {
        // @todo check locker balance ?
        require(params.initalStake >= minDeposit, "Invalid stake");
        require(params.signerPubKey.length == 64, "not pub");
        address signer = address(uint160(uint256(keccak256(params.signerPubKey))));
        require(signer != address(0) && signerToValidator[signer] == 0, "Invalid signer");
        registerParams[staker] = params;
    }
}
