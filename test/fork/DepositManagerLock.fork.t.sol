// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IDepositManagerFork {
    function implementation() external view returns (address);
    function updateImplementation(address newImplementation) external;
    function lock() external;
    function unlock() external;
    function locked() external view returns (bool);
    function governance() external view returns (address);
    function owner() external view returns (address);
    function registry() external view returns (address);
    function rootChain() external view returns (address);
    function stateSender() external view returns (address);
    function childChain() external view returns (address);
    function maxErc20Deposit() external view returns (uint256);
    function deposits(uint256 depositId) external view returns (bytes32 depositHash, uint256 createdAt);
    function depositEther() external payable;
    function depositERC20(address token, uint256 amount) external;
    function depositERC20ForUser(address token, address user, uint256 amount) external;
    function depositBulk(address[] calldata tokens, uint256[] calldata amountOrTokens, address user) external;
    function updateMaxErc20Deposit(uint256 maxDepositAmount) external;
}

interface IGovernanceFork {
    function update(address target, bytes calldata data) external;
}

interface ITimelockFork {
    function getMinDelay() external view returns (uint256);
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
    function execute(
        address target,
        uint256 value,
        bytes calldata payload,
        bytes32 predecessor,
        bytes32 salt
    ) external payable;
}

interface IRegistryFork {
    function getWethTokenAddress() external view returns (address);
    function contractMap(bytes32 key) external view returns (address);
}

