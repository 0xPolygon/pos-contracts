pragma solidity 0.5.17;

contract NativeTokenReceiver_Reverts {
    function() external payable {
        revert("!allowed");
    }
}

contract NativeTokenReceiver {
    event SafeReceived(address indexed sender, uint value);

    // bytes32(uint(keccak256("singleton")) - 1)
    bytes32 public constant SINGLETON_SLOT = 0x3d9111c4ec40e72567dff1e7eb8686c719e04ff7490697118315d2143e8e9edb;

    constructor() public {
        address receiver = address(new Receive());
        assembly {
            sstore(SINGLETON_SLOT, receiver)
        }
    }

    function() external payable {
        assembly {
            let singleton := sload(SINGLETON_SLOT)
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), singleton, 0, calldatasize(), 0, 0)
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }
}

contract Receive {
    event SafeReceived(address indexed sender, uint value);
    function() external payable {
        emit SafeReceived(msg.sender, msg.value);
    }
}

contract NativeTokenReceiver_OOG {
    uint counter;
    function() external payable {
        for (uint i; i < 100; i++) {
            counter++;
        }
    }
}
