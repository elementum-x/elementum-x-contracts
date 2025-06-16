// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/core/Vault.sol";
import "../src/core/Router.sol";
import "../src/core/PositionManager.sol";
import "../src/core/Position721.sol";

contract HybridPositionTest is Test {
    Vault vault;
    Router router;
    PositionManager positionManager;
    Position721 positionNFT;
    
    address user = address(0x123);
    address collateralToken = address(0x456);
    address indexToken = address(0x789);

    function setUp() public {
        // Deploy contracts in correct order
        vault = new Vault();
        router = new Router(address(vault));
        positionNFT = new Position721(address(vault));
        positionManager = new PositionManager(address(vault), address(positionNFT));
        
        // Initialize
        vault.initialize(address(positionManager));
        positionNFT.setAuthorizedManager(address(positionManager), true);
        vault.setPrice(indexToken, 50000 * 10**30);
    }

    function testCreateStandardPosition() public {
        vm.prank(user);
        (uint256 positionId, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10**30, // $1000 size
            true,          // long
            PositionManager.PositionType.STANDARD,
            0,             // no expiry
            0              // no protection
        );
        
        // Check hybrid position data
        PositionManager.HybridPosition memory pos = positionManager.getHybridPosition(positionId);
        assertEq(pos.account, user);
        assertEq(uint256(pos.positionType), uint256(PositionManager.PositionType.STANDARD));
        assertEq(pos.expiryTime, 0);
        assertTrue(pos.isActive);
        
        // Check NFT was minted
        assertEq(positionNFT.ownerOf(tokenId), user);
        assertEq(positionNFT.totalSupply(), 1);
        
        // Check underlying vault position
        (uint256 size, uint256 collateral,,,,,, ) = vault.getPosition(
            user,
            collateralToken,
            indexToken,
            true
        );
        assertEq(size, 1000 * 10**30);
        assertGt(collateral, 0);
    }

    function testCreateExpiringPosition() public {
        vm.prank(user);
        (uint256 positionId, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10**30,
            true,
            PositionManager.PositionType.EXPIRING,
            30,            // 30 days expiry
            0
        );
        
        PositionManager.HybridPosition memory pos = positionManager.getHybridPosition(positionId);
        assertEq(pos.expiryTime, block.timestamp + 30 days);
        
        // Check NFT has expiry data
        (,,,, uint256 posType) = positionNFT.getPositionBasicInfo(tokenId);
        assertEq(posType, uint256(PositionManager.PositionType.EXPIRING));
        
        // Fast forward time
        vm.warp(block.timestamp + 31 days);
        assertTrue(positionManager.checkExpiry(positionId));
        
        // Check NFT shows expired
        (,,,bool isExpired,) = positionNFT.getPositionForLending(tokenId);
        assertTrue(isExpired);
    }

    function testProtectedPosition() public {
        uint256 currentPrice = 50000 * 10**30;
        uint256 protectionStrike = 45000 * 10**30; // 10% below current
        
        vm.prank(user);
        (uint256 positionId, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10**30,
            true,
            PositionManager.PositionType.PROTECTED,
            0,
            protectionStrike
        );
        
        PositionManager.HybridPosition memory pos = positionManager.getHybridPosition(positionId);
        assertEq(pos.protectionStrike, protectionStrike);
        
        // Check NFT has protection data
        (,,,, uint256 posType) = positionNFT.getPositionBasicInfo(tokenId);
        assertEq(posType, uint256(PositionManager.PositionType.PROTECTED));
    }

    function testFundedPosition() public {
        vm.prank(user);
        (uint256 positionId, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10**30,
            true,
            PositionManager.PositionType.FUNDED,
            0,
            0
        );
        
        PositionManager.HybridPosition memory pos = positionManager.getHybridPosition(positionId);
        assertEq(uint256(pos.positionType), uint256(PositionManager.PositionType.FUNDED));
        
        // Check NFT
        (,,,, uint256 posType) = positionNFT.getPositionBasicInfo(tokenId);
        assertEq(posType, uint256(PositionManager.PositionType.FUNDED));
    }

    function testNFTMetadata() public {
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10**30,
            true,
            PositionManager.PositionType.PROTECTED,
            30, // 30 days
            45000 * 10**30
        );
        
        // Check tokenURI doesn't revert
        string memory uri = positionNFT.tokenURI(tokenId);
        assertGt(bytes(uri).length, 0);
        
        // Should contain position info
        assertTrue(bytes(uri).length > 100); // Basic check that it's not empty
    }

    function testMultiplePositions() public {
        address user2 = address(0x456);
        
        // User 1 creates position
        vm.prank(user);
        (, uint256 tokenId1) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        // User 2 creates position
        vm.prank(user2);
        (, uint256 tokenId2) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            2000 * 10**30,
            false, // short position
            PositionManager.PositionType.EXPIRING,
            60, // 60 days
            0
        );
        
        // Check both NFTs exist
        assertEq(positionNFT.ownerOf(tokenId1), user);
        assertEq(positionNFT.ownerOf(tokenId2), user2);
        assertEq(positionNFT.totalSupply(), 2);
        
        // Check they have different position data
        (,,,bool isLong1,) = positionNFT.getPositionBasicInfo(tokenId1);
        (,,,bool isLong2,) = positionNFT.getPositionBasicInfo(tokenId2);
        
        assertTrue(isLong1);   // First position is long
        assertFalse(isLong2);  // Second position is short
    }
}