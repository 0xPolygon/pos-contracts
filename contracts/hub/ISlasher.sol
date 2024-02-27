// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.5.17;

/// @title Slasher
/// @author Polygon Labs
/// @notice A Slasher separates the freezing and slashing functionality from a Service.
/// @dev this is an example interface for a slashing contract
interface ISlasher {
    /// @notice Temporarily prevents a Staker from taking action.
    /// @notice Provides proof of malicious behavior.
    /// @dev Called by a service.
    /// @dev Calls freeze on the Hub.
    function freeze(address staker, bytes calldata proof) external;

    /// @notice Slashes a percentage of a Staker's funds.
    /// @notice The Staker must be frozen first.
    /// @dev Called by [up to the Slasher to decide].
    /// @dev Calls slash on the Hub.
    function slash(address staker, uint8[] calldata percentages) external;
}
