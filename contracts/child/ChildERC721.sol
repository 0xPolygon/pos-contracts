pragma solidity ^0.5.2;

import { ERC721Full } from "openzeppelin-solidity/contracts/token/ERC721/ERC721Full.sol";

import "./ChildToken.sol";
import "./misc/IParentToken.sol";
import "./misc/LibTokenTransferOrder.sol";


contract ChildERC721 is ChildToken, LibTokenTransferOrder, ERC721Full {

  event LogTransfer(
    address indexed token,
    address indexed from,
    address indexed to,
    uint256 amountOrTokenId
  );

  // constructor
  constructor (address _owner, address _token, string memory name, string memory symbol) ERC721Full(name, symbol)
    public
    {
    require(_token != address(0x0) && _owner != address(0x0));
    parentOwner = _owner;
    token = _token;
  }

  function setParent(address _parent) public isParentOwner {
    require(_parent != address(0x0));
    parent = _parent;
  }

  /**
   * Deposit tokens
   *
   * @param user address for address
   * @param tokenId token balance
   */
  function deposit(address user, uint256 tokenId) public onlyOwner {
    // check for amount and user
    require(user != address(0x0));
    uint256 input = balanceOf(user);

    _mint(user, tokenId);

    // deposit event
    emit Deposit(token, user, tokenId, input, balanceOf(user));
  }

  /**
   * Withdraw tokens
   *
   * @param tokenId tokens
   */
  function withdraw(uint256 tokenId) public {
    require(ownerOf(tokenId) == msg.sender);

    address user = msg.sender;
    uint256 input1 = balanceOf(user);

    _burn(user, tokenId);

    // withdraw event
    emit Withdraw(token, user, tokenId, input1, balanceOf(user));
  }

  function transferFrom(address from, address to, uint256 tokenId) public {
    if (parent != address(0x0) && !IParentToken(parent).afterTransfer(msg.sender, to, tokenId)) {
      return;
    }
    // actual transfer
    super.transferFrom(from, to, tokenId);

    // log balance
    emit LogTransfer(
      token,
      from,
      to,
      tokenId
    );
  }

  function transferWithSig(bytes memory sig, uint256 tokenId, bytes32 data, uint256 expiration, address to) public returns (address) {
    require(expiration == 0 || block.number <= expiration, "Signature is expired");

    bytes32 dataHash = getTokenTransferOrderHash(
      msg.sender,
      tokenId,
      data,
      expiration
    );
    require(disabledHashes[dataHash] == false, "Sig deactivated");
    disabledHashes[dataHash] = true;

    // recover address and send tokens
    address from = dataHash.ecrecovery(sig);

    // safeTransferFrom
    _transferFrom(from, to, tokenId);
    require(_checkOnERC721Received(from, to, tokenId, ""));

    return from;
  }

}
