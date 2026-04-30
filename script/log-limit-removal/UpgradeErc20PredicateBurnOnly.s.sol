// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

// Generated interfaces (see `npm run generate:interfaces`)
import {Registry} from "../../scripts/helpers/interfaces/Registry.generated.sol";
import {Governance} from "../../scripts/helpers/interfaces/Governance.generated.sol";
import {ERC20PredicateBurnOnly} from "../../scripts/helpers/interfaces/ERC20PredicateBurnOnly.generated.sol";
import {WithdrawManager} from "../../scripts/helpers/interfaces/WithdrawManager.generated.sol";
import {ExitNFT} from "../../scripts/helpers/interfaces/ExitNFT.generated.sol";
import {PriorityQueue} from "../../scripts/helpers/interfaces/PriorityQueue.generated.sol";
import {Timelock} from "../../contracts/common/misc/ITimelock.sol";

/**
 * Upgrade path for the ERC20PredicateBurnOnly (remove `logIndex < MAX_LOGS`).
 *
 * Flow: two separate multisig actions with a grace period in between.
 *
 *   TX 1:     Governance.update(Registry, addErc20Predicate(new))
 *                   — sets singleton=new, adds new to mapping. predicates[old] is
 *                     NOT touched; old stays registered.
 *                   Intermediate state: singleton=new, predicates[new]=ERC20,
 *                                       predicates[old]=ERC20  (both work)
 *
 *   [ grace period: UI/SDKs migrate to the new address; users with old still work ]
 *
 *   TX 2 (later):   Governance.update(Registry, removePredicate(old))
 *                   — drops old from mapping.
 *                   End state: singleton=new, predicates[new]=ERC20,
 *                              predicates[old]=Invalid
 *
 *
 * Two rollback scenarios, each a single multisig batch:
 *
 *   (A) Rollback DURING grace (after TX 1, before TX 2).
 *       Pre-state: singleton=new, predicates[new]=ERC20, predicates[old]=ERC20.
 *       Batch [removePredicate(new), removePredicate(old), addErc20Predicate(old)]
 *       End state: singleton=old, predicates[new]=Invalid, predicates[old]=ERC20.
 *       Needs 3 inner ops because `addErc20Predicate(old)` requires old to be
 *       Invalid first (Registry.addPredicate's "Predicate already added" check).
 *
 *   (B) Rollback AFTER TX 2.
 *       Pre-state: singleton=new, predicates[new]=ERC20, predicates[old]=Invalid.
 *       Batch [removePredicate(new), addErc20Predicate(old)]
 *       End state: singleton=old, predicates[new]=Invalid, predicates[old]=ERC20.
 *       Only 2 inner ops (old is already Invalid).
 *
 * The script emits all four non-rollback payloads (TX 1 schedule+execute,
 * TX 2 schedule+execute) plus both rollback batches (schedule+execute each)
 * and exercises every trajectory against a mainnet fork using vm snapshots.
 */
