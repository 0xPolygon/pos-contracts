// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../script/setup/DeploySystem.s.sol";
import {DepositManager as IDepositManager} from "../../../tools/interfaces/DepositManager.generated.sol";
import {DepositManagerProxy as IDepositManagerProxy} from "../../../tools/interfaces/DepositManagerProxy.generated.sol";
import {MaticWETH} from "../../../tools/interfaces/MaticWETH.generated.sol";
import {RootERC721} from "../../../tools/interfaces/RootERC721.generated.sol";

contract ExitQueueStub {
    function createExitQueue(address) external {}
}

/// @notice Offline coverage for the DepositManager pause: the implementation must read `locked` from the slot the
/// DepositManagerProxy's own `lock()`/`unlock()` write. The mainnet upgrade is covered by the fork tests.
contract DepositManagerLockTest is Test, DeploySystem {
    string constant DEPOSIT_MANAGER_PATH = "out/DepositManager.sol/DepositManager.json";
    string constant DEPOSIT_MANAGER_PROXY_PATH = "out/DepositManagerProxy.sol/DepositManagerProxy.json";

    // Mapping base slot of `deposits`.
    uint256 constant DEPOSITS_SLOT = 6;

    IDepositManager dm;
    MaticWETH weth;
    TestToken token;
    RootERC721 nft;
    address childChain = makeAddr("childChain");
    address user = makeAddr("user");

    function setUp() public {
        deployAll();

        address impl = deployCode(DEPOSIT_MANAGER_PATH);
        dm = IDepositManager(
            payable(
                deployCode(DEPOSIT_MANAGER_PROXY_PATH, abi.encode(impl, registry, rootChain, governanceProxy))
            )
        );

        weth = MaticWETH(payable(deployCode("out/MaticWETH.sol/MaticWETH.json")));
        token = TestToken(deployCode(TestTokenPath, abi.encode("Test Token", "TST")));
        nft = RootERC721(deployCode("out/RootERC721.sol/RootERC721.json", abi.encode("Test NFT", "TNFT")));

        updateRegistryContractMap("depositManager", address(dm));
        updateRegistryContractMap("wethToken", address(weth));
        updateRegistryContractMap("childChain", childChain);
        updateRegistryContractMap("withdrawManager", address(new ExitQueueStub()));
        StateSender(registry.contractMap(keccak256("stateSender"))).register(address(dm), childChain);
        dm.updateChildChainAndStateSender();

        _mapToken(address(weth), false);
        _mapToken(address(token), false);
        _mapToken(address(nft), true);

        vm.deal(user, 10 ether);
        token.mint(user, 1000e18);
        vm.startPrank(user);
        token.approve(address(dm), type(uint256).max);
        nft.mint(1);
        nft.mint(2);
        nft.mint(3);
        nft.setApprovalForAll(address(dm), true);
        vm.stopPrank();
    }

    function test_lock_blocksEveryDepositPath() public {
        _lock();
        assertTrue(dm.locked());

        vm.startPrank(user);
        vm.expectRevert("Is Locked");
        dm.depositEther{value: 1 ether}();
        vm.expectRevert("Is Locked");
        dm.depositERC20(address(token), 1e18);
        vm.expectRevert("Is Locked");
        dm.depositERC20ForUser(address(token), user, 1e18);
        vm.expectRevert("Is Locked");
        dm.depositERC721(address(nft), 1);
        vm.expectRevert("Is Locked");
        dm.depositERC721ForUser(address(nft), user, 1);
        (address[] memory tokens, uint256[] memory amounts) = _bulk();
        vm.expectRevert("Is Locked");
        dm.depositBulk(tokens, amounts, user);
        vm.stopPrank();
    }

    function test_lock_blocksPlainEtherTransfer() public {
        _lock();

        vm.prank(user);
        (bool ok,) = address(dm).call{value: 1 ether}("");
        assertFalse(ok, "fallback deposit must revert while locked");
    }

    function test_unlock_restoresEveryDepositPath() public {
        _lock();
        governanceUpdateCall(address(dm), abi.encodeWithSignature("unlock()"));
        assertFalse(dm.locked());

        vm.startPrank(user);
        dm.depositEther{value: 1 ether}();
        dm.depositERC20(address(token), 1e18);
        dm.depositERC20ForUser(address(token), user, 1e18);
        dm.depositERC721(address(nft), 1);
        dm.depositERC721ForUser(address(nft), user, 2);
        (address[] memory tokens, uint256[] memory amounts) = _bulk();
        dm.depositBulk(tokens, amounts, user);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), address(dm));
        assertEq(nft.ownerOf(2), address(dm));
        assertEq(nft.ownerOf(3), address(dm));
        assertEq(token.balanceOf(address(dm)), 3e18);
        assertEq(weth.balanceOf(address(dm)), 1 ether);
    }

    function test_lock_onlyGovernance() public {
        vm.expectRevert("Only governance contract is authorized");
        dm.lock();
        vm.expectRevert("Only governance contract is authorized");
        dm.unlock();
    }

    function test_lock_onlyTouchesTheFlagByte() public {
        bytes32 before = vm.load(address(dm), bytes32(uint256(2)));
        _lock();
        bytes32 afterLock = vm.load(address(dm), bytes32(uint256(2)));

        assertEq(uint256(afterLock), uint256(before) | (1 << 160));
        assertEq(address(uint160(uint256(afterLock))), governanceProxy, "governance preserved");
    }

    function test_lock_doesNotBlockGovernance() public {
        _lock();
        governanceUpdateCall(address(dm), abi.encodeWithSignature("updateMaxErc20Deposit(uint256)", 5e18));
        assertEq(dm.maxErc20Deposit(), 5e18);
    }

    /// @dev The proxy's getters are compiled from DepositManagerStorageLegacy, the impl's from whatever the impl
    /// inherits. Same raw storage must read back the same through both, for every variable.
    function test_storageLayout_implMatchesProxy() public {
        address impl = deployCode(DEPOSIT_MANAGER_PATH);
        _assertSameLayout(impl, false);
        _assertSameLayout(impl, true);
    }

    function _assertSameLayout(address impl, bool lockedInSlot2) internal {
        bytes32[9] memory words = [
            bytes32(uint256(uint160(makeAddr("owner_")))),
            // proxyTo; byte 20 is padding in the proxy, so it must not affect `locked` either way.
            bytes32(uint256(uint160(impl)) | (lockedInSlot2 ? 0 : 1 << 160)),
            bytes32(uint256(uint160(makeAddr("governance_"))) | (lockedInSlot2 ? 1 << 160 : 0)),
            bytes32(uint256(uint160(makeAddr("registry_")))),
            bytes32(uint256(uint160(makeAddr("rootChain_")))),
            bytes32(uint256(uint160(makeAddr("stateSender_")))),
            bytes32(0),
            bytes32(uint256(uint160(makeAddr("childChain_")))),
            bytes32(uint256(123e18))
        ];
        bytes32 depositSlot = keccak256(abi.encode(uint256(7), DEPOSITS_SLOT));
        address[2] memory targets = [impl, address(dm)];
        for (uint256 t = 0; t < 2; ++t) {
            for (uint256 i = 0; i < words.length; ++i) {
                vm.store(targets[t], bytes32(i), words[i]);
            }
            vm.store(targets[t], depositSlot, keccak256("depositHash"));
            vm.store(targets[t], bytes32(uint256(depositSlot) + 1), bytes32(uint256(42)));
        }

        IDepositManager a = IDepositManager(payable(impl));
        IDepositManagerProxy b = IDepositManagerProxy(payable(address(dm)));
        assertEq(a.locked(), lockedInSlot2, "impl locked");
        assertEq(b.locked(), lockedInSlot2, "proxy locked");
        assertEq(a.owner(), b.owner(), "owner");
        assertEq(a.governance(), b.governance(), "governance");
        assertEq(a.registry(), b.registry(), "registry");
        assertEq(a.rootChain(), b.rootChain(), "rootChain");
        assertEq(a.stateSender(), b.stateSender(), "stateSender");
        assertEq(a.childChain(), b.childChain(), "childChain");
        assertEq(a.maxErc20Deposit(), b.maxErc20Deposit(), "maxErc20Deposit");
        (bytes32 hashA, uint256 createdAtA) = a.deposits(7);
        (bytes32 hashB, uint256 createdAtB) = b.deposits(7);
        assertEq(hashA, keccak256("depositHash"), "deposits hash");
        assertEq(hashA, hashB, "deposits hash");
        assertEq(createdAtA, createdAtB, "deposits createdAt");
        assertEq(b.implementation(), impl, "proxyTo");
    }

    function _lock() internal {
        governanceUpdateCall(address(dm), abi.encodeWithSignature("lock()"));
    }

    function _mapToken(address rootToken, bool isERC721) internal {
        governanceUpdateCall(
            address(registry),
            abi.encodeCall(Registry.mapToken, (rootToken, address(uint160(uint256(keccak256(abi.encode(rootToken))))), isERC721))
        );
    }

    function _bulk() internal view returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](2);
        amounts = new uint256[](2);
        (tokens[0], amounts[0]) = (address(token), 1e18);
        (tokens[1], amounts[1]) = (address(nft), 3);
    }
}
