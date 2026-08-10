pragma solidity 0.5.17;

import {IPolygonMigration} from "../../common/misc/IPolygonMigration.sol";
import {IERC20} from "../../common/oz/token/ERC20/IERC20.sol";

contract StakeManagerStorageExtension {
    // DEPRECATED. The EventsHub is resolved from the Registry on every use — see
    // StakeManager.eventsHub. Nothing reads or writes this slot any more; it is kept only to hold
    // the layout. It cannot be removed or reordered: on the live proxy it still holds the address
    // written in 2021, and it packs into the low bytes of the slot it shares with
    // Initializable.inited, so dropping it would shift every variable below.
    address internal eventsHub_deprecated;
    uint256 public rewardPerStake;
    address public extensionCode;
    address[] public signers;

    uint256 internal constant CHK_REWARD_PRECISION = 100;
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
