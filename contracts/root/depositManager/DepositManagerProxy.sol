pragma solidity ^0.5.2;

import {DepositManagerStorageLegacy} from "./DepositManagerStorageLegacy.sol";
import {Proxy} from "../../common/misc/Proxy.sol";
import {Registry} from "../../common/Registry.sol";
import {RootChain} from "../RootChain.sol";
import {LockableLegacy} from "../../common/mixin/LockableLegacy.sol";

// The DepositManagerProxy has a single, immutable deployment that predates the
// Lockable/GovernanceLockable split (commit d0cbfb42). It therefore uses the
// legacy storage (LockableLegacy => `locked` at slot 2) so a normal `forge build`
// reproduces its on-chain bytecode and layout. The live implementation uses the
// modern DepositManagerStorage (`locked` at slot 1); the divergence is the known
// pause-slot issue and is preserved here on purpose.
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
