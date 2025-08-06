// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/deprecated/VaultVulnerable.sol";

contract VaultTest is Test {
    VaultVulnerable public vault;

    // 为了方便测试，我们定义几个虚拟用户地址
    address USER_A = makeAddr("USER_A");
    address USER_B = makeAddr("USER_B");

    // setUp 函数会在每个测试用例运行前被调用
    function setUp() public {
        // 创建一个新的 Vault 合约实例
        vault = new VaultVulnerable();

        // [FIX] 使用 vm.deal 为测试用户设置初始余额，比如 100 ETH
        // 这是解决问题的关键！
        vm.deal(USER_A, 100 ether);
        vm.deal(USER_B, 100 ether);
    }

    // --- 成功场景测试 ---

    function test_Deposit() public {
        // 模拟 USER_A 调用合约
        vm.prank(USER_A);
        // USER_A 存入 1 ETH
        vault.deposit{value: 1 ether}();

        // 断言：检查 USER_A 在 Vault 中的余额是否为 1 ETH
        assertEq(vault.balances(USER_A), 1 ether, "User A balance should be 1 ether");
    }

    function test_WithdrawSuccessfully() public {
        // 准备阶段：USER_A 先存入 1 ETH
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        // 测试阶段：USER_A 取出 0.5 ETH
        uint256 userA_initial_balance = USER_A.balance; // 记录 USER_A 取款前的钱包余额
        vm.prank(USER_A);
        vault.withdraw(0.5 ether);

        // 断言1：检查 USER_A 在 Vault 中的余额是否减少到 0.5 ETH
        assertEq(vault.balances(USER_A), 0.5 ether, "Vault balance should be 0.5 ether");
        // 断言2：检查 USER_A 的钱包余额是否增加了 0.5 ETH
        assertEq(
            USER_A.balance, userA_initial_balance + 0.5 ether, "User A wallet balance should increase by 0.5 ether"
        );
    }

    // --- 失败和攻击场景测试 ---

    function test_RevertIf_WithdrawInsufficientBalance() public {
        // 准备：USER_A 存入 1 ETH
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        // 预期：当 USER_A 尝试取出 2 ETH 时，交易会失败（revert）
        // 并返回我们指定的错误信息 "Insufficient balance"
        vm.expectRevert("Insufficient balance");

        // 操作：USER_A 尝试取出 2 ETH
        vm.prank(USER_A);
        vault.withdraw(2 ether);
    }

    function test_RevertWhen_OtherUserWithdraws() public {
        // 准备：USER_A 存入 1 ETH
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        // 准备：USER_B 没有任何存款
        assertEq(vault.balances(USER_B), 0);

        // 预期：当 USER_B 尝试取出 USER_A 的钱时，交易会失败
        // 因为 B 的余额为 0，会触发 "Insufficient balance" 的 revert
        vm.expectRevert("Insufficient balance");

        // 操作：USER_B 尝试取出 0.5 ETH
        vm.prank(USER_B);
        vault.withdraw(0.5 ether);
    }

    function test_RevertIf_WithdrawAmountIsZero() public {
        // 预期：当尝试取出 0 时，交易会 revert
        vm.expectRevert("Withdraw amount must be greater than zero");

        // 操作
        vm.prank(USER_A);
        vault.withdraw(0);
    }
}
