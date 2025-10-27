pragma solidity 0.5.17;

import {IValidatorShare} from "./IValidatorShare.sol";
import {ERC20} from "../../common/oz/token/ERC20/ERC20.sol";
import {OwnableLockable} from "../../common/mixin/OwnableLockable.sol";
import {Initializable} from "../../common/mixin/Initializable.sol";
import {IERC20Permit} from "../../common/misc/IERC20Permit.sol";
import {StakingInfo} from "./../StakingInfo.sol";
import {IStakeManager} from "../stakeManager/IStakeManager.sol";
import {EventsHub} from "./../EventsHub.sol";
import {Registry} from "../../common/Registry.sol";
import {ECVerify} from "../../common/lib/ECVerify.sol";

contract ValidatorShare is IValidatorShare, ERC20, OwnableLockable, Initializable, IERC20Permit {
    struct DelegatorUnbond {
        uint256 shares;
        uint256 withdrawEpoch;
    }

    uint256 constant EXCHANGE_RATE_PRECISION = 100;
    // maximum matic possible, even if rate will be 1 and all matic will be staked in one go, it will result in 10 ^ 58
    // shares
    uint256 constant EXCHANGE_RATE_HIGH_PRECISION = 10 ** 29;
    uint256 constant MAX_COMMISION_RATE = 100;
    uint256 constant REWARD_PRECISION = 10 ** 25;

    /* solhint-disable var-name-mixedcase */
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    string private constant _VERSION = "1";

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    StakingInfo public stakingLogger;
    IStakeManager public stakeManager;
    uint256 public validatorId;
    uint256 public validatorRewards_deprecated; // Now in StakeManager
    uint256 public commissionRate_deprecated; // Now in StakeManager
    uint256 private lastCommissionUpdate_deprecated; // Now in StakeManager

    uint256 private totalStake_deprecated; // Now in StakeManager
    uint256 public rewardPerShare;
    uint256 public activeAmount;

    bool public delegation;

    uint256 public withdrawPool;
    uint256 public withdrawShares;

    mapping(address => uint256) amountStaked_deprecated; // deprecated, keep for foundation delegators
    mapping(address => DelegatorUnbond) public unbonds;
    mapping(address => uint256) public initalRewardPerShare;

    mapping(address => uint256) public unbondNonces;
    mapping(address => mapping(uint256 => DelegatorUnbond)) public unbonds_new;

    EventsHub public eventsHub;

    IERC20Permit public polToken;

    // EIP712 Storage
    mapping(address => uint256) internal _nonces;

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 internal _CACHED_DOMAIN_SEPARATOR;
    uint256 internal _CACHED_CHAIN_ID;

    bytes32 internal _HASHED_NAME;
    bytes32 internal _HASHED_VERSION;
    bytes32 internal _TYPE_HASH;
    /* solhint-enable var-name-mixedcase */

    constructor() public {
        _disableInitializer();
    }

    function initialize(uint256 _validatorId, address _stakingLogger, address _stakeManager) external initializer {
        validatorId = _validatorId;
        stakingLogger = StakingInfo(_stakingLogger);
        stakeManager = IStakeManager(_stakeManager);
        _transferOwnership(_stakeManager);
        _getOrCacheEventsHub();
        _getOrCachePOLToken();
        delegation = true;

        _cacheDomainSeparatorV4();
    }

    // ERC20 functions, dynamic
    function name() public view returns (string memory) {
        return string(abi.encodePacked("Delegated POL #", _toHexString(validatorId)));
    }

    function symbol() public view returns (string memory) {
        return string(abi.encodePacked("dPOL", _toHexString(validatorId)));
    }

    /**
     * Public View Methods
     */
    function exchangeRate() public view returns (uint256) {
        uint256 totalShares = totalSupply();
        uint256 precision = _getRatePrecision();
        return totalShares == 0 ? precision : stakeManager.delegatedAmount(validatorId).mul(precision).div(totalShares);
    }

    function getTotalStake(address user) public view returns (uint256, uint256) {
        uint256 shares = balanceOf(user);
        uint256 rate = exchangeRate();
        if (shares == 0) {
            return (0, rate);
        }

        return (rate.mul(shares).div(_getRatePrecision()), rate);
    }

    function withdrawExchangeRate() public view returns (uint256) {
        uint256 precision = _getRatePrecision();
        if (validatorId < 8) {
            // fix of potentially broken withdrawals for future unbonding
            // foundation validators have no slashing enabled and thus we can return default exchange rate
            // because without slashing rate will stay constant
            return precision;
        }

        uint256 _withdrawShares = withdrawShares;
        return _withdrawShares == 0 ? precision : withdrawPool.mul(precision).div(_withdrawShares);
    }

    function getLiquidRewards(address user) public view returns (uint256) {
        return _calculateReward(user, getRewardPerShare());
    }

    function getRewardPerShare() public view returns (uint256) {
        return _calculateRewardPerShareWithRewards(stakeManager.delegatorsReward(validatorId));
    }

    /**
     * Public Methods
     */
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        // Sender gets their rewards paid out (code from _withdrawAndTransferReward)
        uint256 liquidRewardFrom = _calcAndResetReward(from);
        if (liquidRewardFrom != 0) {
            require(stakeManager.transferFundsPOL(validatorId, liquidRewardFrom, from), "Insufficent rewards");
            stakingLogger.logDelegatorClaimRewards(validatorId, from, liquidRewardFrom);
        }

        // recipient already has POL staked with this validator? restake their rewards
        if (balanceOf(to) > 0) {
            // rewardPerShare was updated when calling _calcAndResetReward above
            uint256 liquidRewardsTo = _calculateReward(to, rewardPerShare);
            if (liquidRewardsTo != 0) {
                // reusing liquidReward saves us a call here
                // restake rewards to reset initialRewardPerShare value (code from _restake)
                uint256 amountRestaked;
                amountRestaked = _buyShares(liquidRewardsTo, 0, to);

                if (liquidRewardsTo > amountRestaked) {
                    // return change to the user
                    _payout(liquidRewardsTo - amountRestaked, to, "Insufficent rewards", true);
                    stakingLogger.logDelegatorClaimRewards(validatorId, to, liquidRewardsTo - amountRestaked);
                }

                (uint256 totalStaked,) = getTotalStake(to);
                stakingLogger.logDelegatorRestaked(validatorId, to, totalStaked);
            }
        }
        // set "to" baseline to current to prevent claiming historical rewards
        // Do this after calling _calcAndResetReward to use the updated rewardPerShare
        initalRewardPerShare[to] = rewardPerShare;

        // Call parent's transferFrom which checks allowance and transfers shares
        bool success = super.transferFrom(from, to, value);

        // Log the transfer event
        _getOrCacheEventsHub().logSharesTransfer(validatorId, from, to, value);

        return success;
    }

    function buyVoucher(uint256 _amount, uint256 _minSharesToMint) public returns (uint256 amountToDeposit) {
        return _buyVoucher(_amount, _minSharesToMint, false);
    }

    // @dev permit only available on pol token
    // @dev txn fails if frontrun, use buyVoucher instead
    function buyVoucherWithPermit(
        uint256 _amount,
        uint256 _minSharesToMint,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (uint256 amountToDeposit) {
        IERC20Permit _polToken = _getOrCachePOLToken();
        uint256 nonceBefore = _polToken.nonces(msg.sender);
        _polToken.permit(msg.sender, address(stakeManager), _amount, deadline, v, r, s);
        require(_polToken.nonces(msg.sender) == nonceBefore + 1, "Invalid permit");
        return _buyVoucher(_amount, _minSharesToMint, true); // invokes stakeManager to pull token from msg.sender
    }

    function buyVoucherPOL(uint256 _amount, uint256 _minSharesToMint) public returns (uint256 amountToDeposit) {
        return _buyVoucher(_amount, _minSharesToMint, true);
    }

    function _buyVoucher(
        uint256 _amount,
        uint256 _minSharesToMint,
        bool pol
    ) internal returns (uint256 amountToDeposit) {
        _withdrawAndTransferReward(msg.sender, pol);

        amountToDeposit = _buyShares(_amount, _minSharesToMint, msg.sender);
        require(
            pol
                ? stakeManager.delegationDepositPOL(validatorId, amountToDeposit, msg.sender)
                : stakeManager.delegationDeposit(validatorId, amountToDeposit, msg.sender),
            "deposit failed"
        );

        return amountToDeposit;
    }

    function restake() public returns (uint256, uint256) {
        return _restake(msg.sender, false);
    }

    function restakePOL() public returns (uint256, uint256) {
        return _restake(msg.sender, true);
    }

    function restakeAndStakePOL(
        uint256 _amount
    ) public returns (uint256, uint256) {

        uint256 liquidReward = _calcAndResetReward(msg.sender);

        uint256 amountPlusReward = _amount.add(liquidReward);

        uint256 amountToDeposit = _buyShares(amountPlusReward, amountPlusReward, msg.sender);
        require(amountToDeposit == amountPlusReward, "exchange rate not 1");

        (uint256 totalStaked,) = getTotalStake(msg.sender);
        stakingLogger.logDelegatorRestaked(validatorId, msg.sender, totalStaked);

        // transferring POL from sender, total amountToDeposit - liquidReward
        require(
            stakeManager.delegationDepositPOL(validatorId, _amount, msg.sender),
            "deposit failed"
        );

        return (amountToDeposit, liquidReward);
    }

    function _restake(address user, bool pol) private returns (uint256, uint256) {
        uint256 liquidReward = _calcAndResetReward(user);
        uint256 amountRestaked;

        if (liquidReward != 0) {
            amountRestaked = _buyShares(liquidReward, 0, user);

            if (liquidReward > amountRestaked) {
                // return change to the user
                _payout(liquidReward - amountRestaked, user, "Insufficent rewards", pol);
                stakingLogger.logDelegatorClaimRewards(validatorId, user, liquidReward - amountRestaked);
            }

            (uint256 totalStaked,) = getTotalStake(user);
            stakingLogger.logDelegatorRestaked(validatorId, user, totalStaked);
        }

        return (amountRestaked, liquidReward);
    }

    function sellVoucher(uint256 claimAmount, uint256 maximumSharesToBurn) public {
        __sellVoucher(claimAmount, maximumSharesToBurn, false);
    }

    function sellVoucherPOL(uint256 claimAmount, uint256 maximumSharesToBurn) public {
        __sellVoucher(claimAmount, maximumSharesToBurn, true);
    }

    function __sellVoucher(uint256 claimAmount, uint256 maximumSharesToBurn, bool pol) internal {
        (uint256 shares, uint256 _withdrawPoolShare) = _sellVoucher(claimAmount, maximumSharesToBurn, pol);

        DelegatorUnbond memory unbond = unbonds[msg.sender];
        unbond.shares = unbond.shares.add(_withdrawPoolShare);
        // refresh unbond period
        unbond.withdrawEpoch = stakeManager.epoch();
        unbonds[msg.sender] = unbond;

        StakingInfo logger = stakingLogger;
        logger.logShareBurned(validatorId, msg.sender, claimAmount, shares);
        logger.logStakeUpdate(validatorId);
    }

    function withdrawRewards() public {
        _withdrawAndTransferReward(msg.sender, false);
    }

    function withdrawRewardsPOL() public {
        _withdrawAndTransferReward(msg.sender, true);
    }

    function migrateOut(address user, uint256 amount) external onlyOwner {
        _withdrawAndTransferReward(user, true);
        (uint256 totalStaked, uint256 rate) = getTotalStake(user);
        require(totalStaked >= amount, "Migrating too much");

        uint256 precision = _getRatePrecision();
        uint256 shares = amount.mul(precision).div(rate);
        _burn(user, shares);

        stakeManager.updateValidatorState(validatorId, -int256(amount));
        activeAmount = activeAmount.sub(amount);

        stakingLogger.logShareBurned(validatorId, user, amount, shares);
        stakingLogger.logStakeUpdate(validatorId);
        stakingLogger.logDelegatorUnstaked(validatorId, user, amount);
    }

    function migrateIn(address user, uint256 amount) external onlyOwner {
        _withdrawAndTransferReward(user, true);
        _buyShares(amount, 0, user);
    }

    function unstakeClaimTokens() public {
        _unstakeClaimTokens(false);
    }

    function unstakeClaimTokensPOL() public {
        _unstakeClaimTokens(true);
    }

    function _unstakeClaimTokens(bool pol) internal {
        DelegatorUnbond memory unbond = unbonds[msg.sender];
        uint256 amount = _unstakeClaimTokens(unbond, pol);
        delete unbonds[msg.sender];
        stakingLogger.logDelegatorUnstaked(validatorId, msg.sender, amount);
    }

    function updateDelegation(bool _delegation) external onlyOwner {
        delegation = _delegation;
    }

    /**
     * New shares exit API
     */
    function sellVoucher_new(uint256 claimAmount, uint256 maximumSharesToBurn) public {
        _sellVoucher_new(claimAmount, maximumSharesToBurn, false);
    }

    function sellVoucher_newPOL(uint256 claimAmount, uint256 maximumSharesToBurn) public {
        _sellVoucher_new(claimAmount, maximumSharesToBurn, true);
    }

    function _sellVoucher_new(uint256 claimAmount, uint256 maximumSharesToBurn, bool pol) public {
        (uint256 shares, uint256 _withdrawPoolShare) = _sellVoucher(claimAmount, maximumSharesToBurn, pol);

        uint256 unbondNonce = unbondNonces[msg.sender].add(1);

        DelegatorUnbond memory unbond =
            DelegatorUnbond({shares: _withdrawPoolShare, withdrawEpoch: stakeManager.epoch()});
        unbonds_new[msg.sender][unbondNonce] = unbond;
        unbondNonces[msg.sender] = unbondNonce;

        _getOrCacheEventsHub().logShareBurnedWithId(validatorId, msg.sender, claimAmount, shares, unbondNonce);
        stakingLogger.logStakeUpdate(validatorId);
    }

    function unstakeClaimTokens_new(uint256 unbondNonce) public {
        _unstakeClaimTokens_new(unbondNonce, false);
    }

    function unstakeClaimTokens_newPOL(uint256 unbondNonce) public {
        _unstakeClaimTokens_new(unbondNonce, true);
    }

    function _unstakeClaimTokens_new(uint256 unbondNonce, bool pol) internal {
        DelegatorUnbond memory unbond = unbonds_new[msg.sender][unbondNonce];
        uint256 amount = _unstakeClaimTokens(unbond, pol);
        delete unbonds_new[msg.sender][unbondNonce];
        _getOrCacheEventsHub().logDelegatorUnstakedWithId(validatorId, msg.sender, amount, unbondNonce);
    }

    /**
     * Private Methods
     */
    function _getOrCacheEventsHub() private returns (EventsHub) {
        EventsHub _eventsHub = eventsHub;
        if (_eventsHub == EventsHub(0x0)) {
            _eventsHub = EventsHub(Registry(stakeManager.getRegistry()).contractMap(keccak256("eventsHub")));
            eventsHub = _eventsHub;
        }
        return _eventsHub;
    }

    function _getOrCachePOLToken() private returns (IERC20Permit) {
        IERC20Permit _polToken = polToken;
        if (_polToken == IERC20Permit(0x0)) {
            _polToken = IERC20Permit(Registry(stakeManager.getRegistry()).contractMap(keccak256("pol")));
            require(_polToken != IERC20Permit(0x0), "unset");
            polToken = _polToken;
        }
        return _polToken;
    }

    function _sellVoucher(
        uint256 claimAmount,
        uint256 maximumSharesToBurn,
        bool pol
    ) private returns (uint256, uint256) {
        // first get how much staked in total and compare to target unstake amount
        (uint256 totalStaked, uint256 rate) = getTotalStake(msg.sender);
        require(totalStaked != 0 && totalStaked >= claimAmount, "Too much requested");

        // convert requested amount back to shares
        uint256 precision = _getRatePrecision();
        uint256 shares = claimAmount.mul(precision).div(rate);
        require(shares <= maximumSharesToBurn, "too much slippage");

        _withdrawAndTransferReward(msg.sender, pol);

        _burn(msg.sender, shares);
        stakeManager.updateValidatorState(validatorId, -int256(claimAmount));
        activeAmount = activeAmount.sub(claimAmount);

        uint256 _withdrawPoolShare = claimAmount.mul(precision).div(withdrawExchangeRate());
        withdrawPool = withdrawPool.add(claimAmount);
        withdrawShares = withdrawShares.add(_withdrawPoolShare);

        return (shares, _withdrawPoolShare);
    }

    function _unstakeClaimTokens(DelegatorUnbond memory unbond, bool pol) private returns (uint256) {
        uint256 shares = unbond.shares;
        require(
            unbond.withdrawEpoch.add(stakeManager.withdrawalDelay()) <= stakeManager.epoch() && shares > 0,
            "Incomplete withdrawal period"
        );

        uint256 _amount = withdrawExchangeRate().mul(shares).div(_getRatePrecision());
        withdrawShares = withdrawShares.sub(shares);
        withdrawPool = withdrawPool.sub(_amount);

        _payout(_amount, msg.sender, "Insufficent rewards", pol);

        return _amount;
    }

    function _getRatePrecision() private view returns (uint256) {
        // if foundation validator, use old precision
        if (validatorId < 8) {
            return EXCHANGE_RATE_PRECISION;
        }

        return EXCHANGE_RATE_HIGH_PRECISION;
    }

    function _calculateRewardPerShareWithRewards(uint256 accumulatedReward) private view returns (uint256) {
        uint256 _rewardPerShare = rewardPerShare;
        if (accumulatedReward != 0) {
            uint256 totalShares = totalSupply();

            if (totalShares != 0) {
                _rewardPerShare = _rewardPerShare.add(accumulatedReward.mul(REWARD_PRECISION).div(totalShares));
            }
        }

        return _rewardPerShare;
    }

    function _calculateReward(address user, uint256 _rewardPerShare) private view returns (uint256) {
        uint256 shares = balanceOf(user);
        if (shares == 0) {
            return 0;
        }

        uint256 _initialRewardPerShare = initalRewardPerShare[user];

        if (_initialRewardPerShare == _rewardPerShare) {
            return 0;
        }

        return _rewardPerShare.sub(_initialRewardPerShare).mul(shares).div(REWARD_PRECISION);
    }

    function _calcAndResetReward(address user) private returns (uint256) {
        uint256 _rewardPerShare =
            _calculateRewardPerShareWithRewards(stakeManager.withdrawDelegatorsReward(validatorId));
        uint256 liquidRewards = _calculateReward(user, _rewardPerShare);

        rewardPerShare = _rewardPerShare;
        initalRewardPerShare[user] = _rewardPerShare;
        return liquidRewards;
    }

    function _withdrawAndTransferReward(address user, bool pol) private returns (uint256) {
        uint256 liquidRewards = _calcAndResetReward(user);
        if (liquidRewards != 0) {
            _payout(liquidRewards, user, "Insufficent rewards", pol);
            stakingLogger.logDelegatorClaimRewards(validatorId, user, liquidRewards);
        }
        return liquidRewards;
    }

    function _buyShares(
        uint256 _amount,
        uint256 _minSharesToMint,
        address user
    ) private onlyWhenUnlocked returns (uint256) {
        require(delegation, "Delegation is disabled");

        uint256 rate = exchangeRate();
        uint256 precision = _getRatePrecision();
        uint256 shares = _amount.mul(precision).div(rate);
        require(shares >= _minSharesToMint, "Too much slippage");
        require(unbonds[user].shares == 0, "Ongoing exit");

        _mint(user, shares);

        // clamp amount of tokens in case resulted shares requires less tokens than anticipated
        _amount = rate.mul(shares).div(precision);

        stakeManager.updateValidatorState(validatorId, int256(_amount));
        activeAmount = activeAmount.add(_amount);

        StakingInfo logger = stakingLogger;
        logger.logShareMinted(validatorId, user, _amount, shares);
        logger.logStakeUpdate(validatorId);

        return _amount;
    }

    function _payout(uint256 amount, address user, string memory message, bool pol) private {
        require(
            pol
                ? stakeManager.transferFundsPOL(validatorId, amount, user)
                : stakeManager.transferFunds(validatorId, amount, user),
            message
        );
    }

    function transferPOL(address to, uint256 value) public returns (bool) {
        _transferShares(to, value, true);
        return true;
    }

    function transfer(address to, uint256 value) public returns (bool) {
        _transferShares(to, value, false);
        return true;
    }

    function _transferShares(address to, uint256 value, bool pol) internal {
        address from = msg.sender;
        // get rewards for recipient
        _withdrawAndTransferReward(to, pol);
        // convert rewards to shares
        _withdrawAndTransferReward(from, pol);
        // move shares to recipient
        super._transfer(from, to, value);
        _getOrCacheEventsHub().logSharesTransfer(validatorId, from, to, value);
    }

    // ERC20Permit
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        if (block.timestamp > deadline) {
            revert("ERC2612ExpiredSignature");
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        if (_chainId() != _CACHED_CHAIN_ID) {
            _cacheDomainSeparatorV4();
        }

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECVerify.ecrecovery(hash, v, r, s);
        if (signer != owner) {
            revert("ERC2612InvalidSigner");
        }

        _approve(owner, spender, value);
    }

    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _CACHED_DOMAIN_SEPARATOR;
    }

    function _useNonce(address owner) private returns (uint256 current) {
        current = _nonces[owner];
        _nonces[owner] = current + 1;
    }

    function _compress(uint8 v, bytes32 r, bytes32 s) private pure returns (bytes memory) {
        bytes memory signature = new bytes(65);

        assembly {
            mstore(add(signature, 0x20), r)
            mstore(add(signature, 0x40), s)
            mstore8(add(signature, 0x60), v)
        }

        return signature;
    }

    function eip712Version() public view returns (string memory) {
        return _VERSION;
    }

    function _chainId() public pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    function _cacheDomainSeparatorV4() public returns (bytes32) {
        bytes32 hashedName = keccak256(bytes(name()));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));
        _TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = _chainId();
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator();
        return _CACHED_DOMAIN_SEPARATOR;
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION, _chainId(), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _toTypedDataHash(_CACHED_DOMAIN_SEPARATOR, structHash);
    }

    function _toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // utils
    function _toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 4;
        }
        bytes memory buffer = new bytes(length);
        for (uint256 i = length; i > 0; --i) {
            buffer[i - 1] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}
