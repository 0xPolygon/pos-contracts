// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.5.17;

interface IVersioned {
    /// @return The version of the contract
    function version() external pure returns (string memory);
}
