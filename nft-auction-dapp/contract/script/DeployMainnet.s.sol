// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/NftAuctionUpgradeable.sol";

/**
 * @title DeployMainnet
 * @dev 主网（Ethereum）部署脚本
 * 
 * 使用方法:
 *   1. 设置环境变量:
 *      export PRIVATE_KEY=your_private_key
 *   
 *   2. 部署:
 *      forge script script/DeployMainnet.s.sol --broadcast --rpc-url https://mainnet.infura.io/v3/YOUR_KEY
 *   
 *   3. 验证:
 *      forge script script/DeployMainnet.s.sol --rpc-url https://mainnet.infura.io/v3/YOUR_KEY
 */
contract DeployMainnet is Script {
    NftAuctionUpgradeable public auction;

    // 配置
    uint256 public constant PLATFORM_FEE_RATE = 2; // 2%
    uint256 public constant NUM_CONFIRMATIONS = 3; // 主网需要更多确认数

    // 主网代币地址（EIP-55 checksum）
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // 主网 Chainlink 预言机地址（EIP-55 checksum）
    address public constant ETH_USD_FEED = 0x5F4eC3df9CbD4C477d24210F603a834B8fDb1A49;
    address public constant USDC_USD_FEED = 0x8FffFFD4afb6115b956Fd4056Ec72702777C6a09;
    address public constant WBTC_USD_FEED = 0x883bD56429F149245042eEA669f70F4E5d6B2C0D;
    address public constant DAI_USD_FEED = 0xaEd0c3fa41a1FB932Ba2a0B675fa2EeE48890d93;

    function run() external {
        address deployer = msg.sender;
        
        console2.log("=== Ethereum Mainnet Deployment ===");
        console2.log("Deployer:", deployer);

        // 1. 部署实现合约
        console2.log("\n1. Deploying NftAuctionUpgradeable...");
        auction = new NftAuctionUpgradeable();
        console2.log("   Deployed:", address(auction));

        // 2. 初始化
        console2.log("\n2. Initializing contract...");
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
        console2.log("   Initialized");

        // 3. 配置预言机
        console2.log("\n3. Setting Chainlink price feeds...");
        
        auction.setPriceFeed(WETH, ETH_USD_FEED);
        console2.log("   WETH/USD feed configured");
        
        auction.setPriceFeed(USDC, USDC_USD_FEED);
        console2.log("   USDC/USD feed configured");
        
        auction.setPriceFeed(WBTC, WBTC_USD_FEED);
        console2.log("   WBTC/USD feed configured");
        
        auction.setPriceFeed(DAI, DAI_USD_FEED);
        console2.log("   DAI/USD feed configured");

        // 4. 汇总
        console2.log("\n=== Deployment Summary ===");
        console2.log("Contract:", address(auction));
        console2.log("Owner:", auction.owner());
        console2.log("Platform Fee:", PLATFORM_FEE_RATE, "%");
        console2.log("Required Confirmations:", NUM_CONFIRMATIONS);
        
        console2.log("\nSupported tokens:");
        console2.log("  WETH :", WETH);
        console2.log("  USDC :", USDC);
        console2.log("  WBTC :", WBTC);
        console2.log("  DAI  :", DAI);

        console2.log("\nMainnet deployment completed!");
        console2.log("\nIMPORTANT:");
        console2.log("  1. Verify the contract on Etherscan");
        console2.log("  2. Test with small amounts first");
        console2.log("  3. Monitor the contract for suspicious activity");
    }
}
