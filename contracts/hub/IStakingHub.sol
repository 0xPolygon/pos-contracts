// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

/// @title Staking Hub
/// @author Polygon Labs
/// @notice The Staking Hub is the central contract of the Polygon Staking Layer and is responsible for managing and coordinating stakers, lockers and services.
interface IStakingHub {
    struct LockerSettings {
        uint256 lockerId;
        uint8 maxSlashPercentage;
    }
    /// @notice Emitted when a new locker is registered with the staking hub.
    /// @param locker The address of the locker.
    /// @param lockerId The assigned id of the locker.
    event LockerRegistered(address indexed locker, uint256 indexed lockerId);

    /// @notice Emitted when a new service is registered with the staking hub.
    /// @param service The address of the service.
    /// @param serviceId The assigned id of the service.
    /// @param lockers Lockers used by the service.
    /// @param slashingPercentages The compressed slashing percentages of the lockers.
    /// @param unsubNotice The delay period between unsubscription initiation and finalisation.
    event ServiceRegistered(address indexed service, uint256 indexed serviceId, uint256[] lockers, uint256 slashingPercentages, uint40 unsubNotice);

    /// @notice Emitted when a staker subscribes to a service.
    /// @param staker The address of the staker.
    /// @param serviceId The id of the service.
    /// @param lockInUntil The time until the staker is locked in.
    event Subscribed(address indexed staker, uint256 indexed serviceId, uint40 lockInUntil);

    /// @notice Emitted when a staker initiates unsubscription from a service.
    /// @param staker The address of the staker.
    /// @param serviceId The id of the service.
    /// @param unsubscribableFrom The timestamp when the unsubscription can be finalized.
    event UnsubscriptionInitiated(address indexed staker, uint256 indexed serviceId, uint256 unsubscribableFrom);

    /// @notice Emitted when a callback to the service during unsubscription initiation reverts.
    /// @param staker The address of the staker.
    /// @param serviceId The id of the service.
    /// @param data The revert data.
    event UnsubscriptionInitializationWarning(address indexed staker, uint256 indexed serviceId, bytes data);

    /// @notice Emitted when a staker finalizes unsubscription from a service.
    /// @param staker The address of the staker.
    /// @param serviceId The id of the service.
    event Unsubscribed(address indexed staker, uint256 indexed serviceId);

    /// @notice Emitted when a callback to the service during unsubscription reverts.
    /// @param staker The address of the staker.
    /// @param serviceId The id of the service.
    /// @param data The revert data.
    event UnsubscriptionFinalizationWarning(address indexed staker, uint256 indexed serviceId, bytes data);

