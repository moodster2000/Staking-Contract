// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/NFTStaking.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

contract NFTStakingTest is Test {
    NFTStaking public stakingContract;
    MockERC721 public mockNFT;
    
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    uint256[] public tokenIds;
    
    event Staked(address indexed owner, uint256 tokenId, uint256 timestamp);
    event Unstaked(address indexed owner, uint256 tokenId, uint256 timestamp, uint256 stakedDuration);
    event EmergencyUnstaked(address indexed owner, uint256 tokenId, uint256 timestamp);
    event ContractPaused(address admin);
    event ContractUnpaused(address admin);
    
    function setUp() public {
        // Deploy mock NFT contract
        mockNFT = new MockERC721("MockNFT", "MNFT");
        
        // Deploy staking contract with owner as the contract owner
        vm.prank(owner);
        stakingContract = new NFTStaking(address(mockNFT), owner);
        
        // Mint some NFTs to user1
        for (uint256 i = 1; i <= 5; i++) {
            mockNFT.mint(user1, i);
            tokenIds.push(i);
        }
        
        // Mint some NFTs to user2
        for (uint256 i = 6; i <= 10; i++) {
            mockNFT.mint(user2, i);
            tokenIds.push(i);
        }
        
        // Approve staking contract for all users
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(stakingContract), true);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockNFT.setApprovalForAll(address(stakingContract), true);
        vm.stopPrank();
    }
    
    function testConstructor() public {
        assertEq(address(stakingContract.nftContract()), address(mockNFT));
        assertEq(stakingContract.owner(), owner);
    }
    
    function testStakingSingleNFT() public {
        uint256 tokenId = 1;
        
        vm.startPrank(user1);
        
        // Expect the Staked event to be emitted
        vm.expectEmit(true, true, false, true);
        emit Staked(user1, tokenId, block.timestamp);
        
        // Stake NFT
        stakingContract.stake(tokenId);
        
        // Check NFT ownership transferred to staking contract
        assertEq(mockNFT.ownerOf(tokenId), address(stakingContract));
        
        // Check stake info directly using the public stakes mapping
        (address stakeOwner, uint256 tokenIdFromContract, uint256 stakedAt, bool isStaked) = 
            stakingContract.stakes(tokenId);
            
        assertEq(stakeOwner, user1);
        assertEq(tokenIdFromContract, tokenId);
        assertEq(stakedAt, block.timestamp);
        assertTrue(isStaked);
        
        // Check user's staked tokens list
        uint256[] memory userTokens = stakingContract.getStakedTokensByUser(user1);
        assertEq(userTokens.length, 1);
        assertEq(userTokens[0], tokenId);
        
        vm.stopPrank();
    }
    
    function testBatchStaking() public {
        uint256[] memory tokensToStake = new uint256[](3);
        tokensToStake[0] = 1;
        tokensToStake[1] = 2;
        tokensToStake[2] = 3;
        
        vm.startPrank(user1);
        
        // Batch stake NFTs
        stakingContract.batchStake(tokensToStake);
        
        // Check NFT ownerships
        for (uint256 i = 0; i < tokensToStake.length; i++) {
            assertEq(mockNFT.ownerOf(tokensToStake[i]), address(stakingContract));
        }
        
        // Check user's staked tokens list
        uint256[] memory userTokens = stakingContract.getStakedTokensByUser(user1);
        assertEq(userTokens.length, tokensToStake.length);
        
        vm.stopPrank();
    }
    
    function testUnstakingSingleNFT() public {
        uint256 tokenId = 1;
        
        // First stake an NFT
        vm.startPrank(user1);
        stakingContract.stake(tokenId);
        vm.stopPrank();
        
        // Advance time by 1 day to simulate staking period
        skip(1 days);
        
        vm.startPrank(user1);
        
        // Expect the Unstaked event to be emitted with approximately 1 day duration
        vm.expectEmit(true, true, false, false); // We don't check the timestamp or duration
        emit Unstaked(user1, tokenId, block.timestamp, 1 days);
        
        // Unstake NFT
        stakingContract.unstake(tokenId);
        
        // Check NFT returned to owner
        assertEq(mockNFT.ownerOf(tokenId), user1);
        
        // Check stake info is updated to not staked
        (,,,bool isStaked) = stakingContract.stakes(tokenId);
        assertFalse(isStaked);
        
        // Check token removed from user's staked tokens list
        uint256[] memory userTokens = stakingContract.getStakedTokensByUser(user1);
        assertEq(userTokens.length, 0);
        
        vm.stopPrank();
    }
    
    function testBatchUnstaking() public {
        uint256[] memory tokensToStake = new uint256[](3);
        tokensToStake[0] = 1;
        tokensToStake[1] = 2;
        tokensToStake[2] = 3;
        
        // First stake NFTs
        vm.startPrank(user1);
        stakingContract.batchStake(tokensToStake);
        vm.stopPrank();
        
        // Advance time
        skip(2 days);
        
        vm.startPrank(user1);
        
        // Batch unstake NFTs
        stakingContract.batchUnstake(tokensToStake);
        
        // Check NFTs returned to owner
        for (uint256 i = 0; i < tokensToStake.length; i++) {
            assertEq(mockNFT.ownerOf(tokensToStake[i]), user1);
        }
        
        // Check user's staked tokens list
        uint256[] memory userTokens = stakingContract.getStakedTokensByUser(user1);
        assertEq(userTokens.length, 0);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_UnstakingUnauthorized() public {
        uint256 tokenId = 1;
        
        // First stake an NFT as user1
        vm.startPrank(user1);
        stakingContract.stake(tokenId);
        vm.stopPrank();
        
        // Try to unstake as user2 (should revert)
        vm.startPrank(user2);
        vm.expectRevert("You don't own this token");
        stakingContract.unstake(tokenId);
        vm.stopPrank();
    }
    
    function test_RevertWhen_StakingAlreadyStaked() public {
        uint256 tokenId = 1;
        
        // First stake an NFT
        vm.startPrank(user1);
        stakingContract.stake(tokenId);
        
        // Try to stake again (should revert)
        vm.expectRevert("Token is already staked");
        stakingContract.stake(tokenId);
        vm.stopPrank();
    }
    
    function testPauseAndUnpause() public {
        vm.startPrank(owner);
        
        // Pause contract
        vm.expectEmit(true, false, false, true);
        emit ContractPaused(owner);
        stakingContract.pause();
        
        // Unpause contract
        vm.expectEmit(true, false, false, true);
        emit ContractUnpaused(owner);
        stakingContract.unpause();
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_StakingWhenPaused() public {
        // Pause the contract
        vm.prank(owner);
        stakingContract.pause();
        
        // Try to stake (should revert)
        vm.startPrank(user1);
        vm.expectRevert();
        stakingContract.stake(1);
        vm.stopPrank();
    }
    
    function testUpdateNftContract() public {
        address newNftAddress = address(0x123);
        
        vm.startPrank(owner);
        stakingContract.updateNftContract(newNftAddress);
        vm.stopPrank();
        
        assertEq(address(stakingContract.nftContract()), newNftAddress);
    }
    
    function test_RevertWhen_UpdateNftContractUnauthorized() public {
        address newNftAddress = address(0x123);
        
        // Try to update NFT contract as non-owner (should revert)
        vm.startPrank(user1);
        vm.expectRevert();
        stakingContract.updateNftContract(newNftAddress);
        vm.stopPrank();
    }
    
    function testGetStakingStats() public {
        // Stake some NFTs from different users
        vm.startPrank(user1);
        stakingContract.stake(1);
        stakingContract.stake(2);
        vm.stopPrank();
        
        vm.startPrank(user2);
        stakingContract.stake(6);
        vm.stopPrank();
        
        // Get staking stats
        (uint256 totalStaked, uint256 uniqueStakers) = stakingContract.getStakingStats();
        
        assertEq(totalStaked, 3);
        assertEq(uniqueStakers, 2);
    }
    
    function testGetUserTotalStakingTime() public {
        // Stake NFTs as user1
        vm.startPrank(user1);
        stakingContract.stake(1);
        stakingContract.stake(2);
        vm.stopPrank();
        
        // Advance time
        skip(2 days);
        
        // Check total staking time
        (uint256 totalTime, uint256 activeTokens) = stakingContract.getUserTotalStakingTime(user1);
        
        assertEq(activeTokens, 2);
        assertApproxEqAbs(totalTime, 2 days * 2, 10); // Allow small deviation due to block timing
    }
    
    function testStakeInfoForMultipleTokens() public {
        uint256[] memory tokensToStake = new uint256[](3);
        tokensToStake[0] = 1;
        tokensToStake[1] = 2;
        tokensToStake[2] = 3;
        
        // Stake NFTs
        vm.startPrank(user1);
        stakingContract.batchStake(tokensToStake);
        vm.stopPrank();
        
        // Check each stake individually using the public mapping
        for (uint256 i = 0; i < tokensToStake.length; i++) {
            (address owner, uint256 tokenId, uint256 stakedAt, bool isStaked) = 
                stakingContract.stakes(tokensToStake[i]);
                
            assertEq(owner, user1);
            assertEq(tokenId, tokensToStake[i]);
            assertTrue(isStaked);
            assertEq(stakedAt, block.timestamp);
        }
    }
}