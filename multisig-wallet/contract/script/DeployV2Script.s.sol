// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MultiSigWalletUpgradeable} from "../src/MultiSigWalletUpgradeable.sol";
import {MultiSigWalletV2} from "../src/MultiSigWalletV2.sol";

/**
 * @title DeployV2Script
 * @dev 部署 V2 实现合约
 * @notice 此脚本只部署 V2 实现合约，不涉及代理升级
 *         V2 继承自 MultiSigWalletUpgradeable（基础版），升级方式为 owner 直接调用：
 *           cast send $PROXY_ADDRESS "upgradeTo(address)" $V2_ADDRESS --private-key $OWNER_PK
 *
 * 使用方式：
 *   forge script script/DeployV2Script.s.sol --rpc-url sepolia --broadcast
 */
contract DeployV2Script is Script {
    MultiSigWalletV2 public v2Implementation;

    function run() public {
        vm.startBroadcast();

        // 部署 V2 实现合约
        // 注意：UUPS 模式下，实现合约的 constructor 只调用 _disableInitializers()
        // 真正的初始化通过代理的 initialize() 完成
        v2Implementation = new MultiSigWalletV2();


        vm.stopBroadcast();
    }
}
