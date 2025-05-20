// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NFTStaking
 * @dev A contract for staking NFTs and tracking staking time for off-chain rewards
 */
contract NFTStaking is ERC721Holder, Ownable, Pausable, ReentrancyGuard {
    // Structure to store staking info
    struct Stake {
        address owner;
        uint256 stakedAt;
        bool isStaked;
    }
    
    // OpenSea NFT contract address
    IERC721 public nftContract;
    
    // Mapping from token ID to its stake info
    mapping(uint256 => Stake) public stakes;
    
    // Mapping to track all tokens staked by an address
    mapping(address => uint256[]) public stakedTokensByUser;
    
    // Mapping to track index of token in user's array for O(1) removal
    mapping(address => mapping(uint256 => uint256)) private tokenToIndex;
    
    // Track staking stats counters
    uint256 public totalStakedCount;
    uint256 public uniqueStakersCount;
    mapping(address => bool) private isStaker;
    
    // Events
    event Staked(address indexed owner, uint256 tokenId, uint256 timestamp);
    event Unstaked(address indexed owner, uint256 tokenId, uint256 timestamp, uint256 stakedDuration);
    event ContractPaused(address admin);
    event ContractUnpaused(address admin);
    
    /**
     * @dev Constructor sets the NFT contract address and transfers ownership
     * @param _nftContract Address of the NFT contract (from OpenSea factory)
     * @param _owner Initial owner of the staking contract
     */
    constructor(address _nftContract, address _owner) Ownable(_owner) {
        require(_nftContract != address(0), "NFT contract address cannot be zero");
        require(_owner != address(0), "Owner address cannot be zero");
        nftContract = IERC721(_nftContract);
    }
    
    /**
     * @dev Stake a single NFT - transfers the NFT to this contract and records staking time
     * @param _tokenId Token ID of the NFT to stake
     */
    function stake(uint256 _tokenId) external whenNotPaused nonReentrant {
        _stake(msg.sender, _tokenId);
    }
    
    /**
     * @dev Stake multiple NFTs at once - more gas efficient
     * @param _tokenIds Array of token IDs to stake
     */
    function batchStake(uint256[] calldata _tokenIds) external whenNotPaused nonReentrant {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _stake(msg.sender, _tokenIds[i]);
        }
    }
    
    /**
     * @dev Internal function to handle staking logic
     * @param _owner Address of the token owner
     * @param _tokenId Token ID to stake
     */
    function _stake(address _owner, uint256 _tokenId) internal {
        // Ensure the token is not already staked
        require(!stakes[_tokenId].isStaked, "Token is already staked");
        
        // Transfer the NFT to this contract
        nftContract.safeTransferFrom(_owner, address(this), _tokenId);
        
        // Record stake details
        stakes[_tokenId] = Stake({
            owner: _owner,
            stakedAt: block.timestamp,
            isStaked: true
        });
        
        // Add to user's staked tokens list
        stakedTokensByUser[_owner].push(_tokenId);
        
        // Store the index of the token in the user's array for O(1) removal
        tokenToIndex[_owner][_tokenId] = stakedTokensByUser[_owner].length - 1;
        
        // Update staking stats
        totalStakedCount++;
        if (!isStaker[_owner]) {
            isStaker[_owner] = true;
            uniqueStakersCount++;
        }
        
        // Emit staking event
        emit Staked(_owner, _tokenId, block.timestamp);
    }
    
    /**
     * @dev Unstake a single NFT - returns the NFT to the owner and records duration
     * @param _tokenId Token ID of the NFT to unstake
     */
    function unstake(uint256 _tokenId) external nonReentrant {
        _unstake(msg.sender, _tokenId);
    }
    
    /**
     * @dev Unstake multiple NFTs at once - more gas efficient
     * @param _tokenIds Array of token IDs to unstake
     */
    function batchUnstake(uint256[] calldata _tokenIds) external nonReentrant {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _unstake(msg.sender, _tokenIds[i]);
        }
    }
    
    /**
     * @dev Internal function to handle unstaking logic
     * @param _owner Address of the token owner
     * @param _tokenId Token ID to unstake
     */
    function _unstake(address _owner, uint256 _tokenId) internal {
        // Ensure the token is staked and belongs to the sender
        require(stakes[_tokenId].isStaked, "Token is not staked");
        require(stakes[_tokenId].owner == _owner, "You don't own this token");
        
        // Calculate staking duration
        uint256 stakingDuration = block.timestamp - stakes[_tokenId].stakedAt;
        
        // Update state before external calls (prevent reentrancy)
        // Remove from user's staked tokens list
        _removeTokenFromUserList(_owner, _tokenId);
        
        // Update stake info
        stakes[_tokenId].isStaked = false;
        
        // Update staking stats
        totalStakedCount--;
        if (stakedTokensByUser[_owner].length == 0) {
            isStaker[_owner] = false;
            uniqueStakersCount--;
        }
        
        // Transfer the NFT back to the owner (after state changes)
        nftContract.safeTransferFrom(address(this), _owner, _tokenId);
        
        // Emit unstaking event with duration
        emit Unstaked(_owner, _tokenId, block.timestamp, stakingDuration);
    }
    
    /**
     * @dev Helper function to remove a token from a user's staked tokens list (O(1) removal)
     * @param _user Address of the user
     * @param _tokenId Token ID to remove
     */
    function _removeTokenFromUserList(address _user, uint256 _tokenId) internal {
        uint256[] storage userTokens = stakedTokensByUser[_user];
        uint256 index = tokenToIndex[_user][_tokenId];
        uint256 lastIndex = userTokens.length - 1;
        
        if (index != lastIndex) {
            // Move the last element to the position being deleted
            uint256 lastTokenId = userTokens[lastIndex];
            userTokens[index] = lastTokenId;
            
            // Update the index for the moved token
            tokenToIndex[_user][lastTokenId] = index;
        }
        
        // Remove the last element
        userTokens.pop();
        
        // Delete the mapping entry for the removed token
        delete tokenToIndex[_user][_tokenId];
    }
    
    /**
     * @dev Get all staked tokens by a specific user
     * @param _user Address of the user
     * @return Array of token IDs staked by the user
     */
    function getStakedTokensByUser(address _user) external view returns (uint256[] memory) {
        return stakedTokensByUser[_user];
    }
    
    /**
     * @dev Get staking stats for the contract
     * @return totalStaked Total number of NFTs currently staked
     * @return uniqueStakers Number of unique addresses staking
     */
    function getStakingStats() external view returns (uint256 totalStaked, uint256 uniqueStakers) {
        return (totalStakedCount, uniqueStakersCount);
    }
    
    /**
     * @dev Calculate total staking time for a user across all their NFTs
     * @param _user Address of the user
     * @return totalTime Combined staking time in seconds
     * @return activeTokens Number of currently staked tokens
     */
    function getUserTotalStakingTime(address _user) external view returns (uint256 totalTime, uint256 activeTokens) {
        uint256[] memory tokens = stakedTokensByUser[_user];
        
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenId = tokens[i];
            if (stakes[tokenId].isStaked && stakes[tokenId].owner == _user) {
                activeTokens++;
                totalTime += (block.timestamp - stakes[tokenId].stakedAt);
            }
        }
    }
    
    /**
     * @dev Pause the contract in case of emergency
     */
    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }
    
    /**
     * @dev Unpause the contract to resume operations
     */
    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }
}