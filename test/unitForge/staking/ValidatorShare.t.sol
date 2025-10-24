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
    uint256 defaultAmount = 1e18;
    uint256 bobAmount = 2000e18;
    // Found in StakeManager.sol
    uint256 constant STAKEMANAGER_REWARD_PRECISION = 10 ** 25;
    uint256 constant VALIDATORSHARE_REWARD_PRECISION = 10 ** 29;

    function setUp() public {
        deployAll();
        setTestConfig();
        skipFoundationValidators();
        addValidator(createValidator(defaultValidatorId));
        defaultValidator = getValidatorShareContract(defaultValidatorId);
        (alice, alicePk) = makeAddrAndKey("alice");
    }

    function test_lock_notStakeManager() public {
        vm.prank(alice);
        vm.expectRevert(bytes(""));
        defaultValidator.lock();
    }

    function test_unlock_notStakeManager() public {
        vm.prank(alice);
        vm.expectRevert(bytes(""));
        defaultValidator.unlock();
    }

    function test_updateDelegation_notStakeManager() public {
        vm.prank(alice);
        vm.expectRevert(bytes(""));
        defaultValidator.updateDelegation(false);
    }

    function test_updateDelegation_stakeManager() public {
        vm.prank(address(stakeManager));
        defaultValidator.updateDelegation(false);
        assertFalse(defaultValidator.delegation());
    }

    function test_name() public view {
        assertEq(defaultValidator.name(), "Delegated POL #8");
    }

    function test_symbol() public view {
        assertEq(defaultValidator.symbol(), "dPOL8");
    }

    function test_buyVoucherWithPermit() public {
        buyVoucherDefaultPermitTested(defaultAmount, alice, alicePk);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
    }

    function test_buyVoucherWithPermit_invalidSignature() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 v, bytes32 r, bytes32 s) =
            createPermit(alice, address(stakeManager), defaultAmount, deadline, alicePk + 1);

        vm.expectRevert("ERC2612InvalidSigner");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, v, r, s);
    }

    function test_buyVoucherWithPermit_invalidSpender() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 v, bytes32 r, bytes32 s) = createPermit(
            alice,
            address(defaultValidator), /* spender, tokens are pulled from stakeManager */
            defaultAmount,
            deadline,
            alicePk
        );
        vm.expectRevert("ERC2612InvalidSigner");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, v, r, s);
    }

    function test_buyVoucherWithPermit_invalidDeadline() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 v, bytes32 r, bytes32 s) =
            createPermit(alice, address(stakeManager), defaultAmount, deadline, alicePk + 1);
        vm.warp(deadline + 1);
        vm.expectRevert("ERC2612ExpiredSignature");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, v, r, s);
    }

    function test_buyVoucherWithPermit_locked() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 v, bytes32 r, bytes32 s) = createPermit(alice, address(stakeManager), defaultAmount, deadline, alicePk);
        vm.prank(defaultValidator.owner());
        defaultValidator.lock();

        vm.expectRevert("locked");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, v, r, s);
    }

    function test_buyVoucherWithPermit_unstaked() public {
        uint256 deadline = block.timestamp + 10;
        (uint8 v, bytes32 r, bytes32 s) = createPermit(alice, address(stakeManager), defaultAmount, deadline, alicePk);
        vm.prank(stakeManager.governance());
        stakeManager.forceUnstake(defaultValidatorId);

        vm.expectRevert("locked");
        vm.prank(alice);
        defaultValidator.buyVoucherWithPermit(defaultAmount, defaultAmount, deadline, v, r, s);
    }

    function test_buyVoucher_once() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
    }

    function test_buyVoucher_once_matic() public {
        buyVoucherDefaultMaticTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
    }

    function test_buyVoucher_unstaked() public {
        vm.prank(stakeManager.governance());
        stakeManager.forceUnstake(defaultValidatorId);

        vm.expectRevert("locked");
        vm.prank(alice);
        defaultValidator.buyVoucherPOL(defaultAmount, defaultAmount);
    }

    function test_buyVoucher_unstaked_matic() public {
        vm.prank(stakeManager.governance());
        stakeManager.forceUnstake(defaultValidatorId);

        vm.expectRevert("locked");
        vm.prank(alice);
        defaultValidator.buyVoucher(defaultAmount, defaultAmount);
    }

    function test_buyVoucher_delegationDisabled() public {
        vm.prank(defaultValidator.owner());
        defaultValidator.updateDelegation(false);
        vm.expectRevert("Delegation is disabled");
        vm.prank(alice);
        defaultValidator.buyVoucherPOL(defaultAmount, defaultAmount);
    }

    function test_buyVoucher_delegationDisabled_matic() public {
        vm.prank(defaultValidator.owner());
        defaultValidator.updateDelegation(false);
        vm.expectRevert("Delegation is disabled");
        vm.prank(alice);
        defaultValidator.buyVoucher(defaultAmount, defaultAmount);
    }

    function test_buyVoucher_thrice_no_checkpoints() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);

        buyVoucherDefaultTested(defaultAmount * 2, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 3);

        buyVoucherDefaultTested(defaultAmount * 3, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 6);

        withdrawRewardsDefaultTested(alice, 0);

        assertEq(defaultValidator.totalSupply(), defaultAmount * 6, "total supply not correct");
    }

    function test_buyVoucher_thrice_no_checkpoints_matic() public {
        buyVoucherDefaultMaticTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);

        buyVoucherDefaultMaticTested(defaultAmount * 2, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 3);

        buyVoucherDefaultMaticTested(defaultAmount * 3, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 6);

        withdrawRewardsDefaultTested(alice, 0);

        assertEq(defaultValidator.totalSupply(), defaultAmount * 6, "total supply not correct");
    }

    function test_buyVoucher_thrice_with_bob_no_checkpoints() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);

        buyVoucherDefaultTested(bobAmount, bob);
        assertEq(defaultValidator.balanceOf(bob), bobAmount);

        buyVoucherDefaultTested(defaultAmount * 2, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 3);

        buyVoucherDefaultTested(bobAmount * 2, bob);
        assertEq(defaultValidator.balanceOf(bob), bobAmount * 3);

        buyVoucherDefaultTested(defaultAmount * 3, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 6);

        buyVoucherDefaultTested(bobAmount * 3, bob);
        assertEq(defaultValidator.balanceOf(bob), bobAmount * 6);

        withdrawRewardsDefaultTested(alice, 0);
        withdrawRewardsDefaultTested(bob, 0);

        assertEq(defaultValidator.totalSupply(), defaultAmount * 6 + bobAmount * 6, "total supply not correct");
    }

    function test_exchangeRate_nosellorwithdraw() public {
        assertEq(defaultValidator.exchangeRate(), 1e29, "initial exchange rate not correct");
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after buyVoucher");
        buyVoucherDefaultMaticTested(defaultAmount, alice);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after buyVoucherMatic");
        progressCheckpointWithRewardsDefault();
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after checkpoint");
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after second buyVoucher");
        buyVoucherDefaultMaticTested(defaultAmount, alice);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after second buyVoucherMatic");
    }

    function test_exchangeRate_sell() public {
        assertEq(defaultValidator.exchangeRate(), 1e29, "initial exchange rate not correct");
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after buyVoucher");
        sellVoucherDefaultTested(alice, defaultAmount, false, true);
        assertEq(defaultValidator.exchangeRate(), 1e29, "exchange rate not correct after sellVoucher");
    }

    function test_sellVoucher() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        sellVoucherDefaultTested(alice, defaultAmount, false, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_matic() public {
        buyVoucherDefaultMaticTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        sellVoucherDefaultMaticTested(alice, defaultAmount, false, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_two_checkpoints() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        sellVoucherDefaultTested(alice, defaultAmount, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_partial_two_checkpoints() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        sellVoucherDefaultTested(alice, defaultAmount / 2, true, true);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount / 2);
        progressCheckpointWithRewardsDefault();
        sellVoucherDefaultTested(alice, defaultAmount / 2, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_partial_two_checkpoints_matic() public {
        buyVoucherDefaultMaticTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        sellVoucherDefaultMaticTested(alice, defaultAmount / 2, true, true);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount / 2);
        progressCheckpointWithRewardsDefault();
        sellVoucherDefaultMaticTested(alice, defaultAmount / 2, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_partial_two_checkpoints_oldApi() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        sellVoucherDefaultTested(alice, defaultAmount / 2, true, false);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount / 2);
        progressCheckpointWithRewardsDefault();
        sellVoucherDefaultTested(alice, defaultAmount / 2, true, false);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_partial_two_checkpoints_oldApi_matic() public {
        buyVoucherDefaultMaticTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        sellVoucherDefaultMaticTested(alice, defaultAmount / 2, true, false);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount / 2);
        progressCheckpointWithRewardsDefault();
        sellVoucherDefaultMaticTested(alice, defaultAmount / 2, true, false);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_two_checkpoints_with_bob() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        buyVoucherDefaultTested(bobAmount, bob);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();

        sellVoucherDefaultTested(alice, defaultAmount, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
        sellVoucherDefaultTested(bob, bobAmount, true, true);
        assertEq(defaultValidator.balanceOf(bob), 0);
    }

    function test_sellVoucher_two_checkpoints_delegationDisabled() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        vm.prank(defaultValidator.owner());
        defaultValidator.updateDelegation(false);
        sellVoucherDefaultTested(alice, defaultAmount, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_two_checkpoints_locked() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        progressCheckpointWithRewardsDefault();
        progressCheckpointWithRewardsDefault();
        vm.prank(defaultValidator.owner());
        defaultValidator.lock();
        sellVoucherDefaultTested(alice, defaultAmount, true, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_toMuchRequested() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        vm.expectRevert("Too much requested");
        vm.prank(alice);
        defaultValidator.sellVoucher_newPOL(defaultAmount + 1, defaultAmount);
    }

    function test_sellVoucher_after_unstake() public {
        buyVoucherDefaultTested(defaultAmount, alice);
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
        sellVoucherDefaultTested(alice, defaultAmount, false, true);
        assertEq(defaultValidator.balanceOf(alice), 0);
    }

    function test_sellVoucher_claim_noshares() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);

        vm.prank(alice);
        vm.expectRevert("Incomplete withdrawal period");
        defaultValidator.unstakeClaimTokensPOL();
    }

    function test_sellVoucher_claim_early() public {
        buyVoucherDefaultTested(defaultAmount, alice);
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

    function test_transfer_norewards() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        assertEq(defaultValidator.balanceOf(bob), 0);
        vm.prank(alice);
        defaultValidator.transferPOL(bob, defaultAmount);
        assertEq(defaultValidator.balanceOf(alice), 0);
        assertEq(defaultValidator.balanceOf(bob), defaultAmount);
        assertEq(polToken.balanceOf(alice), 0);
        assertEq(polToken.balanceOf(bob), 0);
    }

    function test_transfer_bothrewards() public {
        buyVoucherDefaultTested(defaultAmount, alice);
        buyVoucherDefaultTested(bobAmount, bob);

        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        assertEq(defaultValidator.balanceOf(bob), bobAmount);
        assertEq(polToken.balanceOf(alice), 0);
        assertEq(polToken.balanceOf(bob), 0);
        uint256 reward = progressCheckpointWithRewardsDefault();

        uint256 aliceRewards = defaultValidator.getLiquidRewards(alice);
        uint256 bobRewards = defaultValidator.getLiquidRewards(bob);

        // TODO rounding issue in reward calc, likely related to initial reward per share calculations
        assertApproxEqAbs(
            aliceRewards + bobRewards,
            defaultRewardPerfectCheckpoint(reward, defaultAmount + bobAmount, defaultAmount + bobAmount),
            1,
            "Sum of rewards not matching calculated delegator rewards"
        );
        assertEq(
            aliceRewards,
            defaultRewardPerfectCheckpoint(reward, defaultAmount, defaultAmount + bobAmount),
            "Alice reward not as expected"
        );
        assertEq(
            bobRewards,
            defaultRewardPerfectCheckpoint(reward, bobAmount, defaultAmount + bobAmount),
            "Bob reward not as expected"
        );

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

    function test_transferFrom_norewards() public {
        address charlie = makeAddr("charlie");
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount);
        assertEq(defaultValidator.balanceOf(charlie), 0);
        
        // Alice approves charlie to transfer her tokens
        vm.prank(alice);
        defaultValidator.approve(charlie, defaultAmount);
        
        // Charlie transfers from alice to bob
        vm.prank(charlie);
        defaultValidator.transferFrom(alice, bob, defaultAmount);
        
        assertEq(defaultValidator.balanceOf(alice), 0);
        assertEq(defaultValidator.balanceOf(bob), defaultAmount);
        assertEq(polToken.balanceOf(alice), 0);
        assertEq(polToken.balanceOf(bob), 0);
    }

    function test_transferFrom_withrewards_existingRecipient() public {
        address charlie = makeAddr("charlie");
        buyVoucherDefaultTested(defaultAmount, alice);
        buyVoucherDefaultTested(bobAmount, bob);
        
        uint256 reward = progressCheckpointWithRewardsDefault();
        
        uint256 aliceRewards = defaultValidator.getLiquidRewards(alice);
        uint256 bobRewardsBefore = defaultValidator.getLiquidRewards(bob);
        uint256 bobSharesBefore = defaultValidator.balanceOf(bob);
        
        assertEq(
            aliceRewards,
            defaultRewardPerfectCheckpoint(reward, defaultAmount, defaultAmount + bobAmount),
            "Alice reward not as expected"
        );
        assertEq(
            bobRewardsBefore,
            defaultRewardPerfectCheckpoint(reward, bobAmount, defaultAmount + bobAmount),
            "Bob reward not as expected"
        );
        
        // Alice approves charlie to transfer her tokens
        vm.prank(alice);
        defaultValidator.approve(charlie, defaultAmount);
        
        // Expect alice's rewards to be paid out, bob's to be restaked
        vm.expectEmit(true, true, true, true, address(stakingInfo));
        emit StakingInfo.DelegatorClaimedRewards(defaultValidatorId, alice, aliceRewards);
        
        // Charlie transfers from alice to bob
        vm.prank(charlie);
        defaultValidator.transferFrom(alice, bob, defaultAmount);
        
        assertEq(defaultValidator.balanceOf(alice), 0, "Alice must have no shares after transfer");
        // Bob should have original shares + transferred shares + restaked rewards (as shares)
        assertGt(
            defaultValidator.balanceOf(bob),
            defaultAmount + bobSharesBefore,
            "Bob must have shares from transfer plus restaked rewards"
        );
        assertEq(defaultValidator.getLiquidRewards(alice), 0, "Alice must have no liquid rewards after transfer");
        assertEq(defaultValidator.getLiquidRewards(bob), 0, "Bob must have no liquid rewards after transfer (restaked)");
        assertEq(polToken.balanceOf(alice), aliceRewards, "Alice must have her rewards as POL");
        assertEq(polToken.balanceOf(bob), 0, "Bob's rewards were restaked, not paid out");
    }

    function test_transferFrom_withrewards_newRecipient() public {
        address charlie = makeAddr("charlie");
        address newUser = makeAddr("newUser");
        
        buyVoucherDefaultTested(defaultAmount, alice);
        
        progressCheckpointWithRewardsDefault();
        
        uint256 aliceRewards = defaultValidator.getLiquidRewards(alice);
        
        // Alice approves charlie to transfer her tokens
        vm.prank(alice);
        defaultValidator.approve(charlie, defaultAmount);
        
        // Expect alice's rewards to be paid out
        vm.expectEmit(true, true, true, true, address(stakingInfo));
        emit StakingInfo.DelegatorClaimedRewards(defaultValidatorId, alice, aliceRewards);
        
        // Charlie transfers from alice to new user
        vm.prank(charlie);
        defaultValidator.transferFrom(alice, newUser, defaultAmount);
        
        assertEq(defaultValidator.balanceOf(alice), 0, "Alice must have no shares after transfer");
        assertEq(defaultValidator.balanceOf(newUser), defaultAmount, "New user must have transferred shares");
        assertEq(defaultValidator.getLiquidRewards(newUser), 0, "New user should have no claimable rewards yet");
        assertEq(polToken.balanceOf(alice), aliceRewards, "Alice must have her rewards as POL");
        assertEq(polToken.balanceOf(newUser), 0, "New user should have no POL");
        
        // Verify new user's baseline is set correctly (they shouldn't claim historical rewards)
        assertEq(defaultValidator.initalRewardPerShare(newUser), defaultValidator.rewardPerShare(), "New user baseline should be current");
    }

    function test_transferFrom_noApproval() public {
        address charlie = makeAddr("charlie");
        buyVoucherDefaultTested(defaultAmount, alice);
        
        // Charlie tries to transfer without approval
        vm.prank(charlie);
        vm.expectRevert();
        defaultValidator.transferFrom(alice, bob, defaultAmount);
    }

    function test_transferFrom_insufficientApproval() public {
        address charlie = makeAddr("charlie");
        buyVoucherDefaultTested(defaultAmount, alice);
        
        // Alice approves charlie for less than the transfer amount
        vm.prank(alice);
        defaultValidator.approve(charlie, defaultAmount / 2);
        
        // Charlie tries to transfer more than approved
        vm.prank(charlie);
        vm.expectRevert();
        defaultValidator.transferFrom(alice, bob, defaultAmount);
    }

    // Where do these weird numbers come from?
    // CHECKPOINTREWARD = 20_188 * (10 ** 18); // checkpoint reward
    // 20188000000000000000000  total reward for the checkpoint
    //  2018800000000000000000  10% proposer bonus only for the proposer
    // 18169200000000000000000  90% remaining rewards, this gets distributed to all stakes/delegators and the
    // proposer (addition to bonus)
    function test_buyVoucher_thrice_3_checkpoints() public {
        // This breaks if default amount is lower, that's why we use approxEq sometimes
        // console.log("first buyVoucher");
        buyVoucherDefaultTested(defaultAmount, alice);
        assertEq(defaultValidator.balanceOf(alice), defaultAmount, "alice has non 0 dPOL balance");
        assertEq(defaultValidator.getLiquidRewards(alice), 0, "alice has non 0 rewards");
        assertEq(polToken.balanceOf(alice), 0, "alice has non 0 POL balance");

        // console.log("first checkpoint");
        uint256 reward = progressCheckpointWithRewardsDefault();

        uint256 firstRewardAlice = defaultRewardPerfectCheckpoint(reward, defaultAmount, defaultAmount);
        uint256 aliceRewards = defaultValidator.getLiquidRewards(alice);
        assertEq(firstRewardAlice, aliceRewards, "Initial reward not correct");
        // assertEq(
        //     defaultRewardPerfectCheckpoint(reward, defaultAmount + defaultStakeVS, defaultAmount),
        //     defaultRewardPerfectCheckpoint(reward, stakeManager.currentValidatorSetTotalStake(), defaultAmount),
        //     "Total stake not correct"
        // );
        //uint256 stValReward = stakeManager.validatorReward(defaultValidatorId);
        uint256 stDelReward = stakeManager.delegatorsReward(defaultValidatorId);
        assertEq(stDelReward, aliceRewards, "alice rewards not matching delegator rewards");

        // console.log("second buyVoucher");
        buyVoucherDefaultTested(defaultAmount * 2, alice);
        assertEq(polToken.balanceOf(alice), firstRewardAlice, "alice didn't get correct calculated first reward");
        assertEq(polToken.balanceOf(alice), aliceRewards, "alice didn't get assumed first reward");

        // this is almost true, some rounding seems to happen
        //assertEq(v1RwewardCalc * 1001, (defaultRewardPerfectCheckpoint(reward1, defaultAmount)) * 1003);
        // console.log("second checkpoint");
        uint256 reward2 = progressCheckpointWithRewardsDefault();
        // Total reward should be the same each checkpoint
        assertEq(reward2, reward, "Total checkpoint reward not the same");

        // It is times 3 (not 4) because the the rewards from the first cycle were payed out during second buyVoucher
        uint256 secondRewardAlice = defaultRewardPerfectCheckpoint(reward, defaultAmount * 3, defaultAmount * 3);

        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 3, "alice has wrong second dPOL balance");
        assertEq(polToken.balanceOf(alice), firstRewardAlice, "alice POL balance changed after checkpoint");

        // TODO initial reward per share calculations in VS missing in calc
        assertApproxEqAbs(
            secondRewardAlice,
            defaultValidator.getLiquidRewards(alice),
            1,
            "alice liquid rewards don't match after second checkpoint"
        );

        // console.log("third buyVoucher");
        buyVoucherDefaultTested(defaultAmount * 3, alice);

        // Same as above, initial reward per share calcs missing
        assertApproxEqAbs(
            polToken.balanceOf(alice),
            firstRewardAlice + secondRewardAlice,
            1,
            "alice has wrong POL balance after second buyVoucher"
        );

        assertEq(
            defaultValidator.balanceOf(alice), defaultAmount * 6, "alice has wrong dPOL balance after third buyVoucher"
        );
        assertEq(defaultValidator.getLiquidRewards(alice), 0, "alice has non 0 rewards after third buyVoucher");

        // console.log("third checkpoint");
        progressCheckpointWithRewardsDefault();
        uint256 thirdRewardAlice = defaultRewardPerfectCheckpoint(reward, defaultAmount * 6, defaultAmount * 6);

        // TODO initial reward per share calculations in VS missing in calc
        assertApproxEqAbs(
            defaultRewardPerfectCheckpoint(reward, defaultAmount * 6, defaultAmount * 6),
            defaultValidator.getLiquidRewards(alice),
            1,
            "alice liquid rewards don't match after third checkpoint"
        );
        // console.log("withdraw rewards");

        withdrawRewardsDefaultTested(alice, defaultValidator.getLiquidRewards(alice));
        assertEq(defaultValidator.balanceOf(alice), defaultAmount * 6, "alice has wrong dPOL balance after withdraw");

        // 6 were just withdrawn, 1 is from first cycle, and 3 are from second cycle that were withdrawn during
        assertApproxEqAbs(
            polToken.balanceOf(alice),
            firstRewardAlice + secondRewardAlice + thirdRewardAlice,
            2,
            "alice has wrong POL balance after withdraw rewards"
        );
    }

    function defaultRewardPerfectCheckpoint(
        uint256 _reward,
        uint256 _userDelegation,
        uint256 _totalDelegation
    )
        //uint256 lastRewardPerShare
        public
        view
        returns (uint256 delReward /*, uint256 rewardPerShare*/ )
    {
        uint256 currentTotalStake = stakeManager.currentValidatorSetTotalStake();
        uint256 proposerBonus = (_reward * stakeManager.proposerBonus()) / 100;
        uint256 remainingReward = _reward - proposerBonus;
        uint256 rewardPerStake = (remainingReward * STAKEMANAGER_REWARD_PRECISION) / currentTotalStake;
        uint256 eligbleReward = (rewardPerStake * currentTotalStake) / STAKEMANAGER_REWARD_PRECISION;

        uint256 validatorReward = defaultStakeVS * eligbleReward / currentTotalStake;

        // This is important, as calculating a fair reward per share and then using that to calc both validator and
        // delegator leads to rounding issues
        uint256 delegatorReward = eligbleReward - validatorReward;

        // This has to be a bug, if alice is lone delegator, but doesn't get all rewards(only happens on lower amounts
        // and only from second checkpoint on)
        //assertEq(defaultValidator.getLiquidRewards(alice), stakeManager.delegatorsReward(defaultValidatorId), "What");
        // Missing in this calc are the initialrewardper share calcs in the VS, that's why we get slight errors
        uint256 userReward = ((delegatorReward * _userDelegation) * VALIDATORSHARE_REWARD_PRECISION) / _totalDelegation;
        return userReward / VALIDATORSHARE_REWARD_PRECISION;
    }

    // helpers
    function buyVoucherDefaultTested(uint256 _amount, address _user) public {
        buyVoucherDefaultGenericTested(_amount, _user, false, 0);
    }

    function buyVoucherDefaultMaticTested(uint256 _amount, address _user) public {
        buyVoucherDefaultGenericTested(_amount, _user, true, 0);
    }

    function buyVoucherDefaultPermitTested(uint256 _amount, address _user, uint256 _userPk) public {
        buyVoucherDefaultGenericTested(_amount, _user, false, _userPk);
    }

    // if userPk is 0, then no permit is used and it uses regular approve
    function buyVoucherDefaultGenericTested(uint256 _amount, address _user, bool matic, uint256 _userPk) public {
        uint256 currentStakeManagerStake = stakeManager.currentValidatorSetTotalStake();
        uint256 currentUserShares = defaultValidator.balanceOf(_user);
        uint256 currentActiveAmount = defaultValidator.activeAmount();
        uint256 validatorNonce = stakingInfo.validatorNonce(defaultValidatorId);

        // Ensure allowance is zero
        assertEq(polToken.allowance(_user, address(stakeManager)), 0, "initial user allowance not zero");
        assertEq(maticToken.allowance(_user, address(stakeManager)), 0, "initial user allowance not zero");
        fundAddr(_user, _amount, matic);

        if (_userPk == 0) {
            vm.prank(_user);
            if (matic) {
                maticToken.approve(address(stakeManager), _amount);
            } else {
                polToken.approve(address(stakeManager), _amount);
            }
        }

        // Test buying vouchers
        vm.expectEmit(true, true, false, true, address(defaultValidator));
        emit ValidatorShare.Transfer(address(0), _user, _amount);

        vm.expectEmit(true, true, true, true, address(stakingInfo));
        emit StakingInfo.ShareMinted(defaultValidatorId, _user, _amount, _amount);

        vm.expectEmit(true, false, false, true, address(stakingInfo));
        emit StakingInfo.StakeUpdate(defaultValidatorId, validatorNonce, _amount + currentActiveAmount);

        if (_userPk == 0) {
            vm.prank(_user);
            if (matic) {
                defaultValidator.buyVoucher(_amount, _amount);
            } else {
                defaultValidator.buyVoucherPOL(_amount, _amount);
            }
        } else {
            uint256 deadline = block.timestamp + 10;
            (uint8 v, bytes32 r, bytes32 s) = createPermit(_user, address(stakeManager), _amount, deadline, _userPk);

            vm.prank(_user);
            defaultValidator.buyVoucherWithPermit(_amount, _amount, deadline, v, r, s);
        }

        // Assert: staked amounts updated
        assertEq(currentUserShares + _amount, defaultValidator.balanceOf(_user), "users staked amount not correct");
        assertEq(
            currentStakeManagerStake + _amount,
            stakeManager.currentValidatorSetTotalStake(),
            "total stakemanager stake not correct"
        );
    }

    function sellVoucherDefaultTested(address _user, uint256 _amount, bool _expectReward, bool _newApi) public {
        sellVoucherDefaultGenericTested(_user, _amount, _expectReward, false, _newApi);
    }

    function sellVoucherDefaultMaticTested(address _user, uint256 _amount, bool _expectReward, bool _newApi) public {
        sellVoucherDefaultGenericTested(_user, _amount, _expectReward, true, _newApi);
    }

    function sellVoucherDefaultGenericTested(
        address _user,
        uint256 _amount,
        bool _expectReward,
        bool _matic,
        bool _newAPI
    ) public {
        uint256 currentStakeManagerStake = stakeManager.currentValidatorSetTotalStake();
        uint256 currentUserShares = defaultValidator.balanceOf(_user);
        uint256 polBalanceBefore = polToken.balanceOf(_user);
        uint256 maticBalanceBefore = maticToken.balanceOf(_user);
        uint256 rewards = defaultValidator.getLiquidRewards(_user);
        uint256 userNonce = defaultValidator.unbondNonces(_user) + 1;
        uint256 validatorNonce = stakingInfo.validatorNonce(defaultValidatorId);

        address transferedToken = _matic ? address(maticToken) : address(polToken);

        bool fullyUnstaked = true;
        uint256 expectedStakeUpdate = 0;
        // not fully unstaked through validator unstake
        if (currentStakeManagerStake != 0) {
            fullyUnstaked = false;
            expectedStakeUpdate = currentStakeManagerStake - currentUserShares;
        }

        assertEq(rewards > 0, _expectReward, "user reward expectation not met");
        // Test selling vouchers
        if (rewards > 0) {
            vm.expectEmit(true, true, true, true, transferedToken);
            emit ERC20Permit.Transfer(address(stakeManager), _user, rewards);

            vm.expectEmit(true, true, false, true, address(stakingInfo));
            emit StakingInfo.DelegatorClaimedRewards(defaultValidatorId, _user, rewards);
        }

        vm.expectEmit(true, true, false, true, address(defaultValidator));
        emit ValidatorShare.Transfer(_user, address(0), _amount);

        if (_newAPI) {
            vm.expectEmit(true, true, false, true, address(eventsHub));
            emit EventsHub.ShareBurnedWithId(defaultValidatorId, _user, _amount, _amount, userNonce);
        } else {
            vm.expectEmit(true, true, false, true, address(stakingInfo));
            emit StakingInfo.ShareBurned(defaultValidatorId, _user, _amount, _amount);
        }

        vm.expectEmit(true, true, false, true, address(stakingInfo));
        emit StakingInfo.StakeUpdate(defaultValidatorId, validatorNonce + 1, expectedStakeUpdate);

        vm.prank(_user);
        if (_newAPI && _matic) {
            defaultValidator.sellVoucher_new(_amount, _amount);
        } else if (_newAPI && !_matic) {
            defaultValidator.sellVoucher_newPOL(_amount, _amount);
        } else if (!_newAPI && _matic) {
            defaultValidator.sellVoucher(_amount, _amount);
        } else {
            defaultValidator.sellVoucherPOL(_amount, _amount);
        }

        assertEq(currentUserShares - _amount, defaultValidator.balanceOf(_user), "users shares not properly reduced");
        if (!fullyUnstaked) {
            assertEq(
                currentStakeManagerStake - _amount,
                stakeManager.currentValidatorSetTotalStake(),
                "stakeManager total stake not properly reduced"
            );
        }

        if (_newAPI) {
            (, uint256 unbondWithdrawEpoch) = defaultValidator.unbonds_new(_user, userNonce);
            assertEq(unbondWithdrawEpoch, stakeManager.currentEpoch());
        } else {
            (, uint256 unbondWithdrawEpoch) = defaultValidator.unbonds(_user);
            assertEq(unbondWithdrawEpoch, stakeManager.currentEpoch());
        }

        uint256 currentEpoch = stakeManager.currentEpoch();
        uint256 withdrawEpoch = currentEpoch + stakeManager.withdrawalDelay() + 100;
        vm.prank(address(governance));
        stakeManager.setCurrentEpoch(withdrawEpoch);

        vm.expectEmit(true, true, true, true, transferedToken);
        emit ERC20Permit.Transfer(address(stakeManager), _user, _amount);

        if (_newAPI) {
            vm.expectEmit(true, true, true, true, address(eventsHub));
            emit EventsHub.DelegatorUnstakeWithId(defaultValidatorId, _user, _amount, userNonce);
            vm.prank(_user);
            if (_matic) {
                defaultValidator.unstakeClaimTokens_new(userNonce);
            } else {
                defaultValidator.unstakeClaimTokens_newPOL(userNonce);
            }
        } else {
            vm.expectEmit(true, true, true, true, address(stakingInfo));
            emit StakingInfo.DelegatorUnstaked(defaultValidatorId, _user, _amount);
            vm.prank(_user);
            if (_matic) {
                defaultValidator.unstakeClaimTokens();
            } else {
                defaultValidator.unstakeClaimTokensPOL();
            }
        }
        if (_matic) {
            assertEq(
                maticToken.balanceOf(_user),
                maticBalanceBefore + _amount + rewards,
                "user didn't get correct MATIC back"
            );
            //assertEq(polToken.balanceOf(_user), maticBalanceBefore, "user unexpectedly got POL");
        } else {
            assertEq(
                polToken.balanceOf(_user), polBalanceBefore + _amount + rewards, "user didn't get correct POL back"
            );
            //assertEq(maticToken.balanceOf(_user), maticBalanceBefore, "user unexpectedly got matic");
        }
    }

    function withdrawRewardsDefaultTested(address _user, uint256 _expectReward) public {
        uint256 initialBalance = polToken.balanceOf(_user);
        uint256 reward = defaultValidator.getLiquidRewards(_user);

        assertEq(reward, _expectReward);
        // if expect reward is 0, withdrawRewards should revert
        if (reward > 0) {
            vm.expectEmit(true, true, true, true, address(polToken));
            emit ERC20Permit.Transfer(address(stakeManager), _user, reward);
            vm.expectEmit(true, true, true, true, address(stakingInfo));
            emit StakingInfo.DelegatorClaimedRewards(defaultValidatorId, _user, reward);
            vm.prank(_user);
            defaultValidator.withdrawRewardsPOL();
            uint256 finalBalance = polToken.balanceOf(_user);
            assertEq(finalBalance, initialBalance + reward);
            assertEq(defaultValidator.getLiquidRewards(_user), 0);
        } else {
            vm.expectRevert("Too small rewards amount");
            vm.prank(_user);
            defaultValidator.withdrawRewardsPOL();
        }
    }

    function progressCheckpointWithRewardsDefault() public returns (uint256) {
        Validator[] memory defaultValidatorArray = new Validator[](1);
        defaultValidatorArray[0] = createValidator(defaultValidatorId);
        return progressCheckpointWithRewards(defaultValidatorArray, address(defaultValidator));
    }

    function test_restakeAndStakePOL() public {
        // Setup: Alice stakes initial amount
        buyVoucherDefaultTested(defaultAmount, alice);
        uint256 initialShares = defaultValidator.balanceOf(alice);
        
        // Generate rewards via checkpoint
        uint256 checkpointReward = progressCheckpointWithRewardsDefault();
        uint256 aliceRewards = defaultValidator.getLiquidRewards(alice);
        assertGt(aliceRewards, 0, "Alice should have rewards after checkpoint");
        
        // Prepare additional stake amount
        uint256 additionalStake = defaultAmount * 2;
        fundAddr(alice, additionalStake, false);
        
        vm.prank(alice);
        polToken.approve(address(stakeManager), additionalStake);
        
        // Execute restakeAndStakePOL
        uint256 polBalanceBefore = polToken.balanceOf(alice);
        
        vm.expectEmit(true, true, false, true, address(stakingInfo));
        emit StakingInfo.DelegatorRestaked(defaultValidatorId, alice, additionalStake + aliceRewards + defaultAmount);
        
        vm.prank(alice);
        (uint256 amountRestaked, uint256 liquidReward, uint256 amountDeposited) = 
            defaultValidator.restakeAndStakePOL(additionalStake, additionalStake + aliceRewards);
        
        // Assertions
        assertEq(liquidReward, aliceRewards, "Liquid reward should match expected rewards");
        assertEq(amountDeposited, additionalStake + aliceRewards, "Total deposited should be stake + rewards");
        assertEq(amountRestaked, aliceRewards, "Restaked amount should equal rewards");
        assertEq(defaultValidator.getLiquidRewards(alice), 0, "Alice should have no remaining rewards");
        assertEq(
            defaultValidator.balanceOf(alice), 
            initialShares + amountDeposited, 
            "Alice shares should increase by deposited amount"
        );
        assertEq(
            polToken.balanceOf(alice), 
            polBalanceBefore - additionalStake, 
            "Alice should only spend the additional stake, not rewards"
        );
    }

    function test_restakeAndStakePOL_noRewards() public {
        // Setup: Alice has no existing stake or rewards
        uint256 stakeAmount = defaultAmount * 2;
        fundAddr(alice, stakeAmount, false);
        
        vm.prank(alice);
        polToken.approve(address(stakeManager), stakeAmount);
        
        // Execute restakeAndStakePOL with zero rewards
        vm.prank(alice);
        (uint256 amountRestaked, uint256 liquidReward, uint256 amountDeposited) = 
            defaultValidator.restakeAndStakePOL(stakeAmount, stakeAmount);
        
        // Assertions
        assertEq(liquidReward, 0, "Should have no rewards");
        assertEq(amountRestaked, 0, "Should have no restaked amount");
        assertEq(amountDeposited, stakeAmount, "Deposited should equal stake amount");
        assertEq(defaultValidator.balanceOf(alice), stakeAmount, "Alice should have shares equal to stake");
    }

    function test_restakeAndStakePOL_belowMinAmount() public {
        // Setup: Alice stakes and earns small rewards
        buyVoucherDefaultTested(defaultAmount, alice);
        
        // Try to restake with amount + rewards below minAmount
        uint256 tinyAmount = defaultValidator.minAmount() / 10;
        fundAddr(alice, tinyAmount, false);
        
        vm.prank(alice);
        polToken.approve(address(stakeManager), tinyAmount);
        
        vm.expectRevert("amount plus rewards too small to stake");
        vm.prank(alice);
        defaultValidator.restakeAndStakePOL(tinyAmount, 0);
    }
}
