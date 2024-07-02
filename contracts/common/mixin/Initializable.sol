pragma solidity ^0.5.2;

contract Initializable {
    bool inited = false;

    modifier initializer() {
        require(!inited, "already inited");
        inited = true;
        _;
    }

    function _disableInitializer() internal {
        inited = true;
    }
}
