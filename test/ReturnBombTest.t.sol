// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/deprecated/VaultVulnerable.sol";
import "../contracts/production/Vault.sol";
import "./helpers/ReturnBombContract.sol";

/**
 * @title ReturnBombTest
 * @dev 测试Return Bomb攻击和防护机制
 */
contract ReturnBombTest is Test {
    VaultVulnerable public vault;
    Vault public vaultSecure;
    ReturnBombContract public returnBombContract;
    LargeReturnDataContract public largeReturnDataContract;
    NormalContract public normalContract;

    address USER_A = makeAddr("USER_A");

    function setUp() public {
        vault = new VaultVulnerable();
        vaultSecure = new Vault();
        returnBombContract = new ReturnBombContract();
        largeReturnDataContract = new LargeReturnDataContract();
        normalContract = new NormalContract();

        vm.deal(USER_A, 100 ether);
        vm.deal(address(returnBombContract), 10 ether);
        vm.deal(address(largeReturnDataContract), 10 ether);
        vm.deal(address(normalContract), 10 ether);
    }

    // ========= 1. Return Bomb攻击测试 =========

    function test_ReturnBombAttack_OriginalVault() public {
        // 恶意合约存款
        vm.prank(address(returnBombContract));
        vault.deposit{value: 1 ether}();

        // 设置恶意合约为Return Bomb模式
        returnBombContract.setShouldReturnBomb(true);

        // 记录攻击前的gas
        uint256 gasBefore = gasleft();

        // 尝试从恶意合约取款 - 应该触发Return Bomb攻击
        vm.prank(address(returnBombContract));
        vault.withdraw(0.1 ether);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Original Vault Return Bomb Gas Used:", gasUsed);
        assertGt(gasUsed, 10000, "Should consume significant gas due to Return Bomb");
    }

    function test_ReturnBombAttack_SecureVault() public {
        // 恶意合约存款
        vm.prank(address(returnBombContract));
        vaultSecure.deposit{value: 1 ether}();

        // 设置恶意合约为Return Bomb模式
        returnBombContract.setShouldReturnBomb(true);

        // 记录攻击前的gas
        uint256 gasBefore = gasleft();

        // 尝试从恶意合约取款 - 应该被防护机制阻止
        vm.prank(address(returnBombContract));
        vaultSecure.withdraw(0.1 ether);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Secure Vault Return Bomb Gas Used:", gasUsed);
        assertLt(gasUsed, 100000, "Gas consumption should be limited");

        // 验证余额没有减少（因为转账失败）
        assertEq(vaultSecure.balances(address(0), address(returnBombContract)), 1 ether, "Balance should remain unchanged");
    }

    function test_LargeReturnDataAttack_OriginalVault() public {
        // 恶意合约存款
        vm.prank(address(largeReturnDataContract));
        vault.deposit{value: 1 ether}();

        // 记录攻击前的gas
        uint256 gasBefore = gasleft();

        // 尝试从恶意合约取款 - 应该触发大量返回数据攻击
        vm.prank(address(largeReturnDataContract));
        vault.withdraw(0.1 ether);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Original Vault Large Return Data Gas Used:", gasUsed);
        assertGt(gasUsed, 10000, "Should consume significant gas due to large return data");
    }

    function test_LargeReturnDataAttack_SecureVault() public {
        // 恶意合约存款
        vm.prank(address(largeReturnDataContract));
        vaultSecure.deposit{value: 1 ether}();

        // 记录攻击前的gas
        uint256 gasBefore = gasleft();

        // 尝试从恶意合约取款 - 应该被防护机制阻止
        vm.prank(address(largeReturnDataContract));
        vaultSecure.withdraw(0.1 ether);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Secure Vault Large Return Data Gas Used:", gasUsed);
        assertLt(gasUsed, 100000, "Gas consumption should be limited");

        // 验证余额没有减少（因为转账失败）
        assertEq(vaultSecure.balances(address(0), address(largeReturnDataContract)), 1 ether, "Balance should remain unchanged");
    }

    // ========= 2. 正常合约测试 =========

    function test_NormalContract_OriginalVault() public {
        // 正常合约存款
        vm.prank(address(normalContract));
        vault.deposit{value: 1 ether}();

        // 记录gas消耗
        uint256 gasBefore = gasleft();

        // 正常合约取款
        vm.prank(address(normalContract));
        vault.withdraw(0.1 ether);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Original Vault Normal Contract Gas Used:", gasUsed);
        assertLt(gasUsed, 100000, "Normal contract gas consumption should be low");
    }

    function test_NormalContract_SecureVault() public {
        // 正常合约存款
        vm.prank(address(normalContract));
        vaultSecure.deposit{value: 1 ether}();

        // 记录gas消耗
        uint256 gasBefore = gasleft();

        // 正常合约取款
        vm.prank(address(normalContract));
        vaultSecure.withdraw(0.1 ether);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Secure Vault Normal Contract Gas Used:", gasUsed);
        assertLt(gasUsed, 100000, "Normal contract gas consumption should be low");

        // 验证余额没有减少（因为合约检测阻止了转账）
        assertEq(vaultSecure.balances(address(0), address(normalContract)), 1 ether, "Balance should remain unchanged");
    }

    // ========= 3. 配置测试 =========

    function test_ReturnDataSizeConfiguration() public view {
        uint256 maxReturnSize = vaultSecure.MAX_RETURN_DATA_SIZE();
        assertEq(maxReturnSize, 256, "MAX_RETURN_DATA_SIZE should be 256 bytes");
    }

    function test_ExcessivelySafeCall_Configuration() public view {
        // 测试极度安全调用的配置
        uint256 maxGas = vaultSecure.MAX_WITHDRAWAL_GAS();
        uint256 maxReturnSize = vaultSecure.MAX_RETURN_DATA_SIZE();

        assertEq(maxGas, 2300, "MAX_WITHDRAWAL_GAS should be 2300");
        assertEq(maxReturnSize, 256, "MAX_RETURN_DATA_SIZE should be 256");
    }

    // ========= 4. 对比测试 =========

    function test_PerformanceComparison_ReturnBomb() public {
        // 测试Return Bomb攻击的性能对比

        // 原始合约
        vm.prank(address(returnBombContract));
        vault.deposit{value: 1 ether}();
        returnBombContract.setShouldReturnBomb(true);

        uint256 gasBefore = gasleft();
        vm.prank(address(returnBombContract));
        vault.withdraw(0.1 ether);
        uint256 gasAfter = gasleft();
        uint256 originalGas = gasBefore - gasAfter;

        // 安全合约
        vm.prank(address(returnBombContract));
        vaultSecure.deposit{value: 1 ether}();
        returnBombContract.setShouldReturnBomb(true);

        gasBefore = gasleft();
        vm.prank(address(returnBombContract));
        vaultSecure.withdraw(0.1 ether);
        gasAfter = gasleft();
        uint256 secureGas = gasBefore - gasAfter;

        console.log("Original Vault Return Bomb Gas:", originalGas);
        console.log("Secure Vault Return Bomb Gas:", secureGas);

        // 验证安全合约的gas消耗更少
        assertLt(secureGas, originalGas, "Secure vault should consume less gas");
    }

    function test_PerformanceComparison_LargeReturnData() public {
        // 测试大量返回数据攻击的性能对比

        // 原始合约
        vm.prank(address(largeReturnDataContract));
        vault.deposit{value: 1 ether}();

        uint256 gasBefore = gasleft();
        vm.prank(address(largeReturnDataContract));
        vault.withdraw(0.1 ether);
        uint256 gasAfter = gasleft();
        uint256 originalGas = gasBefore - gasAfter;

        // 安全合约
        vm.prank(address(largeReturnDataContract));
        vaultSecure.deposit{value: 1 ether}();

        gasBefore = gasleft();
        vm.prank(address(largeReturnDataContract));
        vaultSecure.withdraw(0.1 ether);
        gasAfter = gasleft();
        uint256 secureGas = gasBefore - gasAfter;

        console.log("Original Vault Large Return Data Gas:", originalGas);
        console.log("Secure Vault Large Return Data Gas:", secureGas);

        // 验证安全合约的gas消耗更少
        assertLt(secureGas, originalGas, "Secure vault should consume less gas");
    }

    // ========= 5. 边界测试 =========

    function test_ReturnDataSizeLimit() public {
        // 测试返回数据大小限制
        vm.prank(address(returnBombContract));
        vaultSecure.deposit{value: 1 ether}();

        // 设置恶意合约为Return Bomb模式
        returnBombContract.setShouldReturnBomb(true);

        // 尝试取款，应该失败
        vm.prank(address(returnBombContract));
        vaultSecure.withdraw(0.1 ether);

        // 验证余额没有减少
        assertEq(vaultSecure.balances(address(0), address(returnBombContract)), 1 ether, "Balance should remain unchanged");
    }

    function test_ContractDetection_ReturnBomb() public view {
        // 测试合约检测功能
        assertEq(
            vaultSecure.isContract(address(returnBombContract)),
            true,
            "ReturnBombContract should be detected as contract"
        );
        assertEq(
            vaultSecure.isContract(address(largeReturnDataContract)),
            true,
            "LargeReturnDataContract should be detected as contract"
        );
        assertEq(vaultSecure.isContract(address(normalContract)), true, "NormalContract should be detected as contract");
        assertEq(vaultSecure.isContract(USER_A), false, "USER_A should not be detected as contract");
    }
}
