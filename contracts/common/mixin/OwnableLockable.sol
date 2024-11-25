pragma solidity ^0.5.2;

import {Lockable} from "./Lockable.sol";
import {Ownable} from "../oz/ownership/Ownable.sol";

contract OwnableLockable is Lockable, Ownable {
    function lock() public onlyOwner {
        super.lock();
    }

    function unlock() public onlyOwner {
        super.unlock();
    }
}
