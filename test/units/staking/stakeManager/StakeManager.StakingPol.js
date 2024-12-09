import { StakingInfo, TestToken, PolygonMigration, ValidatorShare } from '../../../helpers/artifacts.js'

import { checkPoint, assertBigNumberEquality, assertBigNumbergt } from '../../../helpers/utils.js'
import testHelpers from '@openzeppelin/test-helpers'
const expectRevert = testHelpers.expectRevert
const BN = testHelpers.BN
import { wallets, walletAmounts, freshDeploy, approveAndStake } from '../deployment.js'
import { assert, expect } from 'chai'
import * as utils from '../../../helpers/utils.js'

export function doStake(
  wallet,
  { approveAmount, stakeAmount, noMinting = false, acceptDelegation = false, signer } = {}
) {
  return async function () {
    let user = wallet.getAddressString()

    let _approveAmount = approveAmount || walletAmounts[user].amount
    let _stakeAmount = stakeAmount || walletAmounts[user].stakeAmount

    await approveAndStake.call(this, {
      wallet,
      stakeAmount: _stakeAmount,
      approveAmount: _approveAmount,
      acceptDelegation,
      noMinting,
      signer,
      pol: true
    })
  }
}

export function doUnstake(wallet) {
  return async function () {
    let user = wallet.getAddressString()

    const stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))

    const validatorId = await this.stakeManager.getValidatorId(user)
    await stakeManagerUser.unstakePOL(validatorId)
  }
}

export function prepareForTest(dynastyValue, validatorThreshold) {
  return async function () {
    await freshDeploy.call(this)

    await this.governance.update(
      this.stakeManager.address,
      this.stakeManager.interface.encodeFunctionData('updateValidatorThreshold', [validatorThreshold])
    )

    await this.governance.update(
      this.stakeManager.address,
      this.stakeManager.interface.encodeFunctionData('updateDynastyValue', [dynastyValue])
    )
  }
}