    /// @notice Emitted when a slasher update is initiated.
    /// @param serviceId The id of the service.
    /// @param newSlasher The address of the new slasher.
    /// @param scheduledTime The timestamp after which the slasher can be updated.
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher, uint40 scheduledTime);

    /// @notice Emitted when a slasher is updated.
    /// @param serviceId The id of the service.
    /// @param slasher The address of the new slasher.
    event SlasherUpdated(uint256 indexed serviceId, address indexed slasher);

    /// @notice Emitted when a staker is frozen.
    /// @param staker The address of the staker.
    /// @param serviceId The id of the service freezing the staker.
    /// @param until The timestamp until the staker is frozen.
    event StakerFrozen(address indexed staker, uint256 indexed serviceId, uint256 until);

    /// @notice Emitted when a staker is slashed.
    /// @param staker The address of the staker.
    /// @param serviceId The id of the service slashing the staker.
    /// @param lockerIds The ids of the lockers being slashed.
    /// @param percentages The percentages of each locker being slashed.
    event StakerSlashed(address indexed staker, uint256 indexed serviceId, uint256[] lockerIds, uint8[] percentages);

    /// @notice Registers a new locker with the staking hub.
    /// @dev Must be called by the locker contract.
    /// @dev Emits `LockerRegistered` on successful registration.
    /// @return id The new id of the locker.
    function registerLocker() external returns (uint256 id);

    /// @notice Registers a new service with the staking hub.
    /// @dev Must be called by the service contract.
    /// @dev Emits `ServiceRegistered` on successful registration.
    /// @dev Emits `SlasherUpdated`.
    /// @param lockers Settings for lockers. `lockers` must include 1-32 lockers. `lockerId`s must be ordered by locker id in ascending order. `maxSlashPercentage` cannot exceed `100`.
    /// @param unsubNotice Delay period between unsubscription initiation and finalisation.
    /// @param slasher The slashing contract used by the service. It may be the service contract itself.
    /// @dev `unsubNotice` cannot be `0`.
    /// @return id The new id of the service.
    function registerService(LockerSettings[] calldata lockers, uint40 unsubNotice, address slasher) external returns (uint256 id);

    /// @notice Restakes staker to a service.
    /// @dev Cannot be called while the staker is frozen.
    /// @dev Calls `onSubscribe` on all lockers used by the service.
    /// @dev Calls `onSubscribe` on the subscribed service.
    /// @dev Emits `Subscribed` on successful subscription.
    /// @param service The service the staker subscribes to.
    /// @param lockInUntil The time until the staker is locked in and the service can prevent unsubscribing.
    function subscribe(uint256 service, uint40 lockInUntil) external;

    /// @notice Initiates unsubscription from a service.
    /// @notice Cannot be called while the staker is frozen.
    /// @dev Calls `onInitiateUnsubscribe` on the service. If the staker is locked in, the service can prevent unsubscription by reverting. If the staker is not locked in, the service cannot prevent unsubscription by reverting and forwarded gas is limited.
    /// @dev Emits `UnsubscriptionInitializationWarning` if the callback to the service reverts when the user is not locked in.
    /// @dev Emits `UnsubscriptionInitiated` on successful unsubscription initiation.
    /// @param service The service the staker unsubscribes from.
    /// @return unsubscribableFrom Timestamp when the unsubscription can be finalized.
    function initiateUnsubscribe(uint256 service) external returns (uint40 unsubscribableFrom);

    /// @notice Finalizes unsubscription from a service. Needs to be called after `initiateUnsubscribe`.
    /// @notice Cannot be called while the staker is frozen.
    /// @dev Calls `onFinalizeUnsubscribe` on the service. The service cannot prevent unsubscribing by reverting and forwarded gas is limited.
    /// @dev Calls `onUnsubscribe` on all lockers used by the service.
    /// @dev Emits `UnsubscriptionFinalizationWarning` if the callback to the service reverts.
    /// @dev Emits `Unsubscribed` on successful unsubscription finalization.
    /// @param service The service the staker unsubscribes from.
    function finalizeUnsubscribe(uint256 service) external;

    /// @notice Forcefully unsubscribes a staker from a service.
    /// @dev Called by the service the staker is subscribed to.
    /// @dev Calls `onUnsubscribe` on lockers used by the service.
    /// @dev Emits `Unsubscribed` on successful unsubscription.
    /// @param staker The staker to unsubscribe.
    function terminate(address staker) external;

    /// @notice Schedules a slasher update.
    /// @dev Called by the service that wants to update their slasher.
    /// @dev When a new slasher is scheduled, stakers subscribed to the service can unsubscibe from the service.
    /// @dev Emits `SlasherUpdateInitiated` on successful scheduling.
    /// @param newSlasher The new slasher address.
    /// @return scheduledTime Timestamp after which the slasher can be updated.
    function initiateSlasherUpdate(address newSlasher) external returns (uint40 scheduledTime);

    /// @notice Finalizes a slasher update. Must be called after `initiateSlasherUpdate`.
    /// @dev Emits `SlasherUpdated` on successful update.
    function finalizeSlasherUpdate() external;

    /// @notice Freezes a staker for performing a provable malicious action.
    /// @dev A frozen staker cannot take any action until the freeze period ends.
    /// @dev A service can freeze a staker once per freeze period.
    /// @dev Called by the slasher contract.
    /// @dev Emits `StakerFrozen` on successful freezing.
    /// @param staker The staker to freeze.
    function freeze(address staker) external;

    /// @notice Slashes a staker for performing a provable malicious action.
    /// @dev The staker needs to be frozen by the service before slashing.
    /// @dev Called by slasher the slasher contract.
    /// @dev Calls `onSlash` on all lockers used by the service.
    /// @dev Emits `StakerSlashed`.
    /// @param staker The staker to slash.
    /// @param percentages Percentage of funds to slash. Must specify percentages for all lockers. The percentages must be ordered by locker ID. If `0` is passed for a locker, slashing is skipped for that locker. The sum of slash percentages within a freeze period cannot exceed the configured maximum slash percentage.
    function slash(address staker, uint8[] calldata percentages) external;

    /// @notice Checks whether a staker is frozen.
    /// @param staker The staker to check.
    /// @return frozen Whether the staker is frozen.
    function isFrozen(address staker) external view returns (bool frozen);

    /// @notice Returns the id of the locker.
    /// @param lockerAddr The address of the locker.
    /// @return id The id of the locker.
    function lockerId(address lockerAddr) external view returns (uint256 id);

    /// @notice Returns the id of the service.
    /// @param serviceAddr The address of the service.
    /// @return id The id of the service.
    function serviceId(address serviceAddr) external view returns (uint256 id);

}
