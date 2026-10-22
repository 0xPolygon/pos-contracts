// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";

interface IStakeManagerView {
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
    function CHECKPOINT_REWARD() external view returns (uint256);
    function governance() external view returns (address);
    function owner() external view returns (address);
    function updateImplementation(address newImplementation) external;
    function reinitializeValidatorState(uint256 expectedIncrease) external;
}

/// @notice Read-only report on `validatorState.amount`: how far it is from the per-validator records, and what
/// correcting it with `StakeManager.reinitializeValidatorState` would change for consensus and rewards. Nothing is
/// broadcast; the last step simulates the upgrade and the reinit on the fork.
///
///   forge script script/updates/validator-state/ValidatorStateImpact.s.sol --rpc-url mainnet [--fork-block-number N]
///   forge script script/updates/validator-state/ValidatorStateImpact.s.sol --rpc-url sepolia
///
/// LOOKBACK_BLOCKS (default 7200, ~1 day of L1 blocks) sets the window used to measure actual checkpoint rewards.
contract ValidatorStateImpact is Script {
    using stdJson for string;

    uint8 constant STATUS_ACTIVE = 1;
    bytes32 constant NEW_HEADER_BLOCK = keccak256("NewHeaderBlock(address,uint256,uint256,uint256,uint256,bytes32)");

    IStakeManagerView stakeManager;
    address rootChain;

    function run() public {
        string memory input = vm.readFile("script/updates/validator-state/input.json");
        string memory chain = string.concat('["', vm.toString(block.chainid), '"]');
        stakeManager = IStakeManagerView(input.readAddress(string.concat(chain, ".stakeManagerProxy")));
        rootChain = input.readAddress(string.concat(chain, ".rootChainProxy"));

        console.log("chain %s, block %s", block.chainid, block.number);
        console.log("");

        (uint256 stored, uint256 stakerCount) = stakeManager.validatorState();
        uint256 real = _recompute(stakerCount);
        console.log("");

        if (real < stored) {
            console.log(
                "stored total EXCEEDS the records by %s; reinitializeValidatorState would revert", _pol(stored - real)
            );
            return;
        }
        uint256 diff = real - stored;
        _consensus(stored, real);
        console.log("");
        _rewards(stored, real);
        console.log("");
        _simulate(stored, diff);
    }

    /// @dev Same filter as `reinitializeValidatorState`: active, or in its notice period.
    function _recompute(uint256 stakerCount) internal view returns (uint256 total) {
        uint256 epoch = stakeManager.currentEpoch();
        uint256 n = stakeManager.NFTCounter();
        console.log("== validatorState.amount (epoch %s, validator ids 1..%s)", epoch, n - 1);
        uint256 count;
        uint256 noticeStake;
        for (uint256 i = 1; i < n; ++i) {
            (uint256 amount,,, uint256 deactivationEpoch,,,, uint8 status,,,, uint256 delegated,) =
                stakeManager.validators(i);
            if (status != STATUS_ACTIVE || (deactivationEpoch != 0 && deactivationEpoch <= epoch)) continue;
            total += amount + delegated;
            ++count;
            if (deactivationEpoch != 0) {
                noticeStake += amount + delegated;
                console.log(
                    "  validator %s in notice period until epoch %s: %s", i, deactivationEpoch, _pol(amount + delegated)
                );
            }
        }
        (uint256 stored,) = stakeManager.validatorState();
        (int256 queued,) = stakeManager.validatorStateChanges(epoch + 1);

        console.log("stored                 %s", _pol(stored));
        console.log("recomputed             %s", _pol(total));
        if (total >= stored) {
            console.log("difference             +%s", _pol(total - stored));
            console.log("expectedIncrease (wei) %s", total - stored);
        } else {
            console.log("difference             -%s", _pol(stored - total));
        }
        console.log(
            "validators counted     %s (stakerCount %s)%s", count, stakerCount, count == stakerCount ? "" : "  MISMATCH"
        );
        console.log(
            "notice-period stake    %s, queued for epoch %s: %s", _pol(noticeStake), epoch + 1, _polSigned(queued)
        );
    }

    function _consensus(uint256 stored, uint256 real) internal pure {
        uint256 thresholdNow = stored * 2 / 3 + 1;
        uint256 thresholdAfter = real * 2 / 3 + 1;
        console.log("== L1 checkpoint threshold (signed stake >= total * 2/3 + 1)");
        console.log("now                    %s = %s of real stake", _pol(thresholdNow), _pct(thresholdNow, real));
        console.log("after                  %s = %s of real stake", _pol(thresholdAfter), _pct(thresholdAfter, real));
        console.log("raised by              %s", _pol(thresholdAfter - thresholdNow));
    }

    /// @dev Every checkpoint reward is `... * signedStake / validatorState.amount`, so the correction scales each
    /// one by stored / real whatever its interval and signing. Applies that to the rewards actually paid.
    function _rewards(uint256 stored, uint256 real) internal {
        uint256 lookback = vm.envOr("LOOKBACK_BLOCKS", uint256(7200));
        uint256 to = block.number;
        uint256 from = to > lookback ? to - lookback : 0;
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = NEW_HEADER_BLOCK;
        VmSafe.EthGetLogs[] memory logs = vm.eth_getLogs(from, to, rootChain, topics);

        uint256 paid;
        for (uint256 i = 0; i < logs.length; ++i) {
            paid += uint256(logs[i].topics[3]);
        }
        uint256 paidAfter = paid * stored / real;
        uint256 checkpointReward = stakeManager.CHECKPOINT_REWARD();

        console.log("== Checkpoint rewards (blocks %s..%s, %s checkpoints)", from, to, logs.length);
        if (logs.length == 0) {
            console.log("no checkpoints in the window");
            return;
        }
        // 12s L1 blocks.
        uint256 perYear = 365 days / 12;
        console.log("paid in window         %s", _pol(paid));
        console.log("same window, corrected %s (%s)", _pol(paidAfter), _pctChange(paidAfter, paid));
        console.log("per year now           %s", _pol(paid * perYear / (to - from)));
        console.log("per year corrected     %s", _pol(paidAfter * perYear / (to - from)));
        console.log("gross staker APR now   %s", _pct(paid * perYear / (to - from), real));
        console.log("gross APR corrected    %s", _pct(paidAfter * perYear / (to - from), real));
        console.log("CHECKPOINT_REWARD      %s", _pol(checkpointReward));
        console.log(
            "  to keep payout       %s (wei %s)",
            _pol(checkpointReward * real / stored),
            checkpointReward * real / stored
        );
    }

    /// @dev Upgrades to the local build and runs the reinit with the computed value, as governance would.
    function _simulate(uint256 stored, uint256 diff) internal {
        console.log("== Simulation on the fork (local build of StakeManager)");
        address impl = deployCode("out/StakeManager.sol/StakeManager.json");
        vm.prank(stakeManager.owner());
        stakeManager.updateImplementation(impl);
        vm.prank(stakeManager.governance());
        stakeManager.reinitializeValidatorState(diff);
        (uint256 amount,) = stakeManager.validatorState();
        require(amount == stored + diff, "simulation: unexpected total");
        console.log("reinitializeValidatorState(%s) ok, new total %s", diff, _pol(amount));
        console.log("calldata for Governance.update(stakeManager, ...):");
        console.logBytes(abi.encodeCall(IStakeManagerView.reinitializeValidatorState, (diff)));
    }

    function _pol(uint256 wei_) internal pure returns (string memory) {
        uint256 frac = (wei_ % 1e18) / 1e12;
        string memory f = vm.toString(frac);
        while (bytes(f).length < 6) f = string.concat("0", f);
        return string.concat(vm.toString(wei_ / 1e18), ".", f, " POL");
    }

    function _polSigned(int256 wei_) internal pure returns (string memory) {
        return wei_ < 0 ? string.concat("-", _pol(uint256(-wei_))) : _pol(uint256(wei_));
    }

    /// @dev a / b as a percentage with 4 decimals.
    function _pct(uint256 a, uint256 b) internal pure returns (string memory) {
        uint256 bp = a * 1e6 / b;
        string memory f = vm.toString(bp % 1e4);
        while (bytes(f).length < 4) f = string.concat("0", f);
        return string.concat(vm.toString(bp / 1e4), ".", f, "%");
    }

    function _pctChange(uint256 a, uint256 b) internal pure returns (string memory) {
        return a >= b ? string.concat("+", _pct(a - b, b)) : string.concat("-", _pct(b - a, b));
    }
}
