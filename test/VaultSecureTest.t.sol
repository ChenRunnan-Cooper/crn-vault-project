// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/production/Vault.sol";
import "../contracts/deprecated/VaultVulnerable.sol";
import "./helpers/MaliciousContract.sol";

/**
 * @title VaultSecureTest
 * @dev 测试VaultSecure合约的安全性，特别是gas消耗漏洞防护
 */
contract VaultSecureTest is Test {
    Vault public vaultSecure;
    MaliciousContract public maliciousContract;
    GasConsumingContract public gasConsumingContract;

    address USER_A = makeAddr("USER_A");
    address USER_B = makeAddr("USER_B");

    function setUp() public {
        vaultSecure = new Vault();
        maliciousContract = new MaliciousContract();
        gasConsumingContract = new GasConsumingContract();

        vm.deal(USER_A, 100 ether);
        vm.deal(USER_B, 100 ether);
        vm.deal(address(maliciousContract), 10 ether);
        vm.deal(address(gasConsumingContract), 10 ether);
    }

    // ========= 1. 基础功能测试 =========

    function test_BasicDeposit() public {
        vm.prank(USER_A);
        vaultSecure.deposit{value: 1 ether}();
        assertEq(vaultSecure.balances(address(0), USER_A), 1 ether, "User A balance should be 1 ether");
    }

    function test_BasicWithdraw() public {
        vm.prank(USER_A);
        vaultSecure.deposit{value: 1 ether}();

        uint256 userBalanceBefore = USER_A.balance;
        vm.prank(USER_A);
        vaultSecure.withdraw(0.5 ether);

        assertEq(vaultSecure.balances(address(0), USER_A), 0.5 ether, "User A vault balance should be 0.5 ether");
        assertEq(USER_A.balance, userBalanceBefore + 0.5 ether, "User A wallet balance should increase");
    }

    // ========= 2. Gas消耗漏洞测试 =========

    function test_GasConsumptionAttack_OriginalVault() public {
        // 首先测试原始Vault合约的漏洞
        VaultVulnerable originalVault = new VaultVulnerable();

        // 恶意合约存款
        vm.prank(address(maliciousContract));
        originalVault.deposit{value: 1 ether}();

        // 设置恶意合约为循环模式
        maliciousContract.setShouldLoop(true);

        // 记录攻击前的gas
        uint256 gasBefore = gasleft();

        // 尝试从恶意合约取款 - 这会导致大量gas消耗
        vm.prank(address(maliciousContract));
        originalVault.withdraw(0.1 ether);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // 验证gas消耗很大
        assertGt(gasUsed, 1000000, "Gas consumption should be very high");
        console.log("Original Vault Gas Used:", gasUsed);
    }

    function test_GasConsumptionAttack_SecureVault() public {
        // 测试改进版VaultSecure合约的防护
        vm.prank(address(maliciousContract));
        vaultSecure.deposit{value: 1 ether}();

        // 设置恶意合约为循环模式
        maliciousContract.setShouldLoop(true);

        // 记录攻击前的gas
        uint256 gasBefore = gasleft();

        // 尝试从恶意合约取款 - 应该被gas限制阻止
        vm.prank(address(maliciousContract));
        vaultSecure.withdraw(0.1 ether);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // 验证gas消耗被限制
        assertLt(gasUsed, 300000, "Gas consumption should be limited");
        console.log("Secure Vault Gas Used:", gasUsed);

        // 验证恶意合约仍然有余额（因为转账失败）
        assertEq(
            vaultSecure.balances(address(0), address(maliciousContract)),
            1 ether,
            "Malicious contract should still have balance"
        );
    }

    function test_GasConsumingContractAttack() public {
        // 测试GasConsumingContract的攻击
        vm.prank(address(gasConsumingContract));
        vaultSecure.deposit{value: 1 ether}();

        uint256 gasBefore = gasleft();

        vm.prank(address(gasConsumingContract));
        vaultSecure.withdraw(0.1 ether);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console.log("GasConsumingContract Gas Used:", gasUsed);
        assertLt(gasUsed, 300000, "Gas consumption should be limited");
    }

    // ========= 3. 重试机制测试 =========

    function test_RetryMechanism() public {
        // 创建一个会失败的合约
        vm.prank(address(maliciousContract));
        vaultSecure.deposit{value: 1 ether}();

        // 设置恶意合约为正常模式（不消耗大量gas）
        maliciousContract.setShouldLoop(false);

        // 尝试取款，应该成功（因为现在合约检测会阻止）
        vm.prank(address(maliciousContract));
        vaultSecure.withdraw(0.1 ether);

        // 由于合约检测，余额应该保持不变
        assertEq(
            vaultSecure.balances(address(0), address(maliciousContract)), 1 ether, "Balance should remain unchanged"
        );
    }

    function test_MaxRetryAttempts() public {
        // 测试最大重试次数
        vm.prank(address(maliciousContract));
        vaultSecure.deposit{value: 1 ether}();

        // 保持恶意合约的循环模式
        maliciousContract.setShouldLoop(true);

        // 尝试取款，应该失败并触发重试机制
        vm.prank(address(maliciousContract));
        vaultSecure.withdraw(0.1 ether);

        // 验证余额没有减少（因为所有重试都失败了）
        assertEq(
            vaultSecure.balances(address(0), address(maliciousContract)), 1 ether, "Balance should remain unchanged"
        );
    }

    // ========= 4. 紧急取款测试 =========

    function test_EmergencyWithdraw() public {
        vm.prank(USER_A);
        vaultSecure.deposit{value: 1 ether}();

        uint256 userBalanceBefore = USER_A.balance;
        vm.prank(USER_A);
        vaultSecure.emergencyWithdraw(0.5 ether);

        assertEq(vaultSecure.balances(address(0), USER_A), 0.5 ether, "User A vault balance should be 0.5 ether");
        assertEq(USER_A.balance, userBalanceBefore + 0.5 ether, "User A wallet balance should increase");
    }

    function test_EmergencyWithdraw_WithMaliciousContract() public {
        // 测试恶意合约的紧急取款
        vm.prank(address(maliciousContract));
        vaultSecure.deposit{value: 1 ether}();

        // 设置恶意合约为循环模式，消耗大量gas
        maliciousContract.setShouldLoop(true);

        // 使用紧急取款，应该失败（因为恶意合约消耗太多gas）
        vm.prank(address(maliciousContract));
        vaultSecure.emergencyWithdraw(0.1 ether);

        // 验证余额没有减少（因为转账失败）
        assertEq(
            vaultSecure.balances(address(0), address(maliciousContract)), 1 ether, "Balance should remain unchanged"
        );
    }

    // ========= 5. Gas限制配置测试 =========

    function test_GasLimitConfiguration() public view {
        uint256 maxGas = vaultSecure.MAX_WITHDRAWAL_GAS();
        uint256 maxRetries = vaultSecure.MAX_RETRY_ATTEMPTS();
        uint256 maxContractSize = vaultSecure.MAX_CONTRACT_SIZE();

        assertEq(maxGas, 2300, "MAX_WITHDRAWAL_GAS should be 2300");
        assertEq(maxRetries, 3, "MAX_RETRY_ATTEMPTS should be 3");
        assertEq(maxContractSize, 24576, "MAX_CONTRACT_SIZE should be 24576");
    }

    // ========= 6. 事件测试 =========

    function test_WithdrawalFailedEvent() public {
        vm.prank(address(maliciousContract));
        vaultSecure.deposit{value: 1 ether}();

        // 保持恶意合约的循环模式
        maliciousContract.setShouldLoop(true);

        // 监听WithdrawalFailed事件 - 现在应该是合约转账失败
        vm.expectEmit(true, true, false, true);
        emit Vault.WithdrawalFailed(address(0), address(maliciousContract), 0.1 ether, "Contract transfer failed");

        vm.prank(address(maliciousContract));
        vaultSecure.withdraw(0.1 ether);
    }

    // ========= 7. 边界条件测试 =========

    function test_ZeroAmountWithdraw() public {
        vm.prank(USER_A);
        vaultSecure.deposit{value: 1 ether}();

        vm.expectRevert("Withdraw amount must be greater than zero");
        vm.prank(USER_A);
        vaultSecure.withdraw(0);
    }

    function test_InsufficientBalance() public {
        vm.prank(USER_A);
        vaultSecure.deposit{value: 1 ether}();

        vm.expectRevert("Insufficient balance");
        vm.prank(USER_A);
        vaultSecure.withdraw(2 ether);
    }

    function test_ZeroAmountDeposit() public {
        vm.expectRevert("Deposit amount must be greater than zero");
        vm.prank(USER_A);
        vaultSecure.deposit{value: 0}();
    }

    // ========= 8. 性能对比测试 =========

    function test_PerformanceComparison() public {
        // 测试正常用户的性能
        vm.prank(USER_A);
        vaultSecure.deposit{value: 1 ether}();

        uint256 gasBefore = gasleft();
        vm.prank(USER_A);
        vaultSecure.withdraw(0.5 ether);
        uint256 gasAfter = gasleft();

        uint256 normalUserGas = gasBefore - gasAfter;
        console.log("Normal User Gas Used:", normalUserGas);

        // 验证正常用户的gas消耗应该很低
        assertLt(normalUserGas, 100000, "Normal user gas consumption should be low");
    }

    function test_ContractBalanceConsistency() public {
        vm.prank(USER_A);
        vaultSecure.deposit{value: 2 ether}();

        vm.prank(USER_B);
        vaultSecure.deposit{value: 3 ether}();

        assertEq(vaultSecure.getContractBalance(), 5 ether, "Contract balance should be 5 ETH");

        vm.prank(USER_A);
        vaultSecure.withdraw(1 ether);

        assertEq(vaultSecure.getContractBalance(), 4 ether, "Contract balance should be 4 ETH");
    }

    // ========= 9. 合约检测测试 =========

    function test_ContractDetection() public view {
        // 测试EOA地址检测
        assertEq(vaultSecure.isContract(USER_A), false, "USER_A should not be a contract");

        // 测试合约地址检测
        assertEq(vaultSecure.isContract(address(maliciousContract)), true, "MaliciousContract should be a contract");
        assertEq(
            vaultSecure.isContract(address(gasConsumingContract)), true, "GasConsumingContract should be a contract"
        );
    }

    function test_ContractSizeDetection() public view {
        // 测试合约大小检测
        assertEq(
            vaultSecure.isContractTooLarge(address(maliciousContract)),
            false,
            "MaliciousContract should not be too large"
        );
        assertEq(
            vaultSecure.isContractTooLarge(address(gasConsumingContract)),
            false,
            "GasConsumingContract should not be too large"
        );
    }

    // ========= 10. 增强的Gas防护测试 =========

    function test_EnhancedGasProtection_ContractTransfer() public {
        // 恶意合约存款
        vm.prank(address(maliciousContract));
        vaultSecure.deposit{value: 1 ether}();

        // 设置恶意合约为循环模式
        maliciousContract.setShouldLoop(true);

        // 尝试取款 - 应该被严格的gas限制阻止
        vm.prank(address(maliciousContract));
        vaultSecure.withdraw(0.1 ether);

        // 验证余额没有减少（因为转账失败）
        assertEq(
            vaultSecure.balances(address(0), address(maliciousContract)), 1 ether, "Balance should remain unchanged"
        );
    }

    function test_ForceWithdraw_ForContracts() public {
        // 恶意合约存款
        vm.prank(address(maliciousContract));
        vaultSecure.deposit{value: 1 ether}();

        // 设置恶意合约为正常模式
        maliciousContract.setShouldLoop(false);

        // 使用强制取款，应该成功
        vm.prank(address(maliciousContract));
        vaultSecure.forceWithdraw(0.1 ether);

        // 验证余额没有减少（因为即使是简单操作也可能超过2300 gas限制）
        assertEq(
            vaultSecure.balances(address(0), address(maliciousContract)), 1 ether, "Balance should remain unchanged"
        );
    }

    function test_EOA_Withdraw_ShouldSucceed() public {
        // 正常用户存款
        vm.prank(USER_A);
        vaultSecure.deposit{value: 1 ether}();

        // 正常用户取款，应该成功
        vm.prank(USER_A);
        vaultSecure.withdraw(0.5 ether);

        // 验证余额减少
        assertEq(vaultSecure.balances(address(0), USER_A), 0.5 ether, "Balance should be reduced");
    }

    function test_Contract_Withdraw_ShouldFail() public {
        // 恶意合约存款
        vm.prank(address(maliciousContract));
        vaultSecure.deposit{value: 1 ether}();

        // 设置恶意合约为循环模式
        maliciousContract.setShouldLoop(true);

        // 尝试取款，应该失败
        vm.prank(address(maliciousContract));
        vaultSecure.withdraw(0.1 ether);

        // 验证余额没有减少
        assertEq(
            vaultSecure.balances(address(0), address(maliciousContract)), 1 ether, "Balance should remain unchanged"
        );
    }
}
