import {
  TestToken,
  ValidatorShare,
  StakingInfo,
  EventsHub
} from '../../helpers/artifacts.js'
import testHelpers from '@openzeppelin/test-helpers'
import { checkPoint, assertBigNumberEquality, assertInTransaction } from '../../helpers/utils.js'
import { wallets } from './deployment.js'
import { buyVoucherPOL, sellVoucherPOL, sellVoucherNewPOL, doDeployPOL, ValidatorDefaultStake, Dynasty } from './ValidatorShareHelper.js'

const BN = testHelpers.BN
const expectRevert = testHelpers.expectRevert
const toWei = web3.utils.toWei
const ZeroAddr = '0x0000000000000000000000000000000000000000'
const ExchangeRatePrecision = new BN('100000000000000000000000000000')

describe('ValidatorSharePOL', function () {
  const wei100 = toWei('100')

  function deployAliceAndBob() {
    before(doDeployPOL)
    before('Alice & Bob', async function () {
      this.alice = wallets[2].getChecksumAddressString()
      this.bob = wallets[3].getChecksumAddressString()
      this.totalStaked = new BN(0)

      const mintAmount = new BN(toWei('70000')).toString()

      await this.polToken.mint(this.alice, mintAmount)
      const polTokenAlice = this.polToken.connect(this.polToken.provider.getSigner(this.alice))
      await polTokenAlice.approve(this.stakeManager.address, mintAmount)

      await this.polToken.mint(this.bob, mintAmount)
      const polTokenBob = this.polToken.connect(this.polToken.provider.getSigner(this.bob))
      await polTokenBob.approve(this.stakeManager.address, mintAmount)
    })
  }

  describe('buyVoucher', function () {
    function testbuyVoucherPOL({
      voucherValue,
      voucherValueExpected,
      userTotalStaked,
      totalStaked,
      shares,
      reward,
      initialBalance
    }) {
      it('must buy voucher', async function () {
        this.receipt = await (await buyVoucherPOL(this.validatorContract, voucherValue, this.user, shares)).wait()
      })

      shouldBuyShares({
        voucherValueExpected,
        shares,
        totalStaked
      })

      shouldHaveCorrectStakes({
        userTotalStaked,
        totalStaked
      })

      shouldWithdrawReward({
        initialBalance,
        reward,
        validatorId: '8'
      })
    }

    describe('when Alice purchases voucher once', function () {
      deployAliceAndBob()

      before(function () {
        this.user = this.alice
      })

      testbuyVoucherPOL({
        voucherValue: toWei('100'),
        voucherValueExpected: toWei('100'),
        userTotalStaked: toWei('100'),
        totalStaked: toWei('200'),
        shares: toWei('100'),
        reward: '0',
        initialBalance: toWei('70705')
      })
    })

    describe('when Alice purchases voucher with exact minSharesToMint', function () {
      deployAliceAndBob()

      before(function () {
        this.user = this.alice
      })

      testbuyVoucherPOL({
        voucherValue: toWei('100'),
        voucherValueExpected: toWei('100'),
        userTotalStaked: toWei('100'),
        totalStaked: toWei('200'),
        shares: toWei('100'),
        reward: '0',
        initialBalance: toWei('70705')
      })
    })

    describe('when validator turns off delegation', function () {
      deployAliceAndBob()

      before('disable delegation', async function () {
        const stakeManagerValidator = this.stakeManager.connect(
          this.stakeManager.provider.getSigner(this.validatorUser.getChecksumAddressString())
        )
        await stakeManagerValidator.updateValidatorDelegation(false)
      })

      it('reverts', async function () {
        await expectRevert(buyVoucherPOL(this.validatorContract, toWei('150'), this.alice), 'Delegation is disabled')
      })
    })

    describe('when staking manager delegation is disabled', function () {
      deployAliceAndBob()

      before('disable delegation', async function () {
        await this.governance.update(
          this.stakeManager.address,
          this.stakeManager.interface.encodeFunctionData('setDelegationEnabled', [false])
        )
      })

      it('reverts', async function () {
        await expectRevert(
          buyVoucherPOL(this.validatorContract, web3.utils.toWei('150'), this.alice),
          'Delegation is disabled'
        )
      })
    })

    describe('when Alice purchases voucher 3 times in a row, no checkpoints inbetween', function () {
      deployAliceAndBob()

      before(function () {
        this.user = this.alice
      })

      describe('1st purchase', async function () {
        testbuyVoucherPOL({
          voucherValue: toWei('100'),
          voucherValueExpected: toWei('100'),
          userTotalStaked: toWei('100'),
          totalStaked: toWei('200'),
          shares: toWei('100'),
          reward: '0',
          initialBalance: toWei('70705')
        })
      })

      describe('2nd purchase', async function () {
        testbuyVoucherPOL({
          voucherValue: toWei('150'),
          voucherValueExpected: toWei('150'),
          userTotalStaked: toWei('250'),
          totalStaked: toWei('350'),
          shares: toWei('150'),
          reward: '0',
          initialBalance: toWei('70555')
        })
      })

      describe('3rd purchase', async function () {
        testbuyVoucherPOL({
          voucherValue: toWei('250'),
          voucherValueExpected: toWei('250'),
          userTotalStaked: toWei('500'),
          totalStaked: toWei('600'),
          shares: toWei('250'),
          reward: '0',
          initialBalance: toWei('70305')
        })
      })
    })

    describe('when Alice purchases voucher 3 times in a row, 1 checkpoint inbetween', function () {
      function advanceCheckpointAfter() {
        after(async function () {
          await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
        })
      }

      deployAliceAndBob()

      before(function () {
        this.user = this.alice
      })

      describe('1st purchase', async function () {
        advanceCheckpointAfter()

        testbuyVoucherPOL({
          voucherValue: toWei('100'),
          voucherValueExpected: toWei('100'),
          userTotalStaked: toWei('100'),
          totalStaked: toWei('200'),
          shares: toWei('100'),
          reward: '0',
          initialBalance: toWei('70705')
        })
      })

      describe('2nd purchase', async function () {
        advanceCheckpointAfter()

        testbuyVoucherPOL({
          voucherValue: toWei('150'),
          voucherValueExpected: toWei('150'),
          userTotalStaked: toWei('250'),
          totalStaked: toWei('350'),
          shares: toWei('150'),
          reward: toWei('4500'),
          initialBalance: toWei('70555')
        })
      })

      describe('3rd purchase', async function () {
        testbuyVoucherPOL({
          voucherValue: toWei('250'),
          voucherValueExpected: toWei('250'),
          userTotalStaked: toWei('500'),
          totalStaked: toWei('600'),
          shares: toWei('250'),
          reward: '6428571428571428571428',
          initialBalance: toWei('74805')
        })
      })
    })

    describe('when Alice and Bob purchase vouchers, no checkpoints inbetween', function () {
      deployAliceAndBob()

      describe('when Alice stakes 1st time', function () {
        before(function () {
          this.user = this.alice
        })

        testbuyVoucherPOL({
          voucherValue: toWei('100'),
          voucherValueExpected: toWei('100'),
          userTotalStaked: toWei('100'),
          totalStaked: toWei('200'),
          shares: toWei('100'),
          reward: '0',
          initialBalance: toWei('70705')
        })
      })

      describe('when Bob stakes 1st time', function () {
        before(function () {
          this.user = this.bob
        })

        testbuyVoucherPOL({
          voucherValue: toWei('100'),
          voucherValueExpected: toWei('100'),
          userTotalStaked: toWei('100'),
          totalStaked: toWei('300'),
          shares: toWei('100'),
          reward: '0',
          initialBalance: toWei('70750')
        })
      })

      describe('when Alice stakes 2nd time', function () {
        before(function () {
          this.user = this.alice
        })

        testbuyVoucherPOL({
          voucherValue: toWei('200'),
          voucherValueExpected: toWei('200'),
          userTotalStaked: toWei('300'),
          totalStaked: toWei('500'),
          shares: toWei('200'),
          reward: '0',
          initialBalance: toWei('70505')
        })
      })

      describe('when Bob stakes 2nd time', function () {
        before(function () {
          this.user = this.bob
        })

        testbuyVoucherPOL({
          voucherValue: toWei('200'),
          voucherValueExpected: toWei('200'),
          userTotalStaked: toWei('300'),
          totalStaked: toWei('700'),
          shares: toWei('200'),
          reward: '0',
          initialBalance: toWei('70550')
        })
      })
    })

    describe('when Alice and Bob purchase vouchers, 1 checkpoint inbetween', function () {
      function advanceCheckpointAfter() {
        after(async function () {
          await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
        })
      }

      deployAliceAndBob()

      describe('when Alice stakes 1st time', function () {
        advanceCheckpointAfter()
        before(function () {
          this.user = this.alice
        })

        testbuyVoucherPOL({
          voucherValue: toWei('100'),
          voucherValueExpected: toWei('100'),
          userTotalStaked: toWei('100'),
          totalStaked: toWei('200'),
          shares: toWei('100'),
          reward: '0',
          initialBalance: toWei('70705')
        })
      })

      describe('when Bob stakes 1st time', function () {
        advanceCheckpointAfter()
        before(function () {
          this.user = this.bob
        })

        testbuyVoucherPOL({
          voucherValue: toWei('100'),
          voucherValueExpected: toWei('100'),
          userTotalStaked: toWei('100'),
          totalStaked: toWei('300'),
          shares: toWei('100'),
          reward: '0',
          initialBalance: toWei('70750')
        })
      })

      describe('when Alice stakes 2nd time', function () {
        advanceCheckpointAfter()
        before(function () {
          this.user = this.alice
        })

        testbuyVoucherPOL({
          voucherValue: toWei('200'),
          voucherValueExpected: toWei('200'),
          userTotalStaked: toWei('300'),
          totalStaked: toWei('500'),
          shares: toWei('200'),
          reward: toWei('7500'),
          initialBalance: toWei('70505')
        })
      })

      describe('when Bob stakes 2nd time', function () {
        before(function () {
          this.user = this.bob
        })

        testbuyVoucherPOL({
          voucherValue: toWei('200'),
          voucherValueExpected: toWei('200'),
          userTotalStaked: toWei('300'),
          totalStaked: toWei('700'),
          shares: toWei('200'),
          reward: toWei('4800'),
          initialBalance: toWei('70550')
        })
      })
    })

    describe('when locked', function () {
      deployAliceAndBob()

      before(async function () {
        await this.stakeManager.testLockShareContract(this.validatorId, true)
      })

      it('reverts', async function () {
        await expectRevert(buyVoucherPOL(this.validatorContract, toWei('100'), this.alice, toWei('100')), 'locked')
      })
    })

    describe('when validator unstaked', function () {
      deployAliceAndBob()
      before(async function () {
        const stakeManagerValidator = this.stakeManager.connect(
          this.stakeManager.provider.getSigner(this.validatorUser.getChecksumAddressString())
        )
        await stakeManagerValidator.unstake(this.validatorId)
        await this.stakeManager.advanceEpoch(Dynasty)
      })

      it('reverts', async function () {
        await expectRevert(buyVoucherPOL(this.validatorContract, new BN(toWei('100')), this.alice), 'locked')
      })
    })
  })

  describe('exchangeRate', function () {
    describe('when Alice purchases voucher 2 times, 1 epoch between', function () {
      before(doDeployPOL)

      before(async function () {
        this.user = wallets[2].getAddressString()
        this.totalStaked = new BN(0)

        const voucherAmount = new BN(toWei('70000')).toString()
        await this.polToken.mint(this.user, voucherAmount)
        const polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(this.user))
        await polTokenUser.approve(this.stakeManager.address, voucherAmount)
      })

      it('must buy voucher', async function () {
        const voucherValue = toWei('100')
        this.totalStaked = this.totalStaked.add(new BN(voucherValue))

        await buyVoucherPOL(this.validatorContract, voucherValue, this.user)
      })

      it('exchange rate must be correct', async function () {
        assertBigNumberEquality(await this.validatorContract.exchangeRate(), ExchangeRatePrecision)
      })

      it('must buy another voucher 1 epoch later', async function () {
        await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)

        const voucherValue = toWei('5000')
        this.totalStaked = this.totalStaked.add(new BN(voucherValue))
        await buyVoucherPOL(this.validatorContract, voucherValue, this.user)
      })

      it('exchange rate must be correct', async function () {
        assertBigNumberEquality(await this.validatorContract.exchangeRate(), ExchangeRatePrecision)
      })
    })

    describe('when Alice purchases voucher and sells it', function () {
      before(doDeployPOL)
      before(async function () {
        this.user = wallets[2].getAddressString()
        await this.polToken.mint(this.user, toWei('250'))

        this.beforeExchangeRate = await this.validatorContract.exchangeRate()
        const polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(this.user))
        await polTokenUser.approve(this.stakeManager.address, toWei('250'))
      })

      it('must purchase voucher', async function () {
        await buyVoucherPOL(this.validatorContract, toWei('100'), this.user)
      })

      it('must sell voucher', async function () {
        await sellVoucherPOL(this.validatorContract, this.user)
      })

      it('must have initial exchange rate', async function () {
        let afterExchangeRate = await this.validatorContract.exchangeRate()
        assertBigNumberEquality(afterExchangeRate, this.beforeExchangeRate)
      })
    })
  })

  describe('sellVoucher', function () {
    const aliceStake = new BN(toWei('100'))
    const bobStake = new BN(toWei('200'))
    const Alice = wallets[2].getChecksumAddressString()
    const Bob = wallets[1].getChecksumAddressString()

    async function doDeployPOLAndBuyVoucherForAliceAndBob(includeBob = false) {
      await doDeployPOL.call(this)

      const stake = async ({ user, stake }) => {
        await this.polToken.mint(user, stake)
        const polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(user))
        await polTokenUser.approve(this.stakeManager.address, stake)
        await buyVoucherPOL(this.validatorContract, stake, user)
      }

      await stake({ user: Alice, stake: aliceStake.toString() })

      if (includeBob) {
        await stake({ user: Bob, stake: bobStake.toString() })
      }

      for (let i = 0; i < 4; i++) {
        await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
      }
    }

    function testsellVoucherPOLNew({
      returnedStake,
      reward,
      initialBalance,
      validatorId,
      user,
      minClaimAmount,
      userTotalStaked,
      totalStaked,
      shares,
      nonce,
      withdrawalExchangeRate = ExchangeRatePrecision
    }) {
      if (minClaimAmount) {
        it('must sell voucher with slippage', async function () {
          this.receipt = await (await sellVoucherNewPOL(this.validatorContract, user, minClaimAmount)).wait()
        })
      } else {
        it('must sell voucher', async function () {
          this.receipt = await (await sellVoucherNewPOL(this.validatorContract, user)).wait()
        })
      }

      if (nonce) {
        it('must emit ShareBurnedWithId', async function () {
          assertInTransaction(this.receipt, EventsHub, 'ShareBurnedWithId', {
            validatorId: validatorId,
            tokens: shares.toString(),
            amount: returnedStake.toString(),
            user: user,
            nonce
          })
        })
      } else {
        it('must emit ShareBurned', async function () {
          assertInTransaction(this.receipt, StakingInfo, 'ShareBurned', {
            validatorId: validatorId,
            tokens: shares,
            amount: returnedStake,
            user: user
          })
        })
      }

      shouldWithdrawReward({ initialBalance, validatorId, user, reward })

      shouldHaveCorrectStakes({
        userTotalStaked,
        totalStaked,
        user
      })

      it('must have correct withdrawal exchange rate', async function () {
        const rate = await this.validatorContract.withdrawExchangeRate()
        assertBigNumberEquality(rate, withdrawalExchangeRate)
      })
    }

    function testsellVoucherPOL({
      returnedStake,
      reward,
      initialBalance,
      validatorId,
      user,
      minClaimAmount,
      userTotalStaked,
      totalStaked,
      shares,
      withdrawalExchangeRate = ExchangeRatePrecision
    }) {
      if (minClaimAmount) {
        it('must sell voucher with slippage', async function () {
          this.receipt = await (await sellVoucherPOL(this.validatorContract, user, minClaimAmount.toString())).wait()
        })
      } else {
        it('must sell voucher', async function () {
          this.receipt = await (await sellVoucherPOL(this.validatorContract, user)).wait()
        })
      }

      it('must emit ShareBurned', async function () {
        assertInTransaction(this.receipt, StakingInfo, 'ShareBurned', {
          validatorId: validatorId,
          tokens: shares.toString(),
          amount: returnedStake.toString(),
          user: user
        })
      })

      shouldWithdrawReward({ initialBalance, validatorId, user, reward })

      shouldHaveCorrectStakes({
        userTotalStaked,
        totalStaked,
        user
      })

      it('must have correct withdrawal exchange rate', async function () {
        const rate = await this.validatorContract.withdrawExchangeRate()
        assertBigNumberEquality(rate, withdrawalExchangeRate)
      })
    }

    describe('when Alice sells voucher', function () {
      before(doDeployPOLAndBuyVoucherForAliceAndBob)

      testsellVoucherPOL({
        returnedStake: aliceStake,
        reward: toWei('18000'),
        initialBalance: toWei('805'),
        validatorId: '8',
        user: Alice,
        userTotalStaked: toWei('0'),
        totalStaked: ValidatorDefaultStake,
        shares: aliceStake
      })
    })

    describe('when delegation is disabled after voucher was purchased by Alice', function () {
      before(doDeployPOLAndBuyVoucherForAliceAndBob)
      before('disable delegation', async function () {
        await this.governance.update(
          this.stakeManager.address,
          this.stakeManager.interface.encodeFunctionData('setDelegationEnabled', [false])
        )
      })

      testsellVoucherPOL({
        returnedStake: aliceStake,
        reward: toWei('18000'),
        initialBalance: toWei('805'),
        validatorId: '8',
        user: Alice,
        userTotalStaked: toWei('0'),
        totalStaked: ValidatorDefaultStake,
        shares: aliceStake
      })
    })

    describe('when Alice sells with claimAmount greater than expected', function () {
      before(doDeployPOLAndBuyVoucherForAliceAndBob)

      it('reverts', async function () {
        const maxShares = await this.validatorContract.balanceOf(Alice)
        const validatorAlice = this.validatorContract.connect(this.validatorContract.provider.getSigner(Alice))
        await expectRevert(validatorAlice.sellVoucherPOL(toWei('100.00001'), maxShares), 'Too much requested')
      })
    })

    describe('when locked', function () {
      before(doDeployPOLAndBuyVoucherForAliceAndBob)

      before(async function () {
        await this.stakeManager.testLockShareContract(this.validatorId, true)
      })

      testsellVoucherPOL({
        returnedStake: aliceStake,
        reward: toWei('18000'),
        initialBalance: toWei('805'),
        validatorId: '8',
        user: Alice,
        userTotalStaked: toWei('0'),
        totalStaked: ValidatorDefaultStake,
        shares: aliceStake
      })
    })

    describe('when validator unstaked', function () {
      before(doDeployPOLAndBuyVoucherForAliceAndBob)
      before(async function () {
        const stakeManagerValidator = this.stakeManager.connect(
          this.stakeManager.provider.getSigner(this.validatorUser.getChecksumAddressString())
        )
        await stakeManagerValidator.unstake(this.validatorId)
        await this.stakeManager.advanceEpoch(Dynasty)
      })

      testsellVoucherPOL({
        returnedStake: aliceStake,
        reward: toWei('18000'),
        initialBalance: toWei('805'),
        validatorId: '8',
        user: Alice,
        userTotalStaked: toWei('0'),
        totalStaked: 0,
        shares: aliceStake
      })
    })

    describe('when Alice and Bob sell within withdrawal delay', function () {
      before(async function () {
        await doDeployPOLAndBuyVoucherForAliceAndBob.call(this, true)
      })

      describe('when Alice sells', function () {
        testsellVoucherPOL({
          returnedStake: aliceStake,
          reward: toWei('9000'),
          initialBalance: toWei('805'),
          validatorId: '8',
          user: Alice,
          userTotalStaked: toWei('0'),
          shares: aliceStake,
          totalStaked: new BN(bobStake).add(ValidatorDefaultStake)
        })
      })

      describe('when Bob sells', function () {
        testsellVoucherPOL({
          returnedStake: bobStake,
          reward: toWei('18000'),
          initialBalance: toWei('1200'),
          validatorId: '8',
          user: Bob,
          userTotalStaked: toWei('0'),
          shares: bobStake,
          totalStaked: ValidatorDefaultStake
        })
      })
    })

    describe('partial sell', function () {
      describe('new API', function () {
        describe('when Alice sells', function () {
          before(doDeployPOLAndBuyVoucherForAliceAndBob)

          const halfStake = aliceStake.div(new BN('2'))

          describe('when Alice sells 50%', function () {
            testsellVoucherPOLNew({
              shares: new BN(toWei('50')),
              minClaimAmount: halfStake,
              returnedStake: halfStake,
              reward: toWei('18000'),
              initialBalance: toWei('805'),
              validatorId: '8',
              user: Alice,
              userTotalStaked: halfStake,
              nonce: '1',
              totalStaked: halfStake.add(ValidatorDefaultStake)
            })
          })

          describe('when Alice sells 50%, after 1 epoch, within withdrawal delay', function () {
            before(async function () {
              await this.stakeManager.advanceEpoch(1)
            })

            testsellVoucherPOLNew({
              shares: new BN(toWei('50')),
              minClaimAmount: halfStake,
              returnedStake: halfStake,
              reward: '0',
              initialBalance: new BN(toWei('18805')),
              validatorId: '8',
              user: Alice,
              userTotalStaked: '0',
              nonce: '2',
              totalStaked: ValidatorDefaultStake
            })
          })
        })
      })

      describe('old API', function () {
        describe('when Alice sells', function () {
          before(doDeployPOLAndBuyVoucherForAliceAndBob)

          const halfStake = aliceStake.div(new BN('2'))

          describe('when Alice sells 50%', function () {
            testsellVoucherPOL({
              shares: new BN(toWei('50')).toString(),
              minClaimAmount: halfStake,
              returnedStake: halfStake,
              reward: toWei('18000'),
              initialBalance: toWei('805'),
              validatorId: '8',
              user: Alice,
              userTotalStaked: halfStake,
              totalStaked: halfStake.add(ValidatorDefaultStake)
            })
          })

          describe('when Alice sells 50%, after 1 epoch, within withdrawal delay', function () {
            before(async function () {
              await this.stakeManager.advanceEpoch(1)
            })

            testsellVoucherPOL({
              shares: new BN(toWei('50')),
              minClaimAmount: halfStake,
              returnedStake: halfStake,
              reward: '0',
              initialBalance: new BN(toWei('18805')),
              validatorId: '8',
              user: Alice,
              userTotalStaked: '0',
              totalStaked: ValidatorDefaultStake
            })

            it('unbond epoch must be set to current epoch', async function () {
              const unbond = await this.validatorContract.unbonds(Alice)
              assertBigNumberEquality(unbond.withdrawEpoch, await this.stakeManager.currentEpoch())
            })
          })
        })
      })
    })
  })

  describe('withdrawRewards', function () {
    const Alice = wallets[5].getChecksumAddressString()
    const Bob = wallets[6].getChecksumAddressString()
    const Eve = wallets[7].getChecksumAddressString()
    const Carol = wallets[8].getChecksumAddressString()

    let totalDelegatorRewardsReceived
    let totalStaked
    let totalInitialBalance
    let delegators = []

    function testWithdraw({ label, user, expectedReward, initialBalance }) {
      describe(`when ${label} withdraws`, function () {
        if (expectedReward.toString() === '0') {
          it('reverts', async function () {
            const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(user))
            await expectRevert(validatorUser.withdrawRewardsPOL(), 'Too small rewards amount')
          })
        } else {
          it('must withdraw rewards', async function () {
            const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(user))
            this.receipt = await (await validatorUser.withdrawRewardsPOL()).wait()
          })

          shouldWithdrawReward({
            reward: expectedReward,
            user: user,
            validatorId: '8',
            initialBalance: initialBalance
          })
        }
      })
    }

    function testStake({ user, amount, label, initialBalance = new BN(0) }) {
      describe(`${label} buyVoucher for ${amount.toString()} wei`, function () {
        it(`must purchase voucher`, async function () {
          totalInitialBalance = totalInitialBalance.add(initialBalance)
          totalStaked = totalStaked.add(new BN(amount))

          await this.polToken.mint(user, initialBalance.add(amount).toString())
          const polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(user))
          await polTokenUser.approve(this.stakeManager.address, amount.toString())
          await buyVoucherPOL(this.validatorContract, amount.toString(), user)
          delegators[user] = delegators[user] || {
            rewards: new BN(0)
          }
        })

        it('must have correct initalRewardPerShare', async function () {
          const currentRewardPerShare = await this.validatorContract.getRewardPerShare()
          const userRewardPerShare = await this.validatorContract.initalRewardPerShare(user)
          assertBigNumberEquality(currentRewardPerShare, userRewardPerShare)
        })
      })
    }

    function testCheckpoint(checkpoints) {
      describe('checkpoints', function () {
        it(`${checkpoints} more checkpoint(s)`, async function () {
          let c = 0
          while (c++ < checkpoints) {
            await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
          }

          totalDelegatorRewardsReceived = new ethers.BigNumber.from(0)
          for (const user in delegators) {
            const rewards = await this.validatorContract.getLiquidRewards(user)
            totalDelegatorRewardsReceived = totalDelegatorRewardsReceived.add(rewards)
          }
        })
      })
    }

    function testLiquidRewards({ user, label, expectedReward }) {
      describe(`${label} liquid rewards`, function () {
        it(`${expectedReward.toString()}`, async function () {
          const rewards = await this.validatorContract.getLiquidRewards(user)
          assertBigNumberEquality(rewards, expectedReward)
        })
      })
    }

    function testAllRewardsReceived({ validatorReward, totalExpectedRewards }) {
      async function getValidatorReward() {
        return this.stakeManager.validatorReward(this.validatorId)
      }

      describe('total rewards', function () {
        it(`validator rewards == ${validatorReward.toString()}`, async function () {
          assertBigNumberEquality(await getValidatorReward.call(this), validatorReward)
        })

        it(`all expected rewards should be ${totalExpectedRewards.toString()}`, async function () {
          const validatorRewards = await getValidatorReward.call(this)
          assertBigNumberEquality(validatorRewards.add(totalDelegatorRewardsReceived.toString()), totalExpectedRewards)
        })

        it(`total received rewards must be correct`, async function () {
          const validatorRewards = await getValidatorReward.call(this)
          const totalReceived = validatorRewards.add(totalDelegatorRewardsReceived.toString())

          const stakeManagerValidator = this.stakeManager.connect(
            this.stakeManager.provider.getSigner(this.validatorUser.getChecksumAddressString())
          )
          await stakeManagerValidator.withdrawRewardsPOL(this.validatorId)

          const tokensLeft = await this.polToken.balanceOf(this.stakeManager.address)

          assertBigNumberEquality(
            this.initialPolTokenBalance
              .add(totalStaked.toString())
              .sub(totalReceived),
            tokensLeft
          )
        })
      })
    }

    function runWithdrawRewardsTest(timeline) {
      before(doDeployPOL)
      before(async function () {
        delegators = {}
        totalInitialBalance = new BN(0)
        totalStaked = new BN(0)
        totalDelegatorRewardsReceived = new BN(0)
        this.initialPolTokenBalance = await this.polToken.balanceOf(this.stakeManager.address)
      })

      for (const step of timeline) {
        if (step.stake) {
          testStake(step.stake)
        } else if (step.checkpoints) {
          testCheckpoint(step.checkpoints)
        } else if (step.withdraw) {
          testWithdraw(step.withdraw)
        } else if (step.liquidRewards) {
          testLiquidRewards(step.liquidRewards)
        } else if (step.allRewards) {
          testAllRewardsReceived(step.allRewards)
        }
      }
    }

    describe('when Alice purchases voucher after checkpoint', function () {
      runWithdrawRewardsTest([
        { checkpoints: 1 },
        { stake: { user: Alice, label: 'Alice', amount: new BN(wei100) } },
        { withdraw: { user: Alice, label: 'Alice', expectedReward: '0' } },
        { allRewards: { validatorReward: toWei('9000'), totalExpectedRewards: toWei('9000') } }
      ])
    })

    describe('when 1 checkpoint passed', function () {
      runWithdrawRewardsTest([
        { stake: { user: Alice, label: 'Alice', amount: new BN(wei100) } },
        { checkpoints: 1 },
        { withdraw: { user: Alice, label: 'Alice', expectedReward: toWei('4500') } },
        { allRewards: { validatorReward: toWei('4500'), totalExpectedRewards: toWei('9000') } }
      ])
    })

    describe('Alice, Bob, Eve and Carol stake #1', function () {
      runWithdrawRewardsTest([
        { stake: { user: Alice, label: 'Alice', amount: new BN(toWei('100')) } },
        { checkpoints: 1 },
        { liquidRewards: { user: Alice, label: 'Alice', expectedReward: toWei('4500') } },
        { stake: { user: Bob, label: 'Bob', amount: new BN(toWei('500')) } },
        { checkpoints: 1 },
        { liquidRewards: { user: Alice, label: 'Alice', expectedReward: '5785714285714285714285' } },
        { liquidRewards: { user: Bob, label: 'Bob', expectedReward: '6428571428571428571428' } },
        { stake: { user: Carol, label: 'Carol', amount: new BN(toWei('500')) } },
        { checkpoints: 1 },
        { liquidRewards: { user: Alice, label: 'Alice', expectedReward: '6535714285714285714285' } },
        { liquidRewards: { user: Bob, label: 'Bob', expectedReward: '10178571428571428571428' } },
        { liquidRewards: { user: Carol, label: 'Carol', expectedReward: '3750000000000000000000' } },
        { stake: { user: Eve, label: 'Eve', amount: new BN(toWei('500')), initialBalance: new BN(1) } },
        { checkpoints: 1 },
        { withdraw: { user: Alice, label: 'Alice', expectedReward: '7065126050420168067226' } },
        { withdraw: { user: Bob, label: 'Bob', expectedReward: '12825630252100840336133' } },
        { withdraw: { user: Carol, label: 'Carol', expectedReward: '6397058823529411764705' } },
        { withdraw: { user: Eve, label: 'Eve', expectedReward: '2647058823529411764705', initialBalance: new BN(1) } },
        { allRewards: { validatorReward: '7065126050420168067226', totalExpectedRewards: '35999999999999999999995' } }
      ])
    })

    describe('when not enough rewards', function () {
      before(doDeployPOL)

      it('reverts', async function () {
        const validatorContractAlice = this.validatorContract.connect(this.validatorContract.provider.getSigner(Alice))
        await expectRevert(validatorContractAlice.withdrawRewardsPOL(), 'Too small rewards amount')
      })
    })

    describe('when Alice withdraws 2 times in a row', async function () {
      runWithdrawRewardsTest([
        { stake: { user: Alice, label: 'Alice', amount: new BN(toWei('100')) } },
        { checkpoints: 1 },
        { withdraw: { user: Alice, label: 'Alice', expectedReward: toWei('4500') } },
        { withdraw: { user: Alice, label: 'Alice', expectedReward: '0' } }
      ])
    })

    describe('when locked', function () {
      before(doDeployPOL)

      before(async function () {
        const amount = toWei('100')
        await this.polToken.mint(Alice, amount)
        const polTokenAlice = this.polToken.connect(this.polToken.provider.getSigner(Alice))
        await polTokenAlice.approve(this.stakeManager.address, amount)
        await buyVoucherPOL(this.validatorContract, amount, Alice)
        await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
        await this.stakeManager.testLockShareContract(this.validatorId, true)
      })

      it('must withdraw rewards', async function () {
        const validatorContractAlice = this.validatorContract.connect(this.validatorContract.provider.getSigner(Alice))
        this.receipt = await (await validatorContractAlice.withdrawRewardsPOL()).wait()
      })

      shouldWithdrawReward({
        initialBalance: new BN('0'),
        validatorId: '8',
        user: Alice,
        reward: toWei('4500')
      })
    })

    describe('when validator unstaked', function () {
      before(doDeployPOL)
      before(async function () {
        const amount = toWei('100')
        await this.polToken.mint(Alice, amount)
        const polTokenAlice = this.polToken.connect(this.polToken.provider.getSigner(Alice))
        await polTokenAlice.approve(this.stakeManager.address, amount)
        await buyVoucherPOL(this.validatorContract, amount, Alice)
        await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
        const stakeManagerAlice = this.stakeManager.connect(
          this.stakeManager.provider.getSigner(this.validatorUser.getChecksumAddressString())
        )
        await stakeManagerAlice.unstake(this.validatorId)
        await this.stakeManager.advanceEpoch(Dynasty)
      })

      it('must withdraw rewards', async function () {
        const validatorContractAlice = this.validatorContract.connect(this.validatorContract.provider.getSigner(Alice))
        this.receipt = await (await validatorContractAlice.withdrawRewardsPOL()).wait()
      })

      shouldWithdrawReward({
        initialBalance: new BN('0'),
        validatorId: '8',
        user: Alice,
        reward: toWei('4500')
      })
    })
  })

  describe('restake', function () {
    function prepareForTest({ skipCheckpoint } = {}) {
      before(doDeployPOL)
      before(async function () {
        this.user = wallets[2].getChecksumAddressString()

        await this.polToken.mint(this.user, this.stakeAmount.toString())
        const polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(this.user))
        await polTokenUser.approve(this.stakeManager.address, this.stakeAmount.toString())

        await buyVoucherPOL(this.validatorContract, this.stakeAmount.toString(), this.user)
        this.shares = await this.validatorContract.balanceOf(this.user)

        if (!skipCheckpoint) {
          await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
        }
      })
    }

    describe('when Alice restakes', function () {
      const voucherValueExpected = new BN(toWei('4500'))
      const reward = new BN(toWei('4500'))
      const userTotalStaked = new BN(toWei('4600'))
      const shares = new BN(toWei('4500'))
      const totalStaked = new BN(toWei('4700'))
      const initialBalance = new BN(toWei('100'))

      prepareForTest()

      it('must restake', async function () {
        const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
        this.receipt = await (await validatorUser.restakePOL()).wait()
      })

      shouldBuyShares({
        voucherValueExpected,
        userTotalStaked,
        totalStaked,
        shares,
        reward,
        initialBalance
      })

      shouldWithdrawReward({
        reward: '0', // we need only partial test here, reward is not really claimed
        initialBalance,
        checkBalance: false,
        validatorId: '8'
      })

      it('must emit DelegatorRestaked', async function () {
        assertInTransaction(this.receipt, StakingInfo, 'DelegatorRestaked', {
          validatorId: this.validatorId,
          totalStaked: userTotalStaked.toString()
        })
      })
    })

    describe('when no liquid rewards', function () {
      prepareForTest({ skipCheckpoint: true })

      it('reverts', async function () {
        const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
        await expectRevert(validatorUser.restakePOL(), 'Too small rewards to restake')
      })
    })

    describe('when staking manager delegation is disabled', function () {
      prepareForTest()

      before('disable delegation', async function () {
        await this.governance.update(
          this.stakeManager.address,
          this.stakeManager.interface.encodeFunctionData('setDelegationEnabled', [false])
        )
      })

      it('reverts', async function () {
        const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
        await expectRevert(validatorUser.restakePOL(), 'Delegation is disabled')
      })
    })

    describe('when validator unstaked', function () {
      prepareForTest()
      before(async function () {
        const stakeManagerValidator = this.stakeManager.connect(
          this.stakeManager.provider.getSigner(this.validatorUser.getChecksumAddressString())
        )
        await stakeManagerValidator.unstake(this.validatorId)
      })

      it('reverts', async function () {
        const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
        await expectRevert(validatorUser.restakePOL(), 'locked')
      })
    })

    describe('when locked', function () {
      prepareForTest()

      before(async function () {
        await this.stakeManager.testLockShareContract(this.validatorId, true)
      })

      it('reverts', async function () {
        const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
        await expectRevert(validatorUser.restakePOL(), 'locked')
      })
    })
  })

  describe('unstakeClaimTokens', function () {
    function prepareForTest({ skipSell, skipBuy } = {}) {
      before(doDeployPOL)
      before(async function () {
        this.user = wallets[2].getChecksumAddressString()

        await this.polToken.mint(this.user, this.stakeAmount.toString())
        const polTokenUser = this.polToken.connect(this.polToken.provider.getSigner(this.user))
        await polTokenUser.approve(this.stakeManager.address, this.stakeAmount.toString())

        this.totalStaked = this.stakeAmount
      })

      if (!skipBuy) {
        before('buy', async function () {
          await buyVoucherPOL(this.validatorContract, this.stakeAmount.toString(), this.user)
        })
      }

      if (!skipSell) {
        before('sell', async function () {
          await sellVoucherPOL(this.validatorContract, this.user)
        })
      }
    }

    describe('when Alice unstakes right after voucher sell', function () {
      prepareForTest()

      before('checkpoint', async function () {
        let currentEpoch = await this.stakeManager.currentEpoch()
        let exitEpoch = currentEpoch.add(await this.stakeManager.WITHDRAWAL_DELAY())

        for (let i = currentEpoch; i <= exitEpoch; i++) {
          await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
        }
      })

      it('must unstake', async function () {
        const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
        this.receipt = await (await validatorUser.unstakeClaimTokensPOL()).wait()
      })

      it('must emit DelegatorUnstaked', async function () {
        assertInTransaction(this.receipt, StakingInfo, 'DelegatorUnstaked', {
          validatorId: this.validatorId,
          user: this.user,
          amount: this.stakeAmount.toString()
        })
      })

      shouldHaveCorrectStakes({
        userTotalStaked: '0',
        totalStaked: toWei('100')
      })
    })

    describe('when Alice claims too early', function () {
      prepareForTest()

      it('reverts', async function () {
        const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
        await expectRevert(
          validatorUser.unstakeClaimTokensPOL(),
          'Incomplete withdrawal period'
        )
      })
    })

    describe('when Alice claims with 0 shares', function () {
      prepareForTest({ skipSell: true })

      it('reverts', async function () {
        const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
        await expectRevert(
          validatorUser.unstakeClaimTokensPOL(),
          'Incomplete withdrawal period'
        )
      })
    })

    describe("when Alice didn't buy voucher", function () {
      prepareForTest({ skipSell: true, skipBuy: true })

      it('reverts', async function () {
        const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
        await expectRevert(
          validatorUser.unstakeClaimTokensPOL(),
          'Incomplete withdrawal period'
        )
      })
    })

    describe('new API', function () {
      describe('when Alice claims 2 seperate unstakes (1 epoch between unstakes)', function () {
        prepareForTest({ skipSell: true })

        before('sell shares twice', async function () {
          this.claimAmount = this.stakeAmount.div(new BN('2'))

          await sellVoucherNewPOL(this.validatorContract, this.user, this.claimAmount)
          await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
          await sellVoucherNewPOL(this.validatorContract, this.user, this.claimAmount)
        })

        before('checkpoint', async function () {
          let currentEpoch = await this.stakeManager.currentEpoch()
          let exitEpoch = currentEpoch.add(await this.stakeManager.WITHDRAWAL_DELAY())

          for (let i = currentEpoch; i <= exitEpoch; i++) {
            await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
          }
        })

        it('must claim 1st unstake', async function () {
          const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
          this.receipt = await (await validatorUser.unstakeClaimTokens_newPOL('1')).wait()
        })

        it('must emit DelegatorUnstakeWithId', async function () {
          assertInTransaction(this.receipt, EventsHub, 'DelegatorUnstakeWithId', {
            validatorId: this.validatorId,
            user: this.user,
            amount: this.claimAmount.toString(),
            nonce: '1'
          })
        })

        it('must claim 2nd unstake', async function () {
          const validatorUser = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.user))
          this.receipt = await (await validatorUser.unstakeClaimTokens_newPOL('2')).wait()
        })

        it('must emit DelegatorUnstakeWithId', async function () {
          assertInTransaction(this.receipt, EventsHub, 'DelegatorUnstakeWithId', {
            validatorId: this.validatorId,
            user: this.user,
            amount: this.claimAmount.toString(),
            nonce: '2'
          })
        })

        it('must have 0 shares', async function () {
          assertBigNumberEquality(await this.validatorContract.balanceOf(this.user), '0')
        })
      })
    })
  })

  describe('getLiquidRewards', function () {
    describe('when Alice and Bob buy vouchers (1 checkpoint in-between) and Alice withdraw the rewards', function () {
      deployAliceAndBob()
      before(async function () {
        await buyVoucherPOL(this.validatorContract, toWei('100'), this.alice)
        await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
        await buyVoucherPOL(this.validatorContract, toWei('4600'), this.bob)
        const validatorAlice = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.alice))
        await validatorAlice.withdrawRewardsPOL()
      })

      it('Bob must call getLiquidRewards', async function () {
        await this.validatorContract.getLiquidRewards(this.bob)
      })
    })
  })

  describe('transfer', function () {
    describe('when Alice has no rewards', function () {
      deployAliceAndBob()

      let initialSharesBalance

      before('Alice purchases voucher', async function () {
        await buyVoucherPOL(this.validatorContract, toWei('100'), this.alice)
        initialSharesBalance = await this.validatorContract.balanceOf(this.alice)
      })

      it('must Transfer shares', async function () {
        const validatorAlice = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.alice))
        await validatorAlice.transferPOL(this.bob, initialSharesBalance)
      })

      it('Alice must have 0 shares', async function () {
        assertBigNumberEquality(await this.validatorContract.balanceOf(this.alice), '0')
      })

      it("Bob must have Alice's shares", async function () {
        assertBigNumberEquality(await this.validatorContract.balanceOf(this.bob), initialSharesBalance)
      })
    })

    describe('when Alice and Bob have unclaimed rewards', function () {
      deployAliceAndBob()

      let initialAliceSharesBalance
      let initialBobSharesBalance

      let initialAlicePolBalance
      let initialBobPolBalance

      let initialAliceStakeBalance
      let initialBobStakeBalance

      before('Alice and Bob purchases voucher, checkpoint is commited', async function () {
        await buyVoucherPOL(this.validatorContract, ValidatorDefaultStake, this.alice)
        await buyVoucherPOL(this.validatorContract, ValidatorDefaultStake, this.bob)

        initialAliceSharesBalance = await this.validatorContract.balanceOf(this.alice)
        initialBobSharesBalance = await this.validatorContract.balanceOf(this.bob)

        initialAlicePolBalance = await this.polToken.balanceOf(this.alice)
        initialBobPolBalance = await this.polToken.balanceOf(this.bob)

        initialAliceStakeBalance = await this.stakeToken.balanceOf(this.alice)
        initialBobStakeBalance = await this.stakeToken.balanceOf(this.bob)

        await checkPoint([this.validatorUser], this.rootChainOwner, this.stakeManager)
      })

      it('must Transfer shares', async function () {
        const validatorAlice = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.alice))
        this.receipt = await (await validatorAlice.transferPOL(this.bob, initialAliceSharesBalance)).wait()
      })

      it('must emit DelegatorClaimedRewards for Alice', async function () {
        assertInTransaction(this.receipt, StakingInfo, 'DelegatorClaimedRewards', {
          validatorId: this.validatorId,
          user: this.alice,
          rewards: toWei('3000')
        })
      })

      it('Alice must claim 3000 pol', async function () {
        assertBigNumberEquality(
          await this.polToken.balanceOf(this.alice),
          initialAlicePolBalance.add(toWei('3000'))
        )
      })

      it('Alice must have unchanged matic', async function () {
        assertBigNumberEquality(
          await this.stakeToken.balanceOf(this.alice),
          initialAliceStakeBalance
          )
      })

      it('Alice must have 0 liquid rewards', async function () {
        assertBigNumberEquality(await this.validatorContract.getLiquidRewards(this.alice), '0')
      })

      it('Alice must have 0 shares', async function () {
        assertBigNumberEquality(await this.validatorContract.balanceOf(this.alice), '0')
      })

      it("Bob must have Alice's shares", async function () {
        assertBigNumberEquality(
          await this.validatorContract.balanceOf(this.bob),
          initialBobSharesBalance.add(initialAliceSharesBalance)
        )
      })

      it('must emit DelegatorClaimedRewards for Bob', async function () {
        assertInTransaction(this.receipt, StakingInfo, 'DelegatorClaimedRewards', {
          validatorId: this.validatorId,
          user: this.bob,
          rewards: toWei('3000')
        })
      })

      it('Bob must claim 3000 pol', async function () {
        assertBigNumberEquality(
          await this.polToken.balanceOf(this.bob),
          initialBobPolBalance.add(toWei('3000'))
        )
      })

      it('Bob must have unchanged matic', async function () {
        assertBigNumberEquality(
          await this.stakeToken.balanceOf(this.bob),
          initialBobStakeBalance
        )
      })

      it('Bob must have 0 liquid rewards', async function () {
        assertBigNumberEquality(await this.validatorContract.getLiquidRewards(this.bob), '0')
      })
    })

    describe('when transfer to 0x0 address', function () {
      deployAliceAndBob()

      let initialAliceSharesBalance

      before('Alice purchases voucher', async function () {
        initialAliceSharesBalance = await this.validatorContract.balanceOf(this.alice)

        await buyVoucherPOL(this.validatorContract, ValidatorDefaultStake, this.alice)
      })

      it('reverts', async function () {
        const validatorAlice = this.validatorContract.connect(this.validatorContract.provider.getSigner(this.alice))
        await expectRevert.unspecified(
          validatorAlice.transferPOL(ZeroAddr, initialAliceSharesBalance)
        )
      })
    })
  })
})