describe('stake POL', function () {
  function testStakeRevert(user, userPubkey, amount, stakeAmount, unspecified = false) {
    let stakeManagerUser, polTokenUser

    before('Approve', async function () {
      this.initialBalance = await this.stakeManager.totalStakedFor(user)

      polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(user))
      stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))

      await polTokenUser.approve(this.stakeManager.address, new BN(amount).add(this.defaultHeimdallFee).toString())
    })

    it('must revert', async function () {
      if (unspecified) {
        await expectRevert(
          stakeManagerUser.stakeForPOL(user, stakeAmount, this.defaultHeimdallFee.toString(), false, userPubkey),
          'no more slots'
        )
      } else {
        await expectRevert(
          stakeManagerUser.stakeForPOL(user, stakeAmount, this.defaultHeimdallFee.toString(), false, userPubkey),
          'Invalid signer'
        )
      }
    })

    it('must have unchanged staked balance', async function () {
      const stakedFor = await this.stakeManager.totalStakedFor(user)
      assertBigNumberEquality(stakedFor, this.initialBalance)
    })
  }

  function testStake(user, userPubkey, amount, stakeAmount, validatorId, fee) {
    let stakeManagerUser, polTokenUser
    before('Approve', async function () {
      this.user = user
      this.fee = new BN(fee || this.defaultHeimdallFee)

      polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(user))
      stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))

      await polTokenUser.approve(this.stakeManager.address, new BN(amount).add(this.fee).toString())
    })

    it('must stake', async function () {
      this.receipt = await (
        await stakeManagerUser.stakeForPOL(user, stakeAmount.toString(), this.fee.toString(), false, userPubkey)
      ).wait()
    })

    it('must emit Staked', async function () {
      utils.assertInTransaction(this.receipt, StakingInfo, 'Staked', {
        signerPubkey: userPubkey,
        signer: user,
        amount: stakeAmount
      })
    })

    if (fee) {
      it('must emit TopUpFee', async function () {
        utils.assertInTransaction(this.receipt, StakingInfo, 'TopUpFee', {
          user: user,
          fee: this.fee.toString()
        })
      })
    }

    it(`must have correct staked amount`, async function () {
      const stakedFor = await this.stakeManager.totalStakedFor(user)
      assertBigNumberEquality(stakedFor, stakeAmount)
    })

    it('must have correct total staked balance', async function () {
      const stake = await this.stakeManager.currentValidatorSetTotalStake()
      assertBigNumberEquality(stake, stakeAmount)
    })

    it(`must have validatorId == ${validatorId}`, async function () {
      const _validatorId = await this.stakeManager.getValidatorId(user)
      _validatorId.toString().should.be.equal(validatorId.toString())
    })

    it('must have valid validatorId', async function () {
      const validatorId = await this.stakeManager.getValidatorId(user)
      const value = await this.stakeManager.isValidator(validatorId.toString())
      assert.isTrue(value)
    })

    it('must pay out rewards correctly', async function () {
      const validatorId = await this.stakeManager.getValidatorId(user)
      const reward = await this.stakeManager.validatorReward(validatorId)
      const balanceBefore = await this.polToken.balanceOf(user)
      assertBigNumberEquality(reward, new BN(0))

      await checkPoint(wallets, this.rootChainOwner, this.stakeManager)
      await checkPoint(wallets, this.rootChainOwner, this.stakeManager)
      const newReward = await this.stakeManager.validatorReward(validatorId)
      assertBigNumbergt(newReward, reward)
      await stakeManagerUser.withdrawRewardsPOL(validatorId)
      const balanceAfter = await this.polToken.balanceOf(user)
      assertBigNumberEquality(balanceAfter.sub(balanceBefore), newReward)

      await checkPoint(wallets, this.rootChainOwner, this.stakeManager)
      await checkPoint(wallets, this.rootChainOwner, this.stakeManager)
      const newReward2 = await this.stakeManager.validatorReward(validatorId)
      await stakeManagerUser.withdrawRewardsPOL(validatorId)
      const balanceAfter2 = await this.polToken.balanceOf(user)
      assertBigNumberEquality(balanceAfter2.sub(balanceAfter), newReward2)
      assertBigNumberEquality(newReward2, newReward)
    })
  }

  function testRestake(user, amount, stakeAmount, restakeAmount, totalStaked) {
    let stakeManagerUser, polTokenUser

    before('Approve', async function () {
      this.user = user
      polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(user))
      stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))

      await polTokenUser.approve(this.stakeManager.address, amount.toString())
    })

    it('must restake', async function () {
      const validatorId = await this.stakeManager.getValidatorId(this.user)
      this.receipt = await (await stakeManagerUser.restakePOL(validatorId, restakeAmount, false)).wait()
    })

    it('must emit StakeUpdate', async function () {
      const validatorId = await this.stakeManager.getValidatorId(this.user)
      await utils.assertInTransaction(this.receipt, StakingInfo, 'StakeUpdate', {
        validatorId: validatorId.toString()
      })
    })

    it('must emit Restaked', async function () {
      const validatorId = await this.stakeManager.getValidatorId(this.user)
      await utils.assertInTransaction(this.receipt, StakingInfo, 'Restaked', {
        validatorId,
        amount: stakeAmount.toString(),
        total: totalStaked.toString()
      })
    })

    it(`must have correct total staked amount`, async function () {
      const stakedFor = await this.stakeManager.totalStakedFor(user)
      assertBigNumberEquality(stakedFor, stakeAmount)
    })
  }

  describe('double stake', async function () {
    before('deploy', async function() {
      await freshDeploy.call(this)
    })

    describe('when stakes first time', function () {
      const amounts = walletAmounts[wallets[1].getAddressString()]
      testStake(
        wallets[1].getChecksumAddressString(),
        wallets[1].getPublicKeyString(),
        amounts.amount,
        amounts.stakeAmount,
        1
      )
    })

    describe('when stakes again', function () {
      testStakeRevert(
        wallets[1].getChecksumAddressString(),
        wallets[1].getPublicKeyString(),
        web3.utils.toWei('200'),
        web3.utils.toWei('200')
      )
    })
  })

  describe('stake and restake following by another stake', function () {
    before('deploy', async function() {
      await freshDeploy.call(this)
    })

    const amounts = walletAmounts[wallets[2].getAddressString()]
    before('Stake', doStake(wallets[2]))

    describe('when restakes', function () {
      testRestake(
        wallets[2].getChecksumAddressString(),
        amounts.restakeAmonut,
        amounts.amount,
        amounts.restakeAmonut,
        amounts.amount
      )
    })

    describe('when stakes again', function () {
      testStakeRevert(
        wallets[2].getChecksumAddressString(),
        wallets[2].getPublicKeyString(),
        web3.utils.toWei('250'),
        web3.utils.toWei('150')
      )
    })
  })

  describe('stake beyond validator threshold', async function () {
    before(prepareForTest(2, 1))

    describe('when user stakes', function () {
      const amounts = walletAmounts[wallets[3].getAddressString()]
      testStake(
        wallets[3].getChecksumAddressString(),
        wallets[3].getPublicKeyString(),
        amounts.amount,
        amounts.stakeAmount,
        1
      )
    })

    describe('when other user stakes beyond validator threshold', function () {
      testStakeRevert(
        wallets[4].getChecksumAddressString(),
        wallets[4].getPublicKeyString(),
        web3.utils.toWei('100'),
        web3.utils.toWei('100'),
        true
      )
    })
  })

  describe('consecutive stakes', function () {
    before('deploy', async function() {
      await freshDeploy.call(this)
    })

    it('validatorId must increment 1 by 1', async function () {
      const _wallets = [wallets[1], wallets[2], wallets[3]]
      let expectedValidatorId = 1
      for (const wallet of _wallets) {
        await doStake(wallet, { approveAmount: web3.utils.toWei('100'), stakeAmount: web3.utils.toWei('100') }).call(
          this
        )

        const validatorId = await this.stakeManager.getValidatorId(wallet.getAddressString())
        assertBigNumberEquality(expectedValidatorId, validatorId)
        expectedValidatorId++
      }
    })
  })

  describe('stake with heimdall fee', function () {
    before('deploy', async function() {
      await freshDeploy.call(this)
    })

    testStake(
      wallets[0].getChecksumAddressString(),
      wallets[0].getPublicKeyString(),
      web3.utils.toWei('200'),
      web3.utils.toWei('150'),
      1,
      web3.utils.toWei('50')
    )
  })

  describe('when Alice stakes, change signer and stakes with old signer', function () {
    const AliceWallet = wallets[1]
    const newSigner = wallets[2].getPublicKeyString()

    before('deploy', async function() {
      await freshDeploy.call(this)
    })
    before(doStake(AliceWallet))
    before('Change signer', async function () {
      const signerUpdateLimit = await this.stakeManager.signerUpdateLimit()
      await this.stakeManager.advanceEpoch(signerUpdateLimit)

      this.validatorId = await this.stakeManager.getValidatorId(AliceWallet.getAddressString())

      const stakeManagerAlice = this.stakeManager.connect(
        this.stakeManager.provider.getSigner(AliceWallet.getAddressString())
      )
      await stakeManagerAlice.updateSigner(this.validatorId, newSigner)
    })

    it('reverts', async function () {
      await expectRevert(doStake(wallets[3], { signer: AliceWallet.getPublicKeyString() }).call(this), 'Invalid signer')
    })
  })
})

