// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.5.17;

import {IService} from "../../hub/IService.sol";
import {ILocker} from "../../hub/ILocker.sol";
import {IStakingHub} from "../../hub/IStakingHub.sol";
import {IStakingNFT} from "./IStakingNFT.sol";
import {SafeERC20} from "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import {IERC20} from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract IServiceExtention is IService {
    function pullSelfStake(uint256 validatorId) external returns(uint256 amount, address staker);
    function migrateValidator(uint256 validatorId) external;
}

contract ServiceMigrator {
    using SafeERC20 for IERC20;

    IStakingNFT internal old_stakingNFT;
    IStakingNFT internal new_stakingNFT;
    IServiceExtention internal posService;
    IStakingHub internal stakingHub;
    ILocker internal polLocker;
    IERC20 internal polToken;
    IERC20 internal maticToken;
    uint256 internal serviceId;

    constructor(address _old_stakingNFT, address _new_stakingNFT, address _posService, address _hub,address _polLocker, address _polToken, address _maticToken) public {
        old_stakingNFT = IStakingNFT(_old_stakingNFT);
        new_stakingNFT = IStakingNFT(_new_stakingNFT);
        posService = IServiceExtention(_posService);
        stakingHub = IStakingHub(_hub);
        polLocker = ILocker(_polLocker);
        polToken = IERC20(_polToken);
        maticToken = IERC20(_maticToken);
        serviceId = stakingHub.serviceId(address(posService));
    }

    function migrateStake(uint256 validatorId) external {
        // all matic is migrated to pol, pull pol
        (uint256 amount, address staker) = posService.pullSelfStake(validatorId);

        // deposit in locker
        polToken.safeApprove(address(polLocker), amount);
        polLocker.depositAndApproveFor(staker, serviceId, amount);

        // migrateValidator
        posService.migrateValidator(validatorId);
    }
}
