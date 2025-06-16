// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/core/Vault.sol";
import "../src/core/PositionManager.sol";
import "../src/core/Position721.sol";

contract Position721Test is Test {
    Vault vault;
    Position721 positionNFT;
    PositionManager positionManager;

    address user = address(0x123);
    address collateralToken = address(0x456);
    address indexToken = address(0x789);

    function setUp() public {
        vault = new Vault();
        positionNFT = new Position721(address(vault));
        positionManager = new PositionManager(
            address(vault),
            address(positionNFT)
        );

        vault.initialize(address(positionManager));
        positionNFT.setPositionManager(address(positionManager));
        vault.setPrice(indexToken, 50000 * 10 ** 30);
    }

    function testMintPositionNFT() public {
        vm.prank(user);
        (uint256 positionId, uint256 tokenId) = positionManager
            .createHybridPosition(
                collateralToken,
                indexToken,
                1000 * 10 ** 30,
                true,
                PositionManager.PositionType.STANDARD,
                0,
                0
            );

        // Check NFT was minted
        assertEq(positionNFT.ownerOf(tokenId), user);
        assertEq(positionNFT.totalSupply(), 1);

        // Check position data using the new getter
        (
            address account,
            address collToken,
            address indexTok,
            bool isLong,
            uint256 posType
        ) = positionNFT.getPositionBasicInfo(tokenId);

        assertEq(account, user);
        assertEq(collToken, collateralToken);
        assertEq(indexTok, indexToken);
        assertTrue(isLong);
        assertEq(posType, 0); // STANDARD = 0
    }

    function testNFTTransfer() public {
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

        address newOwner = address(0x999);

        // Transfer NFT
        vm.prank(user);
        positionNFT.transferFrom(user, newOwner, tokenId);

        assertEq(positionNFT.ownerOf(tokenId), newOwner);
    }

    function testPositionValueForLending() public {
        vm.prank(user);
        (, uint256 tokenId) = positionManager.createHybridPosition(
            collateralToken,
            indexToken,
            1000 * 10 ** 30,
            true,
            PositionManager.PositionType.PROTECTED,
            30, // 30 days
            45000 * 10 ** 30 // Protection strike
        );

        (
            uint256 collateralValue,
            uint256 currentValue,
            uint256 healthRatio,
            bool isExpired,
            uint256 positionType
        ) = positionNFT.getPositionForLending(tokenId);

        assertGt(collateralValue, 0);
        assertGt(currentValue, 0);
        assertFalse(isExpired);
        assertEq(positionType, 1); // PROTECTED = 1
    }
}
