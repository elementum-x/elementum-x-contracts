// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../src/core/Vault.sol";
import "../src/core/PositionManager.sol";
import "../src/core/Position721.sol";
import "../src/core/LiquidationEngine.sol";

contract LiquidationEngineTest is Test {
    Vault vault;
    PositionManager positionManager;
    Position721 positionNFT;
    LiquidationEngine liquidationEngine;

    address user = address(0x123);
    address user2 = address(0x124);
    address user3 = address(0x125);
    address liquidator = address(0x456);
    address nonKeeper = address(0x789);
    address collateralToken = address(0x789);
    address indexToken = address(0xABC);

    event PositionLiquidated(
        uint256 indexed tokenId,
        address indexed liquidator,
        address indexed positionOwner,
        uint256 liquidationReward,
        string reason
    );
    
    event KeeperAdded(address indexed keeper);
    event KeeperRemoved(address indexed keeper);
    event LiquidationThresholdUpdated(uint256 positionType, uint256 threshold);

    function setUp() public {
        console.log("=== Setting up test ===");

        vault = new Vault();
        console.log("Vault deployed at:", address(vault));

        positionNFT = new Position721(address(vault));
        console.log("Position721 deployed at:", address(positionNFT));

        positionManager = new PositionManager(
            address(vault),
            address(positionNFT)
        );
        console.log("PositionManager deployed at:", address(positionManager));

        liquidationEngine = new LiquidationEngine(
            address(vault),
            address(positionNFT),
            address(positionManager)
        );
        console.log(
            "LiquidationEngine deployed at:",
            address(liquidationEngine)
        );

        // Initialize vault
        vault.initialize(address(positionManager));
        console.log("Vault initialized with PositionManager");

        // Authorize both PositionManager and LiquidationEngine for NFT operations
        positionNFT.setAuthorizedManager(address(positionManager), true);
        positionNFT.setAuthorizedManager(address(liquidationEngine), true);
        console.log("Authorized managers set");

        // Set liquidation engine in vault
        vault.setLiquidationEngine(address(liquidationEngine));
        console.log("LiquidationEngine set in Vault");

        // Set initial price
        vault.setPrice(indexToken, 50000 * 10 ** 30);
        console.log("Initial price set: 50000");

        // Set liquidator as keeper
        liquidationEngine.setKeeper(liquidator, true);
        console.log("Liquidator set as keeper");

        console.log("=== Setup complete ===\n");
    }

    // ============ ACCESS CONTROL TESTS ============

    function testSetKeeperOnlyOwner() public {
        console.log("=== Test: Set Keeper Only Owner ===");
        
        // Non-owner cannot set keeper
        vm.prank(nonKeeper);
        vm.expectRevert();
        liquidationEngine.setKeeper(nonKeeper, true);
        
        // Owner can set keeper
        liquidationEngine.setKeeper(nonKeeper, true);
        assertTrue(liquidationEngine.isKeeper(nonKeeper));
        
        // Check event emission
        vm.expectEmit(true, false, false, false);
        emit KeeperAdded(user);
        liquidationEngine.setKeeper(user, true);
        
        // Remove keeper
        vm.expectEmit(true, false, false, false);
        emit KeeperRemoved(user);
        liquidationEngine.setKeeper(user, false);
        assertFalse(liquidationEngine.isKeeper(user));
    }

    function testSetLiquidationThresholdOnlyOwner() public {
        console.log("=== Test: Set Liquidation Threshold Only Owner ===");
        
        // Non-owner cannot set threshold
        vm.prank(nonKeeper);
        vm.expectRevert();
        liquidationEngine.setLiquidationThreshold(0, 300);
        
        // Owner can set threshold
        vm.expectEmit(false, false, false, true);
        emit LiquidationThresholdUpdated(0, 300);
        liquidationEngine.setLiquidationThreshold(0, 300);
        
        // Check threshold was set
        assertEq(liquidationEngine.liquidationThresholds(0), 300);
        
        // Cannot set threshold too high
        vm.expectRevert("Threshold too high");
        liquidationEngine.setLiquidationThreshold(0, 1001);
    }

    function testLiquidatePositionOnlyKeeper() public {
        console.log("=== Test: Liquidate Position Only Keeper ===");
        
        // Create liquidatable position
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        // Make position liquidatable
        vault.setPrice(indexToken, 25000 * 10**30);
        
        // Non-keeper cannot liquidate
        vm.prank(nonKeeper);
        vm.expectRevert("Not authorized");
        liquidationEngine.liquidatePosition(tokenId);
        
        // Keeper can liquidate
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(tokenId);
        
        // Check NFT was burned
        vm.expectRevert();
        positionNFT.ownerOf(tokenId);
    }

    function testOwnerCanLiquidateWithoutKeeper() public {
        console.log("=== Test: Owner Can Liquidate Without Keeper ===");
        
        // Create liquidatable position
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        // Make position liquidatable
        vault.setPrice(indexToken, 25000 * 10**30);
        
        // Owner can liquidate even without being a keeper
        liquidationEngine.liquidatePosition(tokenId);
        
        // Check NFT was burned
        vm.expectRevert();
        positionNFT.ownerOf(tokenId);
    }

    // ============ LIQUIDATION LOGIC TESTS ============

    function testLiquidateUnhealthyPosition() public {
        console.log("=== Test: Liquidate Unhealthy Position ===");

        // Create a position
        console.log("Creating position for user:", user);
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10 ** 30, // $1000 position
            true, // long
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        console.log("Position created with tokenId:", tokenId);

        // Check initial position health
        (bool canLiquidateInitial, string memory reasonInitial) = liquidationEngine.canLiquidatePosition(tokenId);
        console.log("Can liquidate initially:", canLiquidateInitial);
        console.log("Initial reason:", reasonInitial);

        // Crash the price to make position liquidatable
        console.log("Crashing price from 50000 to 25000...");
        vault.setPrice(indexToken, 25000 * 10 ** 30); // 50% drop

        // Check if position can be liquidated
        (bool canLiquidate, string memory reason) = liquidationEngine.canLiquidatePosition(tokenId);
        console.log("Can liquidate after price drop:", canLiquidate);
        console.log("Reason:", reason);
        assertTrue(canLiquidate, "Position should be liquidatable after price crash");

        // Check event emission
        address positionOwner = positionNFT.ownerOf(tokenId);
        vm.expectEmit(true, true, true, false);
        emit PositionLiquidated(tokenId, liquidator, positionOwner, 0, reason);

        // Liquidate position
        console.log("Attempting liquidation...");
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(tokenId);
        console.log("Liquidation successful!");

        // Check position NFT was burned
        vm.expectRevert();
        positionNFT.ownerOf(tokenId);
        console.log("NFT successfully burned");
    }

    function testCannotLiquidateHealthyPosition() public {
        console.log("=== Test: Cannot Liquidate Healthy Position ===");

        // Create a position
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );

        // Price stays healthy (even improves)
        vault.setPrice(indexToken, 55000 * 10**30);

        // Check position cannot be liquidated
        (bool canLiquidate, string memory reason) = liquidationEngine.canLiquidatePosition(tokenId);
        assertFalse(canLiquidate, "Healthy position should not be liquidatable");
        assertEq(reason, "Position healthy");

        // Attempt liquidation should fail
        vm.prank(liquidator);
        vm.expectRevert();
        liquidationEngine.liquidatePosition(tokenId);
    }

    function testLiquidateExpiredPosition() public {
        console.log("=== Test: Liquidate Expired Position ===");

        // Create expiring position
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.EXPIRING,
            1, // 1 day expiry
            0
        );

        // Check not expired initially
        (bool canLiquidateInitial, string memory reasonInitial) = liquidationEngine.canLiquidatePosition(tokenId);
        assertFalse(canLiquidateInitial);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);

        // Check position can be liquidated due to expiry
        (bool canLiquidate, string memory reason) = liquidationEngine.canLiquidatePosition(tokenId);
        assertTrue(canLiquidate, "Expired position should be liquidatable");
        assertEq(reason, "Position expired");

        // Liquidate expired position
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(tokenId);

        // Check NFT was burned
        vm.expectRevert();
        positionNFT.ownerOf(tokenId);
    }

    function testBatchLiquidation() public {
        console.log("=== Test: Batch Liquidation ===");
        
        uint256[] memory tokenIds = new uint256[](3);
        address[] memory users = new address[](3);
        users[0] = user;
        users[1] = user2;
        users[2] = user3;
        
        // Create multiple positions with different users
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            (, uint256 tokenId) = positionManager.createHybridPosition(
                collateralToken,
                indexToken,
                100 * 10**30,
                1000 * 10**30,
                true,
                PositionManager.PositionType.STANDARD,
                0,
                0
            );
            tokenIds[i] = tokenId;
        }
        
        // Crash price to make all positions liquidatable
        vault.setPrice(indexToken, 20000 * 10**30);
        
        // Check all can be liquidated
        for (uint256 i = 0; i < 3; i++) {
            (bool canLiquidate,) = liquidationEngine.canLiquidatePosition(tokenIds[i]);
            assertTrue(canLiquidate, "All positions should be liquidatable");
        }
        
        // Batch liquidate
        vm.prank(liquidator);
        liquidationEngine.liquidatePositions(tokenIds);
        
        // Check each NFT was burned
        for (uint256 i = 0; i < 3; i++) {
            vm.expectRevert();
            positionNFT.ownerOf(tokenIds[i]);
        }
    }

    function testLiquidateExpiredPositions() public {
        console.log("=== Test: Liquidate Expired Positions Function ===");
        
        uint256[] memory tokenIds = new uint256[](2);
        
        // Create expired positions
        vm.prank(user);
        (, uint256 tokenId1) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.EXPIRING,
            1, // 1 day expiry
            0
        );
        
        vm.prank(user2);
        (, uint256 tokenId2) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.EXPIRING,
            1, // 1 day expiry
            0
        );
        
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);
        
        // Liquidate expired positions
        vm.prank(liquidator);
        liquidationEngine.liquidateExpiredPositions(tokenIds);
        
        // Check both NFTs were burned
        vm.expectRevert();
        positionNFT.ownerOf(tokenId1);
        vm.expectRevert();
        positionNFT.ownerOf(tokenId2);
    }

    function testCannotLiquidateNonExistentPosition() public {
        console.log("=== Test: Cannot Liquidate Non-Existent Position ===");
        
        uint256 nonExistentTokenId = 999;
        
        (bool canLiquidate, string memory reason) = liquidationEngine.canLiquidatePosition(nonExistentTokenId);
        assertFalse(canLiquidate);
        assertEq(reason, "Position not found");
        
        vm.prank(liquidator);
        vm.expectRevert("Position not found");
        liquidationEngine.liquidatePosition(nonExistentTokenId);
    }

    function testCannotLiquidateAlreadyLiquidatedPosition() public {
        console.log("=== Test: Cannot Liquidate Already Liquidated Position ===");
        
        // Create and liquidate position
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        vault.setPrice(indexToken, 25000 * 10**30);
        
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(tokenId);
        
        // Try to liquidate again
        vm.prank(liquidator);
        vm.expectRevert("Position not found");
        liquidationEngine.liquidatePosition(tokenId);
    }

    function testBatchLiquidationWithNonExistentPositions() public {
        console.log("=== Test: Batch Liquidation With Non-Existent Positions ===");
        
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 999; // Non-existent
        tokenIds[1] = 998; // Non-existent
        tokenIds[2] = 997; // Non-existent
        
        // Should not revert, just skip non-existent positions
        vm.prank(liquidator);
        liquidationEngine.liquidatePositions(tokenIds);
    }

    function testBatchLiquidationWithMixedPositions() public {
        console.log("=== Test: Batch Liquidation With Mixed Positions ===");
        
        // Create one liquidatable position
        vm.prank(user);
        (, uint256 liquidatableTokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        // Create one healthy position
        vm.prank(user2);
        (, uint256 healthyTokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            500 * 10**30, // More collateral
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        // Make only first position liquidatable
        vault.setPrice(indexToken, 40000 * 10**30); // Moderate drop
        
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = liquidatableTokenId;
        tokenIds[1] = healthyTokenId;
        tokenIds[2] = 999; // Non-existent
        
        vm.prank(liquidator);
        liquidationEngine.liquidatePositions(tokenIds);
        
        // Check only liquidatable position was burned
        vm.expectRevert();
        positionNFT.ownerOf(liquidatableTokenId);
        
        // Healthy position should still exist
        address owner = positionNFT.ownerOf(healthyTokenId);
        assertEq(owner, user2);
    }

    function testBatchLiquidationGasLimit() public {
        console.log("=== Test: Batch Liquidation Gas Limit ===");
        
        uint256[] memory tokenIds = new uint256[](11); // One more than maxPositionsPerCall
        
        vm.prank(liquidator);
        vm.expectRevert("Too many positions");
        liquidationEngine.liquidatePositions(tokenIds);
    }

    function testGetLiquidationInfo() public {
        console.log("=== Test: Get Liquidation Info ===");
        
        // Create positions with different states
        vm.prank(user);
        (, uint256 healthyTokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            500 * 10**30, // High collateral
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        vm.prank(user2);
        (, uint256 unhealthyTokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30, // Low collateral
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        // Make one position unhealthy
        vault.setPrice(indexToken, 30000 * 10**30);
        
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = healthyTokenId;
        tokenIds[1] = unhealthyTokenId;
        tokenIds[2] = 999; // Non-existent
        
        LiquidationEngine.LiquidationInfo[] memory infos = liquidationEngine.getLiquidationInfo(tokenIds);
        
        assertEq(infos.length, 3);
        
        // Check healthy position
        assertEq(infos[0].tokenId, healthyTokenId);
        assertEq(infos[0].account, user);
        assertFalse(infos[0].canLiquidate);
        
        // Check unhealthy position
        assertEq(infos[1].tokenId, unhealthyTokenId);
        assertEq(infos[1].account, user2);
        assertTrue(infos[1].canLiquidate);
        
        // Non-existent position should have default values
        assertEq(infos[2].tokenId, 0);
        assertEq(infos[2].account, address(0));
    }

    function testLiquidationWithCustomThresholds() public {
        console.log("=== Test: Liquidation With Custom Thresholds ===");
        
        // Set very high threshold for STANDARD positions
        liquidationEngine.setLiquidationThreshold(0, 900); // 9%
        
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        // Moderate price drop that would normally not trigger liquidation
        vault.setPrice(indexToken, 45000 * 10**30); // 10% drop
        
        (bool canLiquidate, string memory reason) = liquidationEngine.canLiquidatePosition(tokenId);
        
        // With high threshold, position might be liquidatable
        // (depends on health ratio calculation in Position721)
        console.log("Can liquidate with high threshold:", canLiquidate);
        console.log("Reason:", reason);
    }

    function testLiquidationEventData() public {
        console.log("=== Test: Liquidation Event Data ===");
        
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        
        vault.setPrice(indexToken, 25000 * 10**30);
        
        // Check that event contains correct data
        vm.expectEmit(true, true, true, false);
        emit PositionLiquidated(tokenId, liquidator, user, 0, "Below liquidation threshold");
        
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(tokenId);
    }

    function testLiquidateExpiredPositionsFunction() public {
        console.log("=== Test: Liquidate Expired Positions Function ===");
        
        uint256[] memory tokenIds = new uint256[](2);
        
        // Create expired positions
        vm.prank(user);
        (, uint256 tokenId1) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.EXPIRING,
            1, // 1 day expiry
            0
        );
        
        vm.prank(user2);
        (, uint256 tokenId2) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            100 * 10**30,
            1000 * 10**30,
            true,
            PositionManager.PositionType.EXPIRING,
            1, // 1 day expiry
            0
        );
        
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);
        
        // Liquidate expired positions
        vm.prank(liquidator);
        liquidationEngine.liquidateExpiredPositions(tokenIds);
        
        // Check both NFTs were burned
        vm.expectRevert();
        positionNFT.ownerOf(tokenId1);
        vm.expectRevert();
        positionNFT.ownerOf(tokenId2);
    }
}
