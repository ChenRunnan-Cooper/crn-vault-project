// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./USDValueVault.sol";

/**
 * @title SimplePriceOracle
 * @dev 简单的价格预言机实现，用于测试USD价值计算
 * 在生产环境中，应该使用Chainlink等专业预言机
 */
contract SimplePriceOracle is IPriceOracle {
    // 代币地址 => USD价格 (18位小数)
    mapping(address => uint256) private prices;

    // 权限控制
    address public owner;

    // 价格更新事件
    event PriceUpdated(address indexed asset, uint256 price);

    // ETH哨兵值
    address private constant ETH_SENTINEL = address(0);

    constructor() {
        owner = msg.sender;

        // 设置一些初始价格作为示例
        // 1 ETH = 2000 USD
        prices[ETH_SENTINEL] = 2000 * 10 ** 18;

        // 其他代币可以在部署后设置
    }

    /**
     * @dev 获取资产的USD价格
     * @param asset 资产地址
     * @return USD价格 (18位小数)
     */
    function getAssetPrice(address asset) external view override returns (uint256) {
        uint256 price = prices[asset];
        require(price > 0, "Price not available");
        return price;
    }

    /**
     * @dev 设置资产的USD价格
     * @param asset 资产地址
     * @param price USD价格 (18位小数)
     */
    function setAssetPrice(address asset, uint256 price) external {
        require(msg.sender == owner, "Not authorized");
        require(price > 0, "Invalid price");

        prices[asset] = price;
        emit PriceUpdated(asset, price);
    }

    /**
     * @dev 批量设置价格
     * @param assets 资产地址数组
     * @param newPrices 对应的价格数组
     */
    function setBatchPrices(address[] calldata assets, uint256[] calldata newPrices) external {
        require(msg.sender == owner, "Not authorized");
        require(assets.length == newPrices.length, "Arrays length mismatch");

        for (uint256 i = 0; i < assets.length; i++) {
            require(newPrices[i] > 0, "Invalid price");
            prices[assets[i]] = newPrices[i];
            emit PriceUpdated(assets[i], newPrices[i]);
        }
    }

    /**
     * @dev 转移所有权
     * @param newOwner 新的所有者地址
     */
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Not authorized");
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    /**
     * @dev 检查资产是否有价格
     * @param asset 资产地址
     */
    function hasPriceInfo(address asset) external view returns (bool) {
        return prices[asset] > 0;
    }
}
