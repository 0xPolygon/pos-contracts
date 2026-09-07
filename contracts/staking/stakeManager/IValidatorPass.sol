pragma solidity 0.5.17;

/// @title IValidatorPass
/// @notice Hook the StakeManager calls to permission validator entry, resolved from the Registry
///         under `keccak256("validatorPass")` (unset => permissionless).
interface IValidatorPass {
    /// @notice Consume a validator's single-use pass on entry. Governance authorizes by issuing the
    ///         pass; this consumes it. State-changing, so implementations MUST restrict it to the
    ///         StakeManager. This call is the frozen boundary of the pass system (widening it later
    ///         requires a StakeManager upgrade), so it forwards the full entry context; modules are
    ///         free to ignore what their policy does not need.
    /// @param validator Prospective validator (the `user` of `stakeFor`).
    /// @param signerPubkey Consensus key supplied to `stakeFor`.
    /// @param acceptDelegation Whether the entrant is opening a delegation contract on entry.
    /// @param amount Stake amount the entrant is joining with (excludes the heimdall fee).
    /// @param funder `msg.sender` of the stake call — the account paying (third-party entry allowed).
    /// @return consumed True if a valid pass was consumed (entry permitted); false otherwise.
    function consumePass(
        address validator,
        bytes calldata signerPubkey,
        bool acceptDelegation,
        uint256 amount,
        address funder
    ) external returns (bool consumed);
}
