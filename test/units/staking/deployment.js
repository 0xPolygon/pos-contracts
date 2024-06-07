import chai from 'chai'
import chaiAsPromised from 'chai-as-promised'
import deployer from '../../helpers/deployer.js'
import { generateFirstWallets, mnemonics } from '../../helpers/wallets.js'
import { BN } from '@openzeppelin/test-helpers'

chai.use(chaiAsPromised).should()

export const wallets = generateFirstWallets(mnemonics, 10)
export const walletAmounts = {
  [wallets[0].getAddressString()]: {
    amount: web3.utils.toWei('200'),
    stakeAmount: web3.utils.toWei('200'),
    initialBalance: web3.utils.toWei('1200')
  },
  [wallets[1].getAddressString()]: {
    amount: web3.utils.toWei('200'),
    stakeAmount: web3.utils.toWei('200'),
    initialBalance: web3.utils.toWei('1200')
  },
  [wallets[2].getAddressString()]: {
    amount: web3.utils.toWei('250'),
    stakeAmount: web3.utils.toWei('150'),
    restakeAmonut: web3.utils.toWei('100'),
    initialBalance: web3.utils.toWei('805')
  },
  [wallets[3].getAddressString()]: {
    amount: web3.utils.toWei('300'),
    stakeAmount: web3.utils.toWei('300'),
    initialBalance: web3.utils.toWei('850')
  },
  [wallets[4].getAddressString()]: {
    initialBalance: web3.utils.toWei('800')
  }
}

export async function freshDeploy() {
  let contracts = await deployer.deployStakeManager(wallets)
  this.stakeToken = contracts.stakeToken
  this.legacyToken = contracts.legacyToken
  this.stakeManager = contracts.stakeManager
  this.nftContract = contracts.stakingNFT
  this.rootChainOwner = contracts.rootChainOwner
  this.registry = contracts.registry
  this.governance = contracts.governance
  this.validatorShare = deployer.validatorShare
  this.slashingManager = contracts.slashingManager
  this.migration = contracts.migration

  await this.governance.update(
    this.stakeManager.address,
    this.stakeManager.interface.encodeFunctionData('updateCheckpointReward', [web3.utils.toWei('10000')])
  )
  await this.governance.update(
    this.stakeManager.address,
    this.stakeManager.interface.encodeFunctionData('updateCheckPointBlockInterval', [1])
  )

  for (const walletAddr in walletAmounts) {
    await this.legacyToken.mint(walletAddr, walletAmounts[walletAddr].initialBalance)
    await this.stakeToken.mint(walletAddr, walletAmounts[walletAddr].initialBalance)
  }

  await this.stakeToken.mint(this.stakeManager.address, web3.utils.toWei('10000000'))
  await this.legacyToken.mint(this.stakeManager.address, web3.utils.toWei('20000000'))

  this.defaultHeimdallFee = new BN(web3.utils.toWei('1'))
}

export async function approveAndStake({
  wallet,
  stakeAmount,
  approveAmount,
  acceptDelegation = false,
  heimdallFee,
  noMinting = false,
  signer,
  legacy = false
}) {
  const fee = heimdallFee || this.defaultHeimdallFee

  const mintAmount = new BN(approveAmount || stakeAmount).add(new BN(fee))

  let token
  if (legacy) {
    token = this.legacyToken
  } else {
    token = this.stakeToken
  }

  if (noMinting) {
    // check if allowance covers fee
    const balance = await token.balanceOf(wallet.getAddressString())
    if (balance.lt(mintAmount.toString())) {
      // mint more
      await token.mint(wallet.getAddressString(), mintAmount.sub(balance).toString())
    }
  } else {
    await token.mint(wallet.getAddressString(), mintAmount.toString())
  }

  const tokenWallet = token.connect(token.provider.getSigner(wallet.getAddressString()))
  await tokenWallet.approve(this.stakeManager.address, mintAmount.toString())

  const stakeManagerWallet = this.stakeManager.connect(this.stakeManager.provider.getSigner(wallet.getAddressString()))

  if (legacy) {
    await stakeManagerWallet.stakeForLegacy(
      wallet.getAddressString(),
      stakeAmount.toString(),
      fee.toString(),
      acceptDelegation,
      signer || wallet.getPublicKeyString()
    )
  } else {
    await stakeManagerWallet.stakeFor(
      wallet.getAddressString(),
      stakeAmount.toString(),
      fee.toString(),
      acceptDelegation,
      signer || wallet.getPublicKeyString()
    )
  }

}
