// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IVault.sol";
import "./Position721.sol";
import "./PositionManager.sol";

contract LiquidationEngine is Ownable, ReentrancyGuard {
    
    IVault public immutable vault;
    Position721 public immutable positionNFT;
    PositionManager public immutable positionManager;
    
    // Liquidation parameters
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public liquidationRewardBps = 500; // 5% reward for liquidators
    uint256 public maxPositionsPerCall = 10; // Gas limit protection
    
    // Position type specific liquidation thresholds
    mapping(uint256 => uint256) public liquidationThresholds; // position type => threshold in bps
    
    // Keeper system
    mapping(address => bool) public isKeeper;
    
    struct LiquidationInfo {
        uint256 tokenId;
        address account;
        address collateralToken;
        address indexToken;
        bool isLong;
        uint256 positionType;
        bool canLiquidate;
        bool isExpired;
        uint256 healthRatio;
    }
    
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
    
    modifier onlyKeeper() {
        require(isKeeper[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }
    
    constructor(
        address _vault,
        address _positionNFT,
        address _positionManager
    ) Ownable(msg.sender) {
        vault = IVault(_vault);
        positionNFT = Position721(_positionNFT);
        positionManager = PositionManager(_positionManager);
        
        // Set default liquidation thresholds for each position type
        liquidationThresholds[0] = 200;  // STANDARD: 2% collateral ratio
        liquidationThresholds[1] = 150;  // PROTECTED: 1.5% (has downside protection)
        liquidationThresholds[2] = 250;  // FUNDED: 2.5% (less stable funding)
        liquidationThresholds[3] = 300;  // EXPIRING: 3% (time risk)
    }
    
    /**
     * @dev Add/remove liquidation keepers
     */
    function setKeeper(address _keeper, bool _isActive) external onlyOwner {
        isKeeper[_keeper] = _isActive;
        if (_isActive) {
            emit KeeperAdded(_keeper);
        } else {
            emit KeeperRemoved(_keeper);
        }
    }
    
    /**
     * @dev Set liquidation threshold for position type
     */
    function setLiquidationThreshold(uint256 _positionType, uint256 _threshold) external onlyOwner {
        require(_threshold <= 1000, "Threshold too high"); // Max 10%
        liquidationThresholds[_positionType] = _threshold;
        emit LiquidationThresholdUpdated(_positionType, _threshold);
    }
    
    /**
     * @dev Check if a specific position can be liquidated
     */
    function canLiquidatePosition(uint256 tokenId) public view returns (bool canLiquidate, string memory reason) {
    if (!_exists(tokenId)) {
        return (false, "Position not found");
    }
    
    // Get position data from NFT
    (
        uint256 collateralValue,
        uint256 currentValue,
        uint256 healthRatio,
        bool isExpired,
        uint256 positionType
    ) = positionNFT.getPositionForLending(tokenId);
    
    // Check if expired
    if (isExpired) {
        return (true, "Position expired");
    }
    
    // Skip if position has no size (already closed)
    if (currentValue == 0) {
        return (false, "Position already closed");
    }
    
    // Check health ratio against liquidation threshold
    uint256 threshold = liquidationThresholds[positionType];
    if (healthRatio < threshold) {
        return (true, "Below liquidation threshold");
    }
    
    // Check vault-level liquidation
    (
        address account,
        address collateralToken,
        address indexToken,
        bool isLong,
    ) = positionNFT.getPositionBasicInfo(tokenId);
    
    bool vaultCanLiquidate = vault.canLiquidatePosition(account, collateralToken, indexToken, isLong);
    if (vaultCanLiquidate) {
        return (true, "Vault liquidation criteria met");
    }
    
    return (false, "Position healthy");
}
    
    /**
     * @dev Liquidate a single position
     */
    function liquidatePosition(uint256 tokenId) external nonReentrant onlyKeeper {
        require(_exists(tokenId), "Position not found");
        
        (bool canLiquidate, string memory reason) = canLiquidatePosition(tokenId);
        require(canLiquidate, string(abi.encodePacked("Cannot liquidate: ", reason)));
        
        address positionOwner = positionNFT.ownerOf(tokenId);
        
        // Get position details
        (
            address account,
            address collateralToken,
            address indexToken,
            bool isLong,
        ) = positionNFT.getPositionBasicInfo(tokenId);
        
        // Execute liquidation in vault
        uint256 liquidationReward = vault.forceLiquidatePosition(
            account,
            collateralToken,
            indexToken,
            isLong,
            msg.sender
        );
        
        // Burn the NFT
        positionNFT.burn(tokenId);
        
        // TODO: Transfer liquidation reward to liquidator
        // For now, we'll handle this in the lending protocol
        
        emit PositionLiquidated(tokenId, msg.sender, positionOwner, liquidationReward, reason);
    }
    
    /**
     * @dev Batch liquidate multiple positions (for keepers)
     */
    function liquidatePositions(uint256[] calldata tokenIds) external nonReentrant onlyKeeper {
    require(tokenIds.length <= maxPositionsPerCall, "Too many positions");
    
    for (uint256 i = 0; i < tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i];
        
        // More detailed logging would go here in a debug version
        // But since we can't use events in the middle, let's just ensure proper execution
        
        if (!_exists(tokenId)) {
            continue; // Skip non-existent positions
        }
        
        (bool canLiquidate,) = canLiquidatePosition(tokenId);
        if (!canLiquidate) {
            continue; // Skip healthy positions
        }
        
        // Get position data BEFORE liquidation (since NFT will be burned)
        address positionOwner = positionNFT.ownerOf(tokenId);
        
        (
            address account,
            address collateralToken,
            address indexToken,
            bool isLong,
        ) = positionNFT.getPositionBasicInfo(tokenId);
        
        // Execute liquidation in vault first
        uint256 liquidationReward = vault.forceLiquidatePosition(
            account,
            collateralToken,
            indexToken,
            isLong,
            msg.sender
        );
        
        // Then burn NFT
        positionNFT.burn(tokenId);
        
        emit PositionLiquidated(tokenId, msg.sender, positionOwner, liquidationReward, "Batch liquidation");
    }
}
    
    /**
     * @dev Get liquidation info for multiple positions (for UI/monitoring)
     */
    function getLiquidationInfo(uint256[] calldata tokenIds) external view returns (LiquidationInfo[] memory) {
        LiquidationInfo[] memory infos = new LiquidationInfo[](tokenIds.length);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            if (!_exists(tokenId)) {
                continue;
            }
            
            (
                address account,
                address collateralToken,
                address indexToken,
                bool isLong,
                uint256 positionType
            ) = positionNFT.getPositionBasicInfo(tokenId);
            
            (
                ,
                ,
                uint256 healthRatio,
                bool isExpired,
            ) = positionNFT.getPositionForLending(tokenId);
            
            (bool canLiquidate,) = canLiquidatePosition(tokenId);
            
            infos[i] = LiquidationInfo({
                tokenId: tokenId,
                account: account,
                collateralToken: collateralToken,
                indexToken: indexToken,
                isLong: isLong,
                positionType: positionType,
                canLiquidate: canLiquidate,
                isExpired: isExpired,
                healthRatio: healthRatio
            });
        }
        
        return infos;
    }
    
    /**
     * @dev Emergency function to liquidate expired positions
     */
    function liquidateExpiredPositions(uint256[] calldata tokenIds) external onlyKeeper {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            if (!_exists(tokenId)) {
                continue;
            }
            
            (,,,bool isExpired,) = positionNFT.getPositionForLending(tokenId);
            
            if (isExpired) {
                address positionOwner = positionNFT.ownerOf(tokenId);
                
                (
                    address account,
                    address collateralToken,
                    address indexToken,
                    bool isLong,
                ) = positionNFT.getPositionBasicInfo(tokenId);
                
                vault.forceLiquidatePosition(account, collateralToken, indexToken, isLong, msg.sender);
                positionNFT.burn(tokenId);
                
                emit PositionLiquidated(tokenId, msg.sender, positionOwner, 0, "Position expired");
            }
        }
    }
    
    function _exists(uint256 tokenId) internal view returns (bool) {
        try positionNFT.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
}

// LATER

// This is the contract that Chainlink Automation or another off-chain bot pings to:

// Check if a position’s health factor is below threshold.

// If so, call:

// PositionManager.liquidatePosition(positionId) → which:

// Closes the position

// Sends collateral to insurance/liquidator

// Burns or marks NFT as closed