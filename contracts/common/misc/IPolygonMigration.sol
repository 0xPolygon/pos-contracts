pragma solidity 0.5.17;

interface IPolygonMigration {
    function migrate(uint256 amount) external;
    function unmigrate(uint256 amount) external;
}
