// 单行注释
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//多行注释
/**
 * @title VaultVulnerable
 * @dev 一个简单的金库合约，用于存储和提取以太币。
 * 每个用户的资金都独立记录，只有存款人本人才能提取。
 * 合约遵循 Checks-Effects-Interactions 模式以防止重入攻击。
 * 
 * ⚠️ 警告：此合约存在安全漏洞，仅用于测试对比，不要在生产环境中使用！
 */

// 合约主体内容
contract VaultVulnerable {
    // 定义映射，可以通过地址查询balances
    mapping(address => uint256) public balances;

    // 定义合约内事件，用于记录合约内发生的类似事件的记录，以下的记录方式大约是“
    /**
     * DepositMade:
     * account: 0x123... (发起存款的地址)
     * amount: 1000000000000000000 (1 ETH)
     */
    event DepositMade(address indexed account, uint256 amount);
    event WithdrawalMade(address indexed account, uint256 amount);


    /**
     * @dev 存钱函数。
     */
    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        balances[msg.sender] += msg.value;
        emit DepositMade(msg.sender, msg.value);
    }

    /**
     * @dev 取钱函数。
     * @param _amount 要提取的金额。
     */
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "Withdraw amount must be greater than zero");
        uint256 userBalance = balances[msg.sender];
        require(userBalance >= _amount, "Insufficient balance");

        // Checks-Effects-Interactions Pattern:
        // 1. Effects (Update state)
        balances[msg.sender] = userBalance - _amount;
        
        // 2. Interactions (External call)
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Failed to send Ether");

        emit WithdrawalMade(msg.sender, _amount);
    }
}