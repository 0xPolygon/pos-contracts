import { getPermitDigest } from './permitHelper.js'
import { wallets, freshDeploy, approveAndStake } from './deployment.js'
import testHelpers from '@openzeppelin/test-helpers'
import { ValidatorShare } from '../../helpers/artifacts.js'

const BN = testHelpers.BN
const toWei = web3.utils.toWei
export const ValidatorDefaultStake = new BN(toWei('100'))
export const Dynasty = 8

export async function buyVoucher(validatorContract, amount, delegator, minSharesToMint) {
  const validatorContract_Delegator = validatorContract.connect(validatorContract.provider.getSigner(delegator))
  return validatorContract_Delegator.buyVoucher(amount.toString(), minSharesToMint || 0)
}

export async function buyVoucherWithPermit(
  validatorContract,
  amount,
  delegator,
  minSharesToMint,
  spender,
  token,
  deadline
) {
  const signer = validatorContract.provider.getSigner(delegator)
  const validatorContract_Delegator = validatorContract.connect(signer)

  if (!deadline) deadline = (await validatorContract.provider.getBlock('latest')).timestamp + 10

  const signature = await signer._signTypedData(...(await getPermitDigest(delegator, spender, amount, token, deadline)))

  const r = signature.slice(0, 66)
  const s = '0x' + signature.slice(66, 130)
  const v = '0x' + signature.slice(130, 132)

  return validatorContract_Delegator.buyVoucherWithPermit(amount.toString(), minSharesToMint || 0, deadline, v, r, s)
}

export async function sellVoucher(validatorContract, delegator, minClaimAmount, maxShares) {
  if (maxShares === undefined) {
    maxShares = await validatorContract.balanceOf(delegator)
  }

  if (minClaimAmount === undefined) {
    minClaimAmount = await validatorContract.amountStaked(delegator)
  }

  const validatorContract_Delegator = validatorContract.connect(validatorContract.provider.getSigner(delegator))

  return validatorContract_Delegator.sellVoucher(minClaimAmount, maxShares)
}

export async function sellVoucherNew(validatorContract, delegator, minClaimAmount, maxShares) {
  if (maxShares === undefined) {
    maxShares = await validatorContract.balanceOf(delegator)
  }

  if (minClaimAmount === undefined) {
    minClaimAmount = await validatorContract.amountStaked(delegator)
  }
  const validatorContract_Delegator = validatorContract.connect(validatorContract.provider.getSigner(delegator))

  return validatorContract_Delegator.sellVoucher_new(minClaimAmount.toString(), maxShares)
}

export async function buyVoucherPOL(validatorContract, amount, delegator, minSharesToMint) {
  const validatorContract_Delegator = validatorContract.connect(validatorContract.provider.getSigner(delegator))
  return validatorContract_Delegator.buyVoucherPOL(amount.toString(), minSharesToMint || 0)
}

export async function sellVoucherPOL(validatorContract, delegator, minClaimAmount, maxShares) {
  if (maxShares === undefined) {
    maxShares = await validatorContract.balanceOf(delegator)
  }

  if (minClaimAmount === undefined) {
    minClaimAmount = await validatorContract.amountStaked(delegator)
  }

  const validatorContract_Delegator = validatorContract.connect(validatorContract.provider.getSigner(delegator))

  return validatorContract_Delegator.sellVoucherPOL(minClaimAmount, maxShares)
}

export async function sellVoucherNewPOL(validatorContract, delegator, minClaimAmount, maxShares) {
  if (maxShares === undefined) {
    maxShares = await validatorContract.balanceOf(delegator)
  }

  if (minClaimAmount === undefined) {
    minClaimAmount = await validatorContract.amountStaked(delegator)
  }
  const validatorContract_Delegator = validatorContract.connect(validatorContract.provider.getSigner(delegator))

  return validatorContract_Delegator.sellVoucher_newPOL(minClaimAmount.toString(), maxShares)
}

export async function doDeployPOL() {
  await doDeploy.call(this, true)
}

export async function doDeploy(pol = false) {
  await freshDeploy.call(this)
  this.validatorId = '8'
  this.validatorUser = wallets[0]
  this.stakeAmount = ValidatorDefaultStake

  await this.governance.update(
    this.stakeManager.address,
    this.stakeManager.interface.encodeFunctionData('updateDynastyValue', [Dynasty])
  )
  await this.governance.update(
    this.stakeManager.address,
    this.stakeManager.interface.encodeFunctionData('updateValidatorThreshold', [8])
  )

  // we need to increase validator id beyond foundation id, repeat 7 times
  for (let i = 0; i < 7; ++i) {
    await approveAndStake.call(this, {
      wallet: this.validatorUser,
      stakeAmount: this.stakeAmount,
      acceptDelegation: true,
      pol: pol
    })
    if(pol) {
      await this.governance.update(
        this.stakeManager.address,
        this.stakeManager.interface.encodeFunctionData('forceUnstakePOL', [i + 1])
      )
    } else {
      await this.governance.update(
        this.stakeManager.address,
        this.stakeManager.interface.encodeFunctionData('forceUnstake', [i + 1])
      )
    }
    await this.stakeManager.forceFinalizeCommit()
    await this.stakeManager.advanceEpoch(Dynasty)
    const stakeManagerValidator = this.stakeManager.connect(
      this.stakeManager.provider.getSigner(this.validatorUser.getChecksumAddressString())
    )
    if(pol) {
      await stakeManagerValidator.unstakeClaimPOL(i + 1)
    } else {
      await stakeManagerValidator.unstakeClaim(i + 1)
    }
    await this.stakeManager.resetSignerUsed(this.validatorUser.getChecksumAddressString())
  }

  await approveAndStake.call(this, {
    wallet: this.validatorUser,
    stakeAmount: this.stakeAmount,
    acceptDelegation: true,
    pol: pol
  })
  await this.stakeManager.forceFinalizeCommit()

  const validator = await this.stakeManager.validators(this.validatorId)
  this.validatorContract = ValidatorShare.attach(validator.contractAddress)
}