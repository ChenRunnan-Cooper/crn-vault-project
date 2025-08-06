// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/deprecated/VaultVulnerable.sol";

// ================== 恶意攻击合约 (用于重入测试) ==================
// 这个合约定义在测试文件顶部，以便测试合约可以使用它。
contract Attacker {
    VaultVulnerable public immutable vault;
    uint256 public attackCount = 0;

    constructor(address _vaultAddress) {
        vault = VaultVulnerable(_vaultAddress);
    }

    // 接收ETH的fallback函数，这是重入攻击的核心
    receive() external payable {
        attackCount++;
        // 在第一次取款的外部调用完成前，尝试再次从Vault取款
        if (attackCount < 2) {
            vault.withdraw(0.1 ether);
        }
    }

    // 启动攻击
    function attack() external {
        // 先向Vault存入1 ETH，以便有资金可以取
        vault.deposit{value: 1 ether}();
        // 发起第一次取款，这将触发上面的receive()函数，尝试重入
        vault.withdraw(0.1 ether);
    }
}


// ================== 全面的Vault测试套件 ==================
contract ComprehensiveVaultTest is Test {
    VaultVulnerable public vault;
    address USER_A = makeAddr("USER_A");
    address USER_B = makeAddr("USER_B");

    // 在每个测试用例运行前执行，确保干净的测试环境
    function setUp() public {
        vault = new VaultVulnerable();

        // 为测试用户预存一些ETH，否则他们无法发起需要发送value的交易
        vm.deal(USER_A, 100 ether);
        vm.deal(USER_B, 100 ether);
    }

    // ========= 1. 成功路径测试 (Happy Path) =========
    
    function test_Success_Deposit() public {
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();
        assertEq(vault.balances(USER_A), 1 ether, "User A balance in vault should be 1 ether");
        assertEq(address(vault).balance, 1 ether, "Vault total balance should be 1 ether");
    }

    function test_Success_WithdrawPartial() public {
        vm.prank(USER_A);
        vault.deposit{value: 5 ether}();

        uint256 userWalletBefore = USER_A.balance;
        
        vm.prank(USER_A);
        vault.withdraw(2 ether);

        assertEq(vault.balances(USER_A), 3 ether, "User A balance in vault should be 3 ether");
        assertEq(address(vault).balance, 3 ether, "Vault total balance should be 3 ether");
        assertEq(USER_A.balance, userWalletBefore + 2 ether, "User A wallet balance should increase by 2 ether");
    }

    function test_Success_WithdrawFull() public {
        vm.prank(USER_A);
        vault.deposit{value: 5 ether}();

        vm.prank(USER_A);
        vault.withdraw(5 ether);
        
        assertEq(vault.balances(USER_A), 0, "User A balance in vault should be 0");
    }


    // ========= 2. 失败与回滚测试 (Sad Path / Reverts) =========

    function test_RevertIf_WithdrawInsufficientBalance() public {
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        vm.expectRevert("Insufficient balance");
        vm.prank(USER_A);
        vault.withdraw(2 ether);
    }

    function test_RevertIf_OtherUserWithdraws() public {
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        vm.expectRevert("Insufficient balance");
        vm.prank(USER_B); // USER_B 尝试取钱
        vault.withdraw(1 ether);
    }

    function test_RevertIf_DepositZero() public {
        vm.expectRevert("Deposit amount must be greater than zero");
        vm.prank(USER_A);
        vault.deposit{value: 0}();
    }
    
    function test_RevertIf_WithdrawZero() public {
        vm.expectRevert("Withdraw amount must be greater than zero");
        vm.prank(USER_A);
        vault.withdraw(0);
    }


    // ========= 3. 事件触发测试 (Event Emission) =========

    function test_Event_EmitDepositMade() public {
        vm.expectEmit(true, true, false, true); // 检查所有字段
        // 明确指定事件来源的合约
        emit VaultVulnerable.DepositMade(USER_A, 1 ether);

        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();
    }

    function test_Event_EmitWithdrawalMade() public {
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        vm.expectEmit(true, true, false, true);
        // 明确指定事件来源的合约
        emit VaultVulnerable.WithdrawalMade(USER_A, 1 ether);
        
        vm.prank(USER_A);
        vault.withdraw(1 ether);
    }


    // ========= 4. 多用户交互测试 =========

    function test_Interaction_StateIsolation() public {
        // Step 1: User A deposits
        vm.prank(USER_A);
        vault.deposit{value: 10 ether}();
        assertEq(vault.balances(USER_A), 10 ether);
        assertEq(vault.balances(USER_B), 0);
        assertEq(address(vault).balance, 10 ether);

        // Step 2: User B deposits
        vm.prank(USER_B);
        vault.deposit{value: 5 ether}();
        assertEq(vault.balances(USER_A), 10 ether);
        assertEq(vault.balances(USER_B), 5 ether);
        assertEq(address(vault).balance, 15 ether);

        // Step 3: User A withdraws, User B's balance must not change
        vm.prank(USER_A);
        vault.withdraw(3 ether);
        assertEq(vault.balances(USER_A), 7 ether);
        assertEq(vault.balances(USER_B), 5 ether, "User B balance MUST NOT change");
        assertEq(address(vault).balance, 12 ether);
    }


    // ========= 5. 安全性测试 (Security) =========

    function test_Security_NoReentrancy() public {
        // 部署攻击合约
        Attacker attacker = new Attacker(address(vault));
        // 为攻击合约预存资金
        uint256 attackerInitialWalletBalance = 2 ether;
        vm.deal(address(attacker), attackerInitialWalletBalance);

        // 启动攻击
        vm.prank(address(attacker));
        attacker.attack();
        
        // 【核心断言】
        // 验证攻击结束后，状态是否正确，而不是期望它 revert。
        
        // 1. 攻击者在Vault中的余额应该是 1(存) - 0.1(取) - 0.1(重入取) = 0.8 ETH
        assertEq(vault.balances(address(attacker)), 0.8 ether, "Attacker balance in vault should be 0.8 ETH");

        // 2. Vault合约的总资金也应该是 0.8 ETH
        assertEq(address(vault).balance, 0.8 ether, "Vault total balance should be 0.8 ETH");

        // 3. 攻击者合约自己的钱包余额，应该是 初始(2) - 存入(1) + 取回(0.2) = 1.2 ETH
        assertEq(address(attacker).balance, attackerInitialWalletBalance - 1 ether + 0.2 ether, "Attacker wallet balance is incorrect");
    }

    
    // ========= 6. 模糊测试 (Fuzz Testing) =========
    
    function test_Fuzz_DepositAndWithdraw(uint128 _depositAmount) public {
        // 用 vm.assume 约束随机输入，使其落在有效范围内
        vm.assume(_depositAmount > 0 && _depositAmount < 50 ether);

        uint256 userWalletBefore = USER_A.balance;

        // --- Deposit ---
        vm.prank(USER_A);
        vault.deposit{value: _depositAmount}();
        assertEq(vault.balances(USER_A), _depositAmount);

        // --- Withdraw ---
        vm.prank(USER_A);
        vault.withdraw(_depositAmount);

        // --- Final State Check ---
        assertEq(vault.balances(USER_A), 0);
        // 比较钱包最终余额和初始余额
        assertEq(USER_A.balance, userWalletBefore);
    }
}