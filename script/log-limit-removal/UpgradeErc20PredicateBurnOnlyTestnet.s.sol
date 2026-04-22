// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";

import {Registry} from "../../scripts/helpers/interfaces/Registry.generated.sol";
import {Governance} from "../../scripts/helpers/interfaces/Governance.generated.sol";

/**
 * Sepolia-flavoured version of UpgradeErc20PredicateBurnOnly.
 *
 * Differences from the mainnet script:
 *   - No Timelock: Governance is owned directly by an EOA/multisig. All calldata is a
 *     single Governance.update(Registry, ...) call per action, no schedule/execute pair,
 *     no scheduleBatch/executeBatch for rollbacks.
 *   - The rollback-during-grace "batch" fans out to 3 independent Governance.update calls;
 *     rollback-after-tx2 fans out to 2 independent calls. On testnet that atomicity loss is
 *     acceptable since no real funds are at risk.
 *   - Fork URL comes from FORK_RPC_URL env var (no "sepolia" default — caller sets it).
 *
 * Reads the `"11155111"` entry of input.json.  The `gSafe` field is re-used as
 * "Governance owner" (the account the script pranks as when calling Governance.update).
 */
contract UpgradeErc20PredicateBurnOnlyTestnet is Script {
    using stdJson for string;

    Registry registry;
    address governance;
    address gSafe; // Governance.owner() on Sepolia
    address withdrawManager;
    address depositManager;
    address OLD_PREDICATE;

    struct Payloads {
        // Each slot is a complete `Governance.update(Registry, innerRegistryCall)` calldata.
        bytes tx1; // addErc20Predicate(new)
        bytes tx2; // removePredicate(old)
        bytes rbGrace1; // removePredicate(new)
        bytes rbGrace2; // removePredicate(old)    [so old can be re-added]
        bytes rbGrace3; // addErc20Predicate(old)  [restores singleton and mapping]
        bytes rbPost1; // removePredicate(new)
        bytes rbPost2; // addErc20Predicate(old)
    }

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        string memory rpc = vm.envOr("FORK_RPC_URL", string("https://sepolia.gateway.tenderly.co"));
        vm.selectFork(vm.createFork(rpc));
        require(block.chainid == 11155111, "expected Sepolia chain id 11155111");

        string memory input = vm.readFile("script/log-limit-removal/input.json");
        string memory slug = '["11155111"]';
        registry = Registry(input.readAddress(string.concat(slug, ".registry")));
        depositManager = input.readAddress(string.concat(slug, ".depositManagerProxy"));
        governance = input.readAddress(string.concat(slug, ".governance"));
        gSafe = input.readAddress(string.concat(slug, ".gSafe"));
        OLD_PREDICATE = input.readAddress(string.concat(slug, ".oldPredicate"));
        withdrawManager = registry.getWithdrawManagerAddress();

        require(registry.erc20Predicate() == OLD_PREDICATE, "OLD_PREDICATE no longer matches singleton");
        require(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 1, "OLD_PREDICATE not Type.ERC20");

        bytes memory ctorArgs = abi.encode(withdrawManager, depositManager);
        vm.broadcast(pk);
        address newPredicate =
            deployCode("ERC20PredicateBurnOnly.sol:ERC20PredicateBurnOnly", ctorArgs);

        Payloads memory p = _buildPayloads(newPredicate);

        console.log("# ERC20PredicateBurnOnly upgrade (Sepolia testnet)");
        console.log("");
        console.log("## Deploy");
        console.log("");
        console.log("- Chain id:        11155111 (Sepolia)");
        console.log("- Deployer:        ", deployer);
        console.log("- New predicate:   ", newPredicate);
        console.log("- withdrawManager: ", withdrawManager);
        console.log("- depositManager:  ", depositManager);
        console.log("- Old predicate:   ", OLD_PREDICATE);
        console.log("");
        console.log("All payloads below target the Governance contract directly:", governance);
        console.log("Expected caller: Governance.owner()", gSafe);
        console.log("(No Timelock on Sepolia - each call executes immediately on send.)");

        _logUpgrade(p);
        _logRollback(p);

        console.log("");
        console.log("## Fork simulation");
        console.log("");
        _simulate(p, newPredicate);
    }

    function _buildPayloads(address newPredicate) internal view returns (Payloads memory p) {
        bytes memory addNewInner = abi.encodeCall(Registry.addErc20Predicate, (newPredicate));
        bytes memory remOldInner = abi.encodeCall(Registry.removePredicate, (OLD_PREDICATE));
        bytes memory remNewInner = abi.encodeCall(Registry.removePredicate, (newPredicate));
        bytes memory addOldInner = abi.encodeCall(Registry.addErc20Predicate, (OLD_PREDICATE));

        p.tx1 = abi.encodeCall(Governance.update, (address(registry), addNewInner));
        p.tx2 = abi.encodeCall(Governance.update, (address(registry), remOldInner));
        p.rbGrace1 = abi.encodeCall(Governance.update, (address(registry), remNewInner));
        p.rbGrace2 = abi.encodeCall(Governance.update, (address(registry), remOldInner));
        p.rbGrace3 = abi.encodeCall(Governance.update, (address(registry), addOldInner));
        p.rbPost1 = abi.encodeCall(Governance.update, (address(registry), remNewInner));
        p.rbPost2 = abi.encodeCall(Governance.update, (address(registry), addOldInner));
    }

    function _logUpgrade(Payloads memory p) internal view {
        console.log("");
        console.log("## TX 1 - `addErc20Predicate(new)` (send now)");
        console.log("");
        console.log("Target: Governance (", governance, ")");
        console.log("Caller: Governance.owner() (", gSafe, ")");
        console.log("");
        console.log("Calldata:");
        console.log("```");
        console.logBytes(p.tx1);
        console.log("```");

        console.log("");
        console.log("## TX 2 - `removePredicate(old)` (send after grace)");
        console.log("");
        console.log("Target: Governance (", governance, ")");
        console.log("Caller: Governance.owner() (", gSafe, ")");
        console.log("");
        console.log("Calldata:");
        console.log("```");
        console.logBytes(p.tx2);
        console.log("```");
    }

    function _logRollback(Payloads memory p) internal view {
        console.log("");
        console.log("## Rollback (A) - during grace   *** DO NOT SEND UNLESS ROLLING BACK ***");
        console.log("");
        console.log("Three separate Governance.update calls (no atomic batch on Sepolia).");
        console.log("Send in order to `", governance, "` as Governance.owner():");
        console.log("");
        console.log("1. `removePredicate(new)` calldata:");
        console.log("```");
        console.logBytes(p.rbGrace1);
        console.log("```");
        console.log("");
        console.log("2. `removePredicate(old)` calldata  (so old can be re-added):");
        console.log("```");
        console.logBytes(p.rbGrace2);
        console.log("```");
        console.log("");
        console.log("3. `addErc20Predicate(old)` calldata  (restores singleton and mapping):");
        console.log("```");
        console.logBytes(p.rbGrace3);
        console.log("```");

        console.log("");
        console.log("## Rollback (B) - after TX 2   *** DO NOT SEND UNLESS ROLLING BACK ***");
        console.log("");
        console.log("Two separate Governance.update calls. Send in order:");
        console.log("");
        console.log("1. `removePredicate(new)` calldata:");
        console.log("```");
        console.logBytes(p.rbPost1);
        console.log("```");
        console.log("");
        console.log("2. `addErc20Predicate(old)` calldata:");
        console.log("```");
        console.logBytes(p.rbPost2);
        console.log("```");
    }

    function _simulate(Payloads memory p, address newPredicate) internal {
        vm.startPrank(gSafe);

        uint256 snapInitial = vm.snapshotState();

        // Trajectory 1: happy path TX 1 -> (grace) -> TX 2
        _call(p.tx1, "TX 1");
        assert(Registry.Type.unwrap(registry.predicates(newPredicate)) == 1);
        assert(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 1);
        assert(registry.erc20Predicate() == newPredicate);
        console.log("- [PASS] After TX 1 (grace): new=ERC20, old=ERC20, singleton=new");

        uint256 snapGrace = vm.snapshotState();

        _call(p.tx2, "TX 2");
        assert(Registry.Type.unwrap(registry.predicates(newPredicate)) == 1);
        assert(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 0);
        assert(registry.erc20Predicate() == newPredicate);
        console.log("- [PASS] After TX 2 (end): new=ERC20, old=Invalid, singleton=new");

        // Rollback B from end state
        _call(p.rbPost1, "rollback-B step 1");
        _call(p.rbPost2, "rollback-B step 2");
        assert(Registry.Type.unwrap(registry.predicates(newPredicate)) == 0);
        assert(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 1);
        assert(registry.erc20Predicate() == OLD_PREDICATE);
        console.log("- [PASS] Rollback (B): new=Invalid, old=ERC20, singleton=old");

        // Rollback A from grace state
        vm.revertToState(snapGrace);
        _call(p.rbGrace1, "rollback-A step 1");
        _call(p.rbGrace2, "rollback-A step 2");
        _call(p.rbGrace3, "rollback-A step 3");
        assert(Registry.Type.unwrap(registry.predicates(newPredicate)) == 0);
        assert(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 1);
        assert(registry.erc20Predicate() == OLD_PREDICATE);
        console.log("- [PASS] Rollback (A): new=Invalid, old=ERC20, singleton=old");

        vm.revertToState(snapInitial);
        vm.stopPrank();
    }

    function _call(bytes memory cd, string memory label) internal {
        (bool ok,) = governance.call(cd);
        require(ok, string.concat(label, " failed"));
    }
}
