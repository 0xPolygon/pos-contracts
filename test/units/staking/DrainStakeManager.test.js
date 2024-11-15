/* jshint esversion: 9 */

import chai, { assert } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { BN } from '@openzeppelin/test-helpers'

import { DrainStakeManager } from '../../helpers/artifacts.js'

import deployer from '../../helpers/deployer.js'
import * as utils from '../../helpers/utils.js'

import { generateFirstWallets, mnemonics } from '../../helpers/wallets.js'

chai.use(chaiAsPromised).should()

// todo: is this even needed anymore?
describe('DrainStakeManager', function (accounts) {
  let owner
  before(async function() {
    accounts = await ethers.getSigners()
    accounts = accounts.map((account) => {
      return account.address
    })
    owner = accounts[0]
  })
  
  describe('Upgrade and drain staking contract', function () {
    before(async function () {
      this.wallets = generateFirstWallets(mnemonics, 10)

      let contracts = await deployer.deployStakeManager(this.wallets, true)

      this.governance = contracts.governance
      this.polToken = contracts.polToken
      this.stakeManager = contracts.stakeManager
      this.proxy = contracts.stakeManagerProxy
      this.stakeManagerImpl = contracts.stakeManagerImpl

      this.gSafe = await deployer.deployGnosisMultisig(accounts.slice(0, 3))
      await this.stakeManager.transferOwnership(this.gSafe.address)
    })

    it('must have some tokens', async function () {
      const initalAmount = web3.utils.toWei('10000000')
      const amount = web3.utils.toWei('90000')
      await this.polToken.mint(this.stakeManager.address, amount)
      ;(await this.polToken.balanceOf(this.stakeManager.address)).toString().should.be.equal(BN(amount).add(BN(initalAmount)).toString())
    })

    it('must lock stake manager', async function () {
      await this.governance.update(this.stakeManager.address, this.stakeManager.interface.encodeFunctionData('lock'))
      ;(await this.stakeManager.locked()).should.be.equal(true)
    })

    it('must swap to drainable implementaion', async function () {
      this.stakeManagerDrainable = await DrainStakeManager.deploy()
      const result = await (
        await execSafe(
          this.gSafe,
          this.stakeManager.address,
          this.proxy.interface.encodeFunctionData('updateImplementation', [this.stakeManagerDrainable.address]),
          [accounts[0], accounts[1]]
        )
      ).wait()
      assert.equal(await this.proxy.implementation(), this.stakeManagerDrainable.address)
    })

    it('must fail draining when not drained owner', async function () {
      try {
        await this.stakeManagerDrainable.drain(owner)
        assert.fail('Funds should not be drained')
      } catch (error) {
        assert(error.message.search('revert') >= 0, "Expected revert, got '" + error + "' instead")
      }
    })

    it('must drain all funds when drained by owner (Gnosis safe)', async function () {
      const balanceSM = await this.polToken.balanceOf(this.stakeManager.address)
      const balanceO = await this.polToken.balanceOf(owner)
      
      const data = this.stakeManagerDrainable.interface.encodeFunctionData('drain', [owner])
      await execSafe(this.gSafe, this.stakeManager.address, data, [accounts[1], accounts[2]])
      assert.equal((await this.polToken.balanceOf(this.stakeManager.address)).toString(), '0')
      assert.equal((await this.polToken.balanceOf(owner)).toString(), (balanceSM.add(balanceO)).toString())
    })

    it('must swap back to normal implementaion', async function () {
      await execSafe(
        this.gSafe,
        this.stakeManager.address,
        this.proxy.interface.encodeFunctionData('updateImplementation', [this.stakeManagerImpl.address]),
        [accounts[2], accounts[0]]
      )
      assert.equal(await this.proxy.implementation(), this.stakeManagerImpl.address)
    })

    it('must unlock stake manager', async function () {
      await this.governance.update(this.stakeManager.address, this.stakeManager.interface.encodeFunctionData('unlock'))
      ;(await this.stakeManager.locked()).should.be.equal(false)
    })
  })
})

async function execSafe(gSafe, address, data, confirmingAccounts) {
  const params = safeParams(address, data, await gSafe.nonce())
  const txHash = await gSafe.getTransactionHash(...params)
  let signatureBytes = '0x'
  confirmingAccounts.sort()
  for (var i = 0; i < confirmingAccounts.length; i++) {
    // Adjust v (it is + 4 to differentiate them from typed data signatures in the Safe)
    // ethSign already returns 27 or 28
    let signature = (await ethSign(confirmingAccounts[i], txHash))
      .replace('0x', '')
      .replace(/1b$/, '1f')
      .replace(/1c$/, '20')
    signatureBytes += signature
  }
  params[9] = signatureBytes
  return gSafe.execTransaction(...params)
}

function safeParams(address, data, nonce) {
  return [
    address,
    0, // value
    data,
    0, // Operation.Call
    0, // safeTxGas
    4000000, // baseGas
    0, // gasPrice
    utils.ZeroAddress, // gasToken
    utils.ZeroAddress, // refundReceiver
    nonce.toString()
  ]
}

function ethSign(account, hash) {
  return new Promise(function (resolve, reject) {
    web3.currentProvider.send(
      {
        jsonrpc: '2.0',
        method: 'eth_sign',
        params: [account, hash],
        id: new Date().getTime()
      },
      function (err, response) {
        if (err) {
          return reject(err)
        }
        resolve(response.result)
      }
    )
  })
}
