pragma solidity ^0.4.24;


contract TokenManager {
  // mapping for (root token => child token)
  mapping(address => address) public tokens;

  // mapping for (child token => root token)
  mapping(address => address) public reverseTokens;

  // mapping whether a token is erc721 or not
  mapping(address => bool) public isERC721;

  // weth token
  address public wethToken;

  //
  // Events
  //

  event TokenMapped(address indexed _rootToken, address indexed _childToken);

  //
  // Internal methods
  //

  /**
   * @dev Checks if token is mapped
   */
  function _isTokenMapped(address _token) internal view returns (bool) {
    return _token != address(0x0) && tokens[_token] != address(0x0);
  }

  /**
   * @dev Map root token to child token
   */
  function _mapToken(address _rootToken, address _childToken, bool _isERC721) internal {
    // throw if token is already mapped
    require(!_isTokenMapped(_rootToken));

    // map token
    tokens[_rootToken] = _childToken;
    reverseTokens[_childToken] = _rootToken;

    isERC721[_rootToken] = _isERC721;

    // emit token mapped event
    emit TokenMapped(_rootToken, _childToken);
  }
}
