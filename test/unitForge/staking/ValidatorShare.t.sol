// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../script/setup/DeploySystem.s.sol";

contract ValidatorShareTest is Test, DeploySystem {
    ValidatorShare defaultValidator;
    uint8 defaultValidatorId = 8;

    address alice;
    uint256 alicePk;
    address bob = makeAddr("bob");
    uint256 defaultAmount = 100e18;
    uint256 bobAmount = 200e18;

    function setUp() public {
        deployAll();
        setTestConfig();
        skipFoundationValidators();
        addValidator(createValidator(defaultValidatorId));
        defaultValidator = getValidatorShareContract(defaultValidatorId);
        (alice, alicePk) = makeAddrAndKey("alice");
    }

    function test_lock_revertsWhenNotStakeManager() public {
        vm.prank(alice);
        vm.expectRevert();
        defaultValidator.lock();
    }

    function test_unlock_revertsWhenNotStakeManager() public {
        vm.prank(alice);
        vm.expectRevert();
        defaultValidator.unlock();
    }

    function test_updateDelegation_revertsWhenNotStakeManager() public {
        vm.prank(alice);
        vm.expectRevert();
        defaultValidator.updateDelegation(false);
    }

    function test_updateDelegation_updatesWhenStakeManager() public {
        vm.prank(address(stakeManager));
        defaultValidator.updateDelegation(false);
        assertFalse(defaultValidator.delegation());
    }

    function test_buyVoucherWithPermit() public {
        uint256 amount = 1e18;
        buyVoucherDefault(amount, alice, alicePk);
        assertEq(defaultValidator.balanceOf(alice), amount);
    }

    function test_buyVoucherWithPermit_invalidSignature() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 _v, bytes32 _r, bytes32 _s) =
            createPermit(alice, address(stakeManager), defaultAmount, deadline, alicePk + 1);

        vm.expectRevert("ERC2612InvalidSigner");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, _v, _r, _s);
    }

    function test_buyVoucherWithPermit_invalidSpender() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 _v, bytes32 _r, bytes32 _s) = createPermit(
            alice,
            address(defaultValidator), /* spender, tokens are pulled from stakeManager */
            defaultAmount,
            deadline,
            alicePk
        );
        vm.expectRevert("ERC2612InvalidSigner");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, _v, _r, _s);
    }

    function test_buyVoucherWithPermit_invalidDeadline() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 _v, bytes32 _r, bytes32 _s) =
            createPermit(alice, address(stakeManager), defaultAmount, deadline, alicePk + 1);
        vm.warp(deadline + 1);
        vm.expectRevert("ERC2612ExpiredSignature");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, _v, _r, _s);
    }

    function test_buyVoucherWithPermit_locked() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 _v, bytes32 _r, bytes32 _s) = createPermit(
            alice,
            address(stakeManager), /* spender, tokens are pulled from stakeManager */
            defaultAmount,
            deadline,
            alicePk
        );
        vm.prank(defaultValidator.owner());
        defaultValidator.lock();

        vm.expectRevert("locked");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, _v, _r, _s);
    }

    function test_buyVoucherWithPermit_unstaked() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 _v, bytes32 _r, bytes32 _s) = createPermit(
            alice,
            address(stakeManager), /* spender, tokens are pulled from stakeManager */
            defaultAmount,
            deadline,
            alicePk
        );
        vm.prank(stakeManager.governance());
        stakeManager.forceUnstake(defaultValidatorId);

        vm.expectRevert("locked");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, _v, _r, _s);
    }

    function test_buyVoucher_once() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
    }

    function test_buyVoucher_unstaked() public {
        vm.prank(stakeManager.governance());
        stakeManager.forceUnstake(defaultValidatorId);

        vm.expectRevert("locked");
        vm.prank(alice);
        defaultValidator.buyVoucherPOL(defaultAmount, defaultAmount);
    }

    function test_buyVoucher_delegation_disabled() public {
        vm.prank(defaultValidator.owner());
        defaultValidator.updateDelegation(false);
        vm.expectRevert("Delegation is disabled");
        vm.prank(alice);
        defaultValidator.buyVoucherPOL(defaultAmount, defaultAmount);
    }

    function test_buyVoucher_thrice_no_checkpoints() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);

        buyVoucherDefault(defaultAmount * 2, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 3);

        buyVoucherDefault(defaultAmount * 3, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 6);

        withdrawRewardsDefault(alice, 0);

        assertEq(defaultValidator.totalSupply(), defaultAmount * 6, "total supply not correct");
    }

    function test_buyVoucher_thrice_with_bob_no_checkpoints() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);

        buyVoucherDefault(bobAmount, bob, 0);
        assertEq(defaultValidator.balanceOf(bob), bobAmount);

        buyVoucherDefault(defaultAmount * 2, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 3);

        buyVoucherDefault(bobAmount * 2, bob, 0);
        assertEq(defaultValidator.balanceOf(bob), bobAmount * 3);

        buyVoucherDefault(defaultAmount * 3, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 6);

        buyVoucherDefault(bobAmount * 3, bob, 0);
        assertEq(defaultValidator.balanceOf(bob), bobAmount * 6);

        withdrawRewardsDefault(alice, 0);
        withdrawRewardsDefault(bob, 0);

        assertEq(defaultValidator.totalSupply(), defaultAmount * 6 + bobAmount * 6, "total supply not correct");
    }

    function test_exchangeRate_no_sell_withdraw() public {
        assertEq(defaultValidator.exchangeRate(), 1e29, "initial exchange rate not correct");
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after buyVoucher");
        progressCheckpointWithRewardsDefault();
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after checkpoint");
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after second buyVoucher");
    }

    function test_exchangeRate_with_sell() public {
        assertEq(defaultValidator.exchangeRate(), 1e29, "initial exchange rate not correct");
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after buyVoucher");
        sellVoucherDefault(alice, defaultAmount, false, true);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after sellVoucher");
    }

    function test_sellVoucher() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        sellVoucherDefault(alice, defaultAmount, false, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_two_checkpoints() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        sellVoucherDefault(alice, defaultAmount, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_partial_two_checkpoints() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        sellVoucherDefault(alice, defaultAmount / 2, true, true);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount / 2);
        progressCheckpointWithRewardsDefault();
        sellVoucherDefault(alice, defaultAmount / 2, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_partial_two_checkpoints_old() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        sellVoucherDefault(alice, defaultAmount / 2, true, false);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount / 2);
        progressCheckpointWithRewardsDefault();
        sellVoucherDefault(alice, defaultAmount / 2, true, false);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_two_checkpoints_with_bob() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        buyVoucherDefault(bobAmount, bob, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();

        sellVoucherDefault(alice, defaultAmount, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
        sellVoucherDefault(bob, bobAmount, true, true);
        assertEq(defaultValidator.balanceOf(bob), 0);
    }

    function test_sellVoucher_two_checkpoints_delegation_disabled() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        vm.prank(defaultValidator.owner());
        defaultValidator.updateDelegation(false);
        sellVoucherDefault(alice, defaultAmount, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_two_checkpoints_locked() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        vm.prank(defaultValidator.owner());
        defaultValidator.lock();
        sellVoucherDefault(alice, defaultAmount, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_to_much_requested() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        vm.expectRevert("Too much requested");
        vm.prank(alice);
        defaultValidator.sellVoucher_newPOL(defaultAmount + 1, defaultAmount);
    }

    function test_sellVoucher_after_unstake() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        vm.prank(stakeManager.governance());
        stakeManager.forceUnstake(defaultValidatorId);

        uint256 currentEpoch = stakeManager.currentEpoch();
        uint256 withdrawEpoch = currentEpoch + stakeManager.withdrawalDelay() + 100;
        vm.prank(address(governance));
        stakeManager.setCurrentEpoch(withdrawEpoch);
        vm.prank(StakingNFT(stakeManager.NFTContract()).ownerOf(defaultValidatorId));
        stakeManager.unstakeClaimPOL(defaultValidatorId);

        vm.prank(alice);
        sellVoucherDefault(alice, defaultAmount, false, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_claim_no_shares() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);

        vm.prank(alice);
        vm.expectRevert("Incomplete withdrawal period");
        defaultValidator.unstakeClaimTokensPOL();
    }

    function test_sellVoucher_claim_early() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);

        vm.prank(alice);
        defaultValidator.sellVoucherPOL(defaultAmount, defaultAmount);
        assertEq(defaultValidator.balanceOf(alice), 0);

        vm.prank(alice);
        vm.expectRevert("Incomplete withdrawal period");
        defaultValidator.unstakeClaimTokensPOL();
    }

    function test_sellVoucher_no_buy() public {
        assertEq(defaultValidator.balanceOf(alice), 0);

        vm.prank(alice);
        vm.expectRevert("Too much requested");
        defaultValidator.sellVoucherPOL(defaultAmount, defaultAmount);
    }

    function test_transfer_no_rewards() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        assertEq(defaultValidator.balanceOf(bob), 0);
        vm.prank(alice);
        defaultValidator.transferPOL(bob, defaultAmount);
        assertEq(defaultValidator.balanceOf(alice), 0);
        assertEq(defaultValidator.balanceOf(bob), defaultAmount);
        assertEq(polToken.balanceOf(alice), 0);
        assertEq(polToken.balanceOf(bob), 0);
    }

    function test_transfer_both_rewards() public {
        buyVoucherDefault(defaultAmount, alice, 0);
        buyVoucherDefault(bobAmount, bob, 0);

        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        assertEq(defaultValidator.balanceOf(bob), bobAmount);
        assertEq(polToken.balanceOf(alice), 0);
        assertEq(polToken.balanceOf(bob), 0);
        uint256 reward = progressCheckpointWithRewardsDefault();

        uint256 aliceRewards = defaultValidator.getLiquidRewards(alice);
        uint256 bobRewards = defaultValidator.getLiquidRewards(bob);

        // Fix by making defaultRewardPerfectCheckpoint accurate
        // assertEq(aliceRewards, defaultRewardPerfectCheckpoint(reward, defaultAmount), "Alice reward not as
        // expected");
        // assertEq(bobRewards, defaultRewardPerfectCheckpoint(reward, bobAmount), "Bob reward not as expected");
        assertGt(aliceRewards, 0, "Alice reward is 0");
        assertGt(bobRewards, 0, "Bob reward is 0");

        vm.expectEmit(true, true, true, true, address(stakingInfo));
        emit StakingInfo.DelegatorClaimedRewards(defaultValidatorId, bob, bobRewards);
        vm.expectEmit(true, true, true, true, address(stakingInfo));
        emit StakingInfo.DelegatorClaimedRewards(defaultValidatorId, alice, aliceRewards);

        vm.prank(alice);
        defaultValidator.transferPOL(bob, defaultAmount);

        assertEq(defaultValidator.balanceOf(alice), 0, "Alice must have no shares after transfer");
        assertEq(
            defaultValidator.balanceOf(bob),
            defaultAmount + bobAmount,
            "Bob must have both share amounts after transfer"
        );
        assertEq(defaultValidator.getLiquidRewards(alice), 0, "Alice must have no liquid rewards after transfer");
        assertEq(defaultValidator.getLiquidRewards(bob), 0, "Bob must have no liquid rewards after target of transfer");
        assertEq(polToken.balanceOf(alice), aliceRewards, "Alice must have her rewards");
        assertEq(polToken.balanceOf(bob), bobRewards, "Bob must have only his rewards");
        assertEq(maticToken.balanceOf(alice), 0, "Alice must have unchanged matic balance");
        assertEq(maticToken.balanceOf(bob), 0, "Bob must have unchanged matic balance");
    }

    // Where do these weird numbers come from?
    // CHECKPOINT_REWARD = 20_188 * (10 ** 18); // checkpoint reward
    // 20188000000000000000000  total reward for the checkpoint
    //  2018800000000000000000  10% proposer bonus only for the proposer
    // 18169200000000000000000  90% remaining rewards, this gets distributed to all stakes/delegators and the
    // proposer (addition to bonus)
    function test_buyVoucher_thrice_3_checkpoints() public {
        defaultAmount = 1000e18;
        console.log("first buyVoucher");
        buyVoucherDefault(defaultAmount, alice, 0);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount, "alice has non 0 dPOL balance");
        assertEq(defaultValidator.getLiquidRewards(alice), 0, "alice has non 0 rewards");
        assertEq(polToken.balanceOf(alice), 0, "alice has non 0 POL balance");

        console.log("first checkpoint");
        uint256 reward = progressCheckpointWithRewardsDefault();

        uint256 firstRewardAlice = defaultRewardPerfectCheckpoint(reward, defaultAmount);
        uint256 aliceRewards = defaultValidator.getLiquidRewards(alice);
        assertEq(firstRewardAlice, aliceRewards, "Initial reward not correct");
        assertEq(
            defaultRewardPerfectCheckpoint(reward, defaultAmount + defaultStakeVS),
            defaultRewardPerfectCheckpoint(reward, stakeManager.currentValidatorSetTotalStake()),
            "Total stake not correct"
        );
        //uint256 stValReward = stakeManager.validatorReward(defaultValidatorId);
        uint256 stDelReward = stakeManager.delegatorsReward(defaultValidatorId);
        assertEq(stDelReward, aliceRewards, "alice rewards not matching delegator rewards");

        // assertEq(
        //     defaultRewardPerfectCheckpoint(reward, stakeManager.currentValidatorSetTotalStake()),
        //     stValReward + stDelReward,
        //     "Total reward calc not correct"
        // );

        console.log("second buyVoucher");
        buyVoucherDefault(defaultAmount * 2, alice, 0);
        assertEq(polToken.balanceOf(alice), firstRewardAlice, "alice didn't get correct calculated first reward");
        assertEq(polToken.balanceOf(alice), aliceRewards, "alice didn't get assumed first reward");

        // this is almost true, some rounding seems to happen
        //assertEq(v1RwewardCalc * 1001, (defaultRewardPerfectCheckpoint(reward1, defaultAmount)) * 1003);
        console.log("second checkpoint");
        uint256 reward2 = progressCheckpointWithRewardsDefault();
        // Total reward should be the same each checkpoint
        assertEq(reward2, reward, "Total checkpoint reward not the same");

        // It is times 3 (not 4) because the the rewards from the first cycle were payed out during second buyVoucher
        uint256 secondRewardAlice = defaultRewardPerfectCheckpoint(reward, defaultAmount * 3);

        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 3, "alice has wrong second dPOL balance");
        assertEq(polToken.balanceOf(alice), firstRewardAlice, "alice POL balance changed after checkpoint");

        assertEq(
            secondRewardAlice,
            defaultValidator.getLiquidRewards(alice),
            "alice liquid rewards don't match after second checkpoint"
        );

        console.log("third buyVoucher");
        buyVoucherDefault(defaultAmount * 3, alice, 0);

        assertEq(
            polToken.balanceOf(alice),
            firstRewardAlice + secondRewardAlice,
            "alice has wrong POL balance after second buyVoucher"
        );

        assertEq(
            defaultValidator.balanceOf(alice), defaultAmount * 6, "alice has wrong dPOL balance after third buyVoucher"
        );
        assertEq(defaultValidator.getLiquidRewards(alice), 0, "alice has non 0 rewards after third buyVoucher");

        console.log("third checkpoint");
        progressCheckpointWithRewardsDefault();
        uint256 thirdRewardAlice = defaultRewardPerfectCheckpoint(reward, defaultAmount * 6);

        assertEq(
            defaultRewardPerfectCheckpoint(reward, defaultAmount * 6),
            defaultValidator.getLiquidRewards(alice),
            "alice liquid rewards don't match after third checkpoint"
        );
        console.log("withdraw rewards");
        withdrawRewardsDefault(alice, defaultRewardPerfectCheckpoint(reward, defaultAmount * 6));
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 6, "alice has wrong dPOL balance after withdraw");

        // 6 were just withdrawn, 1 is from first cycle, and 3 are from second cycle that were withdrawn during
        assertEq(
            polToken.balanceOf(alice),
            firstRewardAlice + secondRewardAlice + thirdRewardAlice,
            "alice has wrong POL balance after withdraw rewards"
        );
    }

    function defaultRewardPerfectCheckpoint(
        uint256 reward,
        uint256 amount
    )
        //uint256 lastRewardPerShare
        public
        view
        returns (uint256 delReward /*, uint256 rewardPerShare*/ )
    {
        uint256 currentTotalStake = stakeManager.currentValidatorSetTotalStake();
        // console.log("total stake", currentTotalStake);
        uint256 proposerBonus = (reward * stakeManager.proposerBonus()) / 100;
        // console.log("proposer bonus", proposerBonus);
        uint256 remainingReward = reward - proposerBonus;
        //console.log("remaining reward", remainingReward);
        uint256 rewardPerStake = (remainingReward * 10 ** 25) /* stakeManager.REWARD_PRECISION() */ / currentTotalStake;
        uint256 eligbleReward = (rewardPerStake * currentTotalStake) / uint256(10 ** 25);

        uint256 validatorReward = defaultStakeVS * eligbleReward / currentTotalStake;
        // This needs to be done this way (first calc validator reward, then substract from total reward, instead of
        // calcing one shared exchange rate for both validator and delegators)

        // uint256 stValReward = stakeManager.validatorReward(defaultValidatorId);
        // uint256 stDelReward = stakeManager.delegatorsReward(defaultValidatorId);
        //stValReward -= proposerBonus;

        uint256 delegatorReward = eligbleReward - validatorReward;

        // This has to be a bug, if alice is lone delegator, but doesn't get all rewards(only happens on lower amounts)
        //assertEq(defaultValidator.getLiquidRewards(alice), stakeManager.delegatorsReward(defaultValidatorId), "What");
        return delegatorReward;
        // tried rounding up, seens kluje tghe solution is that sometimes the validaotrs takes some more tokens
        // if (((rewardPerStake * amount) / uint256(10 ** 24)) % 10 > 4) {
        //     return ((rewardPerStake * amount) / uint256(10 ** 25)) + 1; /* stakeManager.REWARD_PRECISION() */
        // } else {
        //     return ((rewardPerStake * amount) / uint256(10 ** 25)); /* stakeManager.REWARD_PRECISION() */
        // }
    }

    // helpers
    // if userPk is 0, then no permit is used and it uses regular approve
    function buyVoucherDefault(uint256 amount, address user, uint256 userPk) public {
        uint256 currentStakeManagerStake = stakeManager.currentValidatorSetTotalStake();
        uint256 currentUserShares = defaultValidator.balanceOf(user);
        uint256 currentActiveAmount = defaultValidator.activeAmount();
        uint256 validatorNonce = stakingInfo.validatorNonce(defaultValidatorId);

        // Ensure allowance is zero
        assertEq(polToken.allowance(user, address(stakeManager)), 0, "initial user allowance not zero");
        fundAddr(user, amount);

        if (userPk == 0) {
            vm.prank(user);
            polToken.approve(address(stakeManager), amount);
        }

        // Test buying vouchers
        vm.expectEmit(true, true, false, true, address(defaultValidator));
        emit ValidatorShare.Transfer(address(0), user, amount);

        vm.expectEmit(true, true, true, true, address(stakingInfo));
        emit StakingInfo.ShareMinted(defaultValidatorId, user, amount, amount);

        vm.expectEmit(true, false, false, true, address(stakingInfo));
        emit StakingInfo.StakeUpdate(defaultValidatorId, validatorNonce, amount + currentActiveAmount);

        if (userPk == 0) {
            vm.prank(user);
            defaultValidator.buyVoucherPOL(amount, amount);
        } else {
            buyVouchersPOLPermit(defaultValidatorId, user, userPk, amount);
        }

        // Assert: staked amounts updated
        assertEq(currentUserShares + amount, defaultValidator.balanceOf(user), "users staked amount not correct");
        assertEq(
            currentStakeManagerStake + amount,
            stakeManager.currentValidatorSetTotalStake(),
            "total stakemanager stake not correct"
        );
    }

    function sellVoucherDefault(address user, uint256 amount, bool expectReward, bool newAPI) public {
        uint256 currentStakeManagerStake = stakeManager.currentValidatorSetTotalStake();

        uint256 currentUserShares = defaultValidator.balanceOf(user);
        uint256 polBalanceBefore = polToken.balanceOf(user);
        uint256 rewards = defaultValidator.getLiquidRewards(user);
        // why three?
        uint256 userNonce = defaultValidator.unbondNonces(user) + 1;
        uint256 validatorNonce = stakingInfo.validatorNonce(defaultValidatorId);

        bool fullyUnstaked = true;
        uint256 expectedStakeUpdate = 0;
        // not fully unstaked through validator unstake
        if (currentStakeManagerStake != 0) {
            fullyUnstaked = false;
            expectedStakeUpdate = currentStakeManagerStake - currentUserShares;
        }

        assertEq(rewards > 0, expectReward, "user reward expectation not met");
        // Test selling vouchers
        if (rewards > 0) {
            vm.expectEmit(true, true, true, true, address(polToken));
            emit ERC20Permit.Transfer(address(stakeManager), user, rewards);

            vm.expectEmit(true, true, false, true, address(stakingInfo));
            emit StakingInfo.DelegatorClaimedRewards(defaultValidatorId, user, rewards);
        }

        vm.expectEmit(true, true, false, true, address(defaultValidator));
        emit ValidatorShare.Transfer(user, address(0), amount);

        if (newAPI) {
            vm.expectEmit(true, true, false, true, address(eventsHub));
            emit EventsHub.ShareBurnedWithId(defaultValidatorId, user, amount, amount, userNonce);
        } else {
            vm.expectEmit(true, true, false, true, address(stakingInfo));
            emit StakingInfo.ShareBurned(defaultValidatorId, user, amount, amount);
        }

        vm.expectEmit(true, true, false, true, address(stakingInfo));
        emit StakingInfo.StakeUpdate(defaultValidatorId, validatorNonce + 1, expectedStakeUpdate);

        if (newAPI) {
            vm.prank(user);
            defaultValidator.sellVoucher_newPOL(amount, amount);
        } else {
            vm.prank(user);
            defaultValidator.sellVoucherPOL(amount, amount);
        }

        // Assert: staked amounts updated
        assertEq(currentUserShares - amount, defaultValidator.balanceOf(user), "users shares not properly reduced");
        if (!fullyUnstaked) {
            assertEq(
                currentStakeManagerStake - amount,
                stakeManager.currentValidatorSetTotalStake(),
                "stakeManager total stake not properly reduced"
            );
        }

        if (newAPI) {
            (, uint256 unbondWithdrawEpoch) = defaultValidator.unbonds_new(user, userNonce);
            assertEq(unbondWithdrawEpoch, stakeManager.currentEpoch());
        } else {
            (, uint256 unbondWithdrawEpoch) = defaultValidator.unbonds(user);
            assertEq(unbondWithdrawEpoch, stakeManager.currentEpoch());
        }

        uint256 currentEpoch = stakeManager.currentEpoch();
        uint256 withdrawEpoch = currentEpoch + stakeManager.withdrawalDelay() + 100;
        vm.prank(address(governance));
        stakeManager.setCurrentEpoch(withdrawEpoch);

        vm.expectEmit(true, true, true, true, address(polToken));
        emit ERC20Permit.Transfer(address(stakeManager), user, amount);

        if (newAPI) {
            vm.expectEmit(true, true, true, true, address(eventsHub));
            emit EventsHub.DelegatorUnstakeWithId(defaultValidatorId, user, amount, userNonce);
            vm.prank(user);
            defaultValidator.unstakeClaimTokens_newPOL(userNonce);
        } else {
            vm.expectEmit(true, true, true, true, address(stakingInfo));
            emit StakingInfo.DelegatorUnstaked(defaultValidatorId, user, amount);
            vm.prank(user);
            defaultValidator.unstakeClaimTokensPOL();
        }

        assertEq(polToken.balanceOf(user), polBalanceBefore + amount + rewards, "user didn't get correct POL back");
    }

    // if expect reward is 0, withdrawRewards should revert
    function withdrawRewardsDefault(address user, uint256 expectReward) public {
        uint256 initialBalance = polToken.balanceOf(user);
        uint256 reward = defaultValidator.getLiquidRewards(user);

        assertEq(reward, expectReward);
        if (reward > 0) {
            vm.expectEmit(true, true, true, true, address(polToken));
            emit ERC20Permit.Transfer(address(stakeManager), user, reward);
            vm.expectEmit(true, true, true, true, address(stakingInfo));
            emit StakingInfo.DelegatorClaimedRewards(defaultValidatorId, user, reward);
            vm.prank(user);
            defaultValidator.withdrawRewardsPOL();
            uint256 finalBalance = polToken.balanceOf(user);
            assertEq(finalBalance, initialBalance + reward);
            assertEq(defaultValidator.getLiquidRewards(user), 0);
        } else {
            vm.expectRevert("Too small rewards amount");
            vm.prank(user);
            defaultValidator.withdrawRewardsPOL();
        }
    }

    function progressCheckpointWithRewardsDefault() public returns (uint256) {
        Validator[] memory defaultValidatorArray = new Validator[](1);
        defaultValidatorArray[0] = createValidator(defaultValidatorId);
        return progressCheckpointWithRewards(defaultValidatorArray, address(defaultValidator));
    }
}
