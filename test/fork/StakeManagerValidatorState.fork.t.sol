// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

interface IStakeManagerFork {
    function validators(uint256 validatorId)
        external
        view
        returns (
            uint256 amount,
            uint256 reward,
            uint256 activationEpoch,
            uint256 deactivationEpoch,
            uint256 jailTime,
            address signer,
            address contractAddress,
            uint8 status,
            uint256 commissionRate,
            uint256 lastCommissionUpdate,
            uint256 delegatorsReward,
            uint256 delegatedAmount,
            uint256 initialRewardPerStake
        );
    function validatorState() external view returns (uint256 amount, uint256 stakerCount);
    function validatorStateChanges(uint256 epoch) external view returns (int256 amount, int256 stakerCount);
    function NFTCounter() external view returns (uint256);
    function currentEpoch() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function unstakePOL(uint256 validatorId) external;
    function updateImplementation(address newImplementation) external;
    function reinitializeValidatorState(uint256 expectedIncrease) external;
}

interface IGovernanceFork {
    function update(address target, bytes calldata data) external;
}

/// @notice Fork tests for `StakeManager.reinitializeValidatorState`, which recomputes `validatorState.amount`.
/// See pos-contracts-tools docs/quirks/validatorstate-amount-understates-stake.md.
abstract contract StakeManagerValidatorStateForkBase is Test {
    uint8 constant STATUS_ACTIVE = 1;

    IStakeManagerFork stakeManager;
    IGovernanceFork governance;
    // Owner of both the StakeManagerProxy and the GovernanceProxy.
    address timelock;

    // Low byte: the initialized version (Initializable.inited before). Upper bytes: eventsHub_deprecated.
    uint256 constant INIT_SLOT = 35;
    uint256 constant VALIDATOR_STATE_AMOUNT_SLOT = 28;

    function _initSlot() internal view returns (uint256) {
        return uint256(vm.load(address(stakeManager), bytes32(INIT_SLOT)));
    }

    function _assertVersionBumped(uint256 slotBefore) internal view {
        uint256 slotAfter = _initSlot();
        assertEq(slotBefore & 0xff, 1, "initialized at version 1");
        assertEq(slotAfter & 0xff, 2, "now at version 2");
        assertEq(slotAfter >> 8, slotBefore >> 8, "eventsHub_deprecated untouched");
    }

    function _upgrade() internal {
        address impl = deployCode("out/StakeManager.sol/StakeManager.json");
        vm.prank(timelock);
        stakeManager.updateImplementation(impl);
    }

    function _reinitializeValidatorState(uint256 expectedIncrease) internal {
        vm.prank(timelock);
        governance.update(
            address(stakeManager), abi.encodeCall(IStakeManagerFork.reinitializeValidatorState, (expectedIncrease))
        );
    }

    /// @dev Same filter as the reinit: active, or in its notice period.
    function _loopTotal() internal view returns (uint256 total, uint256 count) {
        uint256 epoch = stakeManager.currentEpoch();
        uint256 n = stakeManager.NFTCounter();
        for (uint256 i = 1; i < n; ++i) {
            (uint256 amount,,, uint256 deactivationEpoch,,,, uint8 status,,,, uint256 delegated,) =
                stakeManager.validators(i);
            if (status == STATUS_ACTIVE && (deactivationEpoch == 0 || deactivationEpoch > epoch)) {
                total += amount + delegated;
                ++count;
            }
        }
    }

    function _firstActiveValidator() internal view returns (uint256) {
        uint256 n = stakeManager.NFTCounter();
        for (uint256 i = 8; i < n; ++i) {
            (,,, uint256 deactivationEpoch,,,, uint8 status,,,, uint256 delegated,) = stakeManager.validators(i);
            if (status == STATUS_ACTIVE && deactivationEpoch == 0 && delegated > 0) return i;
        }
        revert("no active validator");
    }
}

