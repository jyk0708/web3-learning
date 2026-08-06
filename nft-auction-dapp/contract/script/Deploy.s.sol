// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/NftAuctionUpgradeable.sol";
import "../test/MockAggregator.sol";

/**
 * @title Deploy
 * @dev NFT 拍卖合约部署脚本（UUPS 模式）
 *
 * 使用方法:
 *   1. 设置环境变量:
 *      export PRIVATE_KEY=your_private_key
 *      export ETH_USD_FEED=0x... (ETH/USD Chainlink 预言机地址)
 *      export USDC_USD_FEED=0x... (USDC/USD Chainlink 预言机地址)
 *
 *   2. 部署到本地 Anvil:
 *      forge script script/Deploy.s.sol --broadcast --rpc-url http://localhost:8545
 *
 *   3. 部署到 Sepolia:
 *      forge script script/Deploy.s.sol --broadcast --rpc-url https://sepolia.infura.io/v3/YOUR_KEY
 */
contract Deploy is Script {
    // 合约实例
    NftAuctionUpgradeable public implementation;
    NftAuctionUpgradeable public proxy;

    // 预言机实例
    MockAggregator public mockEthUsdFeed;
    MockAggregator public mockUsdcUsdFeed;

    // Sepolia 测试网代币地址（使用编译器校验通过的 checksum 格式）
    address public constant USDC_ADDRESS = 0x1c7d4b196AA478d0ee648F487818A9BB45DFe59d;
    address public constant WETH_ADDRESS = 0x7cEb23fd6BC0Ad45D8E7BAe69B46C0BD06D2efEE;

    // 平台手续费
    uint256 public constant PLATFORM_FEE_RATE = 2; // 2%

    function run() external {
        address deployer = msg.sender;

        console2.log("Deployer:", deployer);
        // 开始广播交易到链上
        vm.startBroadcast();
        // 1. 部署实现合约（构造函数会调用 _disableInitializers，禁止直接初始化）
        implementation = new NftAuctionUpgradeable();
        console2.log("Implementation deployed:", address(implementation));
        // 2. 部署 Mock 预言机（用于测试网络）
        console2.log("Deploying Mock Aggregators...");
        mockEthUsdFeed = new MockAggregator(200000000000, 8); // ETH = 2000 USD
        mockUsdcUsdFeed = new MockAggregator(100000000, 8); // USDC = 1 USD
        // 3. 部署 ERC1967Proxy，在构造时通过代理调用 initialize
        //    UUPS 模式必须通过代理初始化，不能直接在实现合约上调用
        bytes memory initData = abi.encodeWithSelector(
            NftAuctionUpgradeable.initialize.selector,
            PLATFORM_FEE_RATE
        );
        ERC1967Proxy erc1967Proxy = new ERC1967Proxy(address(implementation), initData);
        proxy = NftAuctionUpgradeable(address(erc1967Proxy));
        console2.log("Proxy deployed:", address(proxy));
        // 4. 设置预言机（通过代理调用，msg.sender = deployer = owner）
        proxy.setPriceFeed(WETH_ADDRESS, address(mockEthUsdFeed));
        console2.log("ETH/USD feed set for:", WETH_ADDRESS);
        proxy.setPriceFeed(USDC_ADDRESS, address(mockUsdcUsdFeed));
        console2.log("USDC/USD feed set for:", USDC_ADDRESS);
        vm.stopBroadcast();
        _verifyDeployment();
    }

    function _verifyDeployment() internal view {
        // 验证合约状态
        address owner = proxy.owner();
        require(owner != address(0), "Owner not set");
        console2.log("Owner verified:", owner);

        // 验证预言机设置
        (bool success, uint256 usdValue) = proxy.getPrice2USD(WETH_ADDRESS, 1000000000000000000); // 1 WETH
        if (success) {
            console2.log("ETH/USD price feed working, 1 WETH =", usdValue / 1e8, "USD");
        } else {
            console2.log("ETH/USD price feed not working");
        }

        (success, usdValue) = proxy.getPrice2USD(USDC_ADDRESS, 1000000); // 1 USDC
        if (success) {
            console2.log("USDC/USD price feed working, 1 USDC =", usdValue / 1e6, "USD");
        } else {
            console2.log("USDC/USD price feed not working");
        }
        console2.log("\n Deployment completed successfully!");
    }
}
