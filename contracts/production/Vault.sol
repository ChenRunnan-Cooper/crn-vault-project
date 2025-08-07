// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入OpenZeppelin的SafeERC20库，一个能够处理非标准ERC20代币的库
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title Vault
 * @dev 改进的金库合约，增加了gas限制和重试机制来防止无限调用漏洞
 * 增加了对ERC20代币的支持，包括非标准ERC20代币
 */
contract Vault {
    // ERC是一个代币协议，定义了一个ERC20代币的标准，IERC20是ERC20代币的接口，早期的usdt并非完全的ERC标准，transfer不支持返回布尔值
    using SafeERC20 for IERC20; // 使用SafeERC20库

    // 使用address(0)代表ETH
    address private constant ETH_SENTINEL = address(0);

    // 代币地址 => 用户地址 => 余额
    mapping(address => mapping(address => uint256)) public balances;

    // 添加gas限制配置
    uint256 public constant MAX_WITHDRAWAL_GAS = 2300; // 基础转账gas，防止复杂操作
    uint256 public constant MAX_RETRY_ATTEMPTS = 3;
    uint256 public constant MAX_CONTRACT_SIZE = 24576; // 合约代码大小限制（字节）
    uint256 public constant MAX_RETURN_DATA_SIZE = 256; // 返回数据大小限制（字节）

    // 更新事件定义，增加token参数
    event Deposit(address indexed token, address indexed account, uint256 amount);
    event Withdrawal(address indexed token, address indexed account, uint256 amount);
    event WithdrawalFailed(address indexed token, address indexed account, uint256 amount, string reason);

    // 保留旧事件以兼容现有代码
    event DepositMade(address indexed account, uint256 amount);
    event WithdrawalMade(address indexed account, uint256 amount);

    /**
     * @dev 存入ETH函数
     */
    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        balances[ETH_SENTINEL][msg.sender] += msg.value;

        // 触发新旧两个事件以保持兼容性
        emit Deposit(ETH_SENTINEL, msg.sender, msg.value);
        emit DepositMade(msg.sender, msg.value);
    }

    /**
     * @dev 存入ERC20代币函数
     * @param _token ERC20代币地址
     * @param _amount 存款金额
     * 注意：调用前需要先approve授权
     */
    function depositToken(address _token, uint256 _amount) external {
        require(_token != ETH_SENTINEL, "Use deposit() for ETH");
        require(_amount > 0, "Deposit amount must be greater than zero");

        // 先更新状态，防止重入攻击
        balances[_token][msg.sender] += _amount;

        // 使用SafeERC20安全转账，支持非标准ERC20
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(_token, msg.sender, _amount);
    }

    /**
     * @dev 取出ETH函数，带有gas限制和重试机制
     * @param _amount 要提取的金额
     */
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "Withdraw amount must be greater than zero");
        uint256 userBalance = balances[ETH_SENTINEL][msg.sender];
        require(userBalance >= _amount, "Insufficient balance");

        // 先尝试转账，成功后再更新状态
        bool transferSuccess = _safeTransfer(msg.sender, _amount);

        if (transferSuccess) {
            // 只有在转账成功后才更新状态
            balances[ETH_SENTINEL][msg.sender] = userBalance - _amount;

            // 触发新事件
            emit Withdrawal(ETH_SENTINEL, msg.sender, _amount);
        }
    }

    /**
     * @dev 取出ERC20代币函数
     * @param _token ERC20代币地址
     * @param _amount 取款金额
     */
    function withdrawToken(address _token, uint256 _amount) external {
        require(_token != ETH_SENTINEL, "Use withdraw() for ETH");
        require(_amount > 0, "Withdraw amount must be greater than zero");

        uint256 userBalance = balances[_token][msg.sender];
        require(userBalance >= _amount, "Insufficient balance");

        // 先更新状态，防止重入攻击
        balances[_token][msg.sender] = userBalance - _amount;

        // 使用SafeERC20安全转账，支持非标准ERC20
        // 注意：SafeERC20已经处理了失败情况，会自动revert
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit Withdrawal(_token, msg.sender, _amount);
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
                emit WithdrawalFailed(ETH_SENTINEL, _to, _amount, "Contract too large");
                return false;
            }

            // 对于合约地址，使用极度安全的调用
            bool success = _excessivelySafeCall(_to, _amount, MAX_WITHDRAWAL_GAS, MAX_RETURN_DATA_SIZE);
            if (success) {
                emit WithdrawalMade(_to, _amount);
                return true;
            } else {
                emit WithdrawalFailed(ETH_SENTINEL, _to, _amount, "Contract transfer failed");
                return false;
            }
        } else {
            // 2. 对于EOA地址，使用标准转账
            uint256 attempts = 0;
            bool success = false;

            while (attempts < MAX_RETRY_ATTEMPTS && !success) {
                uint256 gasLeft = gasleft();

                if (gasLeft < MAX_WITHDRAWAL_GAS) {
                    emit WithdrawalFailed(ETH_SENTINEL, _to, _amount, "Insufficient gas");
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
                emit WithdrawalFailed(ETH_SENTINEL, _to, _amount, "Transfer failed after retries");
            }

            return false;
        }
    }

    /**
     * @dev 紧急取款函数，用于处理ETH转账失败的情况
     * @param _amount 要提取的金额
     */
    function emergencyWithdraw(uint256 _amount) external {
        require(_amount > 0, "Withdraw amount must be greater than zero");
        uint256 userBalance = balances[ETH_SENTINEL][msg.sender];
        require(userBalance >= _amount, "Insufficient balance");

        // 先尝试转账，成功后再更新状态
        bool transferSuccess = _safeTransfer(msg.sender, _amount);

        if (transferSuccess) {
            // 只有在转账成功后才更新状态
            balances[ETH_SENTINEL][msg.sender] = userBalance - _amount;
            emit Withdrawal(ETH_SENTINEL, msg.sender, _amount);
        }
    }

    /**
     * @dev 紧急取款ERC20代币函数
     * @param _token ERC20代币地址
     * @param _amount 要提取的金额
     */
    function emergencyWithdrawToken(address _token, uint256 _amount) external {
        require(_token != ETH_SENTINEL, "Use emergencyWithdraw() for ETH");
        require(_amount > 0, "Withdraw amount must be greater than zero");
        uint256 userBalance = balances[_token][msg.sender];
        require(userBalance >= _amount, "Insufficient balance");

        // 先更新状态，防止重入攻击
        balances[_token][msg.sender] = userBalance - _amount;

        // 使用SafeERC20安全转账，支持非标准ERC20
        // 注意：SafeERC20已经处理了失败情况，会自动revert
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit Withdrawal(_token, msg.sender, _amount);
    }

    /**
     * @dev 强制取款函数，用于处理合约地址的ETH取款
     * 注意：此函数会直接转账，不进行复杂的检查
     * @param _amount 要提取的金额
     */
    function forceWithdraw(uint256 _amount) external {
        require(_amount > 0, "Withdraw amount must be greater than zero");
        uint256 userBalance = balances[ETH_SENTINEL][msg.sender];
        require(userBalance >= _amount, "Insufficient balance");

        // 先尝试转账，成功后再更新状态
        bool transferSuccess = _safeTransfer(msg.sender, _amount);

        if (transferSuccess) {
            // 只有在转账成功后才更新状态
            balances[ETH_SENTINEL][msg.sender] = userBalance - _amount;
            emit Withdrawal(ETH_SENTINEL, msg.sender, _amount);
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
     * @dev 查询合约ETH余额
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev 查询合约ERC20代币余额
     * @param _token ERC20代币地址
     */
    function getTokenBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /**
     * @dev 查询用户余额（ETH或ERC20）
     * @param _token 代币地址（address(0)表示ETH）
     * @param _user 用户地址
     */
    function getBalance(address _token, address _user) external view returns (uint256) {
        return balances[_token][_user];
    }
}