contract StakeManagerValidatorStateMainnetForkTest is StakeManagerValidatorStateForkBase {
    uint256 constant FORK_BLOCK = 26_140_000;

    uint256 constant DRIFT = 21_478_224_763_075_260_225_085_417;

    // Values at FORK_BLOCK, recomputed independently with `cast` over validators(1..NFTCounter-1).
    uint256 constant STATE_AMOUNT_AT_FORK = 3_452_345_345_262_043_667_615_095_113;
    uint256 constant LOOP_TOTAL_AT_FORK = 3_473_823_570_025_118_927_840_180_530;
    uint256 constant STAKER_COUNT_AT_FORK = 104;

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK);
        stakeManager = IStakeManagerFork(0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908);
        governance = IGovernanceFork(0x6e7a5820baD6cebA8Ef5ea69c0C92EbbDAc9CE48);
        timelock = 0xCaf0aa768A3AE1297DF20072419Db8Bb8b5C8cEf;
    }

    function test_reinitializeValidatorState_correctsByExactlyTheDrift() public {
        (uint256 stateBefore, uint256 stakerCountBefore) = stakeManager.validatorState();
        (uint256 loopTotal, uint256 loopCount) = _loopTotal();
        uint256 diff = loopTotal - stateBefore;

        assertEq(stateBefore, STATE_AMOUNT_AT_FORK, "pinned validatorState.amount");
        assertEq(loopTotal, LOOP_TOTAL_AT_FORK, "pinned loop total");
        assertEq(diff, DRIFT, "pre-upgrade diff is the documented drift");
        assertEq(stakerCountBefore, STAKER_COUNT_AT_FORK, "pinned stakerCount");
        assertEq(loopCount, stakerCountBefore, "stakerCount already matches the loop filter");

        _upgrade();
        uint256 slotBefore = _initSlot();

        uint256 gasBefore = gasleft();
        _reinitializeValidatorState(diff);
        emit log_named_uint("reinitializeValidatorState gas", gasBefore - gasleft());
        _assertVersionBumped(slotBefore);

        (uint256 stateAfter, uint256 stakerCountAfter) = stakeManager.validatorState();
        assertEq(stateAfter, stateBefore + diff, "corrected by exactly the pre-computed diff");
        assertEq(stateAfter, loopTotal, "total matches the per-validator records");
        assertEq(stakerCountAfter, stakerCountBefore, "stakerCount untouched");

        (uint256 loopTotalAfter,) = _loopTotal();
        assertEq(loopTotalAfter, loopTotal, "per-validator records untouched");
    }

    function test_reinitializeValidatorState_writesOnlyTotalAndVersion() public {
        _upgrade();
        (uint256 stateBefore,) = stakeManager.validatorState();

        vm.startStateDiffRecording();
        _reinitializeValidatorState(DRIFT);
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        uint256 writes;
        for (uint256 i = 0; i < accesses.length; ++i) {
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory sa = accesses[i].storageAccesses[j];
                if (!sa.isWrite || sa.previousValue == sa.newValue) continue;
                ++writes;
                assertEq(sa.account, address(stakeManager), "only StakeManager storage changes");
                if (uint256(sa.slot) == VALIDATOR_STATE_AMOUNT_SLOT) {
                    assertEq(uint256(sa.previousValue), stateBefore);
                    assertEq(uint256(sa.newValue), stateBefore + DRIFT);
                } else {
                    assertEq(uint256(sa.slot), INIT_SLOT, "unexpected slot written");
                }
            }
        }
        assertEq(writes, 2, "exactly the total and the version byte change");
    }

    function test_reinitializeValidatorState_countsValidatorInNoticePeriod() public {
        _upgrade();

        uint256 validatorId = _firstActiveValidator();
        (uint256 amount,,,,,,,,,,, uint256 delegated,) = stakeManager.validators(validatorId);
        (uint256 stateBefore,) = stakeManager.validatorState();

        vm.prank(stakeManager.ownerOf(validatorId));
        stakeManager.unstakePOL(validatorId);

        uint256 exitEpoch = stakeManager.currentEpoch() + 1;
        (,,, uint256 deactivationEpoch,,,,,,,,,) = stakeManager.validators(validatorId);
        assertEq(deactivationEpoch, exitEpoch, "in notice period");
        (int256 queued,) = stakeManager.validatorStateChanges(exitEpoch);
        assertEq(queued, -int256(amount + delegated), "removal queued for exit epoch");

        _reinitializeValidatorState(DRIFT);

        (uint256 stateAfter,) = stakeManager.validatorState();
        assertEq(stateAfter, stateBefore + DRIFT, "notice-period validator still counted");
        // Once the queued change applies, the total equals the stake of the remaining validators exactly.
        (uint256 loopTotal,) = _loopTotal();
        assertEq(int256(stateAfter) + queued, int256(loopTotal - amount - delegated));
    }

    function test_reinitializeValidatorState_secondCallReverts() public {
        _upgrade();
        _reinitializeValidatorState(DRIFT);

        // Governance.update masks the reason as "Update failed", so call as the governance proxy directly.
        vm.startPrank(address(governance));
        vm.expectRevert("already inited");
        stakeManager.reinitializeValidatorState(DRIFT);
        vm.expectRevert("already inited");
        stakeManager.reinitializeValidatorState(0);
        vm.stopPrank();
    }

    function test_reinitializeValidatorState_revertsOnWrongExpectation() public {
        _upgrade();

        vm.startPrank(address(governance));
        vm.expectRevert("unexpected increase");
        stakeManager.reinitializeValidatorState(DRIFT - 1);
        vm.expectRevert("unexpected increase");
        stakeManager.reinitializeValidatorState(DRIFT + 1);
        vm.expectRevert("unexpected increase");
        stakeManager.reinitializeValidatorState(0);
        vm.stopPrank();

        assertEq(_initSlot() & 0xff, 1, "failed reinit leaves the version unchanged");
    }

    function test_reinitializeValidatorState_revertsForNonGovernance() public {
        _upgrade();

        // The Timelock owns the proxy and Governance, but is not Governance itself.
        vm.prank(timelock);
        vm.expectRevert("Only governance contract is authorized");
        stakeManager.reinitializeValidatorState(DRIFT);

        vm.expectRevert("Only governance contract is authorized");
        stakeManager.reinitializeValidatorState(DRIFT);
    }
}

