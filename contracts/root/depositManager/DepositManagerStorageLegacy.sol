// SPDX-License-Identifier: MIT
pragma solidity ^0.5.2;

import {Registry} from "../../common/Registry.sol";
import {RootChain} from "../RootChain.sol";
import {ProxyStorage} from "../../common/misc/ProxyStorage.sol";
import {StateSender} from "../stateSyncer/StateSender.sol";
import {LockableLegacy} from "../../common/mixin/LockableLegacy.sol";
import {DepositManagerHeader} from "./DepositManagerStorage.sol";

// Frozen, pre-refactor DepositManager storage. Inherits the legacy
// `LockableLegacy is GovernableLegacy`, which places `locked` at slot 2 (the
// deployed proxy's layout). The modern DepositManagerStorage inherits
// GovernanceLockable, which places `locked` at slot 1 — that layout is used by
// the live implementation, so both must coexist. Used ONLY by the immutable
// DepositManagerProxy. Do not edit. (The proxy/impl slot divergence is the known
// pause-slot issue; this preserves the on-chain reality byte-for-byte.)
contract DepositManagerStorageLegacy is ProxyStorage, LockableLegacy, DepositManagerHeader {
    Registry public registry;
    RootChain public rootChain;
    StateSender public stateSender;

    mapping(uint256 => DepositBlock) public deposits;

    address public childChain;
    uint256 public maxErc20Deposit = 100 * (10 ** 18);
}
