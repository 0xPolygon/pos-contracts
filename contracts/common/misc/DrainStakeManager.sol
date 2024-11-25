pragma solidity ^0.5.2;

import {StakeManagerStorage} from "../../staking/stakeManager/StakeManagerStorage.sol";
import {StakeManagerStorageExtension} from "../../staking/stakeManager/StakeManagerStorageExtension.sol";
import {GovernanceLockable} from "../mixin/GovernanceLockable.sol";
import {Initializable} from "../../common/mixin/Initializable.sol";

// Inheriting from Initializable as well to keep the storage layout same
contract DrainStakeManager is StakeManagerStorage, Initializable, StakeManagerStorageExtension {
    constructor() public GovernanceLockable(address(0x0)) {}

    function drain(address destination) external onlyOwner {
        require(token.transfer(destination, token.balanceOf(address(this))), "Drain failed");
        require(tokenMatic.transfer(destination, tokenMatic.balanceOf(address(this))), "Drain failed");
    }

    // Overriding isOwner from Ownable.sol because owner() and transferOwnership() have been overridden by
    // UpgradableProxy
    function isOwner() public view returns (bool) {
        address _owner;
        bytes32 position = keccak256("matic.network.proxy.owner");
        assembly {
            _owner := sload(position)
        }
        return msg.sender == _owner;
    }
}
