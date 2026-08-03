// SPDX-License-Identifier: MIT
pragma solidity ^0.5.2;

import {GovernableLegacy} from "../governance/GovernableLegacy.sol";

// Frozen, pre-refactor Lockable: `Lockable is Governable`, revert string
// "Is Locked", lock()/unlock() external+onlyGovernance.
//
// The modern split (mixin/Lockable.sol + mixin/GovernanceLockable.sol, commit
// d0cbfb42) reordered inheritance, which changes the resulting storage layout.
// That split is used by the currently-deployed implementations, so it must stay.
// The immutable DepositManagerProxy (deployed BEFORE the split) uses this legacy
// copy via DepositManagerStorageLegacy so a normal `forge build` reproduces its
// on-chain bytecode and storage layout. Do not edit.
contract LockableLegacy is GovernableLegacy {
    bool public locked;

    modifier onlyWhenUnlocked() {
        require(!locked, "Is Locked");
        _;
    }

    constructor(address _governance) public GovernableLegacy(_governance) {}

    function lock() external onlyGovernance {
        locked = true;
    }

    function unlock() external onlyGovernance {
        locked = false;
    }
}
