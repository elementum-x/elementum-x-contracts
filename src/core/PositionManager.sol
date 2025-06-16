// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IVault.sol";
import "./Position721.sol";

contract PositionManager is Ownable, ReentrancyGuard {
    enum PositionType {
        STANDARD, // Regular perp
        PROTECTED, // Perp with put protection
        FUNDED, // Perp with prepaid funding
        EXPIRING // Perp with expiry date
    }

    struct HybridPosition {
        address account;
        address collateralToken;
        address indexToken;
        bool isLong;
        PositionType positionType;
        uint256 expiryTime; // 0 = no expiry
        uint256 protectionStrike; // For protected positions
        uint256 fundingPrepaid; // For funded positions
        uint256 createdAt;
        bool isActive;
    }

    IVault public immutable vault;
    uint256 public nextPositionId = 1;

    mapping(uint256 => HybridPosition) public hybridPositions;
    mapping(bytes32 => uint256) public vaultKeyToPositionId;

    event HybridPositionCreated(
        uint256 indexed positionId,
        address indexed account,
        PositionType positionType,
        uint256 expiryTime
    );

    Position721 public immutable positionNFT;

    constructor(address _vault, address _positionNFT) Ownable(msg.sender) {
        vault = IVault(_vault);
        positionNFT = Position721(_positionNFT);
    }

    function createHybridPosition(
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        PositionType _positionType,
        uint256 _expiryDays,
        uint256 _protectionStrike
    ) external nonReentrant returns (uint256 positionId, uint256 tokenId) {
        // Create underlying vault position
        vault.increasePosition(
            msg.sender,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong
        );

        // Create hybrid position tracking
        positionId = nextPositionId++;

        uint256 expiryTime = _expiryDays > 0
            ? block.timestamp + (_expiryDays * 1 days)
            : 0;

        hybridPositions[positionId] = HybridPosition({
            account: msg.sender,
            collateralToken: _collateralToken,
            indexToken: _indexToken,
            isLong: _isLong,
            positionType: _positionType,
            expiryTime: expiryTime,
            protectionStrike: _protectionStrike,
            fundingPrepaid: 0,
            createdAt: block.timestamp,
            isActive: true
        });

        // 🎉 MINT NFT
        tokenId = positionNFT.mint(
            msg.sender,
            _collateralToken,
            _indexToken,
            _isLong,
            uint256(_positionType),
            expiryTime,
            _protectionStrike
        );

        bytes32 vaultKey = vault.getPositionKey(
            msg.sender,
            _collateralToken,
            _indexToken,
            _isLong
        );
        vaultKeyToPositionId[vaultKey] = positionId;

        emit HybridPositionCreated(
            positionId,
            msg.sender,
            _positionType,
            expiryTime
        );
    }
    function checkExpiry(
        uint256 positionId
    ) external view returns (bool isExpired) {
        HybridPosition memory pos = hybridPositions[positionId];
        return pos.expiryTime > 0 && block.timestamp >= pos.expiryTime;
    }

    function getHybridPosition(
        uint256 positionId
    ) external view returns (HybridPosition memory) {
        return hybridPositions[positionId];
    }

     function closePosition(uint256 tokenId) external nonReentrant {
        require(positionNFT.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        
        // Get position data from NFT
        (,,,,uint256 positionType) = positionNFT.getPositionForLending(tokenId);
        
        // Close vault position (simplified)
        // vault.decreasePosition(...);
        
        // Burn NFT
        positionNFT.burn(tokenId);
    }
}

// DO THIS FIRST

// PositionManager

// Creates the Position NFT on open.

// Calls Vault to lock/unlock collateral.

// Writes to PositionUtils to calculate size, entry price, margin, PnL, etc.

// Interacts with Oracle to fetch mark/index prices.

// Updates or closes position state based on user actions or liquidations.

// Should support:

// openPosition()

// modifyPosition()

// closePosition()
