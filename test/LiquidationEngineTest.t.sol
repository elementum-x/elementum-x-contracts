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
    address liquidator = address(0x456);
    address collateralToken = address(0x789);
    address indexToken = address(0xABC);

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

    function testLiquidateUnhealthyPosition() public {
        console.log("=== Test: Liquidate Unhealthy Position ===");

        // Create a position
        console.log("Creating position for user:", user);
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10 ** 30, // $1000 position
            true, // long
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        console.log("Position created with tokenId:", tokenId);
        console.log("Position owner:", positionNFT.ownerOf(tokenId));

        // Check initial position health
        (
            bool canLiquidateInitial,
            string memory reasonInitial
        ) = liquidationEngine.canLiquidatePosition(tokenId);
        console.log("Can liquidate initially:", canLiquidateInitial);
        console.log("Initial reason:", reasonInitial);

        // Crash the price to make position liquidatable
        console.log("Crashing price from 50000 to 25000...");
        vault.setPrice(indexToken, 25000 * 10 ** 30); // 50% drop

        // Check vault-level liquidation
        (
            address account,
            address collToken,
            address idxToken,
            bool isLong,

        ) = positionNFT.getPositionBasicInfo(tokenId);

        console.log("Position details:");
        console.log("  Account:", account);
        console.log("  CollateralToken:", collToken);
        console.log("  IndexToken:", idxToken);
        console.log("  IsLong:", isLong);

        bool vaultCanLiquidate = vault.canLiquidatePosition(
            account,
            collToken,
            idxToken,
            isLong
        );
        console.log("Vault says can liquidate:", vaultCanLiquidate);

        // Check position delta
        (bool hasProfit, uint256 delta) = vault.getPositionDelta(
            account,
            collToken,
            idxToken,
            isLong
        );
        console.log("Position hasProfit:", hasProfit);
        console.log("Position delta:", delta);

        // Check if position can be liquidated
        (bool canLiquidate, string memory reason) = liquidationEngine
            .canLiquidatePosition(tokenId);
        console.log("Can liquidate after price drop:", canLiquidate);
        console.log("Reason:", reason);
        assertTrue(
            canLiquidate,
            "Position should be liquidatable after price crash"
        );

        // Check liquidator is authorized
        console.log("Liquidator address:", liquidator);
        console.log(
            "Is liquidator a keeper:",
            liquidationEngine.isKeeper(liquidator)
        );

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
            1000 * 10 ** 30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        console.log("Position created with tokenId:", tokenId);

        // Price stays healthy (even improves)
        vault.setPrice(indexToken, 55000 * 10 ** 30); // 10% gain
        console.log("Price improved to 55000");

        // Check position cannot be liquidated
        (bool canLiquidate, string memory reason) = liquidationEngine
            .canLiquidatePosition(tokenId);
        console.log("Can liquidate healthy position:", canLiquidate);
        console.log("Reason:", reason);
        assertFalse(
            canLiquidate,
            "Healthy position should not be liquidatable"
        );

        // Attempt liquidation should fail
        vm.prank(liquidator);
        vm.expectRevert();
        liquidationEngine.liquidatePosition(tokenId);
        console.log("Liquidation correctly failed for healthy position");
    }

    function testLiquidateExpiredPosition() public {
        console.log("=== Test: Liquidate Expired Position ===");

        // Create expiring position
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10 ** 30,
            true,
            PositionManager.PositionType.EXPIRING,
            1, // 1 day expiry
            0
        );
        console.log("Expiring position created with tokenId:", tokenId);
        console.log("Current time:", block.timestamp);

        // Check not expired initially
        (
            bool canLiquidateInitial,
            string memory reasonInitial
        ) = liquidationEngine.canLiquidatePosition(tokenId);
        console.log("Can liquidate before expiry:", canLiquidateInitial);
        console.log("Reason before expiry:", reasonInitial);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);
        console.log("Time warped to:", block.timestamp);

        // Check position can be liquidated due to expiry
        (bool canLiquidate, string memory reason) = liquidationEngine
            .canLiquidatePosition(tokenId);
        console.log("Can liquidate after expiry:", canLiquidate);
        console.log("Reason after expiry:", reason);
        assertTrue(canLiquidate, "Expired position should be liquidatable");
        assertEq(reason, "Position expired", "Should be expired");

        // Liquidate expired position
        console.log("Attempting to liquidate expired position...");
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(tokenId);
        console.log("Expired position liquidated successfully!");

        // Check NFT was burned
        vm.expectRevert();
        positionNFT.ownerOf(tokenId);
        console.log("Expired position NFT successfully burned");
    }

    function testBatchLiquidation() public {
    console.log("=== Test: Batch Liquidation ===");
    
    uint256[] memory tokenIds = new uint256[](3);
    address[] memory users = new address[](3);
    users[0] = address(0x123);
    users[1] = address(0x124); // Different user
    users[2] = address(0x125); // Different user
    
    // Create multiple positions with DIFFERENT users so they have different vault keys
    console.log("Creating 3 positions with different users...");
    for (uint256 i = 0; i < 3; i++) {
        vm.prank(users[i]);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10**30,
            true,
            PositionManager.PositionType.STANDARD,
            0,
            0
        );
        tokenIds[i] = tokenId;
        console.log("Created position with tokenId:", tokenId);
        console.log("  For user:", users[i]);
    }
    
    // Crash price to make all positions liquidatable
    console.log("Crashing price to make all positions liquidatable...");
    vault.setPrice(indexToken, 20000 * 10**30); // 60% drop
    
    // Check all can be liquidated
    for (uint256 i = 0; i < 3; i++) {
        (bool canLiquidate, string memory reason) = liquidationEngine.canLiquidatePosition(tokenIds[i]);
        console.log("Position can liquidate:", canLiquidate);
        console.log("Reason:", reason);
        assertTrue(canLiquidate, "All positions should be liquidatable");
    }
    
    // Batch liquidate
    console.log("Attempting batch liquidation...");
    vm.prank(liquidator);
    liquidationEngine.liquidatePositions(tokenIds);
    console.log("Batch liquidation successful!");
    
    // Check each NFT was burned
    for (uint256 i = 0; i < 3; i++) {
        try positionNFT.ownerOf(tokenIds[i]) returns (address) {
            assertTrue(false, "NFT should have been burned");
        } catch {
            console.log("Position NFT successfully burned");
        }
    }

}
}
