// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/core/Vault.sol";
import "../src/core/Router.sol";

contract VaultTest is Test {
    Vault vault;
    Router router;
    
    address user = address(0x123);
    address collateralToken = address(0x456);
    address indexToken = address(0x789);

    function setUp() public {
        vault = new Vault();
        router = new Router(address(vault));
        
        vault.initialize(address(router));
        
        // Set a test price for the index token
        vault.setPrice(indexToken, 50000 * 10**30); // $50,000 with 30 decimals
    }

    // =========================================================================
    // POSITION TESTS
    // =========================================================================

    function testCreateLongPosition() public {
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10**30, // $1000 position size
            true           // long position
        );

        // Check position was created
        (uint256 size, uint256 collateral,,,,,, uint256 lastUpdate) = vault.getPosition(
            user,
            collateralToken,
            indexToken,
            true
        );

        assertEq(size, 1000 * 10**30);
        assertEq(collateral, 100 * 10**30);
        assertEq(lastUpdate, block.timestamp);
    }

    function testIncreasePositionSize() public {
        // First create an initial position
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10**30, // $1000 initial position size
            true           // long position
        );

        // Check initial position
        (uint256 initialSize, uint256 initialCollateral, uint256 averagePrice,,,,,) = vault.getPosition(
            user,
            collateralToken,
            indexToken,
            true
        );
        
        assertEq(initialSize, 1000 * 10**30);
        assertEq(initialCollateral, 100 * 10**30);
        assertEq(averagePrice, 50000 * 10**30); // Entry price
        
        // Change price before increasing position
        vault.setPrice(indexToken, 55000 * 10**30); // $55,000 (10% higher)
        
        // Increase the position
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            500 * 10**30, // Add $500 more to position
            true          // long position
        );

        // Check updated position
        (uint256 newSize, uint256 newCollateral, uint256 newAveragePrice,,,,,) = vault.getPosition(
            user,
            collateralToken,
            indexToken,
            true
        );

        assertEq(newSize, 1500 * 10**30); // $1000 + $500 = $1500
        assertEq(newCollateral, 200 * 10**30); // $100 + $100 = $200
        
        // Check weighted average price: (1000 * 50000 + 500 * 55000) / 1500 = 51666.67
        // Calculate step by step to avoid overflow
        uint256 weightedSum = (1000 * 50000 + 500 * 55000); // = 77,500,000
        uint256 expectedAvgPrice = (weightedSum * 10**30) / 1500;
        assertEq(newAveragePrice, expectedAvgPrice);

        // Check new leverage ratio
        uint256 leverage = vault.getPositionLeverage(user, collateralToken, indexToken, true);
        assertEq(leverage, (1500 * 10000) / 200);
    }

    function testDecreasePositionSize() public {
        // First create a position
        vm.prank(user);
        router.increasePosition(collateralToken, indexToken, 100 * 10**30, 1000 * 10**30, true);

        // Then decrease it
        vm.prank(user);
        router.decreasePosition(
            collateralToken,
            indexToken,
            50 * 10**30,  // Remove $50 collateral
            500 * 10**30, // Close half the position
            true
        );

        (uint256 size, uint256 collateral,,,,,, ) = vault.getPosition(
            user,
            collateralToken,
            indexToken,
            true
        );

        assertEq(size, 500 * 10**30);  // Half remaining
        assertEq(collateral, 50 * 10**30); // Half collateral remaining

        // Check new leverage ratio
        uint256 leverage = vault.getPositionLeverage(user, collateralToken, indexToken, true);
        assertEq(leverage, (500 * 10000) / 50);
    }

    function testCloseEntirePosition() public {
        // First create a position
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10**30, // $1000 position size
            true           // long position
        );

        // Verify position exists
        (uint256 initialSize, uint256 initialCollateral,,,,,, ) = vault.getPosition(
            user,
            collateralToken,
            indexToken,
            true
        );
        
        assertEq(initialSize, 1000 * 10**30);
        assertEq(initialCollateral, 100 * 10**30);

        // Close the entire position
        vm.prank(user);
        router.decreasePosition(
            collateralToken,
            indexToken,
            100 * 10**30,  // Remove all collateral
            1000 * 10**30, // Close entire position
            true
        );

        // Check position is closed
        (uint256 finalSize, uint256 finalCollateral,,,,,, ) = vault.getPosition(
            user,
            collateralToken,
            indexToken,
            true
        );

        assertEq(finalSize, 0);       // Position completely closed
        assertEq(finalCollateral, 0); // No collateral remaining
    }

    function testProfitableLongPosition() public {
        // Create long position at $50,000
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10**30, // $1000 position size
            true           // long position
        );

        // Price goes up to $55,000 (10% increase)
        vault.setPrice(indexToken, 55000 * 10**30);

        // Check PnL using getPositionDelta
        (bool hasProfit, uint256 delta) = vault.getPositionDelta(
            user,
            collateralToken,
            indexToken,
            true
        );

        assertTrue(hasProfit);
        // Expected profit: (1000 * 5000) / 50000 = $100
        uint256 expectedProfit = (1000 * 10**30 * 5000 * 10**30) / (50000 * 10**30);
        assertEq(delta, expectedProfit);
    }

    function testLosingLongPosition() public {
        // Create long position at $50,000
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10**30, // $1000 position size
            true           // long position
        );

        // Price goes down to $45,000 (10% decrease)
        vault.setPrice(indexToken, 45000 * 10**30);

        // Check PnL using getPositionDelta
        (bool hasProfit, uint256 delta) = vault.getPositionDelta(
            user,
            collateralToken,
            indexToken,
            true
        );

        assertFalse(hasProfit); // Should be a loss
        // Expected loss: (1000 * 5000) / 50000 = $100
        uint256 expectedLoss = (1000 * 10**30 * 5000 * 10**30) / (50000 * 10**30);
        assertEq(delta, expectedLoss);
    }

    function testProfitableShortPosition() public {
        // Create short position at $50,000
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10**30, // $1000 position size
            false          // short position
        );

        // Price goes down to $45,000 (10% decrease)
        vault.setPrice(indexToken, 45000 * 10**30);

        // Check PnL using getPositionDelta
        (bool hasProfit, uint256 delta) = vault.getPositionDelta(
            user,
            collateralToken,
            indexToken,
            false
        );

        assertTrue(hasProfit); // Short profits when price falls
        // Expected profit: (1000 * 5000) / 50000 = $100
        uint256 expectedProfit = (1000 * 10**30 * 5000 * 10**30) / (50000 * 10**30);
        assertEq(delta, expectedProfit);
    }

    function testLosingShortPosition() public {
        // Create short position at $50,000
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10**30, // $1000 position size
            false          // short position
        );

        // Price goes up to $55,000 (10% increase)
        vault.setPrice(indexToken, 55000 * 10**30);

        // Check PnL using getPositionDelta
        (bool hasProfit, uint256 delta) = vault.getPositionDelta(
            user,
            collateralToken,
            indexToken,
            false
        );

        assertFalse(hasProfit); // Short loses when price rises
        // Expected loss: (1000 * 5000) / 50000 = $100
        uint256 expectedLoss = (1000 * 10**30 * 5000 * 10**30) / (50000 * 10**30);
        assertEq(delta, expectedLoss);
    }

    function testLongPositionLiquidation() public {
        // Create a highly leveraged position (low collateral)
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10**30, // $1000 position size
            true           // long position
        );
        // This creates $100 collateral (10x leverage)

        // Price drops significantly (15%)
        vault.setPrice(indexToken, 42500 * 10**30); // $42,500

        // Get position delta
        (bool hasProfit, uint256 delta) = vault.getPositionDelta(
            user,
            collateralToken,
            indexToken,
            true
        );

        assertFalse(hasProfit); // Should be a loss
        // Expected loss: (1000 * 7500) / 50000 = $150 loss
        // Calculate step by step to avoid overflow
        uint256 expectedLoss = (1000 * 7500 * 10**30) / 50000; // $150 with 30 decimals
        assertEq(delta, expectedLoss);

        // Check if position can be liquidated
        bool canLiquidate = vault.canLiquidatePosition(
            user,
            collateralToken,
            indexToken,
            true
        );
        
        assertTrue(canLiquidate); // Should be liquidatable due to high loss vs collateral
    }

    function testHealthyLongPosition() public {
        // Create position
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
            100 * 10**30, // $100 collateral
            1000 * 10**30, // $1000 position size
            true           // long position
        );

        // Small price movement (2% up)
        vault.setPrice(indexToken, 51000 * 10**30); // $51,000

        // Check if position can be liquidated
        bool canLiquidate = vault.canLiquidatePosition(
            user,
            collateralToken,
            indexToken,
            true
        );

        assertFalse(canLiquidate); // Should NOT be liquidatable - healthy position
    }

     function testShortPositionLiquidation() public {
        // Create short position at $50,000
        vm.prank(address(router));
        vault.increasePosition(user, collateralToken, indexToken, 100 * 10**30, 1000 * 10**30, false);

        // Price goes up significantly (20% increase)
        vault.setPrice(indexToken, 60000 * 10**30); // $60,000

        // Check if short position can be liquidated
        bool canLiquidate = vault.canLiquidatePosition(user, collateralToken, indexToken, false);
        assertTrue(canLiquidate); // Short should be liquidatable when price rises significantly

        // Calculate expected loss: (1000 * 10000) / 50000 = $200 loss
        // With $100 collateral, position should be underwater
        (bool hasProfit, uint256 delta) = vault.getPositionDelta(user, collateralToken, indexToken, false);
        assertFalse(hasProfit);
        
        // Calculate step by step to avoid overflow  
        uint256 expectedLoss = (1000 * 10000 * 10**30) / 50000; // $200 with 30 decimals
        assertEq(delta, expectedLoss); // $200 loss
    }

    function testHealthyShortPosition() public {
        // Create short position
        vm.prank(address(router));
        vault.increasePosition(user, collateralToken, indexToken, 100 * 10**30, 1000 * 10**30, false);

        // Small price increase (2%)
        vault.setPrice(indexToken, 51000 * 10**30);

        // Should not be liquidatable
        bool canLiquidate = vault.canLiquidatePosition(user, collateralToken, indexToken, false);
        assertFalse(canLiquidate);
    }

    // =========================================================================
    // AUTHORIZATION & SECURITY TESTS
    // =========================================================================

    function testInitializeOnlyOwner() public {
        Vault newVault = new Vault();
        
        // Should fail when called by non-owner
        vm.prank(user);
        vm.expectRevert();
        newVault.initialize(address(router));
        
        // Should succeed when called by owner
        newVault.initialize(address(router));
        assertTrue(newVault.isInitialized());
    }

    function testInitializeAlreadyInitialized() public {
        // Vault is already initialized in setUp()
        vm.expectRevert("Vault: already initialized");
        vault.initialize(address(router));
    }

    function testSetPriceOnlyOwner() public {
        // Should fail when called by non-owner
        vm.prank(user);
        vm.expectRevert();
        vault.setPrice(indexToken, 60000 * 10**30);
        
        // Should succeed when called by owner
        vault.setPrice(indexToken, 60000 * 10**30);
        assertEq(vault.getMaxPrice(indexToken), 60000 * 10**30);
    }

    function testIncreasePositionOnlyRouter() public {
        // Should fail when called by non-router
        vm.prank(user);
        vm.expectRevert("Vault: only router");
        vault.increasePosition(user, collateralToken, indexToken, 100 * 10**30, 1000 * 10**30, true);
    }

    function testDecreasePositionOnlyRouter() public {
        // Should fail when called by non-router
        vm.prank(user);
        vm.expectRevert("Vault: only router");
        vault.decreasePosition(user, collateralToken, indexToken, 100 * 10**30, 500 * 10**30, true, user);
    }

    function testSetLiquidationEngineOnlyOwner() public {
        address newEngine = address(0x999);
        
        // Should fail when called by non-owner
        vm.prank(user);
        vm.expectRevert();
        vault.setLiquidationEngine(newEngine);
        
        // Should succeed when called by owner
        vault.setLiquidationEngine(newEngine);
        assertEq(vault.liquidationEngine(), newEngine);
    }

    // =========================================================================
    // EDGE CASES & ERROR HANDLING TESTS
    // =========================================================================

    function testIncreasePositionInvalidSizeDelta() public {
        vm.expectRevert("Vault: invalid sizeDelta");
        vm.prank(address(router));
        vault.increasePosition(user, collateralToken, indexToken, 100 * 10**30, 0, true);
    }

    function testIncreasePositionInvalidPrice() public {
        // Set price to 0
        vault.setPrice(indexToken, 0);
        
        vm.expectRevert("Vault: invalid price");
        vm.prank(address(router));
        vault.increasePosition(user, collateralToken, indexToken, 100 * 10**30, 1000 * 10**30, true);
    }

    function testDecreasePositionInsufficientSize() public {
        // Create small position first
        vm.prank(address(router));
        vault.increasePosition(user, collateralToken, indexToken, 50 * 10**30, 500 * 10**30, true);
        
        // Try to decrease more than position size
        vm.expectRevert("Vault: position size too small");
        vm.prank(address(router));
        vault.decreasePosition(user, collateralToken, indexToken, 50 * 10**30, 1000 * 10**30, true, user);
    }

    function testDecreasePositionInsufficientCollateral() public {
        // Create position first
        vm.prank(address(router));
        vault.increasePosition(user, collateralToken, indexToken, 100 * 10**30, 1000 * 10**30, true);
        
        // Try to decrease more collateral than available
        vm.expectRevert("Vault: collateral too small");
        vm.prank(address(router));
        vault.decreasePosition(user, collateralToken, indexToken, 200 * 10**30, 500 * 10**30, true, user);
    }

    function testGetPositionNonExistent() public {
        // Query non-existent position
        (uint256 size, uint256 collateral, uint256 averagePrice, uint256 entryFundingRate, 
         uint256 reserveAmount, uint256 realisedPnl, bool hasProfit, uint256 lastIncreasedTime) = 
         vault.getPosition(user, collateralToken, indexToken, true);
        
        // All should be zero for non-existent position
        assertEq(size, 0);
        assertEq(collateral, 0);
        assertEq(averagePrice, 0);
        assertEq(entryFundingRate, 0);
        assertEq(reserveAmount, 0);
        assertEq(realisedPnl, 0);
        assertTrue(hasProfit); // hasProfit is true when realisedPnl is 0 (0 >= 0)
        assertEq(lastIncreasedTime, 0);
    }

    function testGetPositionLeverageDivisionByZero() public {
        // Test with position that has zero collateral
        uint256 leverage = vault.getPositionLeverage(user, collateralToken, indexToken, true);
        assertEq(leverage, 0); // Should return 0 for non-existent position
    }

    function testGetPositionDeltaZeroSize() public {
        // Test delta calculation for non-existent position
        (bool hasProfit, uint256 delta) = vault.getPositionDelta(user, collateralToken, indexToken, true);
        assertFalse(hasProfit);
        assertEq(delta, 0);
    }

    function testCanLiquidateNonExistentPosition() public {
        // Test liquidation check for non-existent position
        bool canLiquidate = vault.canLiquidatePosition(user, collateralToken, indexToken, true);
        assertFalse(canLiquidate);
    }

    // =========================================================================
    // LIQUIDATION ENGINE TESTS
    // =========================================================================

    function testForceLiquidatePositionOnlyEngine() public {
        address liquidationEngine = address(0x777);
        vault.setLiquidationEngine(liquidationEngine);

        // Create position first
        vm.prank(address(router));
        vault.increasePosition(user, collateralToken, indexToken, 100 * 10**30, 1000 * 10**30, true);

        // Should fail when called by non-liquidation engine
        vm.prank(user);
        vm.expectRevert("Vault: only liquidation engine");
        vault.forceLiquidatePosition(user, collateralToken, indexToken, true, user);
    }

    function testForceLiquidatePositionNotFound() public {
        address liquidationEngine = address(0x777);
        vault.setLiquidationEngine(liquidationEngine);

        // Try to liquidate non-existent position
        vm.prank(liquidationEngine);
        vm.expectRevert("Vault: position not found");
        vault.forceLiquidatePosition(user, collateralToken, indexToken, true, user);
    }

    function testForceLiquidatePositionSuccess() public {
        address liquidationEngine = address(0x777);
        address liquidator = address(0x888);
        vault.setLiquidationEngine(liquidationEngine);

        // Create underwater position
        vm.prank(address(router));
        vault.increasePosition(user, collateralToken, indexToken, 100 * 10**30, 1000 * 10**30, true);

        // Make position underwater
        vault.setPrice(indexToken, 40000 * 10**30); // 20% drop

        // Liquidate position
        vm.prank(liquidationEngine);
        uint256 reward = vault.forceLiquidatePosition(user, collateralToken, indexToken, true, liquidator);

        // Position should be deleted
        (uint256 size,,,,,,,) = vault.getPosition(user, collateralToken, indexToken, true);
        assertEq(size, 0);

        // Reward should be calculated (should be 0 since position is completely underwater)
        assertEq(reward, 0);
    }

    // =========================================================================
    // LEVERAGE CALCULATION TESTS
    // =========================================================================

    function testGetPositionLeverage() public {
        // Create position
        vm.prank(address(router));
        vault.increasePosition(user, collateralToken, indexToken, 200 * 10**30, 1000 * 10**30, true);

        uint256 leverage = vault.getPositionLeverage(user, collateralToken, indexToken, true);
        
        // Expected: (1000 * 10000) / 200 = 50,000 basis points = 5x leverage
        uint256 expectedLeverage = (1000 * 10000) / 200;
        assertEq(leverage, expectedLeverage);
    }

    // =========================================================================
    // POSITION KEY GENERATION TESTS
    // =========================================================================

    function testGetPositionKeyConsistency() public {
        bytes32 key1 = vault.getPositionKey(user, collateralToken, indexToken, true);
        bytes32 key2 = vault.getPositionKey(user, collateralToken, indexToken, true);
        
        // Should be identical
        assertEq(key1, key2);
        
        // Different direction should produce different key
        bytes32 key3 = vault.getPositionKey(user, collateralToken, indexToken, false);
        assertTrue(key1 != key3);
    }

    // =========================================================================
    // PRICE FUNCTIONS TESTS
    // =========================================================================

    function testPriceFunctions() public {
        uint256 testPrice = 45000 * 10**30;
        vault.setPrice(indexToken, testPrice);
        
        assertEq(vault.getMaxPrice(indexToken), testPrice);
        assertEq(vault.getMinPrice(indexToken), testPrice);
    }

    function testGovFunction() public {
        assertEq(vault.gov(), address(this)); // Test contract is owner
    }
}