// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/production/USDValueVault.sol";
import "../contracts/production/SimplePriceOracle.sol";
import "./helpers/MockERC20.sol";

/**
 * @title USDValueVaultTest
 * @dev 测试基于USD价值的Vault合约
 */
contract USDValueVaultTest is Test {
    USDValueVault public vault;
    SimplePriceOracle public oracle;
    MockERC20 public usdc;
    MockERC20 public dai;

    address USER_A = makeAddr("USER_A");
    address USER_B = makeAddr("USER_B");

    // 常量设置
    uint256 constant INITIAL_ETH = 100 ether;
    uint256 constant INITIAL_TOKEN = 10000 * 10 ** 18;

    // ETH价格初始设为 $2000
    uint256 constant ETH_PRICE = 2000 * 10 ** 18;

    // USDC价格初始设为 $1
    uint256 constant USDC_PRICE = 1 * 10 ** 18;

    // DAI价格初始设为 $1.01
    uint256 constant DAI_PRICE = 1.01 * 10 ** 18;

    function setUp() public {
        // 部署预言机
        oracle = new SimplePriceOracle();

        // 部署Vault
        vault = new USDValueVault(address(oracle));

        // 部署代币
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);

        // 设置代币价格
        oracle.setAssetPrice(address(usdc), USDC_PRICE);
        oracle.setAssetPrice(address(dai), DAI_PRICE);

        // 为用户提供初始资金
        vm.deal(USER_A, INITIAL_ETH);
        vm.deal(USER_B, INITIAL_ETH);

        // 为用户铸造代币
        usdc.mint(USER_A, INITIAL_TOKEN);
        usdc.mint(USER_B, INITIAL_TOKEN);
        dai.mint(USER_A, INITIAL_TOKEN);
        dai.mint(USER_B, INITIAL_TOKEN);
    }

    // ========= 1. ETH存取款测试 =========

    function test_DepositETH_USDValue() public {
        uint256 depositAmount = 1 ether;
        uint256 expectedUsdValue = (depositAmount * ETH_PRICE) / 10 ** 18; // 2000 USD

        vm.prank(USER_A);
        vault.deposit{value: depositAmount}();

        assertEq(vault.getUSDValue(address(0), USER_A), expectedUsdValue, "USD value should match");
        assertEq(vault.getTokenBalance(address(0), USER_A), depositAmount, "Token balance should match");
    }

    function test_WithdrawByUSDValue_ETH() public {
        // 先存款
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        uint256 withdrawUsdValue = 1000 * 10 ** 18; // 提取1000美元
        uint256 expectedEthAmount = (withdrawUsdValue * 10 ** 18) / ETH_PRICE; // 0.5 ETH

        uint256 balanceBefore = USER_A.balance;

        vm.prank(USER_A);
        vault.withdrawByUSDValue(withdrawUsdValue);

        uint256 balanceAfter = USER_A.balance;

        assertEq(balanceAfter - balanceBefore, expectedEthAmount, "ETH amount withdrawn should match");
        assertEq(vault.getUSDValue(address(0), USER_A), 1000 * 10 ** 18, "Remaining USD value should be 1000");
    }

    // ========= 2. 代币存取款测试 =========

    function test_DepositToken_USDValue() public {
        uint256 depositAmount = 1000 * 10 ** 6; // 1000 USDC (6位小数)
        uint256 expectedUsdValue = (depositAmount * USDC_PRICE) / 10 ** 6; // 1000 USD

        vm.startPrank(USER_A);
        usdc.approve(address(vault), depositAmount);
        vault.depositToken(address(usdc), depositAmount);
        vm.stopPrank();

        assertEq(vault.getUSDValue(address(usdc), USER_A), expectedUsdValue, "USD value should match");
        assertEq(vault.getTokenBalance(address(usdc), USER_A), depositAmount, "Token balance should match");
    }

    function test_WithdrawTokenByUSDValue() public {
        // 先存款
        uint256 depositAmount = 1000 * 10 ** 6; // 1000 USDC

        vm.startPrank(USER_A);
        usdc.approve(address(vault), depositAmount);
        vault.depositToken(address(usdc), depositAmount);

        uint256 withdrawUsdValue = 500 * 10 ** 18; // 提取500美元
        uint256 expectedTokenAmount = (withdrawUsdValue * 10 ** 6) / USDC_PRICE; // 500 USDC

        uint256 balanceBefore = usdc.balanceOf(USER_A);

        vault.withdrawTokenByUSDValue(address(usdc), withdrawUsdValue);
        vm.stopPrank();

        uint256 balanceAfter = usdc.balanceOf(USER_A);

        assertEq(balanceAfter - balanceBefore, expectedTokenAmount, "Token amount withdrawn should match");
        assertEq(vault.getUSDValue(address(usdc), USER_A), 500 * 10 ** 18, "Remaining USD value should be 500");
    }

    // ========= 3. 价格波动测试 =========

    function test_PriceFluctuation_ETH() public {
        // 用户存入1 ETH，当时价格是$2000
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        // 价格上涨到$3000
        uint256 newPrice = 3000 * 10 ** 18;
        oracle.setAssetPrice(address(0), newPrice);

        // 用户按USD价值取款 $1000
        uint256 beforeWithdraw = USER_A.balance;
        vm.prank(USER_A);
        vault.withdrawByUSDValue(1000 * 10 ** 18);
        uint256 afterWithdraw = USER_A.balance;

        // 计算实际提取的ETH数量
        uint256 actualWithdrawn = afterWithdraw - beforeWithdraw;

        // 验证结果 - 当ETH价格是$3000时，$1000应该能取出约0.333 ETH
        // 0.333 ETH的近似值为: 333333333333333333 wei
        uint256 expectedApproxEth = 333333333333333333;

        // 使用近似比较，允许一定误差（最多1%的误差）
        uint256 allowedDelta = expectedApproxEth / 100; // 允许1%的误差
        assertApproxEqAbs(
            actualWithdrawn, expectedApproxEth, allowedDelta, "ETH amount withdrawn should reflect price change"
        );
        assertEq(vault.getUSDValue(address(0), USER_A), 1000 * 10 ** 18, "USD value should be unchanged");
    }

    function test_MultiAssetDeposit_DifferentPrices() public {
        // 用户存入不同资产
        vm.startPrank(USER_A);

        // 存入1 ETH - $2000
        vault.deposit{value: 1 ether}();

        // 存入1000 USDC - $1000
        usdc.approve(address(vault), 1000 * 10 ** 6);
        vault.depositToken(address(usdc), 1000 * 10 ** 6);

        // 存入1000 DAI - $1010 (DAI = $1.01)
        dai.approve(address(vault), 1000 * 10 ** 18);
        vault.depositToken(address(dai), 1000 * 10 ** 18);

        vm.stopPrank();

        // 总计USD价值：$4010
        uint256 totalUsdValue = vault.getUSDValue(address(0), USER_A) + vault.getUSDValue(address(usdc), USER_A)
            + vault.getUSDValue(address(dai), USER_A);

        assertEq(totalUsdValue, 4010 * 10 ** 18, "Total USD value should be $4010");
    }

    // ========= 4. 边界条件和安全性测试 =========

    function test_RevertIf_WithdrawExceedsUSDBalance() public {
        // 存款1 ETH - $2000
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        // 尝试提取 $3000
        vm.prank(USER_A);
        vm.expectRevert("Insufficient USD value");
        vault.withdrawByUSDValue(3000 * 10 ** 18);
    }

    function test_RevertIf_PriceChange_InsufficientTokenBalance() public {
        // 存款0.5 ETH - $1000
        vm.prank(USER_A);
        vault.deposit{value: 0.5 ether}();

        // 价格暴跌到$1000
        oracle.setAssetPrice(address(0), 1000 * 10 ** 18);

        // 尝试提取$1000（需要1 ETH，但用户只有0.5 ETH）
        vm.prank(USER_A);
        vm.expectRevert("Insufficient ETH balance");
        vault.withdrawByUSDValue(1000 * 10 ** 18);
    }

    function test_UserIsolation() public {
        // 用户A和用户B各存入不同价值的资产
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}(); // $2000

        vm.prank(USER_B);
        vault.deposit{value: 2 ether}(); // $4000

        // 确认用户余额相互独立
        assertEq(vault.getUSDValue(address(0), USER_A), 2000 * 10 ** 18, "User A USD value");
        assertEq(vault.getUSDValue(address(0), USER_B), 4000 * 10 ** 18, "User B USD value");

        // 用户A提款不应影响用户B
        vm.prank(USER_A);
        vault.withdrawByUSDValue(1000 * 10 ** 18); // $1000

        assertEq(vault.getUSDValue(address(0), USER_A), 1000 * 10 ** 18, "User A USD value after withdraw");
        assertEq(vault.getUSDValue(address(0), USER_B), 4000 * 10 ** 18, "User B USD value should be unchanged");
    }

    function test_PriceOracleFailure() public {
        // 存入1000 USDC
        vm.startPrank(USER_A);
        usdc.approve(address(vault), 1000 * 10 ** 6);
        vault.depositToken(address(usdc), 1000 * 10 ** 6);
        vm.stopPrank();

        // 尝试设置预言机价格为0（模拟故障）
        vm.expectRevert("Invalid price");
        oracle.setAssetPrice(address(usdc), 0);
    }

    function test_PriceOracleUnavailable() public {
        // 部署一个新的预言机，不设置价格
        SimplePriceOracle newOracle = new SimplePriceOracle();
        USDValueVault newVault = new USDValueVault(address(newOracle));

        // 尝试存款应该失败，因为价格不可用
        vm.startPrank(USER_A);
        usdc.approve(address(newVault), 1000 * 10 ** 6);
        vm.expectRevert("Price not available");
        newVault.depositToken(address(usdc), 1000 * 10 ** 6);
        vm.stopPrank();
    }

    // ========= 5. 兼容性测试 =========

    function test_OriginalFunctions_Compatibility() public {
        // 测试原始存取款功能是否仍然兼容

        // 存款1 ETH
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        // 原始方式提款0.5 ETH
        vm.prank(USER_A);
        vault.withdraw(0.5 ether);

        // 检查余额
        assertEq(vault.getTokenBalance(address(0), USER_A), 0.5 ether, "ETH balance should be 0.5");
        assertEq(vault.getUSDValue(address(0), USER_A), 1000 * 10 ** 18, "USD value should be $1000");
    }

    function test_CurrentUSDValue_PriceChange() public {
        // 存款1 ETH - $2000
        vm.prank(USER_A);
        vault.deposit{value: 1 ether}();

        // 初始USD价值
        assertEq(vault.getUSDValue(address(0), USER_A), 2000 * 10 ** 18, "Initial USD value should be $2000");

        // 价格上涨到$3000
        oracle.setAssetPrice(address(0), 3000 * 10 ** 18);

        // getUSDValue应该返回原始存款时的USD价值
        assertEq(vault.getUSDValue(address(0), USER_A), 2000 * 10 ** 18, "Stored USD value should remain $2000");

        // getCurrentUSDValue应该返回基于当前价格的USD价值
        assertEq(vault.getCurrentUSDValue(address(0), USER_A), 3000 * 10 ** 18, "Current USD value should be $3000");
    }
}
