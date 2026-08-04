// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script, console} from "forge-std/Script.sol";

/// Read-only audit of whether `StakeManager.migrateValidatorsData` still has any work left to do.
///
/// The migration (run once in March 2021) moved delegation reward accounting out of each
/// ValidatorShare and into the StakeManager Validator struct. For every validator it set
/// `reward = share.validatorRewards_deprecated() + 1`, `delegatedAmount = share.activeAmount()`,
/// `commissionRate = share.commissionRate_deprecated()` and `delegatorsReward = 1`.
///
/// Run: forge script script/checks/CheckValidatorsMigrated.s.sol --fork-url mainnet -vv
///      forge script script/checks/CheckValidatorsMigrated.s.sol --fork-url sepolia -vv
contract CheckValidatorsMigrated is Script {
    uint256 constant INITIALIZED_AMOUNT = 1;

    struct Validator {
        uint256 amount;
        uint256 reward;
        uint256 activationEpoch;
        uint256 deactivationEpoch;
        uint256 jailTime;
        address signer;
        address contractAddress;
        uint8 status;
        uint256 commissionRate;
        uint256 lastCommissionUpdate;
        uint256 delegatorsReward;
        uint256 delegatedAmount;
        uint256 initialRewardPerStake;
    }

    address stakeManager;

    // running tallies
    uint256 uninitDelegatorsReward;
    uint256 uninitReward;
    uint256 revertingDelegatorsReward;
    uint256 revertingValidatorReward;
    uint256 staleCommission;
    uint256 delegationDrift;
    uint256 rewardWouldChange;
    uint256 rewardWouldBeDestroyed;
    uint256 rewardWouldBeInvented;
    uint256 commissionWouldChange;

    function run() public {
        if (block.chainid == 1) {
            stakeManager = 0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908;
        } else if (block.chainid == 11155111) {
            stakeManager = 0x4AE8f648B1Ec892B6cc68C89cc088583964d08bE;
        } else {
            revert("unsupported chain");
        }

        uint256 nftCounter = abi.decode(_call("NFTCounter()"), (uint256));
        console.log("chainid          ", block.chainid);
        console.log("StakeManager     ", stakeManager);
        console.log("NFTCounter       ", nftCounter);
        console.log("validator ids     1 ..", nftCounter - 1);
        console.log("");

        for (uint256 id = 1; id < nftCounter; ++id) {
            _checkValidator(id);
        }

        console.log("=== Is any migration still outstanding? (all must be 0) ===");
        console.log("delegatorsReward == 0 (never initialized) :", uninitDelegatorsReward);
        console.log("reward == 0           (never initialized) :", uninitReward);
        console.log("delegatorsReward(id) reverts             :", revertingDelegatorsReward);
        console.log("validatorReward(id)  reverts             :", revertingValidatorReward);
        console.log("commissionRate unset but share has one   :", staleCommission);
        console.log("");
        console.log("=== Would re-running it today change anything? (non-zero == destructive) ===");
        console.log("validators whose reward would change     :", rewardWouldChange);
        console.log("  reward wei destroyed                   :", rewardWouldBeDestroyed);
        console.log("  reward wei invented                    :", rewardWouldBeInvented);
        console.log("validators whose commissionRate changes  :", commissionWouldChange);
        console.log("delegatedAmount != share.activeAmount()  :", delegationDrift);
    }

    function _checkValidator(uint256 id) internal {
        Validator memory v = _validator(id);

        // --- 1. is this validator's data in the post-migration shape? ---
        if (v.delegatorsReward == 0) {
            uninitDelegatorsReward++;
            console.log("UNMIGRATED delegatorsReward==0 id:", id);
        }
        if (v.reward == 0) {
            uninitReward++;
            console.log("UNMIGRATED reward==0 id:", id);
        }

        // The exact symptom that exposed the skipped validator 50 in 2021: the getters
        // do `.add(pending).sub(INITIALIZED_AMOUNT)`, which underflows while the field is 0.
        if (!_staticSucceeds(abi.encodeWithSignature("delegatorsReward(uint256)", id))) {
            revertingDelegatorsReward++;
            console.log("REVERTS delegatorsReward(id) id:", id);
        }
        if (!_staticSucceeds(abi.encodeWithSignature("validatorReward(uint256)", id))) {
            revertingValidatorReward++;
            console.log("REVERTS validatorReward(id) id:", id);
        }

        if (v.contractAddress == address(0)) return;

        uint256 depReward = _shareUint(v.contractAddress, "validatorRewards_deprecated()");
        uint256 depComm = _shareUint(v.contractAddress, "commissionRate_deprecated()");
        uint256 active = _shareUint(v.contractAddress, "activeAmount()");

        if (v.commissionRate == 0 && depComm != 0 && v.lastCommissionUpdate == 0) {
            staleCommission++;
            console.log("STALE commission id:", id, "share commissionRate_deprecated:", depComm);
        }

        // --- 2. what would a re-run write, versus what is there now? ---
        uint256 wouldWriteReward = depReward + INITIALIZED_AMOUNT;
        if (wouldWriteReward != v.reward) {
            rewardWouldChange++;
            if (wouldWriteReward < v.reward) {
                rewardWouldBeDestroyed += v.reward - wouldWriteReward;
            } else {
                rewardWouldBeInvented += wouldWriteReward - v.reward;
            }
        }
        if (depComm != v.commissionRate) commissionWouldChange++;
        if (active != v.delegatedAmount) {
            delegationDrift++;
            console.log("DRIFT id:", id);
            console.log("   delegatedAmount:", v.delegatedAmount);
            console.log("   activeAmount   :", active);
        }
    }

    function _validator(uint256 id) internal view returns (Validator memory v) {
        bytes memory ret = _call("validators(uint256)", id);
        (
            v.amount,
            v.reward,
            v.activationEpoch,
            v.deactivationEpoch,
            v.jailTime,
            v.signer,
            v.contractAddress,
            v.status,
            v.commissionRate,
            v.lastCommissionUpdate,
            v.delegatorsReward,
            v.delegatedAmount,
            v.initialRewardPerStake
        ) = abi.decode(
            ret,
            (
                uint256,
                uint256,
                uint256,
                uint256,
                uint256,
                address,
                address,
                uint8,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256
            )
        );
    }

    function _call(string memory sig) internal view returns (bytes memory) {
        (bool ok, bytes memory ret) = stakeManager.staticcall(abi.encodeWithSignature(sig));
        require(ok, sig);
        return ret;
    }

    function _call(string memory sig, uint256 arg) internal view returns (bytes memory) {
        (bool ok, bytes memory ret) = stakeManager.staticcall(abi.encodeWithSignature(sig, arg));
        require(ok, sig);
        return ret;
    }

    function _staticSucceeds(bytes memory data) internal view returns (bool ok) {
        (ok,) = stakeManager.staticcall(data);
    }

    function _shareUint(address share, string memory sig) internal view returns (uint256) {
        (bool ok, bytes memory ret) = share.staticcall(abi.encodeWithSignature(sig));
        return (ok && ret.length >= 32) ? abi.decode(ret, (uint256)) : 0;
    }
}
