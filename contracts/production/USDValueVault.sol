// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入OpenZeppelin的SafeERC20库和其他必要组件
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title USDValueVault
 * @dev 基于USD价值计算的金库合约，扩展了原始Vault功能
 * 用户存入的资产按USD价值计算并记录，取出时基于当前USD价值计算数量
 */
contract USDValueVault {
    using SafeERC20 for IERC20;

    // 使用address(0)代表ETH
    address private constant ETH_SENTINEL = address(0);

    // 价格预言机接口
    IPriceOracle public priceOracle;

    // 代币地址 => 用户地址 => USD价值(以wei为单位，18位精度)
    mapping(address => mapping(address => uint256)) public usdValues;

    // 代币地址 => 用户地址 => 代币数量(原始精度)
    mapping(address => mapping(address => uint256)) public tokenBalances;

    // 添加gas限制配置
    uint256 public constant MAX_WITHDRAWAL_GAS = 2300; // 基础转账gas
    uint256 public constant MAX_RETRY_ATTEMPTS = 3;
    uint256 public constant MAX_CONTRACT_SIZE = 24576; // 合约代码大小限制（字节）
    uint256 public constant MAX_RETURN_DATA_SIZE = 256; // 返回数据大小限制（字节）

    // 美元价值精度(18位小数)
    uint256 public constant USD_DECIMALS = 18;

    // 更新事件定义
    event Deposit(address indexed token, address indexed account, uint256 amount, uint256 usdValue);
    event Withdrawal(address indexed token, address indexed account, uint256 amount, uint256 usdValue);
    event WithdrawalFailed(
        address indexed token, address indexed account, uint256 amount, uint256 usdValue, string reason
    );

    /**
     * @dev 构造函数
     * @param _priceOracle 价格预言机地址
     */
    constructor(address _priceOracle) {
        require(_priceOracle != address(0), "Invalid oracle address");
        priceOracle = IPriceOracle(_priceOracle);
    }

    /**
     * @dev 存入ETH函数，按USD价值计算
     */
    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");

        // 获取ETH的USD价格并计算USD价值
        uint256 ethUsdPrice = priceOracle.getAssetPrice(ETH_SENTINEL);
        uint256 usdValue = (msg.value * ethUsdPrice) / 10 ** 18;

        // 更新用户的USD价值和代币余额
        usdValues[ETH_SENTINEL][msg.sender] += usdValue;
        tokenBalances[ETH_SENTINEL][msg.sender] += msg.value;

        // 触发事件
        emit Deposit(ETH_SENTINEL, msg.sender, msg.value, usdValue);
    }

    /**
     * @dev 存入ERC20代币函数，按USD价值计算
     * @param _token ERC20代币地址
     * @param _amount 存款金额
     * 注意：调用前需要先approve授权
     */
    function depositToken(address _token, uint256 _amount) external {
        require(_token != ETH_SENTINEL, "Use deposit() for ETH");
        require(_amount > 0, "Deposit amount must be greater than zero");

        // 获取代币精度
        uint8 decimals = IERC20Metadata(_token).decimals();

        // 获取代币的USD价格并计算USD价值
        uint256 tokenUsdPrice = priceOracle.getAssetPrice(_token);
        uint256 usdValue = (_amount * tokenUsdPrice) / 10 ** decimals;

        // 更新用户的USD价值和代币余额
        usdValues[_token][msg.sender] += usdValue;
        tokenBalances[_token][msg.sender] += _amount;

        // 使用SafeERC20安全转账
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(_token, msg.sender, _amount, usdValue);
    }

    /**
     * @dev 取出基于USD价值的ETH函数
     * @param _usdValue 要提取的USD价值
     */
    function withdrawByUSDValue(uint256 _usdValue) external {
        require(_usdValue > 0, "Withdraw value must be greater than zero");
        uint256 userUsdValue = usdValues[ETH_SENTINEL][msg.sender];
        require(userUsdValue >= _usdValue, "Insufficient USD value");

        // 获取ETH的USD价格
        uint256 ethUsdPrice = priceOracle.getAssetPrice(ETH_SENTINEL);

        // 计算要提取的ETH数量
        uint256 ethAmount = (_usdValue * 10 ** 18) / ethUsdPrice;

        // 确保用户有足够的ETH余额
        require(tokenBalances[ETH_SENTINEL][msg.sender] >= ethAmount, "Insufficient ETH balance");

        // 先尝试转账，成功后再更新状态
        bool transferSuccess = _safeTransfer(msg.sender, ethAmount);

        if (transferSuccess) {
            // 更新用户的USD价值和代币余额
            usdValues[ETH_SENTINEL][msg.sender] = userUsdValue - _usdValue;
            tokenBalances[ETH_SENTINEL][msg.sender] -= ethAmount;

            emit Withdrawal(ETH_SENTINEL, msg.sender, ethAmount, _usdValue);
        }
    }

    /**
     * @dev 取出基于USD价值的ERC20代币函数
     * @param _token ERC20代币地址
     * @param _usdValue 要提取的USD价值
     */
    function withdrawTokenByUSDValue(address _token, uint256 _usdValue) external {
        require(_token != ETH_SENTINEL, "Use withdrawByUSDValue() for ETH");
        require(_usdValue > 0, "Withdraw value must be greater than zero");

        uint256 userUsdValue = usdValues[_token][msg.sender];
        require(userUsdValue >= _usdValue, "Insufficient USD value");

        // 获取代币精度
        uint8 decimals = IERC20Metadata(_token).decimals();

        // 获取代币的USD价格
        uint256 tokenUsdPrice = priceOracle.getAssetPrice(_token);

        // 计算要提取的代币数量
        uint256 tokenAmount = (_usdValue * 10 ** decimals) / tokenUsdPrice;

        // 确保用户有足够的代币余额
        require(tokenBalances[_token][msg.sender] >= tokenAmount, "Insufficient token balance");

        // 先更新状态，防止重入攻击
        usdValues[_token][msg.sender] = userUsdValue - _usdValue;
        tokenBalances[_token][msg.sender] -= tokenAmount;

        // 使用SafeERC20安全转账
        IERC20(_token).safeTransfer(msg.sender, tokenAmount);
        emit Withdrawal(_token, msg.sender, tokenAmount, _usdValue);
    }

    /**
     * @dev 按代币数量提取ETH（兼容原始功能）
     * @param _amount 要提取的ETH数量
     */
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "Withdraw amount must be greater than zero");
        require(tokenBalances[ETH_SENTINEL][msg.sender] >= _amount, "Insufficient balance");

        // 获取ETH的USD价格
        uint256 ethUsdPrice = priceOracle.getAssetPrice(ETH_SENTINEL);

        // 计算提取的USD价值
        uint256 usdValue = (_amount * ethUsdPrice) / 10 ** 18;

        // 确保用户有足够的USD价值
        require(usdValues[ETH_SENTINEL][msg.sender] >= usdValue, "Insufficient USD value");

        // 尝试转账，成功后更新状态
        bool transferSuccess = _safeTransfer(msg.sender, _amount);

        if (transferSuccess) {
            usdValues[ETH_SENTINEL][msg.sender] -= usdValue;
            tokenBalances[ETH_SENTINEL][msg.sender] -= _amount;

            emit Withdrawal(ETH_SENTINEL, msg.sender, _amount, usdValue);
        }
    }

    /**
     * @dev 按代币数量提取ERC20（兼容原始功能）
     * @param _token ERC20代币地址
     * @param _amount 要提取的代币数量
     */
    function withdrawToken(address _token, uint256 _amount) external {
        require(_token != ETH_SENTINEL, "Use withdraw() for ETH");
        require(_amount > 0, "Withdraw amount must be greater than zero");
        require(tokenBalances[_token][msg.sender] >= _amount, "Insufficient token balance");

        // 获取代币精度
        uint8 decimals = IERC20Metadata(_token).decimals();

        // 获取代币的USD价格
        uint256 tokenUsdPrice = priceOracle.getAssetPrice(_token);

        // 计算提取的USD价值
        uint256 usdValue = (_amount * tokenUsdPrice) / 10 ** decimals;

        // 确保用户有足够的USD价值
        require(usdValues[_token][msg.sender] >= usdValue, "Insufficient USD value");

        // 先更新状态，防止重入攻击
        usdValues[_token][msg.sender] -= usdValue;
        tokenBalances[_token][msg.sender] -= _amount;

        // 使用SafeERC20安全转账
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit Withdrawal(_token, msg.sender, _amount, usdValue);
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
                emit WithdrawalFailed(ETH_SENTINEL, _to, _amount, 0, "Contract too large");
                return false;
            }

            // 对于合约地址，使用极度安全的调用
            bool success = _excessivelySafeCall(_to, _amount, MAX_WITHDRAWAL_GAS, MAX_RETURN_DATA_SIZE);
            if (!success) {
                emit WithdrawalFailed(ETH_SENTINEL, _to, _amount, 0, "Contract transfer failed");
            }
            return success;
        } else {
            // 2. 对于EOA地址，使用标准转账
            uint256 attempts = 0;
            bool success = false;

            while (attempts < MAX_RETRY_ATTEMPTS && !success) {
                uint256 gasLeft = gasleft();

                if (gasLeft < MAX_WITHDRAWAL_GAS) {
                    emit WithdrawalFailed(ETH_SENTINEL, _to, _amount, 0, "Insufficient gas");
                    return false;
                }

                uint256 gasToUse = gasLeft > MAX_WITHDRAWAL_GAS ? MAX_WITHDRAWAL_GAS : gasLeft;

                // 使用极度安全的调用
                success = _excessivelySafeCall(_to, _amount, gasToUse, MAX_RETURN_DATA_SIZE);

                if (!success) {
                    attempts++;
                    // 重试间隔
                    if (attempts < MAX_RETRY_ATTEMPTS) {
                        uint256 dummy = 0;
                        for (uint256 i = 0; i < 50; i++) {
                            dummy += i;
                        }
                    }
                }
            }

            if (!success) {
                emit WithdrawalFailed(ETH_SENTINEL, _to, _amount, 0, "Transfer failed after retries");
            }

            return success;
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
     * @dev 获取用户的USD价值余额
     * @param _token 代币地址（address(0)表示ETH）
     * @param _user 用户地址
     */
    function getUSDValue(address _token, address _user) external view returns (uint256) {
        return usdValues[_token][_user];
    }

    /**
     * @dev 获取用户的代币余额
     * @param _token 代币地址（address(0)表示ETH）
     * @param _user 用户地址
     */
    function getTokenBalance(address _token, address _user) external view returns (uint256) {
        return tokenBalances[_token][_user];
    }

    /**
     * @dev 获取当前汇率下用户代币的USD价值
     * @param _token 代币地址（address(0)表示ETH）
     * @param _user 用户地址
     */
    function getCurrentUSDValue(address _token, address _user) external view returns (uint256) {
        uint256 balance = tokenBalances[_token][_user];
        if (balance == 0) return 0;

        uint256 price = priceOracle.getAssetPrice(_token);

        if (_token == ETH_SENTINEL) {
            return (balance * price) / 10 ** 18;
        } else {
            uint8 decimals = IERC20Metadata(_token).decimals();
            return (balance * price) / 10 ** decimals;
        }
    }

    /**
     * @dev 获取合约的总USD价值
     */
    function getTotalUSDValue() external view returns (uint256) {
        // 这里可以实现计算所有代币总价值的逻辑，但这需要遍历所有代币和用户
        // 为了简化，这个函数留给后续实现
        revert("Not implemented");
    }
}

/**
 * @dev 价格预言机接口
 */
interface IPriceOracle {
    /**
     * @dev 获取资产的USD价格
     * @param asset 资产地址 (address(0)表示ETH)
     * @return price USD价格（18位小数）
     */
    function getAssetPrice(address asset) external view returns (uint256);
}

/**
 * @dev ERC20元数据接口，用于获取代币精度
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev 返回代币精度
     */
    function decimals() external view returns (uint8);
}
