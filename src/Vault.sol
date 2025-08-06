// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Vault
 * @dev 一个简单的金库合约，用于存储和提取以太币。
 * 每个用户的资金都独立记录，只有存款人本人才能提取。
 * 合约遵循 Checks-Effects-Interactions 模式以防止重入攻击。
 */
contract Vault {
    mapping(address => uint256) public balances;

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