describe('unstake POL', function () {
  describe('when Alice unstakes and update the signer', function () {
    const AliceWallet = wallets[1]
    const BobWallet = wallets[3]
    const AliceNewWallet = wallets[2]
    let stakeManagerAlice

    before('deploy', async function() {
      await freshDeploy.call(this)
    })
    before(doStake(AliceWallet))
    before(doStake(BobWallet))
    before('Change signer', async function () {
      const signerUpdateLimit = await this.stakeManager.signerUpdateLimit()
      await this.stakeManager.advanceEpoch(signerUpdateLimit)

      this.validatorId = await this.stakeManager.getValidatorId(AliceWallet.getAddressString())

      stakeManagerAlice = this.stakeManager.connect(
        this.stakeManager.provider.getSigner(AliceWallet.getAddressString())
      )
    })

    it('Alice should unstake', async function () {
      this.receipt = await stakeManagerAlice.unstakePOL(this.validatorId)
    })

    it("Signers list should have only Bob's signer", async function () {
      assert((await this.stakeManager.signers(0)) == BobWallet.getChecksumAddressString(), 'no Bob signer!')
      await expect(this.stakeManager.signers(1))
    })

    it('Alice should update signer', async function () {
      await stakeManagerAlice.updateSigner(this.validatorId, AliceNewWallet.getPublicKeyString())
    })

    it("Signers list should haveonly Bob's signer", async function () {
      assert((await this.stakeManager.signers(0)) == BobWallet.getChecksumAddressString(), 'no Bob signer!')
      await expect(this.stakeManager.signers(1))
    })
  })

  describe('when user unstakes right after stake', async function () {
    const user = wallets[2].getChecksumAddressString()
    const amounts = walletAmounts[wallets[2].getAddressString()]
    let stakeManagerUser

    before('Fresh deploy', prepareForTest(2, 3))
    before(doStake(wallets[2]))
    before(async function () {
      this.validatorId = await this.stakeManager.getValidatorId(user)

      const reward = await this.stakeManager.validatorReward(this.validatorId)
      this.reward = reward
      this.afterStakeBalance = await this.polToken.balanceOf(user)

      stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))
    })

    it('must unstake', async function () {
      this.receipt = await (await stakeManagerUser.unstakePOL(this.validatorId)).wait()
    })

    it('must emit UnstakeInit', async function () {
      await utils.assertInTransaction(this.receipt, StakingInfo, 'UnstakeInit', {
        amount: amounts.stakeAmount,
        validatorId: this.validatorId,
        user
      })
    })

    it('must emit ClaimRewards', async function () {
      await utils.assertInTransaction(this.receipt, StakingInfo, 'ClaimRewards', {
        validatorId: this.validatorId,
        amount: '0',
        totalAmount: '0'
      })
    })

    it('must emit Transfer', async function () {
      await utils.assertInTransaction(this.receipt, TestToken, 'Transfer', {
        value: this.reward,
        to: user
      })
    })

    it('must have increased balance by reward', async function () {
      const balance = await this.polToken.balanceOf(user)
      assertBigNumberEquality(balance, this.afterStakeBalance.add(this.reward))
    })
  })

  describe('when user unstakes after 2 epochs', async function () {
    before('Fresh deploy', prepareForTest(2, 3))

    const user = wallets[3].getChecksumAddressString()
    const amounts = walletAmounts[wallets[3].getAddressString()]
    const w = [wallets[2], wallets[3]]
    let stakeManagerUser

    before(doStake(wallets[2]))
    before(doStake(wallets[3], { acceptDelegation: true }))
    before(async function () {
      this.validatorId = await this.stakeManager.getValidatorId(user)

      const polToken4 = this.polToken.connect(this.polToken.provider.getSigner(wallets[4].getAddressString()))
      stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))

      // delegate tokens to validator
      const validatorShareAddr = await this.stakeManager.getValidatorContract(this.validatorId)
      await polToken4.approve(this.stakeManager.address, web3.utils.toWei('100'))
      const validator = await ValidatorShare.attach(validatorShareAddr)
      const validator4 = validator.connect(validator.provider.getSigner(wallets[4].getAddressString()))
      await validator4.buyVoucherPOL(web3.utils.toWei('100'), 0)

      this.afterStakeBalance = await this.polToken.balanceOf(user)
    })

    before(async function () {
      await checkPoint(w, this.rootChainOwner, this.stakeManager)
      await checkPoint(w, this.rootChainOwner, this.stakeManager)

      this.reward = await this.stakeManager.validatorReward(this.validatorId)
      this.delegatorReward = await this.stakeManager.delegatorsReward(this.validatorId)
    })

    it('must unstake', async function () {
      const validatorId = await this.stakeManager.getValidatorId(user)
      this.receipt = await (await stakeManagerUser.unstakePOL(validatorId)).wait()
    })

    it('must emit UnstakeInit', async function () {
      const validatorId = await this.stakeManager.getValidatorId(user)
      await utils.assertInTransaction(this.receipt, StakingInfo, 'UnstakeInit', {
        amount: amounts.amount,
        validatorId,
        user
      })
    })

    it('must emit ClaimRewards', async function () {
      await utils.assertInTransaction(this.receipt, StakingInfo, 'ClaimRewards', {
        validatorId: this.validatorId,
        amount: this.reward,
        totalAmount: this.reward
      })
    })

    it('must emit Transfer', async function () {
      await utils.assertInTransaction(this.receipt, TestToken, 'Transfer', {
        value: this.reward,
        to: user
      })
    })

    it('must have increased balance by reward', async function () {
      const balance = await this.polToken.balanceOf(user)
      assertBigNumberEquality(balance, this.afterStakeBalance.add(this.reward))
    })

    it('should not distribute additional staking or delegation rewards after unstaking', async function () {
      const validatorId = await this.stakeManager.getValidatorId(user)

      let validatorRewardsBefore = await this.stakeManager.validatorReward(validatorId)
      let delegationRewardsBefore = await this.stakeManager.delegatorsReward(validatorId)
      assertBigNumberEquality(delegationRewardsBefore, this.delegatorReward)

      // complete unstake and remove validator
      await checkPoint(w, this.rootChainOwner, this.stakeManager)

      let validatorRewardsAfter = await this.stakeManager.validatorReward(validatorId)
      let delegationRewardsAfter = await this.stakeManager.delegatorsReward(validatorId)

      assertBigNumbergt(validatorRewardsAfter, validatorRewardsBefore)
      assertBigNumbergt(delegationRewardsAfter, delegationRewardsBefore)

      await stakeManagerUser.withdrawRewardsPOL(validatorId)
      const balanceBefore = await this.polToken.balanceOf(user)

      await checkPoint([wallets[2]], this.rootChainOwner, this.stakeManager)

      await stakeManagerUser.withdrawRewardsPOL(validatorId)
      assertBigNumberEquality(await this.polToken.balanceOf(user), balanceBefore)

      assertBigNumberEquality(await this.stakeManager.validatorReward(validatorId), new BN(0))
      assertBigNumberEquality(await this.stakeManager.delegatorsReward(validatorId), delegationRewardsAfter)
    })
  })

  describe('reverts', function () {
    beforeEach('deploy', async function() {
      await freshDeploy.call(this)
    })
    const user = wallets[2].getChecksumAddressString()
    let stakeManagerUser

    beforeEach(doStake(wallets[2]))

    it('when validatorId is invalid', async function () {
      stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))

      await expectRevert.unspecified(stakeManagerUser.unstakePOL('999999'))
    })

    it('when user is not staker', async function () {
      const validatorId = await this.stakeManager.getValidatorId(user)
      const stakeManager3 = this.stakeManager.connect(this.stakeManager.provider.getSigner(3))
      await expectRevert.unspecified(stakeManager3.unstakePOL(validatorId))
    })

    it('when unstakes 2 times', async function () {
      const validatorId = await this.stakeManager.getValidatorId(user)
      await stakeManagerUser.unstakePOL(validatorId)

      await expectRevert.unspecified(stakeManagerUser.unstakePOL(validatorId))
    })
  })
})

