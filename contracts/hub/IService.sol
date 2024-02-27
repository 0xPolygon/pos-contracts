// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.5.17;

/// @title Service Interface
/// @author Polygon Labs
/// @notice A service is a contract that manages applications within the Polygon Staking Layer.
interface IService {
    /// @notice Called by the Staking Hub when a staker subscribes to the service.
    /// @dev May perform checks, such as minimum stake requirements, etc. and revert if the staker is not eligible to subscribe.
    /// @param staker The staker subscribing to the service.
    /// @param lockingInUntil The time until the staker is locked in.
    function onSubscribe(address staker, uint256 lockingInUntil) external;

    /// @notice Called by the Staking Hub when a staker initiates unsubscription from the service.
    /// @dev If the staker is locked in, the service can prevent unsubsctiption by reverting.
    /// @dev If the staker is not locked in, the forwarded gas is limited and the service should not revert.
    /// @param staker The staker initiating unsubscription from the service.
    /// @param lockedIn Indicates if the staker is locked in.
    function onInitiateUnsubscribe(address staker, bool lockedIn) external;

    /// @notice Called by the Staking Hub when a staker finalizes unsubscription from the service.
    /// @dev The service should not revert and forwarded gas is limited.
    /// @param staker The staker finalizing unsubscription from the service.
    function onFinalizeUnsubscribe(address staker) external;
}
