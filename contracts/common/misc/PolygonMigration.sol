// SPDX-License-Identifier: MIT
pragma solidity 0.5.17;

import {IERC20} from "../oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "../oz/token/ERC20/SafeERC20.sol";
import {IPolygonMigration} from "./IPolygonMigration.sol";

/// @title Polygon Migration
/// @author Polygon Labs (@DhairyaSethi, @gretzke, @qedk)
/// @notice This is the migration contract for Matic <-> Polygon ERC20 token on Ethereum L1
/// @dev The contract allows for a 1-to-1 conversion from $MATIC into $POL and vice-versa
contract PolygonMigration is IPolygonMigration {
    using SafeERC20 for IERC20;

    IERC20 public legacy;
    IERC20 public staking;
    address owner;

    bool public unmigrationLocked;

    modifier onlyUnmigrationUnlocked() {
        require(!unmigrationLocked, "UnmigrationLocked");
        _;
    }

     modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address _legacy, address _staking) public {
        staking = IERC20(_staking);
        legacy = IERC20(_legacy);
        owner = msg.sender;
        unmigrationLocked = false;
    }

    function migrate(uint256 amount) external {
        emit Migrated(msg.sender, amount);

        legacy.safeTransferFrom(msg.sender, address(this), amount);
        staking.safeTransfer(msg.sender, amount);
    }

    function unmigrate(uint256 amount) external onlyUnmigrationUnlocked {
        emit Unmigrated(msg.sender, msg.sender, amount);

        staking.safeTransferFrom(msg.sender, address(this), amount);
        legacy.safeTransfer(msg.sender, amount);
    }

    function unmigrateTo(address recipient, uint256 amount) external onlyUnmigrationUnlocked {
        emit Unmigrated(msg.sender, recipient, amount);

        staking.safeTransferFrom(msg.sender, address(this), amount);
        legacy.safeTransfer(recipient, amount);
    }

    function updateUnmigrationLock(bool unmigrationLocked_) external onlyOwner {
        emit UnmigrationLockUpdated(unmigrationLocked_);
        unmigrationLocked = unmigrationLocked_;
    }
}