describe('unstakeClaim POL', function () {
  describe('when user claims right after stake', function () {
    before('Fresh Deploy', prepareForTest(1, 10))
    before('Stake', doStake(wallets[2]))
    before('Unstake', doUnstake(wallets[2]))

    const user = wallets[2].getAddressString()

    it('must revert', async function () {
      const stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))
      const ValidatorId = await this.stakeManager.getValidatorId(user)
      await expect(stakeManagerUser.unstakeClaimPOL(ValidatorId))
    })
  })

  describe('when user claims after 1 epoch and 1 dynasty passed', function () {
    let dynasties = 1
    const Alice = wallets[2].getChecksumAddressString()
    let stakeManagerAlice

    before('Fresh Deploy', prepareForTest(dynasties, 10))
    before('Alice Stake', doStake(wallets[2]))
    before('Bob Stake', doStake(wallets[3]))
    before('Alice Unstake', doUnstake(wallets[2]))

    before('Checkpoint', async function () {
      this.validatorId = await this.stakeManager.getValidatorId(Alice)
      this.aliceStakeAmount = await this.stakeManager.validatorStake(this.validatorId)
      stakeManagerAlice = this.stakeManager.connect(this.stakeManager.provider.getSigner(Alice))

      await checkPoint([wallets[3], wallets[2]], this.rootChainOwner, this.stakeManager)

      while (dynasties-- > 0) {
        await checkPoint([wallets[3]], this.rootChainOwner, this.stakeManager)
      }
    })

    it('must claim', async function () {
      this.receipt = await (await stakeManagerAlice.unstakeClaimPOL(this.validatorId)).wait()
    })

    it('must emit Unstaked', async function () {
      const stake = await this.stakeManager.currentValidatorSetTotalStake()
      await utils.assertInTransaction(this.receipt, StakingInfo, 'Unstaked', {
        user: Alice,
        validatorId: this.validatorId,
        amount: this.aliceStakeAmount,
        total: stake
      })
    })

    it('must have correct staked balance', async function () {
      const stake = await this.stakeManager.currentValidatorSetTotalStake()
      assertBigNumberEquality(stake, walletAmounts[wallets[3].getAddressString()].stakeAmount)
    })
  })

  describe('when user claims next epoch', function () {
    before('Fresh Deploy', prepareForTest(1, 10))

    before('Alice Stake', doStake(wallets[2]))
    before('Bob Stake', doStake(wallets[3]))

    before('Alice Unstake', doUnstake(wallets[2]))

    let user

    before('Checkpoint', async function () {
      await checkPoint([wallets[3], wallets[2]], this.rootChainOwner, this.stakeManager)
      user = wallets[2].getAddressString()
    })

    it('must revert', async function () {
      const stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))
      const validatorId = await this.stakeManager.getValidatorId(user)
      await expect(stakeManagerUser.unstakeClaimPOL(validatorId))
    })
  })

  describe('when user claims before 1 dynasty passed', function () {
    before('Fresh Deploy', prepareForTest(2, 10))

    before('Alice Stake', doStake(wallets[2]))
    before('Bob Stake', doStake(wallets[3]))

    before('Alice Unstake', doUnstake(wallets[2]))

    let user

    before('Checkpoint', async function () {
      await checkPoint([wallets[3], wallets[2]], this.rootChainOwner, this.stakeManager)
      user = wallets[2].getAddressString()
    })

    it('must revert', async function () {
      const stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))
      const validatorId = await this.stakeManager.getValidatorId(user)
      await expect(stakeManagerUser.unstakeClaimPOL(validatorId))
    })
  })

  describe('when Alice, Bob and Eve stake, but Alice and Bob claim after 1 epoch and 1 dynasty passed', function () {
    before(prepareForTest(1, 10))

    const Alice = wallets[2]
    const Bob = wallets[3]
    const Eve = wallets[4]
    const stakeAmount = web3.utils.toWei('100')

    before('Alice stake', doStake(Alice, { noMinting: true, stakeAmount }))
    before('Bob stake', doStake(Bob, { noMinting: true, stakeAmount }))
    before('Eve stake', doStake(Eve, { noMinting: true, stakeAmount }))

    before('Alice unstake', doUnstake(Alice))
    before('Bob unstake', doUnstake(Bob))

    before('Checkpoint', async function () {
      await checkPoint([Eve, Bob, Alice], this.rootChainOwner, this.stakeManager)
      await checkPoint([Eve], this.rootChainOwner, this.stakeManager)
    })

    describe('when Alice claims', function () {
      const user = Alice.getAddressString()

      it('must claim', async function () {
        const stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))
        this.validatorId = await this.stakeManager.getValidatorId(user)
        this.reward = await this.stakeManager.validatorReward(this.validatorId)
        this.receipt = await (await stakeManagerUser.unstakeClaimPOL(this.validatorId)).wait()
      })

      it('must have correct reward', async function () {
        assertBigNumberEquality(this.reward, web3.utils.toWei('3000'))
      })

      it('must emit ClaimRewards', async function () {
        await utils.assertInTransaction(this.receipt, StakingInfo, 'ClaimRewards', {
          validatorId: this.validatorId,
          amount: web3.utils.toWei('3000'),
          totalAmount: await this.stakeManager.totalRewardsLiquidated()
        })
      })

      it('must have pre-stake + reward - heimdall fee balance', async function () {
        let balance = await this.polToken.balanceOf(user)
        assertBigNumberEquality(
          balance,
          new BN(walletAmounts[user].initialBalance).add(new BN(this.reward.toString())).sub(this.defaultHeimdallFee)
        )
      })
    })

    describe('when Bob claims', function () {
      const user = Bob.getAddressString()

      it('must claim', async function () {
        const stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(user))
        this.validatorId = await this.stakeManager.getValidatorId(user)
        this.reward = await this.stakeManager.validatorReward(this.validatorId)
        this.receipt = await (await stakeManagerUser.unstakeClaimPOL(this.validatorId)).wait()
      })

      it('must have correct reward', async function () {
        assertBigNumberEquality(this.reward, web3.utils.toWei('3000'))
      })

      it('must emit ClaimRewards', async function () {
        await utils.assertInTransaction(this.receipt, StakingInfo, 'ClaimRewards', {
          validatorId: this.validatorId,
          amount: web3.utils.toWei('3000'),
          totalAmount: await this.stakeManager.totalRewardsLiquidated()
        })
      })

      it('must have pre-stake + reward - heimdall fee balance', async function () {
        let balance = await this.polToken.balanceOf(user)
        assertBigNumberEquality(
          balance,
          new BN(walletAmounts[user].initialBalance).add(new BN(this.reward.toString())).sub(this.defaultHeimdallFee)
        )
      })
    })

    describe('afterwards verification', function () {
      it('must have corect number of validators', async function () {
        const validatorCount = await this.stakeManager.currentValidatorSetSize()
        assertBigNumberEquality(validatorCount, '1')
      })

      it('staked balance must have only Eve balance', async function () {
        const stake = await this.stakeManager.currentValidatorSetTotalStake()
        assertBigNumberEquality(stake, stakeAmount)
      })

      it('Eve must have correct rewards', async function () {
        const validatorId = await this.stakeManager.getValidatorId(Eve.getAddressString())
        this.reward = await this.stakeManager.validatorReward(validatorId)
        assertBigNumberEquality(this.reward, web3.utils.toWei('12000'))
      })
    })
  })
})

