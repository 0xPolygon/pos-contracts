import utils from 'ethereumjs-util'

import * as contracts from './artifacts.js'

const web3Child = new web3.constructor(
  new web3.providers.HttpProvider('http://localhost:8546')
)
class Deployer {
  constructor() {
    contracts.ChildChain.web3 = web3Child
    contracts.ChildERC20.web3 = web3Child
    contracts.ChildERC721.web3 = web3Child
  }

  async freshDeploy(options = {}) {
    this.registry = await contracts.Registry.new()
    this.rootChain = await contracts.RootChain.new(this.registry.address)
    this.stakeManager = await contracts.StakeManager.new()
    this.exitNFT = await contracts.ExitNFT.new(
      this.registry.address,
      'ExitNFT',
      'ENFT'
    )

    // no need to re-deploy, since proxy contract can be made to point to it
    // if (this.depositManager == null) {}
    this.depositManager = await contracts.DepositManager.new()
    this.depositManagerProxy = await contracts.DepositManagerProxy.new(
      this.depositManager.address,
      this.registry.address,
      this.rootChain.address
    )

    // if (this.withdrawManager == null) {}
    this.withdrawManager = await contracts.WithdrawManager.new()
    this.withdrawManagerProxy = await contracts.WithdrawManagerProxy.new(
      this.withdrawManager.address,
      this.registry.address,
      this.rootChain.address
    )
    const _withdrawManager = await contracts.WithdrawManager.at(
      this.withdrawManagerProxy.address
    )
    await _withdrawManager.setExitNFTContract(this.exitNFT.address)

    await Promise.all([
      this.registry.updateContractMap(
        utils.keccak256('depositManager'),
        this.depositManagerProxy.address
      ),
      this.registry.updateContractMap(
        utils.keccak256('withdrawManager'),
        this.withdrawManagerProxy.address
      ),
      this.registry.updateContractMap(
        utils.keccak256('stakeManager'),
        this.stakeManager.address
      )
    ])

    let _contracts = {
      registry: this.registry,
      rootChain: this.rootChain,
      // for abi to be compatible
      depositManager: await contracts.DepositManager.at(
        this.depositManagerProxy.address
      ),
      withdrawManager: await contracts.WithdrawManager.at(
        this.withdrawManagerProxy.address
      ),
      exitNFT: this.exitNFT
    }

    if (options.deployTestErc20) {
      _contracts.testToken = await this.deployTestErc20()
    }
    return _contracts
  }

  async deployWithdrawManager() {
    if (this.withdrawManager == null) {
      this.withdrawManager = await contracts.WithdrawManager.new()
    }
    this.withdrawManagerProxy = await contracts.WithdrawManagerProxy.new(
      this.withdrawManager.address,
      this.registry.address,
      this.rootChain.address
    )
    await this.registry.updateContractMap(
      utils.keccak256('withdrawManager'),
      this.withdrawManagerProxy.address
    )
    const w = await contracts.WithdrawManager.at(this.withdrawManagerProxy.address)
    await w.setExitNFTContract(this.exitNFT.address)
    return w
  }

  async deployErc20Predicate() {
    const ERC20Predicate = await contracts.ERC20Predicate.new(this.withdrawManagerProxy.address)
    await this.registry.addProofValidator(ERC20Predicate.address)
    return ERC20Predicate
  }

  async deployErc721Predicate() {
    const ERC721Predicate = await contracts.ERC721Predicate.new(this.withdrawManagerProxy.address)
    await this.registry.addProofValidator(ERC721Predicate.address)
    return ERC721Predicate
  }

  async deployTestErc20(options = { mapToken: true }) {
    // TestToken auto-assigns 10000 to msg.sender
    const testToken = await contracts.TestToken.new('TestToken', 'TST')
    if (options.mapToken) {
      await this.mapToken(
        testToken.address,
        options.childTokenAdress || testToken.address,
        false /* isERC721 */
      )
    }
    return testToken
  }

  async deployTestErc721(options = { mapToken: true }) {
    const testToken = await contracts.RootERC721.new('RootERC721', 'T721')
    if (options.mapToken) {
      await this.mapToken(
        this.rootERC721.address,
        options.childTokenAdress || this.rootERC721.address,
        true /* isERC721 */
      )
    }
    return testToken
  }

  async mapToken(rootTokenAddress, childTokenAddress, isERC721 = false) {
    await this.registry.mapToken(
      rootTokenAddress.toLowerCase(),
      childTokenAddress.toLowerCase(),
      isERC721
    )
  }

  async deployChildErc20(owner) {
    const rootERC20 = await this.deployTestErc20({ mapToken: false })
    const tx = await this.childChain.addToken(
      owner,
      rootERC20.address,
      'ChildToken',
      'CTOK',
      18,
      false /* isERC721 */
    )
    const NewTokenEvent = tx.logs.find(log => log.event === 'NewToken')
    const childToken = await contracts.ChildERC20.at(NewTokenEvent.args.token)
    await this.mapToken(
      rootERC20.address,
      childToken.address,
      false /* isERC721 */
    )
    return { rootERC20, childToken }
  }

  async initializeChildChain(owner, options = {}) {
    this.childChain = await contracts.ChildChain.new()
    let res = { childChain: this.childChain }
    if (options.erc20) {
      const r = await this.deployChildErc20(owner)
      res.rootERC20 = r.rootERC20
      res.childToken = r.childToken // rename to childErc20
    }
    if (options.erc721) {
      const rootERC721 = await this.deployTestErc721({ mapToken: false })
      const tx = await this.childChain.addToken(
        owner,
        rootERC721.address,
        'ChildERC721',
        'C721',
        18,
        true /* isERC721 */
      )
      const NewTokenEvent = tx.logs.find(log => log.event === 'NewToken')
      const childErc721 = await contracts.ChildERC721.at(NewTokenEvent.args.token)
      await this.mapToken(
        rootERC721.address,
        childErc721.address,
        true /* isERC721 */
      )
      res.rootERC721 = rootERC721
      res.childErc721 = childErc721
    }
    return res
  }
}

const deployer = new Deployer()
export default deployer
