// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/NftAuctionUpgradeable.sol";
import "../test/MockAggregator.sol";
import "../test/MockERC20.sol";
import "../test/MockERC721.sol";

/**
 * @title DeployLocal
 * @dev 本地测试环境部署脚本
 * 
 * 使用方法:
 *   1. 启动 Anvil:
 *      anvil --mnemonic "test test test test test test test test test test test junk"
 *   
 *   2. 部署:
 *      forge script script/DeployLocal.s.sol --broadcast --rpc-url http://localhost:8545
 */
contract DeployLocal is Script {
    // 合约实例
    NftAuctionUpgradeable public auction;
    MockERC20 public usdc;
    MockERC721 public nft;
    MockAggregator public usdcFeed;
    MockAggregator public ethFeed;

    // 配置
    uint256 public constant PLATFORM_FEE_RATE = 2; // 2%
    uint256 public constant NUM_CONFIRMATIONS = 1;

    function run() external {
        address deployer = msg.sender;
        
        console2.log("=== Local Deployment ===");
        console2.log("Deployer:", deployer);

        // 1. 部署 Mock 代币
        console2.log("\n1. Deploying Mock Tokens...");
        usdc = new MockERC20("USD Coin", "USDC", 6);
        console2.log("   USDC deployed:", address(usdc));
        
        nft = new MockERC721("Test NFT", "TNFT");
        console2.log("   NFT deployed:", address(nft));

        // 2. 部署 Mock 预言机
        console2.log("\n2. Deploying Mock Aggregators...");
        ethFeed = new MockAggregator(200000000000, 8); // ETH = 2000 USD
        console2.log("   ETH/USD feed:", address(ethFeed), "(price: $2000)");
        
        usdcFeed = new MockAggregator(100000000, 8); // USDC = 1 USD
        console2.log("   USDC/USD feed:", address(usdcFeed), "(price: $1)");

        // 3. 部署拍卖合约
        console2.log("\n3. Deploying NftAuctionUpgradeable...");
        auction = new NftAuctionUpgradeable();
        console2.log("   Implementation:", address(auction));

        // 4. 初始化合约
        console2.log("\n4. Initializing contract...");
        address[] memory owners = new address[](1);
        owners[0] = deployer;
        
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address[],uint256,uint256)",
            owners,
            NUM_CONFIRMATIONS,
            PLATFORM_FEE_RATE
        );
        
        (bool success,) = address(auction).call(initData);
        require(success, "Initialize failed");
        console2.log("   Contract initialized");

        // 5. 设置预言机
        console2.log("\n5. Setting price feeds...");
        auction.setPriceFeed(address(usdc), address(usdcFeed));
        console2.log("   USDC/USD feed set");
        
        auction.setPriceFeed(address(0x7cEb23fd6BC0Ad45D8E7BAe69B46C0BD06D2efEE), address(ethFeed)); // WETH
        console2.log("   ETH/USD feed set (for WETH address)");

        // 6. 铸造测试代币
        console2.log("\n6. Minting test tokens...");
        usdc.mint(deployer, 100000 * 10 ** 6); // 100,000 USDC
        console2.log("   Minted 100,000 USDC to deployer");

        // 7. 汇总
        console2.log("\n=== Deployment Summary ===");
        console2.log("Auction contract:", address(auction));
        console2.log("USDC token:", address(usdc));
        console2.log("NFT token:", address(nft));
        console2.log("ETH/USD feed:", address(ethFeed));
        console2.log("USDC/USD feed:", address(usdcFeed));
        console2.log("Owner:", auction.owner());
        console2.log("Platform Fee:", PLATFORM_FEE_RATE, "%");

        // 8. 验证
        console2.log("\n=== Verification ===");
        _verify();

        console2.log("\n Local deployment completed!");
        console2.log("\nTest the contract:");
        console2.log("  cast call", address(auction), "'owner()'");
        console2.log("  cast send", address(usdc), "'mint(address,uint256)'");
    }

    function _verify() internal view {
        // 验证 owner
        address owner = auction.owner();
        require(owner != address(0), "Owner not set");
        console2.log("Owner:", owner);

        // 验证 USDC 价格
        (bool success, uint256 price) = auction.getPrice2USD(address(usdc), 1000000);
        if (success) {
            console2.log("USDC price: 1 USDC =", price / 1e6, "USD");
        } else {
            console2.log("USDC price feed not working");
        }

        // 验证余额
        uint256 balance = usdc.balanceOf(msg.sender);
        console2.log("Deployer USDC balance:", balance / 1e6, "USDC");
    }
}
