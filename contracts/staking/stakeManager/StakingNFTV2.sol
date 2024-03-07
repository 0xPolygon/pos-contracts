pragma solidity 0.5.17;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721Full.sol";
import {Ownable} from "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import {IStakingNFT} from "./IStakingNFT.sol";

contract StakingNFTV2 is IStakingNFT, ERC721Full, Ownable {
    constructor(string memory name, string memory symbol)
        public
        ERC721Full(name, symbol)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    function mint(address to, uint256 tokenId) public onlyOwner {
        require(
            balanceOf(to) == 0,
            "Validators MUST NOT own multiple stake position"
        );
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) public onlyOwner {
        _burn(tokenId);
    }

    function _transferFrom(address, address, uint256) internal {
        revert("non transferable");
    }
}
