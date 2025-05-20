// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title MockERC721
 * @dev Simple ERC721 mock for testing
 */
contract MockERC721 is ERC721 {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}
    
    /**
     * @dev Mint a new token - for testing only
     */
    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}