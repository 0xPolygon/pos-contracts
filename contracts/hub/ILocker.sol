// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.5.17;

/// @title Locker Interface
/// @author Polygon Labs
/// @notice A locker is responsible for managing a single asset within the Polygon Staking Layer. Lockers are used by stakers to subscribe to services that utilise the locker.
interface ILocker {
    /// @notice Indicates a change in underlying balance. This event should be monitored by services offchain to keep track of the voting power of a staker.
    /// @dev Must be emitted on balance changes (depositing, initiating withdrawal, slashing, etc.).
    /// @param staker The staker whose balance changed.
    /// @param newBalance The new balance of the staker.
    event BalanceChanged(address staker, uint256 newBalance);

    /// @dev Should be emitted when a staker withdraws from the locker.
    /// @param staker The staker who withdraws their balance or parts of it.
    /// @param amount The amount withdrawn.
    event Withdrawn(address staker, uint256 amount);

    /// @notice Called by the Staking Hub when a staker subscribes to a service. Must perform internal accounting such as updating the total supply of assets restaked to the service. May perform risk management.
    /// @param staker The staker subscribing to the service.
    /// @param service The service being subscribed to.
    /// @param maxSlashPercentage Maximum percentage that can be slashed from the staker's balance.
    function onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external;

    /// @notice Called by the Staking Hub when a staker unsubscribes from a service. Must perform internal accounting such as updating the total supply of assets restaked to the service.
    /// @param staker The staker unsubscribing from the service.
    /// @param service The service being unsubscribed from.
    /// @param maxSlashPercentage Maximum percentage that can no longer be slashed from the staker's balance.
    function onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external;

    /// @notice Called by the Staking Hub when a staker is slashed. The locker must burn the slashed funds. The locker should aggregate slashings by applying the percentage to the balance at the start of the freeze period. The locker must burn funds scheduled for withdrawal first.
    /// @dev Emits `BalanceChanged`.
    /// @param staker The staker being slashed.
    /// @param service The service slashing the staker.
    /// @param percentage The percentage of the staker's balance being slashed.
    /// @param freezeStart The freeze period id used to snapshot the stakers balance once at start of freeze period for slashing aggregation.
    function onSlash(address staker, uint256 service, uint8 percentage, uint40 freezeStart) external;

    /// @notice Increases staker's total balance, and approval for the specified service
    /// @dev underlying tokens are transferred, caller must have approved the locker to transfer atleast amount
    /// @param staker The staker whose balance is to be increased.
    /// @param service The service for who the staker's approval is being increased.
    /// @param amount The amount of underlying tokens to be deposited.
    function depositAndApproveFor(address staker, uint256 service, uint256 amount) external;

    /// @return The id of the locker.
    function id() external view returns (uint256);

    /// @return amount The amount of underlying funds of the staker deposited into the locker.
    function balanceOf(address staker) external view returns (uint256 amount);

    /// @return amount The amount of underlying funds of the staker deposited into the locker and restaked to the service.
    function balanceOf(address staker, uint256 service) external view returns (uint256 amount);

    /// @return votingPower The representation of the voting power of the stakers underlying balance.
    function votingPowerOf(address staker) external view returns (uint256 votingPower);

    /// @return votingPower The representation of the voting power of the stakers underlying balance within a service.
    function votingPowerOf(address staker, uint256 service) external view returns (uint256 votingPower);

    /// @return The total supply of underlying funds of all stakers deposited into the locker.
    function totalSupply() external view returns (uint256);

    /// @return The total supply of underlying funds of all stakers deposited into the locker and restaked to the service.
    function totalSupply(uint256 service) external view returns (uint256);

    /// @return The total representation of the voting power of all stakers underlying balances.
    function totalVotingPower() external view returns (uint256);

    /// @return The total representation of the voting power of all stakers underlying balances within a service.
    function totalVotingPower(uint256 service) external view returns (uint256);

    /// @return The services the staker is subscribed to.
    function services(address staker) external view returns (uint256[] memory);

    /// @return Whether staker is subscribed to service.
    function isSubscribed(address staker, uint256 service) external view returns (bool);
}