contract UpgradeErc20PredicateBurnOnly is Script {
    using stdJson for string;

    Registry registry;
    Timelock timelock;
    address governance;
    address gSafe;
    address withdrawManager;
    address depositManager;
    address OLD_PREDICATE; // loaded from input.json

    struct Payloads {
        // upgrade: two separate (non-batched) multisig actions
        bytes tx1Schedule;
        bytes tx1Execute;
        bytes tx2Schedule;
        bytes tx2Execute;
        // rollback-during-grace: single batch
        bytes rbGraceSchedule;
        bytes rbGraceExecute;
        // rollback-after-tx2: single batch
        bytes rbPostSchedule;
        bytes rbPostExecute;
    }

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet")));

        string memory input = vm.readFile("script/log-limit-removal/input.json");
        string memory chainIdSlug = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));

        registry = Registry(input.readAddress(string.concat(chainIdSlug, ".registry")));
        depositManager = input.readAddress(string.concat(chainIdSlug, ".depositManagerProxy"));
        governance = input.readAddress(string.concat(chainIdSlug, ".governance"));
        timelock = Timelock(payable(input.readAddress(string.concat(chainIdSlug, ".timelock"))));
        gSafe = input.readAddress(string.concat(chainIdSlug, ".gSafe"));
        OLD_PREDICATE = input.readAddress(string.concat(chainIdSlug, ".oldPredicate"));
        withdrawManager = registry.getWithdrawManagerAddress();

        // Sanity
        require(registry.erc20Predicate() == OLD_PREDICATE, "OLD_PREDICATE no longer matches singleton");
        require(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 1, "OLD_PREDICATE not Type.ERC20");

        // Deploy new predicate
        bytes memory ctorArgs = abi.encode(withdrawManager, depositManager);
        vm.broadcast(pk);
        address newPredicate = deployCode("ERC20PredicateBurnOnly.sol:ERC20PredicateBurnOnly", ctorArgs);

        Payloads memory p = _buildPayloads(newPredicate);

        // --- markdown-friendly output for pasting into a GitHub issue ---
        console.log("# ERC20PredicateBurnOnly upgrade");
        console.log("");
        console.log("## Deploy");
        console.log("");
        console.log("- Deployer:", deployer);
        console.log("- New predicate:", newPredicate);
        console.log("- withdrawManager:", withdrawManager);
        console.log("- depositManager:", depositManager);
        console.log("- Old predicate (to be removed):", OLD_PREDICATE);
        console.log("");
        console.log("All multisig payloads below target the Timelock:", address(timelock));

        _logUpgradePayloads(p);
        _logRollbackPayloads(p);

        console.log("");
        console.log("## Fork simulation");
        console.log("");
        _simulate(p, newPredicate);
    }

    /// @dev Build all calldata up front so logging and simulation use the same bytes.
    function _buildPayloads(address newPredicate) internal view returns (Payloads memory p) {
        // ---- upgrade inner calls ----
        bytes memory addInner = abi.encodeCall(Registry.addErc20Predicate, (newPredicate));
        bytes memory remOldInner = abi.encodeCall(Registry.removePredicate, (OLD_PREDICATE));

        bytes memory tx1Gov = abi.encodeCall(Governance.update, (address(registry), addInner));
        bytes memory tx2Gov = abi.encodeCall(Governance.update, (address(registry), remOldInner));

        p.tx1Schedule = abi.encodeCall(Timelock.schedule, (governance, 0, tx1Gov, bytes32(0), bytes32(0), 0));
        p.tx1Execute = abi.encodeCall(Timelock.execute, (governance, 0, tx1Gov, bytes32(0), bytes32(0)));
        p.tx2Schedule = abi.encodeCall(Timelock.schedule, (governance, 0, tx2Gov, bytes32(0), bytes32(0), 0));
        p.tx2Execute = abi.encodeCall(Timelock.execute, (governance, 0, tx2Gov, bytes32(0), bytes32(0)));

        // ---- rollback-during-grace (3-op batch) ----
        // pre: singleton=new, predicates[new]=ERC20, predicates[old]=ERC20
        // post: singleton=old, predicates[new]=Invalid, predicates[old]=ERC20
        bytes memory remNewInner = abi.encodeCall(Registry.removePredicate, (newPredicate));
        bytes memory addOldInner = abi.encodeCall(Registry.addErc20Predicate, (OLD_PREDICATE));

        address[] memory rbGraceTargets = new address[](3);
        uint256[] memory rbGraceValues = new uint256[](3);
        bytes[] memory rbGraceDatas = new bytes[](3);
        rbGraceTargets[0] = governance;
        rbGraceTargets[1] = governance;
        rbGraceTargets[2] = governance;
        rbGraceDatas[0] = abi.encodeCall(Governance.update, (address(registry), remNewInner)); // new → Invalid
        rbGraceDatas[1] = abi.encodeCall(Governance.update, (address(registry), remOldInner)); // old → Invalid (prep for readd)
        rbGraceDatas[2] = abi.encodeCall(Governance.update, (address(registry), addOldInner)); // old → ERC20 + singleton=old

        p.rbGraceSchedule = abi.encodeCall(
            Timelock.scheduleBatch, (rbGraceTargets, rbGraceValues, rbGraceDatas, bytes32(0), bytes32(0), 0)
        );
        p.rbGraceExecute =
            abi.encodeCall(Timelock.executeBatch, (rbGraceTargets, rbGraceValues, rbGraceDatas, bytes32(0), bytes32(0)));

        // ---- rollback-after-tx2 (2-op batch) ----
        // pre: singleton=new, predicates[new]=ERC20, predicates[old]=Invalid
        // post: singleton=old, predicates[new]=Invalid, predicates[old]=ERC20
        address[] memory rbPostTargets = new address[](2);
        uint256[] memory rbPostValues = new uint256[](2);
        bytes[] memory rbPostDatas = new bytes[](2);
        rbPostTargets[0] = governance;
        rbPostTargets[1] = governance;
        rbPostDatas[0] = abi.encodeCall(Governance.update, (address(registry), remNewInner));
        rbPostDatas[1] = abi.encodeCall(Governance.update, (address(registry), addOldInner));

        p.rbPostSchedule = abi.encodeCall(
            Timelock.scheduleBatch, (rbPostTargets, rbPostValues, rbPostDatas, bytes32(0), bytes32(0), 0)
        );
        p.rbPostExecute =
            abi.encodeCall(Timelock.executeBatch, (rbPostTargets, rbPostValues, rbPostDatas, bytes32(0), bytes32(0)));
    }

    function _logUpgradePayloads(Payloads memory p) internal pure {
        console.log("");
        console.log("## TX 1 - `addErc20Predicate(new)` (send now)");
        console.log("");
        console.log("Sets `erc20Predicate = new` and registers new in the `predicates` mapping.");
        console.log("Old stays registered - calls to old keep working during the grace period.");
        console.log("");
        console.log(
            "**UI / SDK / exit-watcher note:** after this lands, `Registry.erc20Predicate()` returns the new address."
        );
        console.log(
            "Migrate hardcoded references before TX 2 lands; otherwise those callers revert with `PREDICATE_NOT_AUTHORIZED` once old is dropped."
        );
        console.log("");
        console.log("Schedule calldata:");
        console.log("```");
        console.logBytes(p.tx1Schedule);
        console.log("```");
        console.log("");
        console.log("Execute calldata (send after `Timelock.getMinDelay()`):");
        console.log("```");
        console.logBytes(p.tx1Execute);
        console.log("```");

        console.log("");
        console.log("## TX 2 - `removePredicate(old)` (send after grace)");
        console.log("");
        console.log(
            "Unregisters old. End state: `erc20Predicate = new`, `predicates[new] = ERC20`, `predicates[old] = Invalid`."
        );
        console.log("Do not send until UI/SDKs have migrated and you are ready to close the grace window.");
        console.log("");
        console.log("Schedule calldata:");
        console.log("```");
        console.logBytes(p.tx2Schedule);
        console.log("```");
        console.log("");
        console.log("Execute calldata (send after `Timelock.getMinDelay()`):");
        console.log("```");
        console.logBytes(p.tx2Execute);
        console.log("```");
    }

    function _logRollbackPayloads(Payloads memory p) internal pure {
        console.log("");
        console.log("## Rollback (A) - during grace");
        console.log("");
        console.log("> **Do not send unless rolling back.** Use *after TX 1 and before TX 2* if new turns out broken.");
        console.log("");
        console.log("Batch of 3 `Governance.update` calls:");
        console.log("1. `removePredicate(new)`");
        console.log("2. `removePredicate(old)`   (so old can be re-added)");
        console.log("3. `addErc20Predicate(old)` (restores singleton = old, `predicates[old] = ERC20`)");
        console.log("");
        console.log("scheduleBatch calldata:");
        console.log("```");
        console.logBytes(p.rbGraceSchedule);
        console.log("```");
        console.log("");
        console.log("executeBatch calldata:");
        console.log("```");
        console.logBytes(p.rbGraceExecute);
        console.log("```");

        console.log("");
        console.log("## Rollback (B) - after TX 2");
        console.log("");
        console.log("> **Do not send unless rolling back.** Use *after TX 2 lands* if new turns out broken.");
        console.log("");
        console.log("Batch of 2 `Governance.update` calls:");
        console.log("1. `removePredicate(new)`");
        console.log("2. `addErc20Predicate(old)` (restores singleton = old, `predicates[old] = ERC20`)");
        console.log("");
        console.log("scheduleBatch calldata:");
        console.log("```");
        console.logBytes(p.rbPostSchedule);
        console.log("```");
        console.log("");
        console.log("executeBatch calldata:");
        console.log("```");
        console.logBytes(p.rbPostExecute);
        console.log("```");
    }

    function _simulate(Payloads memory p, address newPredicate) internal {
        uint256 minDelay = timelock.getMinDelay();
        console.log("- Timelock minDelay:", minDelay);

        vm.startPrank(gSafe);

        // ---- Trajectory 1: happy path (TX 1 → grace → TX 2) ----
        uint256 snapInitial = vm.snapshotState();

        _call(p.tx1Schedule, "TX 1 schedule");
        if (minDelay > 0) vm.warp(block.timestamp + minDelay + 1);
        _call(p.tx1Execute, "TX 1 execute");

        // Intermediate (grace) state
        assert(Registry.Type.unwrap(registry.predicates(newPredicate)) == 1);
        assert(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 1);
        assert(registry.erc20Predicate() == newPredicate);
        console.log("- [PASS] After TX 1 (grace): new=ERC20, old=ERC20, singleton=new");

        // Snapshot clean grace state. We branch off of it for the exit test, then for
        // TX 2 / rollback-A, reverting back after each so none of the branches pollute
        // the others.
        uint256 snapGrace = vm.snapshotState();

        // Prove a real logIndex=12 exit works end-to-end through the new predicate, and
        // that *only* the expected state changes occur.
        _verifyExitStillWorks(newPredicate);
        vm.revertToState(snapGrace);
        vm.startPrank(gSafe);

        vm.warp(block.timestamp + 7 days); // representative grace window

        _call(p.tx2Schedule, "TX 2 schedule");
        if (minDelay > 0) vm.warp(block.timestamp + minDelay + 1);
        _call(p.tx2Execute, "TX 2 execute");

        assert(Registry.Type.unwrap(registry.predicates(newPredicate)) == 1);
        assert(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 0);
        assert(registry.erc20Predicate() == newPredicate);
        console.log("- [PASS] After TX 2 (end): new=ERC20, old=Invalid, singleton=new");

        // ---- Trajectory 2: rollback after TX 2 ----
        _call(p.rbPostSchedule, "rollback-B schedule");
        if (minDelay > 0) vm.warp(block.timestamp + minDelay + 1);
        _call(p.rbPostExecute, "rollback-B execute");

        assert(Registry.Type.unwrap(registry.predicates(newPredicate)) == 0);
        assert(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 1);
        assert(registry.erc20Predicate() == OLD_PREDICATE);
        console.log("- [PASS] Rollback (B): new=Invalid, old=ERC20, singleton=old");

        // ---- Trajectory 3: rollback DURING grace ----
        vm.revertToState(snapGrace);
        // Re-assert we're back at the grace state
        assert(Registry.Type.unwrap(registry.predicates(newPredicate)) == 1);
        assert(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 1);
        assert(registry.erc20Predicate() == newPredicate);

        _call(p.rbGraceSchedule, "rollback-A schedule");
        if (minDelay > 0) vm.warp(block.timestamp + minDelay + 1);
        _call(p.rbGraceExecute, "rollback-A execute");

        assert(Registry.Type.unwrap(registry.predicates(newPredicate)) == 0);
        assert(Registry.Type.unwrap(registry.predicates(OLD_PREDICATE)) == 1);
        assert(registry.erc20Predicate() == OLD_PREDICATE);
        console.log("- [PASS] Rollback (A): new=Invalid, old=ERC20, singleton=old");

        // Restore pristine state so vm.stopPrank unwinds cleanly in all forks
        vm.revertToState(snapInitial);
        vm.stopPrank();
    }

    function _call(bytes memory cd, string memory label) internal {
        (bool ok,) = address(timelock).call(cd);
        require(ok, string.concat(label, " failed"));
    }

    // --- exit-still-works fork test ---

    // Values derived off-chain from `exitProof` in input.json (real mainnet Withdraw tx
    // whose event happens to sit at log index 12 — perfect regression for the cap removal).
    address constant EXITOR = 0x71663898Df7470e3b64d52663Ff975895E9b06E8;
    address constant ROOT_TOKEN_MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address constant CHILD_TOKEN_MRC20 = 0x0000000000000000000000000000000000001010;
    uint256 constant EXIT_AMOUNT = 1721058326703688134752; // 0x5d4c7b759445843060, ~1721 POL

    // Expected storage write counts per contract (see predictions in PR discussion).
    // State-change counts (slots whose `newValue != previousValue`). Zero-to-zero
    // SSTOREs are filtered out — we're verifying observable state changes, not opcode counts.
    // WM: 4 effective struct slots (amount, owner, token+isRegularExit packed, predicate; txHash
    //     is a 0→0 no-op so it doesn't count) + 1 for isKnownExit.
    uint256 constant EXPECTED_WM_WRITES = 5;
    uint256 constant EXPECTED_NFT_WRITES = 2; // _tokenOwner + _ownedTokensCount
    uint256 constant EXPECTED_QUEUE_WRITES = 3; // heapList length + new element + currentSize

    function _verifyExitStillWorks(address newPredicate) internal {
        console.log("");
        console.log("## Exit-still-works test (logIndex=12 through new predicate)");

        string memory input = vm.readFile("script/log-limit-removal/input.json");
        string memory slug = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));
        bytes memory exitProof = input.readBytes(string.concat(slug, ".exitProof"));

        // Resolve downstream contract addresses from the registry/withdrawManager
        WithdrawManager wm = WithdrawManager(payable(registry.getWithdrawManagerAddress()));
        ExitNFT exitNft = ExitNFT(wm.exitNft());
        PriorityQueue maticQueue = PriorityQueue(wm.exitsQueues(ROOT_TOKEN_MATIC));

        // Sanity: mainnet mapping is as expected
        require(registry.rootToChildToken(ROOT_TOKEN_MATIC) == CHILD_TOKEN_MRC20, "MATIC->MRC20 not mapped");
        require(!registry.isERC721(ROOT_TOKEN_MATIC), "MATIC is ERC721?");

        // Pre-state
        uint256 prePQSize = maticQueue.currentSize();
        uint256 preBalance = exitNft.balanceOf(EXITOR);

        // Prank in isolation (outer _simulate has an active gSafe prank)
        vm.stopPrank();

        vm.startStateDiffRecording(); // Foundry state-access recording
        vm.recordLogs();

        vm.prank(EXITOR);
        ERC20PredicateBurnOnly(newPredicate).startExitWithBurntTokens(exitProof);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // 1) Events: exactly 2 — Transfer (ExitNFT) then ExitStarted (WithdrawManager)
        require(logs.length == 2, string.concat("expected 2 events, got ", vm.toString(logs.length)));

        require(logs[0].emitter == address(exitNft), "log[0] not from ExitNFT");
        require(
            logs[0].topics[0] == keccak256("Transfer(address,address,uint256)"),
            "log[0] not ERC721 Transfer"
        );
        require(logs[0].topics[1] == bytes32(0), "mint from != 0x0");
        require(address(uint160(uint256(logs[0].topics[2]))) == EXITOR, "mint to != EXITOR");
        uint256 exitId = uint256(logs[0].topics[3]);

        require(logs[1].emitter == address(wm), "log[1] not from WithdrawManager");
        require(
            logs[1].topics[0] == keccak256("ExitStarted(address,uint256,address,uint256,bool)"),
            "log[1] not ExitStarted"
        );
        require(address(uint160(uint256(logs[1].topics[1]))) == EXITOR, "ExitStarted exitor mismatch");
        require(uint256(logs[1].topics[2]) == exitId, "exitId mismatch between Transfer and ExitStarted");
        require(address(uint160(uint256(logs[1].topics[3]))) == ROOT_TOKEN_MATIC, "ExitStarted token mismatch");
        (uint256 loggedAmount, bool loggedIsRegular) = abi.decode(logs[1].data, (uint256, bool));
        if (loggedAmount != EXIT_AMOUNT) {
            console.log("loggedAmount:", loggedAmount);
            console.log("EXIT_AMOUNT :", EXIT_AMOUNT);
            revert("ExitStarted amount mismatch");
        }
        require(loggedIsRegular == true, "ExitStarted isRegularExit must be true for burn");

        console.log("- exitId:", exitId);
        console.log("- [PASS] events: exactly 2 (Transfer + ExitStarted), fields match expectations");

        // 2) Semantic post-state
        (
            uint256 amountOnchain,
            bytes32 txHashOnchain,
            address ownerOnchain,
            address tokenOnchain,
            bool isRegularExitOnchain,
            address predicateOnchain
        ) = wm.exits(exitId);
        require(amountOnchain == EXIT_AMOUNT, "exits.amount");
        require(txHashOnchain == bytes32(0), "exits.txHash");
        require(ownerOnchain == EXITOR, "exits.owner");
        require(tokenOnchain == ROOT_TOKEN_MATIC, "exits.token");
        require(isRegularExitOnchain == true, "exits.isRegularExit");
        require(predicateOnchain == newPredicate, "exits.predicate");

        require(exitNft.ownerOf(exitId) == EXITOR, "ExitNFT.ownerOf");
        require(exitNft.balanceOf(EXITOR) == preBalance + 1, "ExitNFT.balanceOf delta != 1");
        require(maticQueue.currentSize() == prePQSize + 1, "PriorityQueue.currentSize delta != 1");
        require(wm.ownerExits(keccak256(abi.encodePacked(ROOT_TOKEN_MATIC, EXITOR))) == 0, "ownerExits shouldn't be set for regular exit");

        console.log("- [PASS] semantic state: exits struct, ExitNFT mint, queue currentSize +1, ownerExits untouched");

        // 3) Storage-write fingerprint — only the contracts we expect, with the counts we predicted.
        uint256 wmWrites;
        uint256 nftWrites;
        uint256 qWrites;
        uint256 strayWrites;

        for (uint256 i = 0; i < accesses.length; i++) {
            Vm.AccountAccess memory a = accesses[i];
            for (uint256 j = 0; j < a.storageAccesses.length; j++) {
                Vm.StorageAccess memory s = a.storageAccesses[j];
                if (!s.isWrite) continue;
                if (s.newValue == s.previousValue) continue; // no-op SSTORE (value unchanged)
                address acct = s.account;
                if (acct == address(wm)) wmWrites++;
                else if (acct == address(exitNft)) nftWrites++;
                else if (acct == address(maticQueue)) qWrites++;
                else {
                    strayWrites++;
                    console.log("- UNEXPECTED write to", acct);
                    console.log("  slot", vm.toString(s.slot));
                    console.log("  prev", vm.toString(s.previousValue));
                    console.log("  new ", vm.toString(s.newValue));
                }
            }
        }

        require(strayWrites == 0, "unexpected writes to contracts outside {WM, ExitNFT, MATIC queue}");
        require(
            wmWrites == EXPECTED_WM_WRITES,
            string.concat("WM writes=", vm.toString(wmWrites), " expected=", vm.toString(EXPECTED_WM_WRITES))
        );
        require(
            nftWrites == EXPECTED_NFT_WRITES,
            string.concat("NFT writes=", vm.toString(nftWrites), " expected=", vm.toString(EXPECTED_NFT_WRITES))
        );
        require(
            qWrites == EXPECTED_QUEUE_WRITES,
            string.concat(
                "MATIC-queue writes=", vm.toString(qWrites), " expected=", vm.toString(EXPECTED_QUEUE_WRITES)
            )
        );

        console.log("- [PASS] storage writes: WM=5, ExitNFT=2, MATIC-queue=3, elsewhere=0");

        // Phase 2: process the exit and verify the POL payout + NFT burn + Withdraw event.
        _verifyProcessExit(wm, exitNft, exitId);
    }

    function _verifyProcessExit(WithdrawManager wm, ExitNFT exitNft, uint256 exitId) internal {
        console.log("");
        console.log("## Process-exit test (POL payout + ExitNFT burn + Withdraw event)");

        address polToken = registry.contractMap(keccak256("pol"));

        // HALF_EXIT_PERIOD = 1 on mainnet, so exitableAt = max(createdAt + 2, now + 1).
        // Warping +2s puts block.timestamp past our just-created exit's exitableAt.
        vm.warp(block.timestamp + 2);

        uint256 preBalance = IERC20Like(polToken).balanceOf(EXITOR);

        vm.recordLogs();

        wm.processExits(ROOT_TOKEN_MATIC);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(!exitNft.exists(exitId), "exit not processed");

        // MATIC queue currently has only our exit (mainnet currentSize was 0 before startExit),
        // so exactly three logs fire per processed exit: ExitNFT burn, POL Transfer, Withdraw.
        // Any deviation means either a secondary exit slipped in or the predicate's
        // onFinalizeExit reverted (which would drop the POL Transfer via .call-wrapped revert).
        require(logs.length == 3, string.concat("expected 3 logs for one exit, got ", vm.toString(logs.length)));

        uint256 postBalance = IERC20Like(polToken).balanceOf(EXITOR);
        uint256 received = postBalance - preBalance;
        if (received != EXIT_AMOUNT) {
            console.log("received   :", received);
            console.log("EXIT_AMOUNT:", EXIT_AMOUNT);
            revert("POL payout != EXIT_AMOUNT");
        }

        // Filter logs for the three we expect for our specific exitId / transfer.
        bool foundWithdraw;
        bool foundExitNftBurn;
        bool foundPolTransfer;
        bytes32 transferSig = keccak256("Transfer(address,address,uint256)");
        bytes32 withdrawSig = keccak256("Withdraw(uint256,address,address,uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory l = logs[i];

            // WithdrawManager.Withdraw(exitId indexed, user indexed, token indexed, amount)
            if (
                l.emitter == address(wm) && l.topics.length == 4 && l.topics[0] == withdrawSig
                    && uint256(l.topics[1]) == exitId
            ) {
                require(address(uint160(uint256(l.topics[2]))) == EXITOR, "Withdraw.user != EXITOR");
                require(address(uint160(uint256(l.topics[3]))) == ROOT_TOKEN_MATIC, "Withdraw.token != MATIC");
                require(abi.decode(l.data, (uint256)) == EXIT_AMOUNT, "Withdraw.amount != EXIT_AMOUNT");
                require(!foundWithdraw, "multiple Withdraw events for same exitId");
                foundWithdraw = true;
            }

            // ExitNFT.Transfer(from indexed, to indexed, tokenId indexed); burn means to == 0x0
            if (
                l.emitter == address(exitNft) && l.topics.length == 4 && l.topics[0] == transferSig
                    && uint256(l.topics[3]) == exitId && address(uint160(uint256(l.topics[2]))) == address(0)
            ) {
                require(address(uint160(uint256(l.topics[1]))) == EXITOR, "burn.from != EXITOR");
                require(!foundExitNftBurn, "multiple burn events for same exitId");
                foundExitNftBurn = true;
            }

            // POL.Transfer(from indexed, to indexed, amount): from=DepositManager, to=EXITOR, value=EXIT_AMOUNT
            if (
                l.emitter == polToken && l.topics.length == 3 && l.topics[0] == transferSig
                    && address(uint160(uint256(l.topics[1]))) == depositManager
                    && address(uint160(uint256(l.topics[2]))) == EXITOR
                    && abi.decode(l.data, (uint256)) == EXIT_AMOUNT
            ) {
                require(!foundPolTransfer, "multiple exact-amount POL Transfers DepositManager -> EXITOR");
                foundPolTransfer = true;
            }
        }

        require(foundWithdraw, "no Withdraw event for our exitId");
        require(foundExitNftBurn, "no ExitNFT burn Transfer for our exitId");
        require(foundPolTransfer, "no POL Transfer DepositManager -> EXITOR with exact amount");

        console.log("- [PASS] exactly 3 logs fired (ExitNFT burn, POL Transfer, Withdraw)");
        console.log("- [PASS] ExitNFT burned for exitId");
        console.log("- POL payout to EXITOR (wei):", received);
        console.log("- [PASS] POL payout equals EXIT_AMOUNT");
        console.log("- [PASS] Withdraw event emitted with expected (exitId, user, token, amount)");
    }
}

interface IERC20Like {
    function balanceOf(address owner) external view returns (uint256);
}
