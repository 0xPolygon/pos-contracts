// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.5.17;

import {StakeManagerV2} from "./StakeManagerV2.sol";

import {IService} from "@staking-hub/interface/IService.sol";
import {ISlasher} from "@staking-hub/example/interface/ISlasher.sol";
import {ERC20Locker} from "@staking-hub/template/ERC20Locker.sol";
import {StakingHub, LockerSettings} from "@staking-hub/StakingHub.sol";
import {Ownable} from "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/// @title ServicePoS
/// @author Polygon Labs
/// @notice Represents the Polygon PoS network
/// @notice Stakers can subscribe to this Service using the Staking Hub.
contract ServicePoS is StakeManagerV2, IService, Ownable {
    StakingHub stakingHub;
    ISlasher slasher;
    ERC20Locker[] lockerContracts;

    // self-registers as Service, set msg.sender as owner
    constructor(address _stakingHub, LockerSettings[] memory _lockers, uint40 unsubNotice, address _slasher)
        Ownable(msg.sender)
    {
        stakingHub = StakingHub(_stakingHub);

        stakingHub.registerService(_lockers, unsubNotice, _slasher);

        slasher = ISlasher(_slasher);
        lockerContracts = _lockerContracts;
    }

    function initiateSlasherUpdate(address _slasher) public onlyOwner {
        stakingHub.initiateSlasherUpdate(_slasher);
    }

    function finalizeSlasherUpdate() public onlyOwner {
        stakingHub.finalizeSlasherUpdate();
    }

    function freeze(address staker, bytes calldata proof) public onlyOwner {
        slasher.freeze(staker, proof);
    }

    function slash(address staker, uint8[] calldata percentages) public {
        slasher.slash(staker, percentages);
    }

    /// @notice services monitor
    function terminateStaker(address staker) public onlyOwner {
        stakingHub.terminate(staker);
        _unstake(staker, 0, true);
    }

    // ========== TRIGGERS ==========
    function onSubscribe(address staker, uint256 lockingInUntil) public {
        // TODO call _stakeFor and check for validator NFT smh


    }

    function onInitiateUnsubscribe(address staker, bool) public {}

    function onFinalizeUnsubscribe(address staker) public {}
}
