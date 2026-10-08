pragma solidity 0.5.17;

// FROZEN — reproduces the deployed `StakeManagerExtension` (0xef49Ea6996073752b6840CDA34773FFA78F78166).
//
// The live StakeManager pair straddles the POL storage addition: the deployed StakeManager
// implementation (0x3AD88467E40399dc6Ae10427f8B0842348d9076c, 2024) carries the two POL slots
// `tokenMatic`/`migration`, while the extension it delegates to was deployed in 2021 and predates
// them. Because the extension declares `public` state, those two slots would emit two extra
// getters into its runtime bytecode and it would no longer reproduce on-chain.
//
// This contract is the pre-POL layout. `StakeManagerStorageExtension` extends it with the two POL
// slots, so the shared prefix is defined exactly once and cannot drift between the two. Appending
// in the derived contract keeps every slot in this file at the same position for both.
//
// Do not add state here. New storage belongs in `StakeManagerStorageExtension`; adding it here
// would shift the POL slots and break the deployed StakeManager.
contract StakeManagerStorageExtensionLegacy {
    address public eventsHub;
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
}
