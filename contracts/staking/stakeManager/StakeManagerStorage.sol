pragma solidity ^0.5.2;

import {IERC20} from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import {Registry} from "../../common/Registry.sol";
import {Lockable} from "../../common/mixin/Lockable.sol";
import {ProxyStorage} from "../../common/misc/ProxyStorage.sol";
import {RootChainable} from "../../common/mixin/RootChainable.sol";
import {StakingInfo} from "../StakingInfo.sol";
import {StakingNFT} from "./StakingNFT.sol";
import "../validatorShare/ValidatorShareFactory.sol";

contract StakeManagerStorage is ProxyStorage, Lockable, RootChainable {
    IERC20 public token;
    address public registry;
    StakingInfo public logger;
    StakingNFT public NFTContract;
    ValidatorShareFactory public factory;
    uint256 public WITHDRAWAL_DELAY = (2**13); // unit: epoch
    uint256 public currentEpoch = 1;
    // genesis/governance variables
    uint256 public dynasty = 2**13; // unit: epoch 50 days
    uint256 public CHECKPOINT_REWARD = 10000 * (10**18); // @todo update according to Chain
    uint256 public minDeposit = (10**18); // in ERC20 token
    uint256 public minHeimdallFee = (10**18); // in ERC20 token
    uint256 public checkPointBlockInterval = 255;

    uint256 public validatorThreshold = 10; //128
    uint256 public totalStaked;
    uint256 public NFTCounter = 1;
    uint256 public totalRewards;
    uint256 public totalRewardsLiquidated;
    uint256 public auctionPeriod = dynasty / 4; // 1 week in epochs
    bytes32 public accountStateRoot;

    // on dynasty update certain amount of cooldown period where there is no validator auction
    uint256 replacementCoolDown;

    struct Auction {
        uint256 amount;
        uint256 startEpoch;
        address user;
    }

    struct State {
        int256 amount;
        int256 stakerCount;
    }

    enum Status {Inactive, Active, Locked, Unstaked}
    struct Validator {
        uint256 amount;
        uint256 reward;
        uint256 activationEpoch;
        uint256 deactivationEpoch;
        uint256 jailTime;
        address signer;
        address contractAddress;
        Status status;
    }

    mapping(uint256 => Validator) public validators;
    // signer to Validator mapping
    mapping(address => uint256) public signerToValidator;
    //Mapping for epoch to totalStake for that epoch
    mapping(uint256 => State) public validatorState;
    mapping(uint256 => uint256) public validatorFeeExit;
    //Ongoing auctions for validatorId
    mapping(uint256 => Auction) public validatorAuction;

    uint256 public totalHeimdallFee;

}
