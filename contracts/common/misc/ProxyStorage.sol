pragma solidity ^0.5.2;
import {Ownable} from "../oz/ownership/Ownable.sol";

contract ProxyStorage is Ownable {
    address internal proxyTo;
}
