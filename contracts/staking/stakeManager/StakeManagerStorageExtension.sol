pragma solidity 0.5.17;

import {IPolygonMigration} from "../../common/misc/IPolygonMigration.sol";
import {IERC20} from "../../common/oz/token/ERC20/IERC20.sol";

contract StakeManagerStorageExtension {
    address public eventsHub;
    uint256 public rewardPerStake;
    address public extensionCode;
    address[] public signers;

    uint256 constant CHK_REWARD_PRECISION = 100;
    uint256 public prevBlockInterval;
    // how much less reward per skipped checkpoint, 0 - 100%
    uint256 public rewardDecreasePerCheckpoint;
    // how many checkpoints to reward
    uint256 public maxRewardedCheckpoints;
    // increase / decrease value for faster or slower checkpoints, 0 - 100%
    uint256 public checkpointRewardDelta;

    IERC20 public tokenMatic;
    IPolygonMigration public migration;
}   
