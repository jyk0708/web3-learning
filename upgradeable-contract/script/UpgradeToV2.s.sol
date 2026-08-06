// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MultiSigWalletUpgradeable} from "../src/MultiSigWalletUpgradeable.sol";

/**
 * @dev 升级脚本：演示完整的多签升级流程
 *
 * 前提：
 * - 已经通过 DeployUpgradeable 部署了代理 + V1 实现
 * - 设置环境变量 PROXY_ADDRESS 指向代理合约地址
 *
 * 流程：
 * 1. 部署新的 V2 实现合约
 * 2. Owner1 创建升级提案 → 得到 proposalId
 * 3. 各 Owner 依次确认达到阈值
 * 4. 任意 Owner 执行升级
 * 5. 验证升级成功
 */
contract UpgradeToV2 is Script {
    // 从环境变量读取代理地址
    address proxyAddress;
    // 新实现合约
    MultiSigWalletUpgradeable public v2Implementation;
    // 代理的包装接口
    MultiSigWalletUpgradeable public wallet;

    function setUp() public {
        proxyAddress = vm.envAddress("PROXY_ADDRESS");
        wallet = MultiSigWalletUpgradeable(payable(proxyAddress));
    }

    function run() public {
        // ---- 1. 部署 V2 实现合约 ----
        vm.startBroadcast();
        v2Implementation = new MultiSigWalletUpgradeable();
        console.log("V2 Implementation deployed at:", address(v2Implementation));
        vm.stopBroadcast();

        // ---- 2. Owner1 创建升级提案 ----
        address owner1 = vm.envAddress("OWNER1");
        address owner2 = vm.envAddress("OWNER2");
        address owner3 = vm.envAddress("OWNER3");
        uint256 threshold = vm.envUint("THRESHOLD");

        vm.startBroadcast();
        uint256 proposalId = wallet.createUpgradeProposal(address(v2Implementation));
        console.log("Upgrade proposal created, id:", proposalId);
        vm.stopBroadcast();

        // ---- 3. 各 Owner 确认 ----
        // 需要达到 threshold 个确认
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;

        uint256 confirmCount = 0;
        for (uint256 i = 0; i < owners.length && confirmCount < threshold; i++) {
            vm.startBroadcast();
            wallet.confirmUpgradeProposal(proposalId);
            console.log("Owner confirmed upgrade proposal:", owners[i]);
            vm.stopBroadcast();
            confirmCount++;
        }

        // ---- 4. 执行升级 ----
        console.log("Executing upgrade...");
        vm.startBroadcast();
        wallet.executeUpgradeProposal(proposalId);
        vm.stopBroadcast();

        // ---- 5. 验证 ----
        console.log("=== Upgrade completed ===");
        console.log("Proxy address (unchanged):", proxyAddress);
        console.log("New implementation:", address(v2Implementation));
        console.log("Owner count:", wallet.getOwnerCount());
        console.log("Threshold:", wallet.getThreshold());
    }
}
