// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MaliciousContract
 * @dev 恶意合约，用于测试无限调用gas消耗漏洞
 */
contract MaliciousContract {
    uint256 public callCount = 0;
    bool public shouldLoop = true;

    // 接收ETH的fallback函数
    receive() external payable {
        callCount++;

        // 模拟无限循环，消耗大量gas
        if (shouldLoop) {
            uint256 i = 0;
            while (i < 50000) {
                // 减少循环次数，避免gas limit
                i++;
                // 执行一些无意义的操作来消耗gas
                uint256 dummy = i * 2;
                dummy = dummy + 1;
            }
        }
        // 如果不应该循环，则什么都不做，只记录调用次数
    }

    // 设置是否应该执行无限循环
    function setShouldLoop(bool _shouldLoop) external {
        shouldLoop = _shouldLoop;
    }

    // 重置调用计数
    function resetCallCount() external {
        callCount = 0;
    }

    // 获取合约余额
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

/**
 * @title GasConsumingContract
 * @dev 专门用于消耗gas的合约
 */
contract GasConsumingContract {
    uint256 public gasUsed = 0;

    receive() external payable {
        // 记录开始时的gas
        uint256 startGas = gasleft();

        // 执行一些消耗gas的操作
        uint256 sum = 0;
        for (uint256 i = 0; i < 50000; i++) {
            sum += i;
            // 执行一些复杂的计算来消耗更多gas
            sum = sum * 2 + 1;
        }

        // 记录消耗的gas
        gasUsed = startGas - gasleft();
    }

    function resetGasUsed() external {
        gasUsed = 0;
    }
}
