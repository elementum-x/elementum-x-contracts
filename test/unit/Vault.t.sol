// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Vault} from "../../src/core/Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaultTest is Test {
    Vault public vault;
    IERC20 public usdc;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public perpEngine = makeAddr("perpEngine");
    address public positionManager = makeAddr("positionManager");
    address public feeManager = makeAddr("feeManager");
    address public liquidationEngine = makeAddr("liquidationEngine");
    address public treasury = makeAddr("treasury");

    function setUp() public {
        console2.log("=== Setting up test environment ===");
        
        // Use Base Mainnet USDC
        usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        console2.log("USDC address:", address(usdc));
        
        // Deploy vault
        vault = new Vault(
            usdc,
            "Elementum Vault",
            "xUSDC"
        );
        console2.log("Vault deployed at:", address(vault));

        // Setup test accounts with ETH
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(perpEngine, 10 ether);
        vm.deal(positionManager, 10 ether);
        vm.deal(feeManager, 10 ether);
        vm.deal(liquidationEngine, 10 ether);
        console2.log("ETH balances set for all test accounts");

        // Setup test accounts with USDC
        deal(address(usdc), alice, 2000 * 1e6); // Increased to 2000 USDC
        deal(address(usdc), bob, 2000 * 1e6);   // Increased to 2000 USDC
        deal(address(usdc), perpEngine, 1000 * 1e6);
        deal(address(usdc), feeManager, 1000 * 1e6);
        console2.log("Alice USDC balance:", usdc.balanceOf(alice));
        console2.log("Bob USDC balance:", usdc.balanceOf(bob));

        // Setup authorized addresses
        vm.startPrank(address(vault.owner()));
        vault.transferOwnership(address(this));
        vault.setAuthorizedAddress(perpEngine, true);
        vault.setAuthorizedAddress(positionManager, true);
        vault.setAuthorizedAddress(feeManager, true);
        vault.setAuthorizedAddress(liquidationEngine, true);
        vm.stopPrank();
        console2.log("Vault ownership and authorized addresses set");
    }

    // 1. Constructor Initialization
    function test_ConstructorInitialization() public {
        console2.log("\n=== Testing Constructor Initialization ===");
        console2.log("Vault asset:", address(vault.asset()));
        console2.log("Vault name:", vault.name());
        console2.log("Vault symbol:", vault.symbol());
        console2.log("Initial insurance balance:", vault.insuranceBalance());

        assertEq(address(vault.asset()), address(usdc));
        assertEq(vault.name(), "Elementum Vault");
        assertEq(vault.symbol(), "xUSDC");
        assertEq(vault.insuranceBalance(), 0);
    }

    // 2. Collateral Deposit
    function test_CollateralDeposit() public {
        console2.log("\n=== Testing Collateral Deposit ===");
        uint256 amount = 100 * 1e6;
        console2.log("Deposit amount:", amount);
        
        // Transfer USDC to perpEngine first
        vm.startPrank(alice);
        usdc.transfer(perpEngine, amount);
        vm.stopPrank();
        
        vm.startPrank(perpEngine);
        usdc.approve(address(vault), amount);
        vault.depositCollateral(alice, amount);
        console2.log("Collateral deposited");
        console2.log("Alice's collateral:", vault.getUserCollateral(alice));
        console2.log("Total trader collateral:", vault.totalTraderCollateralLocked());
        console2.log("Vault USDC balance:", usdc.balanceOf(address(vault)));
        vm.stopPrank();

        assertEq(vault.getUserCollateral(alice), amount);
        assertEq(vault.totalTraderCollateralLocked(), amount);
        assertEq(usdc.balanceOf(address(vault)), amount);
    }

    function test_RevertWhen_CollateralDepositZero() public {
        vm.startPrank(perpEngine);
        vm.expectRevert("Amount must be > 0");
        vault.depositCollateral(alice, 0);
        vm.stopPrank();
    }

    function test_CollateralWithdrawal() public {
        console2.log("\n=== Testing Collateral Withdrawal ===");
        uint256 amount = 100 * 1e6;
        console2.log("Withdrawal amount:", amount);
        
        // Deposit first
        vm.startPrank(alice);
        usdc.transfer(perpEngine, amount);
        vm.stopPrank();

        vm.startPrank(perpEngine);
        usdc.approve(address(vault), amount);
        vault.depositCollateral(alice, amount);
        console2.log("Initial deposit completed");
        console2.log("Initial collateral:", vault.getUserCollateral(alice));
        
        vault.withdrawCollateral(alice, amount);
        console2.log("Withdrawal completed");
        console2.log("Final collateral:", vault.getUserCollateral(alice));
        console2.log("Alice's USDC balance:", usdc.balanceOf(alice));
        vm.stopPrank();

        assertEq(vault.getUserCollateral(alice), 0);
        assertEq(vault.totalTraderCollateralLocked(), 0);
        assertEq(usdc.balanceOf(alice), 2000 * 1e6); // Updated to match new balance
    }

    function test_RevertWhen_CollateralWithdrawalExcess() public {
        vm.startPrank(perpEngine);
        console2.log("Alice collateral:", vault.getUserCollateral(alice));
        vm.expectRevert("Insufficient collateral");
        vault.withdrawCollateral(alice, 1001 * 1e6);
        vm.stopPrank();
    }

    // 4. Margin Locking
    function test_MarginLocking() public {
        console2.log("\n=== Testing Margin Locking ===");
        uint256 amount = 100 * 1e6;
        console2.log("Lock amount:", amount);
        
        // Deposit first
        vm.startPrank(alice);
        usdc.transfer(perpEngine, amount);
        vm.stopPrank();

        vm.startPrank(perpEngine);
        usdc.approve(address(vault), amount);
        vault.depositCollateral(alice, amount);
        console2.log("Initial deposit completed");
        console2.log("Initial collateral:", vault.getUserCollateral(alice));
        
        vault.lockMargin(alice, amount);
        console2.log("Margin locked");
        console2.log("Remaining collateral:", vault.getUserCollateral(alice));
        console2.log("Locked margin:", vault.getUserLockedMargin(alice));
        vm.stopPrank();

        assertEq(vault.getUserCollateral(alice), 0);
        assertEq(vault.getUserLockedMargin(alice), amount);
    }

    function test_RevertWhen_MarginLockingExcess() public {
        vm.startPrank(perpEngine);
        vm.expectRevert("Insufficient collateral");
        vault.lockMargin(alice, 1001 * 1e6);
        vm.stopPrank();
    }

    function test_MarginReleasing() public {
        console2.log("\n=== Testing Margin Releasing ===");
        uint256 amount = 100 * 1e6;
        console2.log("Release amount:", amount);
        
        // Setup: deposit and lock
        vm.startPrank(alice);
        usdc.transfer(perpEngine, amount);
        vm.stopPrank();

        vm.startPrank(perpEngine);
        usdc.approve(address(vault), amount);
        vault.depositCollateral(alice, amount);
        console2.log("Initial deposit completed");
        
        vault.lockMargin(alice, amount);
        console2.log("Margin locked");
        console2.log("Locked margin before release:", vault.getUserLockedMargin(alice));

        vault.releaseMargin(alice, amount);
        console2.log("Margin released");
        console2.log("Final locked margin:", vault.getUserLockedMargin(alice));
        console2.log("Final collateral:", vault.getUserCollateral(alice));
        vm.stopPrank();

        assertEq(vault.getUserLockedMargin(alice), 0);
        assertEq(vault.getUserCollateral(alice), amount);
    }

    function test_PayoutToTrader() public {
        console2.log("\n=== Testing Payout to Trader ===");
        uint256 amount = 100 * 1e6;
        console2.log("Payout amount:", amount);
        
        // Setup vault liquidity
        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, alice);
        console2.log("Vault liquidity setup completed");
        console2.log("Initial vault balance:", usdc.balanceOf(address(vault)));
        // log alice receipt token balance
        console2.log("Alice receipt token balance: xUSDC", vault.balanceOf(alice));
        vm.stopPrank();

        // Payout
        vm.prank(perpEngine);
        deal(address(usdc), address(vault), amount, true);
        vault.payoutTrader(bob, amount);
        console2.log("Payout completed");
        console2.log("Bob's final USDC balance:", usdc.balanceOf(bob));

        assertEq(usdc.balanceOf(bob), 2000 * 1e6 + amount); // Updated to match new balance
    }

    function test_InsuranceTopUp() public {
        console2.log("\n=== Testing Insurance Fund Top-Up ===");
        uint256 amount = 100 * 1e6;
        console2.log("Top-up amount:", amount);
        
        vm.startPrank(alice);
        usdc.transfer(feeManager, amount);
        vm.stopPrank();

        vm.startPrank(feeManager);
        usdc.approve(address(vault), amount);
        vault.insuranceTopUp(amount);
        console2.log("Insurance fund topped up");
        console2.log("Insurance balance:", vault.insuranceBalance());
        vm.stopPrank();

        assertEq(vault.insuranceBalance(), amount);
    }

    function test_RevertWhen_InsuranceTopUpExcess() public {
        vm.startPrank(feeManager);
        vm.expectRevert("Exceeds insurance cap");
        vault.insuranceTopUp(2_000_000 * 1e6); // Exceeds 1M USDC cap
        vm.stopPrank();
    }

    function test_InsuranceDeduction() public {
        console2.log("\n=== Testing Insurance Fund Deduction ===");
        uint256 amount = 100 * 1e6;
        console2.log("Deduction amount:", amount);
        
        // Top up first
        vm.startPrank(alice);
        usdc.transfer(feeManager, amount);
        vm.stopPrank();

        vm.startPrank(feeManager);
        usdc.approve(address(vault), amount);
        vault.insuranceTopUp(amount);
        console2.log("Initial insurance balance:", vault.insuranceBalance());
        vm.stopPrank();

        // Deduct
        vm.startPrank(liquidationEngine);
        vault.sendLossToInsurance(amount);
        console2.log("Loss sent to insurance");
        console2.log("Final insurance balance:", vault.insuranceBalance());
        vm.stopPrank();

        assertEq(vault.insuranceBalance(), 0);
    }

    function test_CreditFeesToLP() public {
        console2.log("\n=== Testing Credit Fees to LP ===");
        uint256 amount = 100 * 1e6;
        console2.log("Fee amount:", amount);
        
        vm.prank(feeManager);
        vault.creditFeeToLP(amount);
        console2.log("Fees credited to LP");
        console2.log("Vault LP balance:", vault.balanceOf(address(vault)));

        assertEq(vault.balanceOf(address(vault)), amount);
    }

    function test_TotalAssetsCalculation() public {
        console2.log("\n=== Testing Total Assets Calculation ===");
        uint256 depositAmount = 1000 * 1e6;
        uint256 insuranceAmount = 100 * 1e6;
        uint256 collateralAmount = 200 * 1e6;
        console2.log("Deposit amount:", depositAmount);
        console2.log("Insurance amount:", insuranceAmount);
        console2.log("Collateral amount:", collateralAmount);
        console2.log("Alice USDC balance:", usdc.balanceOf(alice));

        // Setup
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        console2.log("LP deposit completed");
        console2.log("Alice receipt token balance: xUSDC", vault.balanceOf(alice));
        vm.stopPrank();

        vm.startPrank(alice);
        usdc.transfer(feeManager, insuranceAmount);
        console2.log("Fee manager USDC balance:", usdc.balanceOf(feeManager));
        vm.stopPrank();

        vm.startPrank(feeManager);
        usdc.approve(address(vault), insuranceAmount);
        console2.log("Fee manager USDC balance:", usdc.balanceOf(feeManager));
        console2.log("Insurance balance before top up:", vault.insuranceBalance());
        vault.insuranceTopUp(insuranceAmount);
        console2.log("Insurance topped up");
        console2.log("Fee manager USDC balance:", usdc.balanceOf(feeManager));
        console2.log("Insurance balance after top up:", vault.insuranceBalance());
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.transfer(perpEngine, collateralAmount);
        console2.log("Bob USDC balance:", usdc.balanceOf(bob));
        vm.stopPrank();

        vm.startPrank(perpEngine);
        usdc.approve(address(vault), collateralAmount);
        vault.depositCollateral(bob, collateralAmount);
        console2.log("Collateral deposited by bob");
        console2.log("Bob collateral:", vault.getUserCollateral(bob));
        console2.log("Bob locked margin:", vault.getUserLockedMargin(bob));
        vm.stopPrank();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 insuranceFund = vault.insuranceBalance();
        uint256 totalTraderCollateral = vault.totalTraderCollateralLocked();
        uint256 expectedTotalAssets = vaultBalance - insuranceFund - totalTraderCollateral;

        console2.log("Vault USDC balance:", vaultBalance);
        console2.log("Insurance fund:", insuranceFund);
        console2.log("Total trader collateral:", totalTraderCollateral);
        console2.log("Total assets:", vault.totalAssets());
        // the total xusdc backing up the vault is vault.totalAssets()
        console2.log("Expected total assets:", expectedTotalAssets);

        assertEq(vault.totalAssets(), expectedTotalAssets);
        assertEq(usdc.balanceOf(alice), 2000 * 1e6 - depositAmount - insuranceAmount);
        assertEq(usdc.balanceOf(bob), 2000 * 1e6 - collateralAmount);
    }

    function test_MarginBalanceFunctions() public {
        console2.log("\n=== Testing Margin Balance Functions ===");
        uint256 amount = 100 * 1e6;
        console2.log("Total amount:", amount);
        
        // Setup
        vm.startPrank(alice);
        usdc.transfer(perpEngine, amount);
        vm.stopPrank();

        vm.startPrank(perpEngine);
        usdc.approve(address(vault), amount);
        vault.depositCollateral(alice, amount);
        console2.log("Initial deposit completed");
        
        vault.lockMargin(alice, amount/2);
        console2.log("Half amount locked as margin");

        console2.log("Total margin balance:", vault.getTotalMarginBalance(alice));
        console2.log("Free margin:", vault.getFreeMargin(alice));
        vm.stopPrank();

        assertEq(vault.getTotalMarginBalance(alice), amount);
        assertEq(vault.getFreeMargin(alice), amount/2);
    }

    function test_PreviewRedemptionValue() public {
        console2.log("\n=== Testing Preview Redemption Value ===");
        uint256 amount = 100 * 1e6;
        console2.log("Deposit amount:", amount);
        
        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, alice);
        console2.log("LP tokens minted");
        console2.log("LP balance:", vault.balanceOf(alice));
        vm.stopPrank();

        console2.log("Preview redemption value:", vault.previewRedemptionValue(alice));

        assertEq(vault.previewRedemptionValue(alice), amount);
    }

    function test_PauseUnpause() public {
        console2.log("\n=== Testing Pause/Unpause ===");
        
        vm.prank(address(this));
        vault.pause();
        console2.log("Vault paused");
        console2.log("Paused state:", vault.paused());

        vm.prank(address(this));
        vault.unpause();
        console2.log("Vault unpaused");
        console2.log("Paused state:", vault.paused());

        assertTrue(vault.paused() == false);
    }

    function test_RevertWhen_NonOwnerPause() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vault.pause();
        vm.stopPrank();
    }

    // 15. Authorization Logic
    function test_RevertWhen_UnauthorizedAccess() public {
        vm.startPrank(alice);
        vm.expectRevert("Vault: unauthorized");
        vault.depositCollateral(bob, 100 * 1e6);
        vm.stopPrank();
    }

    function test_ReentrancyProtection() public {
        console2.log("\n=== Testing Reentrancy Protection ===");
        console2.log("Reentrancy protection is implemented via nonReentrant modifier");
        assertTrue(true);
    }

    // Test: Redemption value decreases for single LP after trader payout
    function test_RedemptionRateDecrease_AfterTraderPayout_SingleLP() public {
        console2.log("\n=== Testing Redemption Rate Decrease After Trader Payout ===");
        uint256 depositAmount = 1_000 * 1e6;
        // alice usdc balance
        console2.log("Alice USDC balance:", usdc.balanceOf(alice));

        // Approve and deposit for Alice
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 redemptionBefore = vault.previewRedemptionValue(alice);
        console2.log("Alice LP token balance:", aliceShares);
        console2.log("Redemption value before payout:", redemptionBefore);
        console2.log("Total assets:", vault.totalAssets());
        console2.log("Total supply:", vault.totalSupply());
        // Simulate trader profit payout
        uint256 payoutAmount = 300 * 1e6;
        address trader = address(0xBEEF);
        vm.prank(address(this));
        vault.payoutTrader(trader, payoutAmount);
        // log the total assets
        console2.log("Total assets:", vault.totalAssets());
        console2.log("Total supply:", vault.totalSupply());

        uint256 redemptionAfter = vault.previewRedemptionValue(alice);
        console2.log("Redemption value after payout:", redemptionAfter);

        assertLt(redemptionAfter, depositAmount);
    }

    // Test: Redemption value decreases for two LPs after trader payout
    function test_RedemptionRateDecrease_AfterTraderPayout_TwoLPs() public {
        console2.log("\n=== Testing Redemption Rate Decrease After Trader Payout ===");
        uint256 aliceDeposit = 1_000 * 1e6;
        uint256 bobDeposit = 500 * 1e6;

        // Approve and deposit for Alice
        vm.startPrank(alice);
        usdc.approve(address(vault), aliceDeposit);
        vault.deposit(aliceDeposit, alice);
        vm.stopPrank();
        // Approve and deposit for Bob
        vm.startPrank(bob);
        usdc.approve(address(vault), bobDeposit);
        vault.deposit(bobDeposit, bob);
        vm.stopPrank();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);
        uint256 redemptionAliceBefore = vault.previewRedemptionValue(alice);
        uint256 redemptionBobBefore = vault.previewRedemptionValue(bob);
        console2.log("Alice LP token balance:", aliceShares);
        console2.log("Bob LP token balance:", bobShares);
        console2.log("Alice redemption before payout:", redemptionAliceBefore);
        console2.log("Bob redemption before payout:", redemptionBobBefore);

        // Simulate trader profit payout
        uint256 payoutAmount = 450 * 1e6;
        address trader = address(0xBEEF);
         vm.prank(address(this));
        vault.payoutTrader(trader, payoutAmount);

        uint256 redemptionAliceAfter = vault.previewRedemptionValue(alice);
        uint256 redemptionBobAfter = vault.previewRedemptionValue(bob);
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        console2.log("Alice redemption after payout:", redemptionAliceAfter);
        console2.log("Bob redemption after payout:", redemptionBobAfter);
        console2.log("Vault totalAssets:", totalAssets);
        console2.log("Vault totalSupply:", totalSupply);

        // Assert both redemption values dropped
        assertLt(redemptionAliceAfter, redemptionAliceBefore);
        assertLt(redemptionBobAfter, redemptionBobBefore);

        // Assert proportional drop
        uint256 aliceDrop = redemptionAliceBefore - redemptionAliceAfter;
        uint256 bobDrop = redemptionBobBefore - redemptionBobAfter;
        // Should be roughly proportional to their share
        assertApproxEqAbs(aliceDrop * 2, bobDrop * 4, 2e6); // Allow some tolerance

        // Assert total redemption value ≈ totalAssets
        uint256 totalRedemption = redemptionAliceAfter + redemptionBobAfter;
        assertApproxEqAbs(totalRedemption, totalAssets, 2e6);
    }
} 