/// @notice Fork tests, at the latest mainnet block, for the DepositManager pause. The immutable DepositManagerProxy
/// answers `lock()`/`unlock()`/`locked()` itself and stores `locked` at slot 2 byte 20. The live implementation
/// checks slot 1 byte 20, so `lock()` stops no deposits. The fixed implementation inherits the proxy's storage
/// layout. Every privileged call goes Root Safe -> Timelock -> (GovernanceProxy ->) DepositManagerProxy.
contract DepositManagerLockForkTest is Test {
    IDepositManagerFork constant dm = IDepositManagerFork(0x401F6c983eA34274ec46f84D70b31C151321188b);
    IGovernanceFork constant governance = IGovernanceFork(0x6e7a5820baD6cebA8Ef5ea69c0C92EbbDAc9CE48);
    ITimelockFork constant timelock = ITimelockFork(0xCaf0aa768A3AE1297DF20072419Db8Bb8b5C8cEf);
    // Holds PROPOSER_ROLE and EXECUTOR_ROLE on the Timelock.
    address constant rootSafe = 0xFa7D2a996aC6350f4b56C043112Da0366a59b74c;
    address constant liveImpl = 0xb00aa68b87256E2F22058fB2Ba3246EEc54A44fc;

    uint256 constant PROXY_TO_SLOT = 1;
    uint256 constant GOVERNANCE_AND_LOCKED_SLOT = 2;
    uint256 constant MAX_ERC20_DEPOSIT_SLOT = 8;

    address user = makeAddr("user");
    address weth;
    address matic;
    address pol;
    uint256 salt;

    event NewDepositBlock(address indexed owner, address indexed token, uint256 amountOrNFTId, uint256 depositBlockId);

    function setUp() public {
        vm.createSelectFork("mainnet");

        assertEq(dm.implementation(), liveImpl, "DepositManager impl changed on mainnet, revisit this test");
        assertFalse(dm.locked(), "DepositManager is locked on mainnet");
        assertEq(_byte20(PROXY_TO_SLOT), 0);
        assertEq(_byte20(GOVERNANCE_AND_LOCKED_SLOT), 0);

        IRegistryFork registry = IRegistryFork(dm.registry());
        weth = registry.getWethTokenAddress();
        matic = registry.contractMap(keccak256("matic"));
        pol = registry.contractMap(keccak256("pol"));

        vm.deal(user, 100 ether);
        deal(pol, user, 1_000e18);
        vm.prank(user);
        IERC20(pol).approve(address(dm), type(uint256).max);
    }

    /// The bug, on the live implementation: `locked()` reports true, deposits keep landing.
    function test_liveImpl_lockDoesNotBlockDeposits() public {
        _lock();

        assertTrue(dm.locked(), "proxy reports locked");
        assertEq(_byte20(GOVERNANCE_AND_LOCKED_SLOT), 1, "proxy wrote slot 2 byte 20");
        assertEq(_byte20(PROXY_TO_SLOT), 0, "slot 1 byte 20, where the live impl looks, stays 0");

        _assertEveryDepositPathSucceeds();
    }

    /// The fix: the same governance `lock()` now stops every deposit path, and `unlock()` reopens them.
    function test_fixedImpl_lockBlocksDeposits_unlockRestores() public {
        _upgrade();
        _assertEveryDepositPathSucceeds();

        _lock();
        assertTrue(dm.locked());
        _assertEveryDepositPathReverts();

        _unlock();
        assertFalse(dm.locked());
        _assertEveryDepositPathSucceeds();
    }

    /// The upgrade changes `proxyTo` and nothing else, in any contract.
    function test_upgrade_writesOnlyTheImplementationSlot() public {
        address impl = deployCode("out/DepositManager.sol/DepositManager.json");
        bytes32[9] memory before = _slots();

        vm.startStateDiffRecording();
        _timelockCall(address(dm), abi.encodeCall(IDepositManagerFork.updateImplementation, (impl)));
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        uint256 writes;
        for (uint256 i = 0; i < accesses.length; ++i) {
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory sa = accesses[i].storageAccesses[j];
                if (!sa.isWrite || sa.reverted || sa.previousValue == sa.newValue) continue;
                if (sa.account == address(timelock)) continue; // the operation's timestamp
                assertEq(sa.account, address(dm), "only DepositManager storage changes");
                assertEq(uint256(sa.slot), PROXY_TO_SLOT, "only proxyTo changes");
                assertEq(sa.newValue, bytes32(uint256(uint160(impl))), "proxyTo is the new impl, padding clear");
                ++writes;
            }
        }
        assertEq(writes, 1);

        bytes32[9] memory afterUpgrade = _slots();
        for (uint256 i = 0; i < before.length; ++i) {
            if (i != PROXY_TO_SLOT) assertEq(afterUpgrade[i], before[i]);
        }
    }

    /// Every variable the impl reads resolves to the same value the proxy reports, and deposits land as before.
    function test_fixedImpl_depositRecordedAsBefore() public {
        _upgrade();

        vm.recordLogs();
        vm.prank(user);
        dm.depositERC20(pol, 10e18);
        uint256 depositId = _lastDepositId();

        // POL is bridged as MATIC.
        (bytes32 depositHash, uint256 createdAt) = dm.deposits(depositId);
        assertEq(depositHash, keccak256(abi.encodePacked(user, matic, uint256(10e18))));
        assertEq(createdAt, block.timestamp);
    }

    /// The flag shares slot 2 with `governance`: setting it must not break `onlyGovernance` in the impl.
    function test_fixedImpl_governanceWorksWhileLocked() public {
        _upgrade();
        _lock();

        bytes32 slot2 = vm.load(address(dm), bytes32(GOVERNANCE_AND_LOCKED_SLOT));
        assertEq(address(uint160(uint256(slot2))), address(governance), "governance preserved");

        _governanceCall(abi.encodeCall(IDepositManagerFork.updateMaxErc20Deposit, (5e18)));
        assertEq(dm.maxErc20Deposit(), 5e18);
        assertEq(vm.load(address(dm), bytes32(GOVERNANCE_AND_LOCKED_SLOT)), slot2, "slot 2 untouched");
    }

    /// Rollout hazard: a `lock()` sent before the upgrade (ignored by the live impl) bites as soon as the fixed impl
    /// is in. Check `locked()` before upgrading.
    function test_upgrade_whileLocked_pauseTakesEffectImmediately() public {
        _lock();
        _assertEveryDepositPathSucceeds();

        _upgrade();
        _assertEveryDepositPathReverts();
    }

    function _assertEveryDepositPathSucceeds() internal {
        (address[] memory tokens, uint256[] memory amounts) = _bulk();
        vm.startPrank(user);
        vm.expectEmit(true, true, false, false, address(dm));
        emit NewDepositBlock(user, weth, 1 ether, 0);
        dm.depositEther{value: 1 ether}();
        vm.expectEmit(true, true, false, false, address(dm));
        emit NewDepositBlock(user, weth, 1 ether, 0);
        (bool ok,) = address(dm).call{value: 1 ether}("");
        assertTrue(ok);
        vm.expectEmit(true, true, false, false, address(dm));
        emit NewDepositBlock(user, matic, 1e18, 0);
        dm.depositERC20(pol, 1e18);
        vm.expectEmit(true, true, false, false, address(dm));
        emit NewDepositBlock(user, matic, 1e18, 0);
        dm.depositERC20ForUser(pol, user, 1e18);
        vm.expectEmit(true, true, false, false, address(dm));
        emit NewDepositBlock(user, matic, 1e18, 0);
        dm.depositBulk(tokens, amounts, user);
        vm.stopPrank();
    }

    function _assertEveryDepositPathReverts() internal {
        (address[] memory tokens, uint256[] memory amounts) = _bulk();
        vm.startPrank(user);
        vm.expectRevert("Is Locked");
        dm.depositEther{value: 1 ether}();
        (bool ok,) = address(dm).call{value: 1 ether}("");
        assertFalse(ok, "fallback deposit");
        vm.expectRevert("Is Locked");
        dm.depositERC20(pol, 1e18);
        vm.expectRevert("Is Locked");
        dm.depositERC20ForUser(pol, user, 1e18);
        vm.expectRevert("Is Locked");
        dm.depositBulk(tokens, amounts, user);
        vm.stopPrank();
    }

    function _bulk() internal view returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](1);
        amounts = new uint256[](1);
        (tokens[0], amounts[0]) = (pol, 1e18);
    }

    function _upgrade() internal {
        address impl = deployCode("out/DepositManager.sol/DepositManager.json");
        _timelockCall(address(dm), abi.encodeCall(IDepositManagerFork.updateImplementation, (impl)));
        assertEq(dm.implementation(), impl);
    }

    function _lock() internal {
        _governanceCall(abi.encodeCall(IDepositManagerFork.lock, ()));
    }

    function _unlock() internal {
        _governanceCall(abi.encodeCall(IDepositManagerFork.unlock, ()));
    }

    function _governanceCall(bytes memory data) internal {
        _timelockCall(address(governance), abi.encodeCall(IGovernanceFork.update, (address(dm), data)));
    }

    function _timelockCall(address target, bytes memory data) internal {
        bytes32 s = keccak256(abi.encode("DepositManagerLockForkTest", ++salt));
        uint256 delay = timelock.getMinDelay();
        vm.prank(rootSafe);
        timelock.schedule(target, 0, data, bytes32(0), s, delay);
        vm.warp(block.timestamp + delay);
        vm.prank(rootSafe);
        timelock.execute(target, 0, data, bytes32(0), s);
    }

    function _lastDepositId() internal returns (uint256) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; --i) {
            if (logs[i - 1].emitter == address(dm) && logs[i - 1].topics[0] == NewDepositBlock.selector) {
                (, uint256 depositId) = abi.decode(logs[i - 1].data, (uint256, uint256));
                return depositId;
            }
        }
        revert("no NewDepositBlock");
    }

    function _slots() internal view returns (bytes32[9] memory s) {
        for (uint256 i = 0; i <= MAX_ERC20_DEPOSIT_SLOT; ++i) {
            s[i] = vm.load(address(dm), bytes32(i));
        }
    }

    function _byte20(uint256 slot) internal view returns (uint256) {
        return (uint256(vm.load(address(dm), bytes32(slot))) >> 160) & 0xff;
    }
}
