pragma solidity 0.5.17;

/// @title IValidatorPass
/// @notice Hook the StakeManager calls to permission validator entry, resolved from the Registry
///         under `keccak256("validatorPass")` (unset => permissionless).
interface IValidatorPass {
    /// @notice Consume a validator's single-use pass on entry. Governance authorizes by issuing the
    ///         pass; this consumes it. State-changing, so implementations MUST restrict it to the
    ///         StakeManager.
    /// @param validator Prospective validator (the `user` of `stakeFor`).
    /// @param signerPubkey Consensus key supplied to `stakeFor`.
    /// @return consumed True if a valid pass was consumed (entry permitted); false otherwise.
    function consumePass(address validator, bytes calldata signerPubkey) external returns (bool consumed);
}
