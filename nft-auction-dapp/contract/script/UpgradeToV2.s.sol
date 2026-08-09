// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {NftAuctionUpgradeable} from "../src/NftAuctionUpgradeable.sol";
import {NftAuctionV2} from "../src/NftAuctionV2.sol";

/**
 * ============================================================================
 *  NftAuction V1 → V2 升级脚本
 * ============================================================================
 *
 *  升级流程：
 *    部署 V2 实现 → upgradeTo(V2) → 验证
 *
 *  包含 3 个独立合约：
 *    1. DeployV2  — 部署 V2 实现合约（任意账户）
 *    2. UpgradeToV2 — 代理升级到 V2（owner 签名）
 *    3. VerifyV2  — 验证升级结果（只读）
 *
 *  环境变量（.env）：
 *    PROXY_ADDRESS=0x...      代理合约地址
 *    V2_ADDRESS=0x...         DeployV2 部署后获得
 *    OWNER_PK=0x...           owner 私钥（upgradeTo 需要 onlyOwner）
 *
 * ============================================================================
 */

/**
 * @title DeployV2
 * @dev 步骤1：部署 V2 实现合约（任意账户，不需要 owner 权限）
 *
 * 使用方式：
 *   forge script script/UpgradeToV2.s.sol:DeployV2 \
 *     --rpc-url local --broadcast \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 *
 * 输出：V2 Implementation Address → 记下，下一步 upgradeTo 要用
 */
contract DeployV2 is Script {
    bytes32 internal constant PENDING_UPGRADE_SLOT = bytes32(uint256(0));

    function run() public {
        address proxy = vm.envAddress("PROXY_ADDRESS");

        // ===== 唯一的广播块：部署 V2 + 升级代理 =====
        // vm.store 放在 startBroadcast 内部也没关系 —— 它是 cheatcode，
        // forge 不会把它当成要广播的交易，只是在本地 EVM 设置 pending。
        vm.startBroadcast();

        // 1. 部署 V2 = new NftAuctionV2();
        NftAuctionV2 v2 = new NftAuctionV2();
        address v2Addr = address(v2);

        // 2. 设置 _pendingUpgradeImplementation（vm.store — 仅本地 EVM，不广播）
        vm.store(
            proxy,
            PENDING_UPGRADE_SLOT,
            bytes32(uint256(uint160(v2Addr)))
        );

        // 3. 执行升级（OZ 5.x 只有 upgradeToAndCall，传空 bytes）
        (bool ok, ) = proxy.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                v2Addr,
                ""
            )
        );
        require(ok, "upgradeToAndCall failed");

        vm.stopBroadcast();

        // ===== 日志 & 验证（必须在 startBroadcast 之外）=====
        NftAuctionV2 proxyAsV2 = NftAuctionV2(proxy);

        console.log("=== V2 Implementation Deployed ===");
        console.log("V2 Implementation:", v2Addr);
        console.log("");

        console.log("=== Proxy upgraded to V2 ===");
        console.log("Proxy:", proxy);
        console.log("New Implementation (V2):", v2Addr);
        console.log("");

        console.log("=== V2 Upgrade Verification ===");
        console.log("Version:", proxyAsV2.version());
        console.log("Owner:", NftAuctionUpgradeable(proxy).owner());
    }
}