function shouldHaveCorrectStakes({ user, userTotalStaked, totalStaked }) {
  it('must have correct total staked', async function () {
    const result = await this.validatorContract.amountStaked(user || this.user)
    assertBigNumberEquality(result, userTotalStaked)
  })

  it('validator state must have correct amount', async function () {
    assertBigNumberEquality(await this.stakeManager.currentValidatorSetTotalStake(), totalStaked)
  })
}

function shouldBuyShares({ shares, voucherValueExpected, totalStaked }) {
  it('ValidatorShare must mint correct amount of shares', async function () {
    assertInTransaction(this.receipt, ValidatorShare, 'Transfer', {
      from: ZeroAddr,
      to: this.user,
      value: shares.toString()
    })
  })

  it('must emit ShareMinted', async function () {
    assertInTransaction(this.receipt, StakingInfo, 'ShareMinted', {
      validatorId: this.validatorId,
      user: this.user,
      amount: voucherValueExpected.toString(),
      tokens: shares.toString()
    })
  })

  it('must emit StakeUpdate', async function () {
    assertInTransaction(this.receipt, StakingInfo, 'StakeUpdate', {
      validatorId: this.validatorId,
      newAmount: totalStaked.toString()
    })
  })
}

function shouldWithdrawReward({ initialBalance, validatorId, user, reward, checkBalance = true }) {
  if (reward > 0) {
    it('must emit Transfer', async function () {
      assertInTransaction(this.receipt, TestToken, 'Transfer', {
        from: this.stakeManager.address,
        to: user || this.user,
        value: reward
      })
    })

    it('must emit DelegatorClaimedRewards', async function () {
      assertInTransaction(this.receipt, StakingInfo, 'DelegatorClaimedRewards', {
        validatorId: validatorId.toString(),
        user: user || this.user,
        rewards: reward.toString()
      })
    })
  }

  if (checkBalance) {
    it('must have updated balance', async function () {
      const balance = await this.polToken.balanceOf(user || this.user)
      assertBigNumberEquality(balance, new BN(initialBalance).add(new BN(reward)))
    })
  }

  it('must have liquid rewards == 0', async function () {
    let rewards = await this.validatorContract.getLiquidRewards(user || this.user)
    assertBigNumberEquality('0', rewards)
  })

  it('must have correct initialRewardPerShare', async function () {
    const currentRewardPerShare = await this.validatorContract.rewardPerShare()
    const userRewardPerShare = await this.validatorContract.initalRewardPerShare(user || this.user)
    assertBigNumberEquality(currentRewardPerShare, userRewardPerShare)
  })
}
