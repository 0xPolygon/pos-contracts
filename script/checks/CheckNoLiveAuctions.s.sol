// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script, console} from "forge-std/Script.sol";

/// Read-only pre-upgrade audit: no auction bid may be sitting in the StakeManager when the
/// auction-less implementation goes live.
///
/// The upgrade removes `startAuction` and `confirmAuctionBid`. A bid held in `validatorAuction`
/// was pulled into the contract by `startAuction`, and `confirmAuctionBid` was the only path that
/// refunded it (to the outbid or losing bidder) or promoted it into a stake; once both are gone
/// the bid is stranded forever. The upgrade is therefore only safe while every
/// `validatorAuction[id].amount` is zero, which this script verifies on a fork of the live chain.
///
/// Note that when the auction window is open (`replacementCoolDown` has passed) a new bid can
/// still land between this check and the upgrade transaction, so run it as close to the upgrade
/// as possible.
///
/// Run: forge script script/checks/CheckNoLiveAuctions.s.sol --fork-url mainnet -vv
///      forge script script/checks/CheckNoLiveAuctions.s.sol --fork-url sepolia -vv
contract CheckNoLiveAuctions is Script {
    address stakeManager;

    uint256 liveBids;
    uint256 strandedAmount;

    function run() public {
        if (block.chainid == 1) {
            stakeManager = 0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908;
        } else if (block.chainid == 11155111) {
            stakeManager = 0x4AE8f648B1Ec892B6cc68C89cc088583964d08bE;
        } else {
            revert("unsupported chain");
        }

        uint256 nftCounter = abi.decode(_call("NFTCounter()"), (uint256));
        uint256 currentEpoch = abi.decode(_call("currentEpoch()"), (uint256));
        uint256 coolDown = abi.decode(_call("replacementCoolDown()"), (uint256));

        console.log("chainid            ", block.chainid);
        console.log("StakeManager       ", stakeManager);
        console.log("currentEpoch       ", currentEpoch);
        console.log("replacementCoolDown", coolDown);
        // Same condition startAuction enforces: bids are accepted once the cooldown has passed.
        if (coolDown == 0 || coolDown <= currentEpoch) {
            console.log("auction window      OPEN (a bid can still land before the upgrade)");
        } else {
            console.log("auction window      CLOSED (cooldown active)");
        }
        console.log("validator ids       1 ..", nftCounter - 1);
        console.log("");

        for (uint256 id = 1; id < nftCounter; ++id) {
            (uint256 amount, uint256 startEpoch, address user) = _auction(id);
            if (amount == 0) continue;
            liveBids++;
            strandedAmount += amount;
            console.log("LIVE BID id:", id);
            console.log("   amount    :", amount);
            console.log("   startEpoch:", startEpoch);
            console.log("   bidder    :", user);
        }

        console.log("=== Safe to upgrade only if live bids == 0 ===");
        console.log("live bids          ", liveBids);
        if (liveBids != 0) {
            console.log("amount the upgrade would strand:", strandedAmount);
            revert("live auction bids found, refund them (confirmAuctionBid) before upgrading");
        }
    }

    function _auction(uint256 id) internal view returns (uint256 amount, uint256 startEpoch, address user) {
        (amount, startEpoch, user, , ) =
            abi.decode(_call("validatorAuction(uint256)", id), (uint256, uint256, address, bool, bytes));
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
}
