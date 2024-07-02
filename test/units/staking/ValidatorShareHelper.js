import { getPermitDigest } from './permitHelper.js'

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

export async function buyVoucherLegacy(validatorContract, amount, delegator, minSharesToMint) {
  const validatorContract_Delegator = validatorContract.connect(validatorContract.provider.getSigner(delegator))
  return validatorContract_Delegator.buyVoucherLegacy(amount.toString(), minSharesToMint || 0)
}

export async function sellVoucherLegacy(validatorContract, delegator, minClaimAmount, maxShares) {
  if (maxShares === undefined) {
    maxShares = await validatorContract.balanceOf(delegator)
  }

  if (minClaimAmount === undefined) {
    minClaimAmount = await validatorContract.amountStaked(delegator)
  }

  const validatorContract_Delegator = validatorContract.connect(validatorContract.provider.getSigner(delegator))

  return validatorContract_Delegator.sellVoucherLegacy(minClaimAmount, maxShares)
}

export async function sellVoucherNewLegacy(validatorContract, delegator, minClaimAmount, maxShares) {
  if (maxShares === undefined) {
    maxShares = await validatorContract.balanceOf(delegator)
  }

  if (minClaimAmount === undefined) {
    minClaimAmount = await validatorContract.amountStaked(delegator)
  }
  const validatorContract_Delegator = validatorContract.connect(validatorContract.provider.getSigner(delegator))

  return validatorContract_Delegator.sellVoucher_newLegacy(minClaimAmount.toString(), maxShares)
}
