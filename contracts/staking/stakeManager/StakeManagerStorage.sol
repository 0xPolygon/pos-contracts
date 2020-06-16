pragma solidity ^0.5.2;

import {IERC20} from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import {Registry} from "../../common/Registry.sol";
import {GovernanceLockable} from "../../common/mixin/GovernanceLockable.sol";
import {RootChainable} from "../../common/mixin/RootChainable.sol";
import {StakingInfo} from "../StakingInfo.sol";
import {StakingNFT} from "./StakingNFT.sol";
import "../validatorShare/ValidatorShareFactory.sol";


contract StakeManagerStorage is GovernanceLockable, RootChainable {
    IERC20 public token;
    address public registry;
    StakingInfo public logger;
    StakingNFT public NFTContract;
    ValidatorShareFactory public factory;
    uint256 public WITHDRAWAL_DELAY; // unit: epoch
    uint256 public currentEpoch;

    // genesis/governance variables
    uint256 public dynasty ; // unit: epoch 50 days
    uint256 public CHECKPOINT_REWARD; // update via governance
    uint256 public minDeposit; // in ERC20 token
    uint256 public minHeimdallFee; // in ERC20 token
    uint256 public checkPointBlockInterval;
    uint256 public signerUpdateLimit;

    uint256 public validatorThreshold; //128
    uint256 public totalStaked;
    uint256 public NFTCounter;
    uint256 public totalRewards;
    uint256 public totalRewardsLiquidated;
    uint256 public auctionPeriod; // 1 week in epochs
    uint256 public proposerBonus; // 10 % of total rewards
    bytes32 public accountStateRoot;
    // Stop validator auction for some time when updating dynasty value
    uint256 public replacementCoolDown;
    bool public delegationEnabled;

    struct Auction {
        uint256 amount;
        uint256 startEpoch;
        address user;
        bool acceptDelegation;
        bytes signerPubkey;
    }

    struct State {
        uint256 amount;
        uint256 stakerCount;
    }

    struct StateChange {
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
    State public validatorState;
    mapping(uint256 => StateChange) public validatorStateChanges;

    mapping(address => uint256) public userFeeExit;
    //Ongoing auctions for validatorId
    mapping(uint256 => Auction) public validatorAuction;
    // validatorId to last signer update epoch
    mapping(uint256 => uint256) public latestSignerUpdateEpoch;

    uint256 public totalHeimdallFee;
}