describe('restake POL', function () {
  const initialStake = web3.utils.toWei('1000')
  const initialStakers = [wallets[0], wallets[1]]

  function doDeploy(acceptDelegation) {
    return async function () {
      await prepareForTest(8, 8).call(this)

      const checkpointReward = new BN(web3.utils.toWei('10000'))

      await this.governance.update(
        this.stakeManager.address,
        this.stakeManager.interface.encodeFunctionData('updateCheckpointReward', [checkpointReward.toString()])
      )

      await this.governance.update(
        this.stakeManager.address,
        this.stakeManager.interface.encodeFunctionData('updateCheckPointBlockInterval', [1])
      )

      const proposerBonus = 10
      await this.governance.update(
        this.stakeManager.address,
        this.stakeManager.interface.encodeFunctionData('updateProposerBonus', [proposerBonus])
      )

      for (const wallet of initialStakers) {
        await approveAndStake.call(this, { wallet, stakeAmount: initialStake, acceptDelegation, pol: true })
      }

      // wait 2 checkpoints for some rewards
      for (let i = 0; i < 2; i++) {
        await checkPoint(initialStakers, this.rootChainOwner, this.stakeManager)
      }
      // without 10% proposer bonus
      this.validatorReward = checkpointReward
        .mul(new BN(100 - proposerBonus))
        .div(new BN(100))
        .mul(new BN(1))
      this.validatorId = '1'
      this.user = initialStakers[0].getAddressString()
      this.amount = web3.utils.toWei('100')

      await this.polToken.mint(this.user, this.amount)
      this.polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(this.user))
      await this.polTokenUser.approve(this.stakeManager.address, this.amount)
    }
  }

  function testRestake(withDelegation, withRewards) {
    before(doDeploy(withDelegation))

    before(async function () {
      this.oldTotalStaked = await this.stakeManager.totalStaked()
      this.validatorOldState = await this.stakeManager.validators(this.validatorId)

      if (!withRewards) {
        this.validatorReward = new BN(0)
        this.oldReward = await this.stakeManager.validatorReward(this.validatorId)
      }
    })

    it('must restake rewards', async function () {
      const stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(this.user))

      this.receipt = await (await stakeManagerUser.restakePOL(this.validatorId, this.amount, withRewards)).wait()
    })

    it('must emit StakeUpdate', async function () {
      await utils.assertInTransaction(this.receipt, StakingInfo, 'StakeUpdate', {
        validatorId: this.validatorId,
        newAmount: this.validatorOldState.amount.add(this.amount.toString()).add(this.validatorReward.toString())
      })
    })

    it('must emit Restaked', async function () {
      await utils.assertInTransaction(this.receipt, StakingInfo, 'Restaked', {
        validatorId: this.validatorId,
        amount: this.validatorOldState.amount.add(this.amount.toString()).add(this.validatorReward.toString()),
        total: this.oldTotalStaked.add(this.amount.toString()).add(this.validatorReward.toString())
      })
    })

    if (withRewards) {
      it('validator rewards must be 0', async function () {
        const reward = await this.stakeManager.validatorReward(this.validatorId)

        assertBigNumberEquality(reward, 0)
      })
    } else {
      it('validator rewards must be untouched', async function () {
        const reward = await this.stakeManager.validatorReward(this.validatorId)

        assertBigNumberEquality(reward, this.oldReward)
      })
    }
  }

  describe('with delegation', function () {
    describe('with rewards', function () {
      testRestake(true, true)
    })

    describe('without rewards', function () {
      testRestake(true, false)
    })
  })

  describe('without delegation', function () {
    describe('with rewards', function () {
      testRestake(false, true)
    })

    describe('without rewards', function () {
      testRestake(false, false)
    })
  })

  describe('reverts', function () {
    before(doDeploy(false))

    before(() => {})

    it('when validatorId is incorrect', async function () {
      const stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(this.user))
      await expect(stakeManagerUser.restakePOL('0', this.amount, false))
    })

    it('when restake after unstake during same epoch', async function () {
      await this.stakeManager.unstakePOL(this.validatorId)
      const stakeManagerUser = this.stakeManager.connect(this.stakeManager.provider.getSigner(this.user))
      await expectRevert(stakeManagerUser.restakePOL(this.validatorId, this.amount, false), 'No restaking')
    })
  })
})
