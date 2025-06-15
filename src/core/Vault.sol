// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVault} from "../interfaces/IVault.sol";

/// @title Vault
/// @notice Core contract for managing collateral, LP positions, and insurance fund in the perpetual DEX system
/// @dev Implements ERC4626 for LP token functionality and includes comprehensive collateral management
contract Vault is IVault, ERC4626, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Event emitted when an address is authorized or unauthorized
    event AuthorizedAddressSet(address indexed addr, bool isAuthorized);

    /// @notice Current balance of the insurance fund
    uint256 public insuranceFund;

    /// @notice Maximum cap for the insurance fund (1M USDC)
    uint256 public constant MAX_INSURANCE_CAP = 1_000_000 * 1e6;

    /// @notice Maximum percentage of TVL that can be used for LP positions (95%)
    uint256 public constant MAX_LP_RATIO = 9500;

    /// @notice Mapping of user addresses to their available collateral
    mapping(address => uint256) public userCollateral;

    /// @notice Mapping of user addresses to their locked margin for open positions
    mapping(address => uint256) public userLockedMargin;

    /// @notice Running total of all trader collateral (available + locked)
    uint256 public totalTraderCollateral;

    /// @notice Mapping of authorized addresses
    mapping(address => bool) public authorizedAddresses;

    /// @notice Restricts function access to authorized contracts and owner
    modifier onlyAuthorized() {
        require(
            msg.sender == owner() || authorizedAddresses[msg.sender],
            "Vault: unauthorized"
        );
        _;
    }

    /// @notice Initializes the Vault contract
    /// @param _asset The address of the underlying asset (USDC)
    /// @param name The name of the LP token
    /// @param symbol The symbol of the LP token
    constructor(
        IERC20 _asset,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC4626(_asset) Ownable(msg.sender) {}

    /// @notice Sets an address as authorized or unauthorized
    /// @param addr The address to set
    /// @param isAuthorized Whether the address should be authorized
    function setAuthorizedAddress(address addr, bool isAuthorized) external onlyOwner {
        authorizedAddresses[addr] = isAuthorized;
        emit AuthorizedAddressSet(addr, isAuthorized);
    }

    /// @notice Deposits collateral for a user
    /// @param user The address of the user
    /// @param amount The amount of collateral to deposit
    function depositCollateral(address user, uint256 amount) 
        external 
        override 
        onlyAuthorized 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be > 0");
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        userCollateral[user] += amount;
        totalTraderCollateral += amount;
        emit CollateralDeposited(user, amount);
    }

    /// @notice Withdraws collateral for a user
    /// @param user The address of the user
    /// @param amount The amount of collateral to withdraw
    function withdrawCollateral(address user, uint256 amount) 
        external 
        override 
        onlyAuthorized 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be > 0");
        require(userCollateral[user] >= amount, "Insufficient collateral");
        userCollateral[user] -= amount;
        totalTraderCollateral -= amount;
        IERC20(asset()).safeTransfer(user, amount);
        emit CollateralWithdrawn(user, amount);
    }

    /// @notice Locks margin for a user's position
    /// @param user The address of the user
    /// @param amount The amount of margin to lock
    function lockMargin(address user, uint256 amount) 
        external 
        override 
        onlyAuthorized 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be > 0");
        require(userCollateral[user] >= amount, "Insufficient collateral");
        userCollateral[user] -= amount;
        userLockedMargin[user] += amount;
        emit MarginLocked(user, amount);
    }

    /// @notice Releases locked margin for a user's position
    /// @param user The address of the user
    /// @param amount The amount of margin to release
    function releaseMargin(address user, uint256 amount) 
        external 
        override 
        onlyAuthorized 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be > 0");
        require(userLockedMargin[user] >= amount, "Insufficient locked margin");
        userLockedMargin[user] -= amount;
        userCollateral[user] += amount;
        emit MarginReleased(user, amount);
    }

    /// @notice Pays out profits to a trader
    /// @param user The address of the trader
    /// @param amount The amount to payout
    function payoutTrader(address user, uint256 amount) 
        external 
        override 
        onlyAuthorized 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be > 0");
        require(getAvailableLiquidity() >= amount, "Insufficient liquidity");
        IERC20(asset()).safeTransfer(user, amount);
        emit TraderPayout(user, amount);
    }

    /// @notice Sends loss to the insurance fund
    /// @param amount The amount of loss to send
    function sendLossToInsurance(uint256 amount) 
        external 
        override 
        onlyAuthorized 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be > 0");
        require(insuranceFund >= amount, "Insufficient insurance");
        insuranceFund -= amount;
        emit InsuranceLoss(amount);
    }

    /// @notice Returns the current balance of the insurance fund
    /// @return The insurance fund balance
    function insuranceBalance() external view override returns (uint256) {
        return insuranceFund;
    }

    /// @notice Adds funds to the insurance fund
    /// @param amount The amount to add to the insurance fund
    function insuranceTopUp(uint256 amount) 
        external 
        override 
        onlyAuthorized 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be > 0");
        require(insuranceFund + amount <= MAX_INSURANCE_CAP, "Exceeds insurance cap");
        insuranceFund += amount;
        emit InsuranceTopUp(amount);
    }

    /// @notice Credits fees to LP positions
    /// @param amount The amount of fees to credit
    function creditFeeToLP(uint256 amount) 
        external 
        override 
        onlyAuthorized 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be > 0");
        // Mint LP shares for the fee amount
        _mint(address(this), convertToShares(amount));
        emit FeeCredited(amount);
    }

    /// @notice Returns the available liquidity in the vault
    /// @return The amount of available liquidity
    function getAvailableLiquidity() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - insuranceFund;
    }

    /// @notice Returns a user's available collateral
    /// @param user The address of the user
    /// @return The amount of available collateral
    function getUserCollateral(address user) external view override returns (uint256) {
        return userCollateral[user];
    }

    /// @notice Returns a user's locked margin
    /// @param user The address of the user
    /// @return The amount of locked margin
    function getUserLockedMargin(address user) external view override returns (uint256) {
        return userLockedMargin[user];
    }

    /// @notice Pauses the vault
    function pause() external override onlyOwner {
        _pause();
    }

    /// @notice Unpauses the vault
    function unpause() external override onlyOwner {
        _unpause();
    }

    /// @notice Returns the total assets in the vault (excluding insurance and trader collateral)
    /// @return The total amount of assets
    function totalAssets() public view override(IERC4626, ERC4626) returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - insuranceFund - totalTraderCollateral;
    }

    /// @notice Returns the total trader collateral (available + locked)
    function totalTraderCollateralLocked() public view returns (uint256) {
        return totalTraderCollateral;
    }

    /// @notice Returns the total margin balance for a user (available + locked)
    /// @param user The address of the user
    /// @return The total margin balance
    function getTotalMarginBalance(address user) external view returns (uint256) {
        return userCollateral[user] + userLockedMargin[user];
    }

    /// @notice Returns the free (available) margin for a user
    /// @param user The address of the user
    /// @return The free margin amount
    function getFreeMargin(address user) external view returns (uint256) {
        return userCollateral[user];
    }

    /// @notice Preview the redemption value for an LP
    function previewRedemptionValue(address lp) external view returns (uint256) {
        uint256 shares = balanceOf(lp);
        return convertToAssets(shares);
    }
}
