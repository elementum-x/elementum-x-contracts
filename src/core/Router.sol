// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IVault.sol";

contract Router {
    using SafeERC20 for IERC20;

    IVault public immutable vault;

    constructor(address _vault) {
        vault = IVault(_vault);
    }

    function increasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong
    ) external {
        vault.increasePosition(
            msg.sender,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong
        );
    }

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong
    ) external {
        vault.decreasePosition(
            msg.sender,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            msg.sender
        );
    }
}