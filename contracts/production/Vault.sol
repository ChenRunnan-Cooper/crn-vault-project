// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Vault
 * @dev 改进的金库合约，增加了gas限制和重试机制来防止无限调用漏洞
 */
contract Vault {
    mapping(address => uint256) public balances;

    // 添加gas限制配置
    uint256 public constant MAX_WITHDRAWAL_GAS = 2300; // 基础转账gas，防止复杂操作
    uint256 public constant MAX_RETRY_ATTEMPTS = 3;
    uint256 public constant MAX_CONTRACT_SIZE = 24576; // 合约代码大小限制（字节）
    uint256 public constant MAX_RETURN_DATA_SIZE = 256; // 返回数据大小限制（字节）

    event DepositMade(address indexed account, uint256 amount);
    event WithdrawalMade(address indexed account, uint256 amount);
    event WithdrawalFailed(address indexed account, uint256 amount, string reason);

    /**
     * @dev 存钱函数。
     */
    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        balances[msg.sender] += msg.value;
        emit DepositMade(msg.sender, msg.value);
    }

    /**
     * @dev 安全的取钱函数，带有gas限制和重试机制
     * @param _amount 要提取的金额。
     */
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "Withdraw amount must be greater than zero");
        uint256 userBalance = balances[msg.sender];
        require(userBalance >= _amount, "Insufficient balance");

        // 先尝试转账，成功后再更新状态
        bool transferSuccess = _safeTransfer(msg.sender, _amount);

        if (transferSuccess) {
            // 只有在转账成功后才更新状态
            balances[msg.sender] = userBalance - _amount;
        }
    }

    /**
     * @dev 检查地址是否为合约
     * @param _addr 要检查的地址
     * @return bool 是否为合约
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    /**
     * @dev 检查合约代码大小是否超过限制
     * @param _addr 合约地址
     * @return bool 是否超过限制
     */
    function _isContractTooLarge(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > MAX_CONTRACT_SIZE;
    }

    /**
     * @dev 极度安全的调用函数，限制gas和返回数据大小
     * @param _target 目标地址
     * @param _value 发送的ETH数量
     * @param _gas 最大gas限制
     * @param _maxReturnSize 最大返回数据大小
     * @return bool 调用是否成功
     */
    function _excessivelySafeCall(address _target, uint256 _value, uint256 _gas, uint256 _maxReturnSize)
        internal
        returns (bool)
    {
        // 检查gas是否足够
        if (gasleft() < _gas) {
            return false;
        }

        // 执行调用并捕获返回数据
        (bool success, bytes memory returnData) = _target.call{value: _value, gas: _gas}("");

        // 检查返回数据大小
        if (returnData.length > _maxReturnSize) {
            return false;
        }

        return success;
    }

    /**
     * @dev 安全的ETH转账函数，带有多重防护机制
     * @param _to 接收地址
     * @param _amount 转账金额
     * @return bool 转账是否成功
     */
    function _safeTransfer(address _to, uint256 _amount) internal returns (bool) {
        // 1. 检查是否为合约地址
        if (_isContract(_to)) {
            // 检查合约代码大小
            if (_isContractTooLarge(_to)) {
                emit WithdrawalFailed(_to, _amount, "Contract too large");
                return false;
            }

            // 对于合约地址，使用极度安全的调用
            bool success = _excessivelySafeCall(_to, _amount, MAX_WITHDRAWAL_GAS, MAX_RETURN_DATA_SIZE);
            if (success) {
                emit WithdrawalMade(_to, _amount);
                return true;
            } else {
                emit WithdrawalFailed(_to, _amount, "Contract transfer failed");
                return false;
            }
        } else {
            // 2. 对于EOA地址，使用标准转账
            uint256 attempts = 0;
            bool success = false;

            while (attempts < MAX_RETRY_ATTEMPTS && !success) {
                uint256 gasLeft = gasleft();

                if (gasLeft < MAX_WITHDRAWAL_GAS) {
                    emit WithdrawalFailed(_to, _amount, "Insufficient gas");
                    return false;
                }

                uint256 gasToUse = gasLeft > MAX_WITHDRAWAL_GAS ? MAX_WITHDRAWAL_GAS : gasLeft;

                // 使用极度安全的调用
                success = _excessivelySafeCall(_to, _amount, gasToUse, MAX_RETURN_DATA_SIZE);

                if (success) {
                    emit WithdrawalMade(_to, _amount);
                    return true;
                }

                attempts++;

                // 重试间隔
                if (attempts < MAX_RETRY_ATTEMPTS) {
                    uint256 dummy = 0;
                    for (uint256 i = 0; i < 50; i++) {
                        dummy += i;
                    }
                }
            }

            if (!success) {
                emit WithdrawalFailed(_to, _amount, "Transfer failed after retries");
            }

            return false;
        }
    }

    /**
     * @dev 紧急取款函数，用于处理转账失败的情况
     * @param _amount 要提取的金额
     */
    function emergencyWithdraw(uint256 _amount) external {
        require(_amount > 0, "Withdraw amount must be greater than zero");
        uint256 userBalance = balances[msg.sender];
        require(userBalance >= _amount, "Insufficient balance");

        // 先尝试转账，成功后再更新状态
        bool transferSuccess = _safeTransfer(msg.sender, _amount);

        if (transferSuccess) {
            // 只有在转账成功后才更新状态
            balances[msg.sender] = userBalance - _amount;
        }
    }

    /**
     * @dev 强制取款函数，用于处理合约地址的取款
     * 注意：此函数会直接转账，不进行复杂的检查
     * @param _amount 要提取的金额
     */
    function forceWithdraw(uint256 _amount) external {
        require(_amount > 0, "Withdraw amount must be greater than zero");
        uint256 userBalance = balances[msg.sender];
        require(userBalance >= _amount, "Insufficient balance");

        // 先尝试转账，成功后再更新状态
        bool transferSuccess = _safeTransfer(msg.sender, _amount);

        if (transferSuccess) {
            // 只有在转账成功后才更新状态
            balances[msg.sender] = userBalance - _amount;
        }
    }

    /**
     * @dev 检查地址是否为合约
     * @param _addr 要检查的地址
     * @return bool 是否为合约
     */
    function isContract(address _addr) external view returns (bool) {
        return _isContract(_addr);
    }

    /**
     * @dev 检查合约是否过大
     * @param _addr 要检查的地址
     * @return bool 是否过大
     */
    function isContractTooLarge(address _addr) external view returns (bool) {
        return _isContractTooLarge(_addr);
    }

    /**
     * @dev 查询合约余额
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
