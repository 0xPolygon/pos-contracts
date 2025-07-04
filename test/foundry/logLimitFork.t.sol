// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "lib/forge-std/src/Test.sol";
import "scripts/deployers/tmp-log-limit-removal/logLimit.s.sol";
import "scripts/helpers/interfaces/ERC20.generated.sol";

contract LogLimitForkTest is Test, LogLimit {
    function setUp() public {
        vm.createSelectFork("mainnet");
        run();
    }

    function test_LogLimit() public {
        // This is their old bridge wrapping contract. Only works with matic by default, but a rescue funds method is available
        address exitingAccount = 0xc980508cC8866f726040Da1C0C61f682e74aBc39;
        ERC20 polToken = ERC20(0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6);
        uint256 expectedAmount = 493_058_332_956_360_409_726_125;

        uint256 oldBalance = polToken.balanceOf(exitingAccount);

        vm.startPrank(posMultisig);
        address(timelock).call(scheduleCallData1);
        address(timelock).call(executeCallData1);
        vm.warp(vm.getBlockTimestamp() + 1);

        address(timelock).call(scheduleCallData2);
        address(timelock).call(executeCallData2);
        vm.stopPrank();

        uint256 newBalance = polToken.balanceOf(exitingAccount);
        assertEq(oldBalance + expectedAmount, newBalance);

        address newOldPredicate = registry.erc20Predicate();
        assertEq(currentPredicate, newOldPredicate);

        Registry.Type newPredicateStatus = registry.predicates(newPredicate);
        assertEq(Registry.Type.unwrap(newPredicateStatus), 0);
    }
}
