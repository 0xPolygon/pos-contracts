pragma solidity ^0.5.2;

interface IRootChain {
    function submitHeaderBlock(bytes calldata data, bytes calldata sigs) external;

    function submitCheckpoint(bytes calldata data, uint256[3][] calldata sigs) external;

    function getLastChildBlock() external view returns (uint256);

    function currentHeaderBlock() external view returns (uint256);
}
