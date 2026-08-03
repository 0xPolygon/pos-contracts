// SPDX-License-Identifier: MIT
pragma solidity ^0.5.2;

import {Registry} from "../../common/Registry.sol";
import {RootChain} from "../RootChain.sol";
import {ProxyStorage} from "../../common/misc/ProxyStorage.sol";
import {StateSender} from "../stateSyncer/StateSender.sol";
import {LockableLegacy} from "../../common/mixin/LockableLegacy.sol";
import {DepositManagerHeader} from "./DepositManagerStorage.sol";

// Frozen, pre-refactor DepositManager storage, reproducing the storage layout of
// the immutable DepositManagerProxy byte-for-byte. It inherits the pre-refactor
// `LockableLegacy is GovernableLegacy`; the modern DepositManagerStorage inherits
// GovernanceLockable and is used by the live implementation, so both must coexist.
// Used ONLY by DepositManagerProxy. Do not edit.
contract DepositManagerStorageLegacy is ProxyStorage, LockableLegacy, DepositManagerHeader {
    Registry public registry;
    RootChain public rootChain;
    StateSender public stateSender;

    mapping(uint256 => DepositBlock) public deposits;

    address public childChain;
    uint256 public maxErc20Deposit = 100 * (10 ** 18);
}