/// @dev Sepolia never had the pre-2022 bug, so the same code runs there with an expected increase of 0.
contract StakeManagerValidatorStateSepoliaForkTest is StakeManagerValidatorStateForkBase {
    uint256 constant FORK_BLOCK = 11_863_000;

    // Values at FORK_BLOCK, recomputed independently with `cast` over validators(1..NFTCounter-1).
    uint256 constant STATE_AMOUNT_AT_FORK = 480_336_920_026_522_681_124_373_273;
    uint256 constant STAKER_COUNT_AT_FORK = 23;

    function setUp() public {
        vm.createSelectFork("sepolia", FORK_BLOCK);
        stakeManager = IStakeManagerFork(0x4AE8f648B1Ec892B6cc68C89cc088583964d08bE);
        governance = IGovernanceFork(0xB7086eda3180c728C1536B35c4d54F6A2B33D6aC);
        timelock = 0xeE76bECaF80fFe451c8B8AFEec0c21518Def02f9;
    }

    function test_reinitializeValidatorState_noDriftIsNoop() public {
        (uint256 stateBefore, uint256 stakerCountBefore) = stakeManager.validatorState();
        (uint256 loopTotal, uint256 loopCount) = _loopTotal();

        assertEq(stateBefore, STATE_AMOUNT_AT_FORK, "pinned validatorState.amount");
        assertEq(loopTotal, stateBefore, "no drift on sepolia");
        assertEq(stakerCountBefore, STAKER_COUNT_AT_FORK, "pinned stakerCount");
        assertEq(loopCount, stakerCountBefore, "stakerCount already matches the loop filter");

        _upgrade();
        uint256 slotBefore = _initSlot();
        _reinitializeValidatorState(0);
        _assertVersionBumped(slotBefore);

        (uint256 stateAfter, uint256 stakerCountAfter) = stakeManager.validatorState();
        assertEq(stateAfter, stateBefore);
        assertEq(stakerCountAfter, stakerCountBefore);
    }
}

