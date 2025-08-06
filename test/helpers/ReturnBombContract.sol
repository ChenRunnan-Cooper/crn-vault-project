// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReturnBombContract
 * @dev 专门用于测试Return Bomb攻击的恶意合约
 */
contract ReturnBombContract {
    uint256 public callCount = 0;
    bool public shouldReturnBomb = true;
    
    // 接收ETH的fallback函数
    receive() external payable {
        callCount++;
        
        if (shouldReturnBomb) {
            // 返回大量数据来消耗调用者的gas
            // 通过assembly返回大量数据
            assembly {
                // 返回一个较大的数据块
                let size := 0x800 // 2KB的数据
                let ptr := mload(0x40)
                mstore(0x40, add(ptr, size))
                
                // 填充数据
                for { let i := 0 } lt(i, size) { i := add(i, 0x20) } {
                    mstore(add(ptr, i), 0x1234567890abcdef)
                }
                
                return(ptr, size)
            }
        }
    }
    
    // 设置是否应该执行Return Bomb攻击
    function setShouldReturnBomb(bool _should) external {
        shouldReturnBomb = _should;
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
 * @title LargeReturnDataContract
 * @dev 返回大量数据的恶意合约
 */
contract LargeReturnDataContract {
    uint256 public callCount = 0;
    
    receive() external payable {
        callCount++;
        
        // 通过assembly返回大量数据
        assembly {
            // 返回一个很大的数据块
            let size := 0x1000 // 4KB的数据
            let ptr := mload(0x40)
            mstore(0x40, add(ptr, size))
            
            // 填充数据
            for { let i := 0 } lt(i, size) { i := add(i, 0x20) } {
                mstore(add(ptr, i), 0x1234567890abcdef)
            }
            
            return(ptr, size)
        }
    }
    
    // 重置调用计数
    function resetCallCount() external {
        callCount = 0;
    }
}

/**
 * @title NormalContract
 * @dev 正常的合约，用于对比测试
 */
contract NormalContract {
    uint256 public callCount = 0;
    
    receive() external payable {
        callCount++;
        // 正常操作，不返回大量数据
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