// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

// extracted using cast interface 0xCaf0aa768A3AE1297DF20072419Db8Bb8b5C8cEf

interface Timelock {
    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );
    event Cancelled(bytes32 indexed id);
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    receive() external payable;

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function EXECUTOR_ROLE() external view returns (bytes32);
    function PROPOSER_ROLE() external view returns (bytes32);
    function TIMELOCK_ADMIN_ROLE() external view returns (bytes32);
    function cancel(bytes32 id) external;
    function execute(address target, uint256 value, bytes memory data, bytes32 predecessor, bytes32 salt)
        external
        payable;
    function executeBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory datas,
        bytes32 predecessor,
        bytes32 salt
    ) external payable;
    function getMinDelay() external view returns (uint256 duration);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getTimestamp(bytes32 id) external view returns (uint256 timestamp);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function hashOperation(address target, uint256 value, bytes memory data, bytes32 predecessor, bytes32 salt)
        external
        pure
        returns (bytes32 hash);
    function hashOperationBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory datas,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32 hash);
    function isOperation(bytes32 id) external view returns (bool pending);
    function isOperationDone(bytes32 id) external view returns (bool done);
    function isOperationPending(bytes32 id) external view returns (bool pending);
    function isOperationReady(bytes32 id) external view returns (bool ready);
    function renounceRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function schedule(
        address target,
        uint256 value,
        bytes memory data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
    function scheduleBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory datas,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function updateDelay(uint256 newDelay) external;
}
