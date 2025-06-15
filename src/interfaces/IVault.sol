// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IVault is IERC4626 {
    // Events
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event MarginLocked(address indexed user, uint256 amount);
    event MarginReleased(address indexed user, uint256 amount);
    event TraderPayout(address indexed user, uint256 amount);
    event InsuranceLoss(uint256 amount);
    event InsuranceTopUp(uint256 amount);
    event FeeCredited(uint256 amount);

    // User Collateral Functions
    function depositCollateral(address user, uint256 amount) external;
    function withdrawCollateral(address user, uint256 amount) external;
    function lockMargin(address user, uint256 amount) external;
    function releaseMargin(address user, uint256 amount) external;

    // Trader Payout Functions
    function payoutTrader(address user, uint256 amount) external;

    // Insurance Fund Functions
    function sendLossToInsurance(uint256 amount) external;
    function insuranceBalance() external view returns (uint256);
    function insuranceTopUp(uint256 amount) external;

    // LP Fee Functions
    function creditFeeToLP(uint256 amount) external;

    // View Functions
    function getAvailableLiquidity() external view returns (uint256);
    function getUserCollateral(address user) external view returns (uint256);
    function getUserLockedMargin(address user) external view returns (uint256);

    // Admin Functions
    function pause() external;
    function unpause() external;
}