/// @dev Replays the first real mainnet checkpoint after the pinned block on top of the upgrade, with and
/// without the correction.
contract StakeManagerValidatorStateCheckpointForkTest is StakeManagerValidatorStateForkBase {
    // RootChain.submitCheckpoint at block 26,140,053; its calldata is pinned in fixtures/.
    bytes32 constant CHECKPOINT_TX = 0x179e64f5a7d5329eb526984a0bb69f428ca5370e3d8e0f9c7a0f90a04e5e6655;
    address constant CHECKPOINT_SENDER = 0x69F5C4D08F6bC8cD29fE5f004d46FB566270868d;
    address constant ROOT_CHAIN = 0x86E4Dc95c7FBdBf52e33D563BbDB00823894C287;
    uint256 constant DRIFT = 21_478_224_763_075_260_225_085_417;
    // Reward CHECKPOINT_TX paid on mainnet.
    uint256 constant ONCHAIN_REWARD = 6_487_180_236_265_770_255_206;
    bytes32 constant NEW_HEADER_BLOCK = keccak256("NewHeaderBlock(address,uint256,uint256,uint256,uint256,bytes32)");

    function setUp() public {
        // Forks at the state right before CHECKPOINT_TX.
        vm.createSelectFork("mainnet", CHECKPOINT_TX);
        stakeManager = IStakeManagerFork(0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908);
        governance = IGovernanceFork(0x6e7a5820baD6cebA8Ef5ea69c0C92EbbDAc9CE48);
        timelock = 0xCaf0aa768A3AE1297DF20072419Db8Bb8b5C8cEf;
        _upgrade();
    }

    function test_checkpoint_rewardScalesWithCorrectedTotal() public {
        uint256 snapshot = vm.snapshotState();
        (uint256 stateUncorrected,) = stakeManager.validatorState();
        uint256 rewardUncorrected = _replayCheckpoint();
        assertEq(rewardUncorrected, ONCHAIN_REWARD, "replay on the upgrade alone matches mainnet");

        vm.revertToState(snapshot);
        _reinitializeValidatorState(DRIFT);
        (uint256 stateCorrected,) = stakeManager.validatorState();
        uint256 rewardCorrected = _replayCheckpoint();

        assertEq(stateCorrected, stateUncorrected + DRIFT);
        assertLt(rewardCorrected, rewardUncorrected, "same signatures earn less against the larger total");
        // reward = floor(base * signed / total), so reward * total is within one total of base * signed.
        assertApproxEqAbs(rewardCorrected * stateCorrected, rewardUncorrected * stateUncorrected, stateCorrected);
        emit log_named_uint("reward uncorrected", rewardUncorrected);
        emit log_named_uint("reward corrected", rewardCorrected);
    }

    function test_checkpoint_appliesNoticePeriodRemovalOnce() public {
        uint256 validatorId = _firstActiveValidator();
        vm.prank(stakeManager.ownerOf(validatorId));
        stakeManager.unstakePOL(validatorId);

        _reinitializeValidatorState(DRIFT);
        _replayCheckpoint();

        // The checkpoint moved the epoch past the exit, so the validator dropped out of both sides.
        (,,, uint256 deactivationEpoch,,,,,,,,,) = stakeManager.validators(validatorId);
        assertEq(stakeManager.currentEpoch(), deactivationEpoch, "exit epoch reached");
        (uint256 state,) = stakeManager.validatorState();
        (uint256 loopTotal, uint256 loopCount) = _loopTotal();
        assertEq(state, loopTotal, "total matches the records after the queued removal");
        (, uint256 stakerCount) = stakeManager.validatorState();
        assertEq(stakerCount, loopCount);
    }

    function _replayCheckpoint() internal returns (uint256 reward) {
        // Sent directly rather than via vm.transact, which keeps the original gas limit (88k headroom).
        bytes memory input = vm.parseBytes(vm.readFile("test/fork/fixtures/checkpoint-0x179e64f5.txt"));
        vm.recordLogs();
        vm.prank(CHECKPOINT_SENDER);
        (bool ok,) = ROOT_CHAIN.call{gas: 10_000_000}(input);
        assertTrue(ok, "submitCheckpoint reverted");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == NEW_HEADER_BLOCK) return uint256(logs[i].topics[3]);
        }
        revert("checkpoint not accepted");
    }
}
