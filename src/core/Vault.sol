// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVault.sol";

contract Vault is ReentrancyGuard, Ownable, IVault {
    struct Position {
        uint256 size; // Position size in USD (30 decimals)
        uint256 collateral; // Collateral in USD (30 decimals)
        uint256 averagePrice; // Average entry price (30 decimals)
        uint256 entryFundingRate; // Funding rate at entry
        uint256 reserveAmount; // Reserved tokens for this position
        int256 realisedPnl; // Realised PnL
        uint256 lastIncreasedTime; // Last time position was increased
    }

    // Constants
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    // State
    bool public override isInitialized;
    address public override router;

    // Position tracking
    mapping(bytes32 => Position) public positions;

    // Pool management
    mapping(address => uint256) public override poolAmounts;
    mapping(address => uint256) public override reservedAmounts;

    // Simple price feeds (we'll make this more sophisticated later)
    mapping(address => uint256) public tokenPrices;

    // Events
    event IncreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee
    );

    event DecreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee
    );

    constructor() Ownable(msg.sender) {}

    function initialize(address _router) external onlyOwner {
        require(!isInitialized, "Vault: already initialized");
        router = _router;
        isInitialized = true;
    }

    // Set simple prices for testing (replace with oracle later)
    function setPrice(address _token, uint256 _price) external onlyOwner {
        tokenPrices[_token] = _price;
    }

    // Price functions (simplified for now)
    function getMaxPrice(
        address _token
    ) external view override returns (uint256) {
        return tokenPrices[_token];
    }

    function getMinPrice(
        address _token
    ) external view override returns (uint256) {
        return tokenPrices[_token];
    }

    function gov() external view override returns (address) {
        return owner();
    }

    // Position key generation
    function getPositionKey(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _account,
                    _collateralToken,
                    _indexToken,
                    _isLong
                )
            );
    }

    // Get position info
    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    )
        external
        view
        override
        returns (
            uint256 size,
            uint256 collateral,
            uint256 averagePrice,
            uint256 entryFundingRate,
            uint256 reserveAmount,
            uint256 realisedPnl,
            bool hasProfit,
            uint256 lastIncreasedTime
        )
    {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position memory position = positions[key];

        uint256 usdPnl = position.realisedPnl >= 0
            ? uint256(position.realisedPnl)
            : uint256(-position.realisedPnl);
        bool profit = position.realisedPnl >= 0;

        return (
            position.size,
            position.collateral,
            position.averagePrice,
            position.entryFundingRate,
            position.reserveAmount,
            usdPnl,
            profit,
            position.lastIncreasedTime
        );
    }

    // Increase position
    function increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external override nonReentrant {
        require(msg.sender == router, "Vault: only router");
        require(_sizeDelta > 0, "Vault: invalid sizeDelta");

        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position storage position = positions[key];

        uint256 price = tokenPrices[_indexToken];
        require(price > 0, "Vault: invalid price");

        // For new position, set average price
        if (position.size == 0) {
            position.averagePrice = price;
        }

        // Update position
        position.size += _sizeDelta;
        position.lastIncreasedTime = block.timestamp;

        // Simple collateral handling (assume 1:1 for now)
        uint256 collateralDelta = _sizeDelta / 10; // 10x leverage assumption
        position.collateral += collateralDelta;

        emit IncreasePosition(
            key,
            _account,
            _collateralToken,
            _indexToken,
            collateralDelta,
            _sizeDelta,
            _isLong,
            price,
            0 // no fees for now
        );
    }

    // Decrease position (simplified)
    function decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        require(msg.sender == router, "Vault: only router");

        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position storage position = positions[key];

        require(position.size >= _sizeDelta, "Vault: position size too small");
        require(
            position.collateral >= _collateralDelta,
            "Vault: collateral too small"
        );

        // Update position
        position.size -= _sizeDelta;
        position.collateral -= _collateralDelta;

        uint256 price = tokenPrices[_indexToken];

        emit DecreasePosition(
            key,
            _account,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            price,
            0
        );

        return _collateralDelta; // Return collateral amount
    }

    // Add to your Vault contract
    function getPositionDelta(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (bool hasProfit, uint256 delta) {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position memory position = positions[key];

        if (position.size == 0) {
            return (false, 0);
        }

        uint256 currentPrice = tokenPrices[_indexToken];
        uint256 priceDelta = position.averagePrice > currentPrice
            ? position.averagePrice - currentPrice
            : currentPrice - position.averagePrice;

        delta = (position.size * priceDelta) / position.averagePrice;

        if (_isLong) {
            hasProfit = currentPrice > position.averagePrice;
        } else {
            hasProfit = position.averagePrice > currentPrice;
        }
    }

    // Liquidation (stub for now)
    function liquidatePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        address _feeReceiver
    ) external override {
        // TODO: Implement liquidation logic
        revert("Vault: liquidation not implemented yet");
    }
}

// DO THIS FIRST

// Vault.sol

// Handles custody and movement of user funds:

// depositCollateral(address user, uint256 amount)

// withdrawCollateral(address user, uint256 amount)

// Must do margin accounting in sync with PositionManager.
