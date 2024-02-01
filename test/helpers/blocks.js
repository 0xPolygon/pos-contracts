import ethUtils from 'ethereumjs-util'
import { Buffer } from 'safe-buffer'

const sha3 = ethUtils.keccak256
const BN = ethUtils.BN

export async function getHeaders(start, end, web3) {
  if (start >= end) {
    return []
  }

  let current = start
  let p = []
  let result = []
  while (current <= end) {
    p = []

    for (let i = 0; i < 10 && current <= end; i++) {
      p.push(web3.eth.getBlock(current))
      current++
    }

    if (p.length > 0) {
      result.push(...(await Promise.all(p)))
    }
  }

  return result.map(getBlockHeader)
}

export function getBlockHeader(block) {
  const n = new BN(block.number).toArrayLike(Buffer, 'be', 32)
  const ts = new BN(block.timestamp).toArrayLike(Buffer, 'be', 32)
  const txRoot = ethUtils.toBuffer(block.transactionsRoot)
  const receiptsRoot = ethUtils.toBuffer(block.receiptsRoot)
  return sha3(Buffer.concat([n, ts, txRoot, receiptsRoot]))
}
