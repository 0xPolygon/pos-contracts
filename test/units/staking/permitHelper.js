import { keccak256 } from 'ethereumjs-util'
import encode from 'ethereumjs-abi'

const PERMIT_TYPEHASH = keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)') // 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9

export function getStructHash({ owner, spender, value, nonce, deadline }) {
  return keccak256(
    encode(
      ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
      [PERMIT_TYPEHASH, owner, spender, value, nonce, deadline]
    )
  )
}

export function getTypedDataHash(DOMAIN_SEPARATOR, permitData) {
  return keccak256(encode(['bytes', 'bytes32', 'bytes32'], ['\x19\x01', DOMAIN_SEPARATOR, getStructHash(permitData)]))
}

const cache = new Map()

export async function getPermitDigest(owner, spender, value, token, deadline) {
  let { name, version } = cache.get(token.address) || {}
  if (!name || !version) {
    ;[name, version] = await Promise.all([token.name(), token.version()])
    cache.set(token.address, { name, version })
  }
  return [
    {
      name: 'POL',
      version: '1.1.0',
      chainId: (await token.provider._network).chainId,
      verifyingContract: token.address
    },
    {
      Permit: [
        {
          name: 'owner',
          type: 'address'
        },
        {
          name: 'spender',
          type: 'address'
        },
        {
          name: 'value',
          type: 'uint256'
        },
        {
          name: 'nonce',
          type: 'uint256'
        },
        {
          name: 'deadline',
          type: 'uint256'
        }
      ]
    },
    {
      owner,
      spender,
      value,
      nonce: await token.nonces(owner),
      deadline
    }
  ]
}
