// SPDX-License-Identifier: MIT
pragma solidity ^0.5.2;

import {IGovernance} from "./IGovernance.sol";

// Frozen, pre-refactor Governable (onlyGovernance inlined at each use site).
//
// The modern Governable (governance/Governable.sol) extracts the check into a
// private _assertGovernance() helper (commit 49b39d8a). That refactor is used by
// the currently-deployed implementations (StakeManager/WithdrawManager/
// DepositManager/RootChain), so it must stay. Immutable contracts deployed
// BEFORE the refactor (Registry) inherit this legacy copy instead, so a normal
// `forge build` reproduces their on-chain bytecode. Behaviour is identical to the
// modern version; only the bytecode shape differs. Do not edit.
contract GovernableLegacy {
    IGovernance public governance;

    constructor(address _governance) public {
        governance = IGovernance(_governance);
    }

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "Only governance contract is authorized");
        _;
    }
}
