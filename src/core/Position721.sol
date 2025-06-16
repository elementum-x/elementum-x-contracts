// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVault.sol";

contract Position721 is ERC721, ERC721Enumerable, Ownable {
    struct PositionNFTData {
        address account; // Original position owner
        address collateralToken;
        address indexToken;
        bool isLong;
        uint256 positionType; // 0=STANDARD, 1=PROTECTED, 2=FUNDED, 3=EXPIRING
        uint256 expiryTime; // 0 = no expiry
        uint256 protectionStrike; // For protected positions
        uint256 createdAt;
        bytes32 vaultPositionKey; // Link to vault position
    }

    IVault public immutable vault;
    mapping(address => bool) public authorizedManagers;

    mapping(uint256 => PositionNFTData) public positionData;
    mapping(bytes32 => uint256) public vaultKeyToTokenId;

    uint256 private _nextTokenId = 1;

    event PositionNFTMinted(
        uint256 indexed tokenId,
        address indexed owner,
        bytes32 indexed vaultKey,
        uint256 positionType
    );

    event PositionNFTBurned(uint256 indexed tokenId, bytes32 indexed vaultKey);

    modifier onlyAuthorizedManager() {
        require(authorizedManagers[msg.sender], "Not authorized manager");
        _;
    }

    constructor(
        address _vault
    ) ERC721("Elementum-X Positions", "EXP") Ownable(msg.sender) {
        vault = IVault(_vault);
    }

    function setAuthorizedManager(
        address _manager,
        bool _authorized
    ) external onlyOwner {
        authorizedManagers[_manager] = _authorized;
    }

    function mint(
        address to,
        address collateralToken,
        address indexToken,
        bool isLong,
        uint256 positionType,
        uint256 expiryTime,
        uint256 protectionStrike
    ) external onlyAuthorizedManager returns (uint256) {
        uint256 tokenId = _nextTokenId++;

        bytes32 vaultKey = vault.getPositionKey(
            to,
            collateralToken,
            indexToken,
            isLong
        );

        positionData[tokenId] = PositionNFTData({
            account: to,
            collateralToken: collateralToken,
            indexToken: indexToken,
            isLong: isLong,
            positionType: positionType,
            expiryTime: expiryTime,
            protectionStrike: protectionStrike,
            createdAt: block.timestamp,
            vaultPositionKey: vaultKey
        });

        vaultKeyToTokenId[vaultKey] = tokenId;

        _mint(to, tokenId);

        emit PositionNFTMinted(tokenId, to, vaultKey, positionType);

        return tokenId;
    }

    function burn(uint256 tokenId) external onlyAuthorizedManager {
        require(_ownerOf(tokenId) != address(0), "Token doesn't exist");

        PositionNFTData memory data = positionData[tokenId];
        delete vaultKeyToTokenId[data.vaultPositionKey];
        delete positionData[tokenId];

        _burn(tokenId);

        emit PositionNFTBurned(tokenId, data.vaultPositionKey);
    }

    // Get current position value from vault
    function getPositionValue(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 size,
            uint256 collateral,
            uint256 currentPnl,
            bool hasProfit,
            bool isExpired
        )
    {
        require(_ownerOf(tokenId) != address(0), "Token doesn't exist");

        PositionNFTData memory data = positionData[tokenId];

        (size, collateral, , , , , , ) = vault.getPosition(
            data.account,
            data.collateralToken,
            data.indexToken,
            data.isLong
        );

        // Check if expired
        isExpired = data.expiryTime > 0 && block.timestamp >= data.expiryTime;

        // Calculate current PnL (you'll need to add this to vault)
        // For now, simplified
        currentPnl = 0;
        hasProfit = true;
    }

    // Get position info for lending protocols
    function getPositionForLending(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 collateralValue,
            uint256 currentValue,
            uint256 healthRatio,
            bool isExpired,
            uint256 positionType
        )
    {
        require(_ownerOf(tokenId) != address(0), "Token doesn't exist");

        PositionNFTData memory data = positionData[tokenId];

        (uint256 size, uint256 collateral, , , , , , ) = vault.getPosition(
            data.account,
            data.collateralToken,
            data.indexToken,
            data.isLong
        );

        collateralValue = collateral;
        currentValue = size; // Simplified - should include PnL

        // Fix division by zero
        if (size == 0) {
            healthRatio = 0;
        } else {
            healthRatio = (collateral * 10000) / size; // Basis points
        }

        isExpired = data.expiryTime > 0 && block.timestamp >= data.expiryTime;
        positionType = data.positionType;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token doesn't exist");

        PositionNFTData memory data = positionData[tokenId];

        // Generate metadata JSON
        // For now, return a simple string - you can make this fancy later
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    _encodeBase64(
                        abi.encodePacked(
                            '{"name":"Elementum-X Position #',
                            _toString(tokenId),
                            '",',
                            '"description":"Hybrid perpetual position NFT",',
                            '"attributes":[',
                            '{"trait_type":"Position Type","value":',
                            _toString(data.positionType),
                            "},",
                            '{"trait_type":"Direction","value":"',
                            data.isLong ? "Long" : "Short",
                            '"},',
                            '{"trait_type":"Expires","value":',
                            _toString(data.expiryTime),
                            "}",
                            "]}"
                        )
                    )
                )
            );
    }

    // Helper functions
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _encodeBase64(
        bytes memory data
    ) internal pure returns (string memory) {
        // Simple base64 encoding - you might want to use a library
        string
            memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        bytes memory result = new bytes(4 * ((data.length + 2) / 3));

        uint256 i = 0;
        uint256 j = 0;

        for (; i + 3 <= data.length; i += 3) {
            uint256 a = uint256(uint8(data[i]));
            uint256 b = uint256(uint8(data[i + 1]));
            uint256 c = uint256(uint8(data[i + 2]));

            uint256 bitmap = (a << 16) | (b << 8) | c;

            result[j++] = bytes1(uint8(bytes(table)[(bitmap >> 18) & 63]));
            result[j++] = bytes1(uint8(bytes(table)[(bitmap >> 12) & 63]));
            result[j++] = bytes1(uint8(bytes(table)[(bitmap >> 6) & 63]));
            result[j++] = bytes1(uint8(bytes(table)[bitmap & 63]));
        }

        return string(result);
    }

    // Override required functions
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function getPositionBasicInfo(
        uint256 tokenId
    )
        external
        view
        returns (
            address account,
            address collateralToken,
            address indexToken,
            bool isLong,
            uint256 positionType
        )
    {
        require(_ownerOf(tokenId) != address(0), "Token doesn't exist");
        PositionNFTData memory data = positionData[tokenId];
        return (
            data.account,
            data.collateralToken,
            data.indexToken,
            data.isLong,
            data.positionType
        );
    }
}

// FIRST

// ERC721 token representing a unique user position:

// Token metadata can optionally encode position summary (size, leverage, entry price, PnL).

// Token ID maps to position state on-chain (via mapping or storage slot).
