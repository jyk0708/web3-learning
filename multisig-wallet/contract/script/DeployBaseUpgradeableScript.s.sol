// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MultiSigWalletUpgradeable} from "../src/MultiSigWalletUpgradeable.sol";

/**
 * @title DeployBaseUpgradeableScript
 * @dev 部署【基础版】V1 多签钱包（实现合约 + ERC1967Proxy 代理）
 *
 * 部署流程：
 *   1. 部署 MultiSigWalletUpgradeable V1 实现合约
 *   2. 编码 initialize(owners, threshold) 的 calldata
 *   3. 部署 ERC1967Proxy 代理，指向 V1 实现，并执行 initialize
 *
 * 最终：代理地址是永久的，以后升级只是修改代理的实现地址
 *
 * 环境变量（.env）：
 *   OWNER1=0x...          owner1 地址
 *   OWNER2=0x...          owner2 地址
 *   OWNER3=0x...          owner3 地址
 *   THRESHOLD=2           多签阈值
 *
 * 使用方式：
 *   source .env
 *   FOUNDRY_PROFILE=dev forge script script/DeployBaseUpgradeableScript.s.sol \
 *     --rpc-url local --broadcast \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 */
contract DeployBaseUpgradeableScript is Script {
    MultiSigWalletUpgradeable public implementation;
    ERC1967Proxy public proxy;
    MultiSigWalletUpgradeable public wallet;

    function run() public {
        // 读取 .env
        address owner1 = vm.envAddress("OWNER1");
        address owner2 = vm.envAddress("OWNER2");
        address owner3 = vm.envAddress("OWNER3");
        uint256 threshold = vm.envUint("THRESHOLD");

        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;

        vm.startBroadcast();

        // ---- 步骤1：部署 V1 实现合约 ----
        // constructor 只调用 _disableInitializers()，不做初始化
        implementation = new MultiSigWalletUpgradeable();
        console.log("=== Step 1: V1 Implementation Deployed ===");
        console.log("V1 Implementation:", address(implementation));

        // ---- 步骤2：编码 initialize calldata ----
        // 代理部署时 delegatecall 执行 initialize
        bytes memory initData = abi.encodeWithSelector(
            MultiSigWalletUpgradeable.initialize.selector,
            owners,
            threshold
        );

        // ---- 步骤3：部署 ERC1967Proxy ----
        // 代理的作用：
        //   所有状态存储在代理中（owners, proposals, ETH 余额）
        //   所有代码执行通过 delegatecall 转发到实现合约
        proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("");
        console.log("=== Step 2: Proxy Deployed ===");
        console.log(unicode"Proxy (永久地址):", address(proxy));

        // ---- 步骤4：验证初始化 ----
        wallet = MultiSigWalletUpgradeable(payable(address(proxy)));
        console.log("");
        console.log("=== Step 3: Verification ===");
        console.log("Owner count:", wallet.getOwnerCount());
        console.log("Threshold:", wallet.getThreshold());
        console.log("Owner1 is owner:", wallet.isOwner(owner1));
        console.log("Owner2 is owner:", wallet.isOwner(owner2));
        console.log("Owner3 is owner:", wallet.isOwner(owner3));
        console.log("");
        console.log("========================================");
        console.log("Save to .env: PROXY_ADDRESS=%s", address(proxy));
        console.log("V1 Implementation: %s", address(implementation));
        console.log("========================================");

        vm.stopBroadcast();
    }
}
