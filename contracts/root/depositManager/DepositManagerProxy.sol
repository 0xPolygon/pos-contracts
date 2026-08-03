pragma solidity ^0.5.2;

import {DepositManagerStorageLegacy} from "./DepositManagerStorageLegacy.sol";
import {Proxy} from "../../common/misc/Proxy.sol";
import {Registry} from "../../common/Registry.sol";
import {RootChain} from "../RootChain.sol";
import {LockableLegacy} from "../../common/mixin/LockableLegacy.sol";

// The DepositManagerProxy has a single, immutable deployment that predates a later
// refactor of the shared Governable/Lockable base contracts (commit d0cbfb42). It
// therefore inherits the frozen pre-refactor storage so that a normal `forge build`
// reproduces its deployed bytecode and storage layout exactly. The live
// implementation is built on the current bases and must stay that way.
// Do not change this inheritance without re-verifying against the deployed bytecode.
contract DepositManagerProxy is Proxy, DepositManagerStorageLegacy {
    constructor(
        address _proxyTo,
        address _registry,
        address _rootChain,
        address _governance
    ) public Proxy(_proxyTo) LockableLegacy(_governance) {
        registry = Registry(_registry);
        rootChain = RootChain(_rootChain);
    }
}
