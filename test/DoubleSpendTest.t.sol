// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/deprecated/VaultVulnerable.sol";

/**
 * @title DoubleSpendTest
 * @dev 专门测试双花攻击场景的测试合约
 */
contract DoubleSpendTest is Test {
    VaultVulnerable public vault;
    address USER_A = makeAddr("USER_A");

    function setUp() public {
        vault = new VaultVulnerable();
        vm.deal(USER_A, 100 ether);
    }

    /**
     * @dev 测试正常取款后余额正确减少，防止双花
     */
    function test_DoubleSpend_PreventedByStateUpdate() public {
        // 用户存入 2 ETH
        vm.prank(USER_A);
        vault.deposit{value: 2 ether}();
        assertEq(vault.balances(USER_A), 2 ether, "Initial balance should be 2 ETH");

        // 第一次取款 1 ETH
        vm.prank(USER_A);
        vault.withdraw(1 ether);
        assertEq(vault.balances(USER_A), 1 ether, "Balance after first withdrawal should be 1 ETH");

        // 尝试第二次取款 1 ETH - 应该成功
        vm.prank(USER_A);
        vault.withdraw(1 ether);
        assertEq(vault.balances(USER_A), 0, "Balance after second withdrawal should be 0");

        // 尝试第三次取款 - 应该失败（双花防护）
        vm.expectRevert("Insufficient balance");
        vm.prank(USER_A);
        vault.withdraw(0.1 ether);
    }

    /**
     * @dev 测试尝试提取超过余额的金额被拒绝
     */
    function test_DoubleSpend_PreventedByBalanceCheck() public {
        // 用户存入 1 ETH
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();
        assertEq(vault.balances(USER_A), 1 ether, "Initial balance should be 1 ETH");

        // 尝试提取超过余额的金额 - 应该失败
        vm.expectRevert("Insufficient balance");
        vm.prank(USER_A);
        vault.withdraw(1.1 ether);

        // 验证余额没有被修改
        assertEq(vault.balances(USER_A), 1 ether, "Balance should remain unchanged");
    }

    /**
     * @dev 测试多次小额取款的总和不超过存款金额
     */
    function test_DoubleSpend_PreventedByAccumulatedWithdrawals() public {
        // 用户存入 1 ETH
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();
        assertEq(vault.balances(USER_A), 1 ether, "Initial balance should be 1 ETH");

        // 多次小额取款
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(USER_A);
            vault.withdraw(0.1 ether);
        }

        // 验证余额为 0
        assertEq(vault.balances(USER_A), 0, "Balance should be 0 after all withdrawals");

        // 尝试再次取款 - 应该失败
        vm.expectRevert("Insufficient balance");
        vm.prank(USER_A);
        vault.withdraw(0.1 ether);
    }

    /**
     * @dev 测试在同一个区块内多次取款的总和不超过余额
     */
    function test_DoubleSpend_PreventedInSameBlock() public {
        // 用户存入 1 ETH
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();
        assertEq(vault.balances(USER_A), 1 ether, "Initial balance should be 1 ETH");

        // 在同一个区块内多次取款
        vm.prank(USER_A);
        vault.withdraw(0.3 ether);

        vm.prank(USER_A);
        vault.withdraw(0.3 ether);

        vm.prank(USER_A);
        vault.withdraw(0.3 ether);

        // 验证余额为 0.1 ETH
        assertEq(vault.balances(USER_A), 0.1 ether, "Balance should be 0.1 ETH");

        // 尝试提取剩余的 0.1 ETH
        vm.prank(USER_A);
        vault.withdraw(0.1 ether);
        assertEq(vault.balances(USER_A), 0, "Balance should be 0");

        // 尝试再次取款 - 应该失败
        vm.expectRevert("Insufficient balance");
        vm.prank(USER_A);
        vault.withdraw(0.1 ether);
    }

    /**
     * @dev 测试合约总余额与用户余额总和的一致性
     */
    function test_DoubleSpend_ContractBalanceConsistency() public {
        address USER_B = makeAddr("USER_B");
        vm.deal(USER_B, 100 ether);

        // 两个用户分别存款
        vm.prank(USER_A);
        vault.deposit{value: 2 ether}();

        vm.prank(USER_B);
        vault.deposit{value: 3 ether}();

        // 验证合约总余额
        assertEq(address(vault).balance, 5 ether, "Contract total balance should be 5 ETH");

        // 用户A取款
        vm.prank(USER_A);
        vault.withdraw(1 ether);
        assertEq(vault.balances(USER_A), 1 ether, "User A balance should be 1 ETH");
        assertEq(address(vault).balance, 4 ether, "Contract balance should be 4 ETH");

        // 用户B取款
        vm.prank(USER_B);
        vault.withdraw(2 ether);
        assertEq(vault.balances(USER_B), 1 ether, "User B balance should be 1 ETH");
        assertEq(address(vault).balance, 2 ether, "Contract balance should be 2 ETH");

        // 验证合约余额等于用户余额总和
        assertEq(
            address(vault).balance,
            vault.balances(USER_A) + vault.balances(USER_B),
            "Contract balance should equal sum of user balances"
        );
    }
}
