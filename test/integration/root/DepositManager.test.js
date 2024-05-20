import * as chai from 'chai'
import chaiAsPromised from 'chai-as-promised'
import deployer from '../../helpers/deployer.js'
import * as utils from '../../helpers/utils.js'
import * as contractFactories from '../../helpers/artifacts.js'
import crypto from 'crypto'

chai.use(chaiAsPromised).should()

describe('DepositManager @skip-on-coverage', async function (accounts) {
  let depositManager, childContracts, maticE20
  const amount = web3.utils.toBN('10').pow(web3.utils.toBN('18'))

  describe('deposits on root and child', async function () {
    before(async () => {
      accounts = await ethers.getSigners()
      accounts = accounts.map((account) => {
        return account.address
      })
    })

    beforeEach(async function () {
      const contracts = await deployer.freshDeploy(accounts[0])
      depositManager = contracts.depositManager
      childContracts = await deployer.initializeChildChain()
      maticE20 = await deployer.deployMaticToken()
    })

    it('depositERC20', async function () {
      const bob = accounts[1]
      const e20 = await deployer.deployChildErc20()
      // console.log('child token from mapping: ', await childContracts.childChain.tokens(e20.rootERC20.address))
      await utils.deposit(depositManager, childContracts.childChain, e20.rootERC20, bob, amount, {
        rootDeposit: true,
        erc20: true
      })

      // assert deposit on child chain
      const balance = await e20.childToken.balanceOf(bob)
      utils.assertBigNumberEquality(balance, amount)
    })

    describe('Matic Tokens', async function () {
      it('deposit to EOA', async function () {
        const bob = '0x' + crypto.randomBytes(20).toString('hex')
        utils.assertBigNumberEquality(await maticE20.childToken.balanceOf(bob), 0)
        await utils.deposit(depositManager, childContracts.childChain, maticE20.rootERC20, bob, amount, {
          rootDeposit: true,
          erc20: true
        })

        // assert deposit on child chain
        utils.assertBigNumberEquality(await maticE20.childToken.balanceOf(bob), amount)
      })

      it('deposit to non EOA', async function () {
        const scwReceiver = await contractFactories.NativeTokenReceiver.deploy()
        utils.assertBigNumberEquality(await maticE20.childToken.balanceOf(scwReceiver.address), 0)
        const stateSyncTxn = await utils.deposit(
          depositManager,
          childContracts.childChain,
          maticE20.rootERC20,
          scwReceiver.address,
          amount,
          {
            rootDeposit: true,
            erc20: true
          }
        )

        utils.assertInTransaction(stateSyncTxn, contractFactories.NativeTokenReceiver, 'SafeReceived', {
          sender: maticE20.childToken.address,
          value: amount.toString()
        })

        // assert deposit on child chain
        utils.assertBigNumberEquality(await maticE20.childToken.balanceOf(scwReceiver.address), amount)
      })

      it('deposit to reverting non EOA', async function () {
        const scwReceiver_Reverts = await contractFactories.NativeTokenReceiver_Reverts.deploy()
        utils.assertBigNumberEquality(await maticE20.childToken.balanceOf(scwReceiver_Reverts.address), 0)
        const newDepositBlockEvent = await utils.depositOnRoot(
          depositManager,
          maticE20.rootERC20,
          scwReceiver_Reverts.address,
          amount.toString(),
          {
            rootDeposit: true,
            erc20: true
          }
        )
        try {
          const tx = await childContracts.childChain.onStateReceive(
            '0xf' /* dummy id */,
            utils.encodeDepositStateSync(
              scwReceiver_Reverts.address,
              maticE20.rootERC20.address,
              amount,
              newDepositBlockEvent.args.depositBlockId
            )
          )
          await tx.wait()
        } catch (error) {
          // problem with return data decoding on bor rpc & hh
          chai.assert(error.message.includes('transaction failed'), 'Transaction should have failed')
        }
        // assert deposit did not happen on child chain
        utils.assertBigNumberEquality(await maticE20.childToken.balanceOf(scwReceiver_Reverts.address), 0)
      })

      it('deposit to reverting with OOG', async function () {
        const scwReceiver_OOG = await contractFactories.NativeTokenReceiver_OOG.deploy()
        utils.assertBigNumberEquality(await maticE20.childToken.balanceOf(scwReceiver_OOG.address), 0)
        const newDepositBlockEvent = await utils.depositOnRoot(
          depositManager,
          maticE20.rootERC20,
          scwReceiver_OOG.address,
          amount.toString(),
          {
            rootDeposit: true,
            erc20: true
          }
        )
        try {
          const tx = await childContracts.childChain.onStateReceive(
            '0xb' /* dummy id */,
            utils.encodeDepositStateSync(
              scwReceiver_OOG.address,
              maticE20.rootERC20.address,
              amount,
              newDepositBlockEvent.args.depositBlockId
            )
          )
          await tx.wait()
        } catch (error) {
          chai.assert(error.message.includes('transaction failed'), 'Transaction should have failed')
        }
        utils.assertBigNumberEquality(await maticE20.childToken.balanceOf(scwReceiver_OOG.address), 0)
      })
    })
  })
})
