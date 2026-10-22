// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../script/setup/DeploySystem.s.sol";
import {StakeManagerStorage} from "../../../tools/interfaces/StakeManager.generated.sol";

/// @notice Offline coverage for `StakeManager.reinitializeValidatorState`. The mainnet numbers live in the fork tests.
contract StakeManagerReinitializeTest is Test, DeploySystem {
    // Slots of `validatorState.amount` and `validatorState.stakerCount`.
    uint256 constant VALIDATOR_STATE_AMOUNT_SLOT = 28;
    uint256 constant VALIDATOR_STATE_STAKER_COUNT_SLOT = 29;

    Validator[] active;
    address alice = makeAddr("alice");
    uint256 delegation = 1000e18;

    function setUp() public {
        deployAll();
        setTestConfig();
        // Leaves validators 1-7 force-unstaked with deactivationEpoch == currentEpoch.
        skipFoundationValidators();
        for (uint8 id = 8; id <= 10; ++id) {
            Validator memory v = createValidator(id);
            addValidator(v);
            active.push(v);
        }
        buyVouchersPOL(9, alice, delegation);
    }

    /// @dev Regression for 48f22883: a delegator exiting after its validator unstaked drifted the total
    /// before that fix. Current code must keep it in lockstep, so the recompute finds nothing to correct.
    function test_reinitializeValidatorState_noCorrectionAfterDelegatorExitFromUnstakedValidator() public {
        vm.prank(active[1].addr);
        stakeManager.unstakePOL(9);
        _checkpoint();
        assertEq(stakeManager.epoch(), _deactivationEpoch(9), "validator 9 has exited");

        (uint256 stake,) = getValidatorShareContract(9).getTotalStake(alice);
        sellVouchersPOL(9, alice, stake);
        assertEq(stakeManager.delegatedAmount(9), 0, "delegator exited");

        (uint256 stateBefore, uint256 stakerCountBefore) = stakeManager.validatorState();
        assertEq(stateBefore, _loopTotal(), "current code keeps the total in lockstep");

        _reinitializeValidatorState(0);

        (uint256 stateAfter, uint256 stakerCountAfter) = stakeManager.validatorState();
        assertEq(stateAfter, stateBefore);
        assertEq(stakerCountAfter, stakerCountBefore);
    }

    function test_reinitializeValidatorState_restoresInjectedDrift() public {
        (uint256 real,) = stakeManager.validatorState();
        uint256 drift = 123e18;
        vm.store(address(stakeManager), bytes32(VALIDATOR_STATE_AMOUNT_SLOT), bytes32(real - drift));

        vm.prank(address(governance));
        vm.expectRevert("unexpected increase");
        stakeManager.reinitializeValidatorState(drift - 1);

        _reinitializeValidatorState(drift);

        (uint256 state,) = stakeManager.validatorState();
        assertEq(state, real);
    }

    function test_reinitializeValidatorState_revertsOnStakerCountMismatch() public {
        (, uint256 stakerCount) = stakeManager.validatorState();
        vm.store(address(stakeManager), bytes32(VALIDATOR_STATE_STAKER_COUNT_SLOT), bytes32(stakerCount + 1));

        vm.prank(address(governance));
        vm.expectRevert("unexpected staker count");
        stakeManager.reinitializeValidatorState(0);
    }

    function _reinitializeValidatorState(uint256 expectedIncrease) internal {
        vm.prank(address(governance));
        stakeManager.reinitializeValidatorState(expectedIncrease);
    }

    function _checkpoint() internal {
        Validator[] memory signers = active;
        // checkSignatures stops at the first out-of-order signer.
        for (uint256 i = 0; i < signers.length; ++i) {
            for (uint256 j = i + 1; j < signers.length; ++j) {
                if (signers[j].addr < signers[i].addr) (signers[i], signers[j]) = (signers[j], signers[i]);
            }
        }
        progressCheckpointWithRewards(signers, signers[0].addr);
    }

    function _deactivationEpoch(uint256 validatorId) internal view returns (uint256 deactivationEpoch) {
        (,,, deactivationEpoch,,,,,,,,,) = stakeManager.validators(validatorId);
    }

    /// @dev Same filter as the reinit: active, or in its notice period.
    function _loopTotal() internal view returns (uint256 total) {
        uint256 epoch = stakeManager.epoch();
        for (uint256 i = 1; i < stakeManager.NFTCounter(); ++i) {
            (uint256 amount,,, uint256 deactivationEpoch,,,, StakeManagerStorage.Status status,,,, uint256 delegated,) =
                stakeManager.validators(i);
            if (StakeManagerStorage.Status.unwrap(status) == 1 && (deactivationEpoch == 0 || deactivationEpoch > epoch))
            {
                total += amount + delegated;
            }
        }
    }
}
