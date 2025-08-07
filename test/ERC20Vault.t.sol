// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/production/Vault.sol";
import "./helpers/MockERC20.sol";
import "./helpers/MockNonStandardERC20.sol";

/**
 * @title ERC20VaultTest
 * @dev 测试Vault合约的ERC20代币存取功能
 */
contract ERC20VaultTest is Test {
    Vault public vault;
    MockERC20 public standardToken;
    MockNonStandardERC20 public nonStandardToken;

    address USER_A = makeAddr("USER_A");
    address USER_B = makeAddr("USER_B");

    uint256 constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        // 部署Vault合约
        vault = new Vault();

        // 部署标准和非标准ERC20代币
        standardToken = new MockERC20("Standard Token", "STD", 18);
        nonStandardToken = new MockNonStandardERC20("Non-Standard Token", "NST", 18);

        // 为测试用户提供ETH
        vm.deal(USER_A, 100 ether);
        vm.deal(USER_B, 100 ether);

        // 为测试用户提供代币
        standardToken.mint(USER_A, INITIAL_BALANCE);
        standardToken.mint(USER_B, INITIAL_BALANCE);
        nonStandardToken.mint(USER_A, INITIAL_BALANCE);
        nonStandardToken.mint(USER_B, INITIAL_BALANCE);
    }

    // ========= 1. 标准ERC20代币测试 =========

    function test_DepositStandardToken_Success() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(USER_A);

        // 授权Vault合约
        standardToken.approve(address(vault), depositAmount);

        // 存入代币
        vault.depositToken(address(standardToken), depositAmount);

        vm.stopPrank();

        // 验证余额
        assertEq(
            vault.getBalance(address(standardToken), USER_A),
            depositAmount,
            "User balance in vault should match deposit"
        );
        assertEq(standardToken.balanceOf(address(vault)), depositAmount, "Vault token balance should match deposit");
    }

    function test_WithdrawStandardToken_Success() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        vm.startPrank(USER_A);

        // 授权并存入代币
        standardToken.approve(address(vault), depositAmount);
        vault.depositToken(address(standardToken), depositAmount);

        // 记录提取前余额
        uint256 userBalanceBefore = standardToken.balanceOf(USER_A);

        // 提取部分代币
        vault.withdrawToken(address(standardToken), withdrawAmount);

        // 验证余额
        assertEq(
            vault.getBalance(address(standardToken), USER_A),
            depositAmount - withdrawAmount,
            "User vault balance should be reduced"
        );
        assertEq(
            standardToken.balanceOf(USER_A), userBalanceBefore + withdrawAmount, "User wallet balance should increase"
        );
        assertEq(
            standardToken.balanceOf(address(vault)), depositAmount - withdrawAmount, "Vault balance should be reduced"
        );

        vm.stopPrank();
    }

    function test_RevertIf_WithdrawStandardToken_InsufficientBalance() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 200 ether; // 超过存款金额

        vm.startPrank(USER_A);

        // 授权并存入代币
        standardToken.approve(address(vault), depositAmount);
        vault.depositToken(address(standardToken), depositAmount);

        // 尝试提取超额代币，应该失败
        vm.expectRevert("Insufficient balance");
        vault.withdrawToken(address(standardToken), withdrawAmount);

        vm.stopPrank();
    }

    function test_RevertIf_DepositStandardToken_WithoutApproval() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(USER_A);

        // 未授权就尝试存款，应该失败
        vm.expectRevert();
        vault.depositToken(address(standardToken), depositAmount);

        vm.stopPrank();
    }

    function test_RevertIf_DepositStandardToken_ZeroAmount() public {
        vm.startPrank(USER_A);

        // 尝试存入0代币，应该失败
        vm.expectRevert("Deposit amount must be greater than zero");
        vault.depositToken(address(standardToken), 0);

        vm.stopPrank();
    }

    // ========= 2. 非标准ERC20代币测试 =========

    function test_DepositNonStandardToken_Success() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(USER_A);

        // 授权Vault合约
        nonStandardToken.approve(address(vault), depositAmount);

        // 存入非标准代币
        vault.depositToken(address(nonStandardToken), depositAmount);

        vm.stopPrank();

        // 验证余额
        assertEq(
            vault.getBalance(address(nonStandardToken), USER_A),
            depositAmount,
            "User balance in vault should match deposit"
        );
        assertEq(nonStandardToken.balanceOf(address(vault)), depositAmount, "Vault token balance should match deposit");
    }

    function test_WithdrawNonStandardToken_Success() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        vm.startPrank(USER_A);

        // 授权并存入非标准代币
        nonStandardToken.approve(address(vault), depositAmount);
        vault.depositToken(address(nonStandardToken), depositAmount);

        // 记录提取前余额
        uint256 userBalanceBefore = nonStandardToken.balanceOf(USER_A);

        // 提取部分代币
        vault.withdrawToken(address(nonStandardToken), withdrawAmount);

        // 验证余额
        assertEq(
            vault.getBalance(address(nonStandardToken), USER_A),
            depositAmount - withdrawAmount,
            "User vault balance should be reduced"
        );
        assertEq(
            nonStandardToken.balanceOf(USER_A),
            userBalanceBefore + withdrawAmount,
            "User wallet balance should increase"
        );
        assertEq(
            nonStandardToken.balanceOf(address(vault)),
            depositAmount - withdrawAmount,
            "Vault balance should be reduced"
        );

        vm.stopPrank();
    }

    // ========= 3. 多用户多代币测试 =========

    function test_MultiUserMultiToken_Isolation() public {
        // USER_A存入标准代币
        vm.startPrank(USER_A);
        standardToken.approve(address(vault), 100 ether);
        vault.depositToken(address(standardToken), 100 ether);
        vm.stopPrank();

        // USER_B存入非标准代币
        vm.startPrank(USER_B);
        nonStandardToken.approve(address(vault), 50 ether);
        vault.depositToken(address(nonStandardToken), 50 ether);
        vm.stopPrank();

        // 验证余额隔离
        assertEq(vault.getBalance(address(standardToken), USER_A), 100 ether, "USER_A standard token balance");
        assertEq(vault.getBalance(address(standardToken), USER_B), 0, "USER_B standard token balance");
        assertEq(vault.getBalance(address(nonStandardToken), USER_A), 0, "USER_A non-standard token balance");
        assertEq(vault.getBalance(address(nonStandardToken), USER_B), 50 ether, "USER_B non-standard token balance");
    }

    function test_RevertIf_OtherUserWithdraws() public {
        // USER_A存入标准代币
        vm.startPrank(USER_A);
        standardToken.approve(address(vault), 100 ether);
        vault.depositToken(address(standardToken), 100 ether);
        vm.stopPrank();

        // USER_B尝试提取USER_A的代币，应该失败
        vm.startPrank(USER_B);
        vm.expectRevert("Insufficient balance");
        vault.withdrawToken(address(standardToken), 100 ether);
        vm.stopPrank();
    }

    // ========= 4. ETH和ERC20混合测试 =========

    function test_MixedETHAndERC20_Balances() public {
        // USER_A存入ETH
        vm.startPrank(USER_A);
        vault.deposit{value: 5 ether}();
        vm.stopPrank();

        // USER_A存入标准代币
        vm.startPrank(USER_A);
        standardToken.approve(address(vault), 100 ether);
        vault.depositToken(address(standardToken), 100 ether);
        vm.stopPrank();

        // 验证两种资产的余额
        assertEq(vault.getBalance(address(0), USER_A), 5 ether, "USER_A ETH balance");
        assertEq(vault.getBalance(address(standardToken), USER_A), 100 ether, "USER_A token balance");

        // 验证合约余额
        assertEq(address(vault).balance, 5 ether, "Vault ETH balance");
        assertEq(standardToken.balanceOf(address(vault)), 100 ether, "Vault token balance");
    }

    function test_EmergencyWithdrawToken_Success() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        vm.startPrank(USER_A);

        // 授权并存入代币
        standardToken.approve(address(vault), depositAmount);
        vault.depositToken(address(standardToken), depositAmount);

        // 记录提取前余额
        uint256 userBalanceBefore = standardToken.balanceOf(USER_A);

        // 紧急提取代币
        vault.emergencyWithdrawToken(address(standardToken), withdrawAmount);

        // 验证余额
        assertEq(
            vault.getBalance(address(standardToken), USER_A),
            depositAmount - withdrawAmount,
            "User vault balance should be reduced"
        );
        assertEq(
            standardToken.balanceOf(USER_A), userBalanceBefore + withdrawAmount, "User wallet balance should increase"
        );

        vm.stopPrank();
    }

    function test_GetTokenBalance() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(USER_A);
        standardToken.approve(address(vault), depositAmount);
        vault.depositToken(address(standardToken), depositAmount);
        vm.stopPrank();

        assertEq(vault.getTokenBalance(address(standardToken)), depositAmount, "Vault token balance should match");
    }
}
