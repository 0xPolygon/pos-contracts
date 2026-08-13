pragma solidity 0.5.17;

import {IERC20} from "../common/oz/token/ERC20/IERC20.sol";
import {IGovernance} from "../common/governance/IGovernance.sol";
import {IPolygonMigration} from "../common/misc/IPolygonMigration.sol";
import {StakingInfo} from "../staking/StakingInfo.sol";
import {StakingNFT} from "../staking/stakeManager/StakingNFT.sol";
import {ValidatorShareFactory} from "../staking/validatorShare/ValidatorShareFactory.sol";
import {StakeManager} from "../staking/stakeManager/StakeManager.sol";

// TEST ONLY — this is not a deployment target.
//
// StakeManager ships without an initializer (see the note there). Tests still need to take a fresh
// proxy from zero storage to the state mainnet has been in since 2020, so this subclass re-adds the
// genesis initializer verbatim.
//
// The flow, used by script/setup/DeploySystem.s.sol and test/helpers/deployer.js:
//   1. deploy this contract as the implementation,
//   2. proxy.updateAndCall(thisImpl, initialize(...)),
//   3. proxy.updateImplementation(implUnderTest) — StakeManager itself, or one of the
//      StakeManagerTest / StakeManagerTestable subclasses.
// Everything after step 3 exercises the implementation under test, which never carries an
// initializer of its own.
//
// This body is now the only description of the genesis state. It must keep matching what the live
// proxy's storage holds, not whatever a test finds convenient.
//
// The initializer machinery lives entirely here: the constructor burns `inited` on this
// implementation, so it can only be initialized through a proxy. StakeManager's own constructor
// supplies GovernanceLockable's argument, so this one does not repeat it.
contract StakeManagerTestInit is StakeManager {
    constructor() public {
        _disableInitializer();
    }

    function initialize(
        address _registry,
        address _rootchain,
        address _tokenLegacy,
        address _NFTContract,
        address _stakingLogger,
        address _validatorShareFactory,
        address _governance,
        address _owner,
        address _token,
        address _migration
    ) external initializer {
        governance = IGovernance(_governance);
        registry = _registry;
        rootChain = _rootchain;
        token = IERC20(_token);
        tokenMatic = IERC20(_tokenLegacy);
        migration = IPolygonMigration(_migration);
        NFTContract = StakingNFT(_NFTContract);
        logger = StakingInfo(_stakingLogger);
        validatorShareFactory = ValidatorShareFactory(_validatorShareFactory);
        _transferOwnership(_owner);

        WITHDRAWAL_DELAY = (2**13); // unit: epoch
        currentEpoch = 1;
        dynasty = 886; // unit: epoch 50 days
        CHECKPOINT_REWARD = 20188 * (10**18); // update via governance
        minDeposit = (10**18); // in ERC20 token
        minHeimdallFee = (10**18); // in ERC20 token
        checkPointBlockInterval = 1024;
        signerUpdateLimit = 100;

        validatorThreshold = 7; //128
        NFTCounter = 1;
        proposerBonus = 10; // 10 % of total rewards
        delegationEnabled = true;
    }
}
