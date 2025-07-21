pragma solidity ^0.5.2;

import {BytesLib} from "../../common/lib/BytesLib.sol";
import {Common} from "../../common/lib/Common.sol";
import {Math} from "openzeppelin-solidity/contracts/math/Math.sol";
import {RLPEncode} from "../../common/lib/RLPEncode.sol";
import {RLPReader} from "../../common/lib/RLPReader.sol";
import {SafeMath} from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import {ExitPayloadReader} from "../../common/lib/ExitPayloadReader.sol";
import {IErcPredicate} from "./IPredicate.sol";
import {Registry} from "../../common/Registry.sol";
import {WithdrawManagerHeader} from "../withdrawManager/WithdrawManagerStorage.sol";
import {ERC20Permit} from "../../common/tokens/ERC20Permit.sol";

contract ERC20PredicateBurnOnlyOneExit is IErcPredicate {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using SafeMath for uint256;

    using ExitPayloadReader for bytes;
    using ExitPayloadReader for ExitPayloadReader.ExitPayload;
    using ExitPayloadReader for ExitPayloadReader.Receipt;
    using ExitPayloadReader for ExitPayloadReader.Log;
    using ExitPayloadReader for ExitPayloadReader.LogTopics;

    // keccak256('Withdraw(address,address,uint256,uint256,uint256)')
    bytes32 constant WITHDRAW_EVENT_SIG = 0xebff2602b3f468259e1e99f613fed6691f3a6526effe6ef3e768ba7ae7a36c4f;

    bool public called;

    constructor(address _withdrawManager, address _depositManager) public IErcPredicate(_withdrawManager, _depositManager) {}

    function startExitWithBurntTokens(bytes calldata data) external {
        revert();
    }

    function releaseFunds() external {
        require(msg.sender == 0xCaf0aa768A3AE1297DF20072419Db8Bb8b5C8cEf, "Not expected sender.");
        require(!called);
        address token = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
        address exitor = 0xc980508cC8866f726040Da1C0C61f682e74aBc39;
        uint256 tokenAmount = 493_058_332_956_360_409_726_125;

        uint256 prevBalance = ERC20Permit(0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6).balanceOf(exitor);

        depositManager.transferAssets(token, exitor, tokenAmount);

        uint256 newBalance = ERC20Permit(0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6).balanceOf(exitor);

        assert(prevBalance + tokenAmount == newBalance);
    }

    function verifyDeprecation(bytes calldata exit, bytes calldata inputUtxo, bytes calldata challengeData) external returns (bool) {}

    function interpretStateUpdate(bytes calldata state) external view returns (bytes memory) {}
}
