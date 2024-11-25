pragma solidity 0.5.17;

interface IPolygonMigration {
    event Migrated(address indexed account, uint256 amount);
    event Unmigrated(address indexed account, address indexed recipient, uint256 amount);
    event UnmigrationLockUpdated(bool lock);

    function migrate(uint256 amount) external;
    function unmigrate(uint256 amount) external;
}
