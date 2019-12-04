const ethUtils = require('ethereumjs-util')
const EthDeployer = require('moonwalker').default

let id = 0

async function deploy() {
  if (!process.env.HEIMDALL_ID) {
    throw new Error('Please export HEIMDALL_ID environment variable')
  }

  const qClient = await EthDeployer.getQueue()
  const deployer = new EthDeployer.Sender(qClient)

  // Libs
  await deployer.deploy(transformArtifact('BytesLib', []))
  await deployer.deploy(transformArtifact('Common', []))

  await deployer.deploy(transformArtifact('ECVerify', []))
  await deployer.deploy(transformArtifact('Merkle', []))
  await deployer.deploy(transformArtifact('MerklePatriciaProof', []))
  await deployer.deploy(transformArtifact('PriorityQueue', []))
  await deployer.deploy(transformArtifact('RLPEncode', []))
  await deployer.deploy(transformArtifact('RLPReader', []))
  await deployer.deploy(transformArtifact('SafeMath', []))

  // contracts
  await deployer.deploy(transformArtifact('Registry', []))
  await deployer.deploy(transformArtifact('RootChain', [
    'Registry',
    { value: process.env.HEIMDALL_ID }
  ]))
  await deployer.deploy(transformArtifact('StakeManager', ['Registry', 'RootChain']))
  await deployer.deploy(transformArtifact('SlashingManager', ['Registry']))
  await deployer.deploy(transformArtifact('DelegationManager', ['Registry']))

  await deployer.deploy(transformArtifact('StateSender', []))

  await deployer.deploy(transformArtifact('DepositManager', []))
  await deployer.deploy(transformArtifact('DepositManagerProxy', ['DepositManager', 'Registry', 'RootChain']))

  await deployer.deploy(transformArtifact('WithdrawManager', []))
  await deployer.deploy(transformArtifact('WithdrawManagerProxy', ['WithdrawManager', 'Registry', 'RootChain']))

  await deployer.deploy(transformArtifact('TestToken', [ { value: 'Test Token' }, { value: 'TST' } ]))

  await deployer.deploy(
    tx('Registry', 'updateContractMap', [
      { value: ethUtils.bufferToHex(ethUtils.keccak256('depositManager')) },
      'DepositManagerProxy'
    ])
  )
  await deployer.deploy(
    tx('Registry', 'updateContractMap', [
      { value: ethUtils.bufferToHex(ethUtils.keccak256('withdrawManager')) },
      'WithdrawManagerProxy'
    ])
  )
  await deployer.deploy(
    tx('Registry', 'updateContractMap', [
      { value: ethUtils.bufferToHex(ethUtils.keccak256('stakeManager')) },
      'StakeManager'
    ])
  )
  await deployer.deploy(
    tx('Registry', 'updateContractMap', [
      { value: ethUtils.bufferToHex(ethUtils.keccak256('delegationManager')) },
      'DelegationManager'
    ])
  )
  await deployer.deploy(
    tx('Registry', 'updateContractMap', [
      { value: ethUtils.bufferToHex(ethUtils.keccak256('slashingManager')) },
      'SlashingManager'
    ])
  )
  await deployer.deploy(
    tx('Registry', 'updateContractMap', [
      { value: ethUtils.bufferToHex(ethUtils.keccak256('stateSender')) },
      'StateSender'
    ])
  )
  await deployer.deploy(
    tx('StakeManager', 'setToken', ['TestToken'])
  )
  // 27 jobs
}

function transformArtifact(contract, args, waitOnJob) {
  const res = {
    contract,
    args,
    id: id++,
    type: 'deploy'
  }
  if (waitOnJob) res.waitOnJob = waitOnJob
  return JSON.stringify(res)
}

function tx(contract, method, args) {
  return JSON.stringify({
    contract,
    method,
    args,
    id: id++,
    type: 'transaction'
  })
}

deploy().then(console.log)
