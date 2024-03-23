pragma solidity ^0.8.0;

import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/access/Ownable.sol";

/**
 * @title MockNFT
 * @dev A mock non-fungible token contract for testing purposes.
 */
contract MockNFT is ERC721, Ownable {
    // Next token id to be minted.
    uint256 private _nextTokenId;

    /**
     * @dev Constructor.
     * @param initialOwner The owner of the contract.
     */
    constructor(
        address initialOwner
    ) ERC721("MockNFT", "MNFT") Ownable(initialOwner) {}

    /**
     * @dev Mints a token for the given address.
     * @param to The address to mint the token for.
     */
    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }
}
