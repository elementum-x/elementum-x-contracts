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

    function testCreatePosition() public {
        vm.prank(user);
        router.increasePosition(
            collateralToken,
            indexToken,
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
        assertEq(collateral, 100 * 10**30); // 10x leverage = $100 collateral
        assertEq(lastUpdate, block.timestamp);
    }

    function testDecreasePosition() public {
        // First create a position
        vm.prank(user);
        router.increasePosition(collateralToken, indexToken, 1000 * 10**30, true);

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
    }
}