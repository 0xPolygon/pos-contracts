// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.5.17;

import {IERC721Full} from "openzeppelin-solidity/contracts/token/ERC721/IERC721Full.sol";

contract IStakingNFT is IERC721Full {
    function mint(address to, uint256 tokenId) external;
    function burn(uint256 tokenId) external;
}
