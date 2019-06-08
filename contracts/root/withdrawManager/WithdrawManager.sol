pragma solidity ^0.5.2;

import { ERC20 } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import { Math } from "openzeppelin-solidity/contracts/math/Math.sol";
import { RLPReader } from "solidity-rlp/contracts/RLPReader.sol";

import { ChildChainVerifier } from "../lib/ChildChainVerifier.sol";
// import { ExitTxValidator } from "../lib/ExitTxValidator.sol";
import { Merkle } from "../../common/lib/Merkle.sol";
import { MerklePatriciaProof } from "../../common/lib/MerklePatriciaProof.sol";
import { PriorityQueue } from "../../common/lib/PriorityQueue.sol";

import { ExitNFT } from "./ExitNFT.sol";

import { IWithdrawManager } from "./IWithdrawManager.sol";
import { IDepositManager } from "../depositManager/IDepositManager.sol";
import { RootChainHeader } from "../RootChainStorage.sol";
import { Registry } from "../../common/Registry.sol";
import { WithdrawManagerStorage } from "./WithdrawManagerStorage.sol";
// import { IPredicate } from "../lib/IPredicate.sol";

contract WithdrawManager is WithdrawManagerStorage /* , IWithdrawManager */ {
  using RLPReader for bytes;
  using RLPReader for RLPReader.RLPItem;
  using Merkle for bytes32;

  modifier isProofValidator() {
    require(
      registry.proofValidatorContracts(msg.sender),
      "UNAUTHORIZED_PROOF_VALIDATOR_CONTRACT");
    _;
  }

  function verifyInclusion(bytes memory data, uint8 offset)
    public
    returns (uint256 age)
  {
    RLPReader.RLPItem[] memory referenceTxData = data.toRlpItem().toList();
    uint256 headerNumber = referenceTxData[offset].toUint();
    bytes memory branchMask = referenceTxData[offset + 8].toBytes();
    require(
      MerklePatriciaProof.verify(
        referenceTxData[offset + 6].toBytes(), // receipt
        branchMask,
        referenceTxData[offset + 7].toBytes(), // receiptProof
        bytes32(referenceTxData[offset + 5].toUint()) // receiptsRoot
      ),
      "INVALID_RECEIPT_MERKLE_PROOF"
    );

    uint256 startBlock;
    bytes32 headerRoot;
    // @todo a function to return just root and startBlock might save gas
    (headerRoot, startBlock,,,) = rootChain.headerBlocks(headerNumber);

    uint256 blockNumber = referenceTxData[offset + 2].toUint();
    require(
      keccak256(abi.encodePacked(
        blockNumber,
        referenceTxData[offset + 3].toUint(), // blockTime
        bytes32(referenceTxData[offset + 4].toUint()), // txRoot
        bytes32(referenceTxData[offset + 5].toUint()) // receiptRoot
      )).checkMembership(blockNumber - startBlock, headerRoot, referenceTxData[offset + 1].toBytes() /* blockProof */),
      "WITHDRAW_BLOCK_NOT_A_PART_OF_SUBMITTED_HEADER"
    );

    age = (
      headerNumber * HEADER_BLOCK_NUMBER_WEIGHT +
      blockNumber * WITHDRAW_BLOCK_NUMBER_WEIGHT +
      branchMask.toRlpItem().toBytes().toRlpItem().toUint() * BRANCH_MASK_WEIGHT
    );
  }


  function createExitQueue(address _token)
    external
  {
    require(msg.sender == address(registry), "UNAUTHORIZED_REGISTRY_ONLY");
    exitsQueues[_token] = address(new PriorityQueue());
  }

  function addInput(uint256 exitId, uint256 age, address signer) public {
    PlasmaExit storage exitObject = exits[exitId];
    require(
      exitObject.token != address(0x0),
      "EXIT_DOES_NOT_EXIST"
    );
    exitObject.inputs[age] = Input(signer);
  }

  function addExitToQueue(
    address exitor,
    address childToken,
    address rootToken,
    uint256 exitAmountOrTokenId,
    bool burnt,
    uint256 priority)
    public
    isProofValidator
  {
    require(
      registry.rootToChildToken(rootToken) == childToken,
      "INVALID_ROOT_TO_CHILD_TOKEN_MAPPING"
    );
    // require(
    //   _registry.isERC721(rootToken) == false,
    //   "NOT_ERC20"
    // );
    require(
      exits[priority].token == address(0x0),
      "EXIT_ALREADY_EXISTS"
    );
    exits[priority] = PlasmaExit(exitor, rootToken, exitAmountOrTokenId, burnt);
    PlasmaExit storage _exitObject = exits[priority];

    bytes32 key;
    if (registry.isERC721(_exitObject.token)) {
      key = keccak256(abi.encodePacked(_exitObject.token, _exitObject.owner, _exitObject.receiptAmountOrNFTId));
    } else {
      // validate amount
      require(_exitObject.receiptAmountOrNFTId > 0, "CANNOT_EXIT_ZERO_AMOUNTS");
      key = keccak256(abi.encodePacked(_exitObject.token, _exitObject.owner));
    }
    // validate token exit
    require(ownerExits[key] == 0, "EXIT_ALREADY_IN_PROGRESS");

    // Calculate priority.
    uint256 exitableAt = Math.max(now + 2 weeks, block.timestamp + 1 weeks);

    PriorityQueue queue = PriorityQueue(exitsQueues[_exitObject.token]);
    queue.insert(exitableAt, priority);

    // create NFT for exit UTXO
    // @todo
    ExitNFT(exitNFTContract).mint(_exitObject.owner, priority);
    exits[priority] = _exitObject;

    // set current exit
    ownerExits[key] = priority;

    // emit exit started event
    emit ExitStarted(_exitObject.owner, priority, _exitObject.token, _exitObject.receiptAmountOrNFTId);
  }

  function deleteExit(uint256 exitId) external isProofValidator {
    ExitNFT exitNFT = ExitNFT(exitNFTContract);
    address owner = exitNFT.ownerOf(exitId);
    exitNFT.burn(owner, exitId);
  }

  function processExits(address _token) external {
    uint256 exitableAt;
    uint256 utxoPos;

    // retrieve priority queue
    PriorityQueue exitQueue = PriorityQueue(exitsQueues[_token]);

    // Iterate while the queue is not empty.
    while (exitQueue.currentSize() > 0 && gasleft() > gasLimit ) {
      (exitableAt, utxoPos) = exitQueue.getMin();

      // Check if this exit has finished its challenge period.
      if (exitableAt > block.timestamp) {
        return;
      }

      // get withdraw block
      PlasmaExit memory currentExit = exits[utxoPos];

      // process if NFT exists
      // If an exit was successfully challenged, owner would be address(0).
      address payable exitOwner = address(uint160(ExitNFT(exitNFTContract).ownerOf(utxoPos)));
      if (exitOwner != address(0)) {
        // burn NFT first
        ExitNFT(exitNFTContract).burn(exitOwner, utxoPos);

        // delete current exit if exit was "burnt"
        if (currentExit.burnt) {
          delete ownerExits[keccak256(abi.encodePacked(_token, currentExit.owner))];
        }

        address depositManager = registry.getDepositManagerAddress(); // TODO: make assembly call and reuse memPtr
        uint256 amount = currentExit.receiptAmountOrNFTId;
        uint256 _gas = gasLimit - 52000; // sub fixed processExit cost , ::=> can't read global vars in asm
        assembly {
          let ptr := mload(64)
          // keccak256('transferAmount(address,address,uint256)') & 0xFFFFFFFF00000000000000000000000000000000000000000000000000000000
          mstore(ptr, 0x01f4747100000000000000000000000000000000000000000000000000000000)
          mstore(add(ptr, 4), _token)
          mstore(add(ptr, 36), exitOwner)
          mstore(add(ptr, 68), amount) // TODO: read directly from struct
          let ret := add(ptr,100)
          let result := call(_gas, depositManager, 0, ptr, 100, ret, 32) // returns 1 if success
          // revert if => result is 0 or return value is false
          if eq(and(result,mload(ret)), 0) {
              revert(0,0)
            }
        }

        // broadcast withdraw events
        emit Withdraw(exitOwner, _token, currentExit.receiptAmountOrNFTId);

        // Delete owner but keep amount to prevent another exit from the same UTXO.
        // delete exits[utxoPos].owner;
      }

      // exit queue
      exitQueue.delMin();
    }
  }

    // Exit NFT
  function setExitNFTContract(address _nftContract) external onlyOwner {
    require(_nftContract != address(0));
    exitNFTContract = _nftContract;
  }

  function getExitId(address _token, address _owner, uint256 _tokenId) public view returns (uint256) {
    if (registry.isERC721(_token)) {
      return ownerExits[keccak256(abi.encodePacked(_token, _owner, _tokenId))];
    }
    return ownerExits[keccak256(abi.encodePacked(_token, _owner))];
  }
}
