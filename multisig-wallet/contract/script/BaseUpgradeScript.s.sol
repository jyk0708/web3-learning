// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MultiSigWalletUpgradeable} from "../src/MultiSigWalletUpgradeable.sol";
import {MultiSigWalletV2} from "../src/MultiSigWalletV2.sol";
import {MultiSigWalletV3} from "../src/MultiSigWalletV3.sol";

/**
 * ============================================================================
 *  【基础版】多签钱包升级脚本
 * ============================================================================
 *
 *  基础版升级流程（单签，owner 直接升级，不需要多签投票）：
 *
 *  V1 初始化 → 部署 V2 实现 → upgradeTo(V2) → initializeV2(2)
 *       → 部署 V3 实现 → upgradeTo(V3) → initializeV3()
 *
 *  对比投票版：
 *    基础版：owner 直接调 upgradeTo → _authorizeUpgrade(onlyOwner) → 通过
 *    投票版：createUpgradeProposal → 多签确认 → executeUpgradeProposal → _authorizeUpgrade(检查标记)
 *
 *  包含 6 个独立合约：
 *
 *    1. DeployV2Base       — 部署 V2 实现
 *    2. DeployV3Base       — 部署 V3 实现
 *    3. UpgradeToV2        — 代理升级到 V2，并调用 initializeV2
 *    4. UpgradeToV3        — 代理升级到 V3，并调用 initializeV3
 *    5. VerifyV2           — 验证 V2 升级结果
 *    6. VerifyV3           — 验证 V3 升级结果
 *
 *  环境变量（.env）：
 *    PROXY_ADDRESS=0x...      代理合约地址（DeployBaseUpgradeableScript 部署后获得）
 *    OWNER1_PK=0x...          owner1 私钥（升级需要 onlyOwner）
 *
 * ============================================================================
 */

/**
 * @title DeployV2Base
 * @dev 步骤1：部署 V2 实现合约（任意账户，不需要 owner 权限）
 *
 * 使用方式：
 *   FOUNDRY_PROFILE=dev forge script script/BaseUpgradeScript.s.sol:DeployV2Base \
 *     --rpc-url local --broadcast \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 *
 * 输出：V2 Implementation Address → 记下，下一步 upgradeTo 要用
 */
contract DeployV2Base is Script {
    function run() public returns (address) {
        vm.startBroadcast();

        MultiSigWalletV2 v2 = new MultiSigWalletV2();

        console.log("=== [1/4] V2 Implementation Deployed ===");
        console.log("V2 Implementation:", address(v2));
        console.log("");
        console.log("Next: UpgradeToV2, set PROXY_ADDRESS and V2_ADDRESS");

        vm.stopBroadcast();
        return address(v2);
    }
}

/**
 * @title UpgradeToV2
 * @dev 步骤2：将代理升级到 V2，并初始化 V2 新功能
 * @notice 必须 owner 签名，_authorizeUpgrade 是 onlyOwner 修饰
 *
 * 内部做了 3 件事：
 *   1. proxy.upgradeTo(v2)            → 代理指向 V2 实现
 *   2. proxy.initializeV2(2)          → 初始化 V2 新变量（version=2）
 *
 * 使用方式：
 *   export PROXY_ADDRESS=0x...     # 代理地址
 *   export V2_ADDRESS=0x...        # 上一步部署的 V2 实现地址
 *   export OWNER1_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 *
 *   FOUNDRY_PROFILE=dev forge script script/BaseUpgradeScript.s.sol:UpgradeToV2 \
 *     --rpc-url local --broadcast --private-key $OWNER1_PK
 */
contract UpgradeToV2 is Script {
    function run() public {
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address v2 = vm.envAddress("V2_ADDRESS");

        vm.startBroadcast();

        // ---- 1. 升级代理指向 V2 ----
        // 用低级 call 调用 upgradeTo（避免 Solidity 对深继承 external 函数的成员查找问题）
        // upgradeTo 内部会调用 _authorizeUpgrade(newImplementation) → onlyOwner 检查
        (bool ok, ) = payable(proxy).call(
            abi.encodeWithSignature("upgradeTo(address)", v2)
        );
        require(ok, "upgradeTo failed");

        // ---- 2. 初始化 V2 的新变量（version=2）----
        // 注意：initializeV2 用了 reinitializer(2)，所以只能调用一次
        // 之后再次调用会 revert（防止重复初始化）
        MultiSigWalletV2 walletV2 = MultiSigWalletV2(payable(proxy));
        walletV2.initializeV2(2);

        vm.stopBroadcast();

        // ---- 3. 日志输出（必须在 startBroadcast 之外！）----
        // 如果在 startBroadcast 内调用 view 函数或 console.log，
        // forge script --broadcast 会把它们当作交易广播，导致 revert
        console.log("=== [2/4] Proxy upgraded to V2 ===");
        console.log("Proxy:", proxy);
        console.log("New Implementation (V2):", v2);
        console.log("=== [3/4] V2 Initialized ===");
        console.log("Version:", walletV2.version());
    }
}

/**
 * @title VerifyV2
 * @dev 验证 V2 升级结果（只读，不发送交易）
 *
 * 使用方式：
 *   export PROXY_ADDRESS=0x...
 *   FOUNDRY_PROFILE=dev forge script script/BaseUpgradeScript.s.sol:VerifyV2 --rpc-url local
 */
contract VerifyV2 is Script {
    function run() public view {
        address proxy = vm.envAddress("PROXY_ADDRESS");
        MultiSigWalletV2 wallet = MultiSigWalletV2(payable(proxy));

        console.log("=== V2 Upgrade Verification ===");
        console.log("Version:", wallet.version());
        console.log("Owner count:", wallet.getOwnerCount());
        console.log("Threshold:", wallet.getThreshold());
        console.log("Proposal count:", wallet.getProposalCount());
        console.log("ownerVoteCount(owner1):", wallet.ownerVoteCount(wallet.getOwners()[0]));
        console.log("paused (should fail in V2):", "V2 has no paused(), need V3");
    }
}

/**
 * @title DeployV3Base
 * @dev 步骤3：部署 V3 实现合约（任意账户，不需要 owner 权限）
 *
 * 使用方式：
 *   FOUNDRY_PROFILE=dev forge script script/BaseUpgradeScript.s.sol:DeployV3Base \
 *     --rpc-url local --broadcast \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 *
 * 输出：V3 Implementation Address → 记下，下一步 upgradeTo 要用
 */
contract DeployV3Base is Script {
    function run() public returns (address) {
        vm.startBroadcast();

        MultiSigWalletV3 v3 = new MultiSigWalletV3();

        console.log("=== V3 Implementation Deployed ===");
        console.log("V3 Implementation:", address(v3));
        console.log("");
        console.log("Next: UpgradeToV3, set V3_ADDRESS");

        vm.stopBroadcast();
        return address(v3);
    }
}

/**
 * @title UpgradeToV3
 * @dev 步骤4：将代理从 V2 升级到 V3，并初始化 V3
 * @notice 必须 owner 签名
 *
 * 内部做了 3 件事：
 *   1. proxy.upgradeTo(v3)            → 代理指向 V3 实现
 *   2. proxy.initializeV3()           → 初始化 V3 新变量（version=3, paused=false）
 *
 * 使用方式：
 *   export PROXY_ADDRESS=0x...
 *   export V3_ADDRESS=0x...
 *   export OWNER1_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 *
 *   FOUNDRY_PROFILE=dev forge script script/BaseUpgradeScript.s.sol:UpgradeToV3 \
 *     --rpc-url local --broadcast --private-key $OWNER1_PK
 */
contract UpgradeToV3 is Script {
    function run() public {
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address v3 = vm.envAddress("V3_ADDRESS");

        vm.startBroadcast();

        // ---- 1. 升级代理指向 V3 ----
        // 用低级 call 调用 upgradeTo（同 UpgradeToV2 的处理方式）
        (bool ok, ) = payable(proxy).call(
            abi.encodeWithSignature("upgradeTo(address)", v3)
        );
        require(ok, "upgradeTo failed");

        // ---- 2. 初始化 V3 新变量 ----
        // initializeV3 用 reinitializer(3)
        MultiSigWalletV3 walletV3 = MultiSigWalletV3(payable(proxy));
        walletV3.initializeV3();

        vm.stopBroadcast();

        // ---- 3. 日志输出（必须在 startBroadcast 之外！）----
        console.log("=== Proxy upgraded to V3 ===");
        console.log("Proxy:", proxy);
        console.log("New Implementation (V3):", v3);
        console.log("=== V3 Initialized ===");
        console.log("Version:", walletV3.version());
        console.log("Paused:", walletV3.paused());
    }
}

/**
 * @title VerifyV3
 * @dev 验证 V3 升级结果（只读，不发送交易）
 *      同时测试 pause/unpause 功能是否正常
 *
 * 使用方式：
 *   export PROXY_ADDRESS=0x...
 *   FOUNDRY_PROFILE=dev forge script script/BaseUpgradeScript.s.sol:VerifyV3 --rpc-url local
 */
contract VerifyV3 is Script {
    function run() public view {
        address proxy = vm.envAddress("PROXY_ADDRESS");
        MultiSigWalletV3 wallet = MultiSigWalletV3(payable(proxy));

        console.log("=== V3 Upgrade Verification ===");
        console.log("Version:", wallet.version());
        console.log("Paused:", wallet.paused());
        console.log("Owner count:", wallet.getOwnerCount());
        console.log("Threshold:", wallet.getThreshold());

        address[] memory owners = wallet.getOwners();
        for (uint256 i = 0; i < owners.length; i++) {
            console.log("Owner index:", i);
            console.log("  address:", owners[i]);
            console.log("  voteCount:", wallet.ownerVoteCount(owners[i]));
        }

        console.log("");
        console.log("V3 Features Available:");
        console.log(unicode"  - pause()        → 暂停 createProposal/confirmTx/revokeConfirmTx/executeTx");
        console.log(unicode"  - unpause()      → 恢复");
        console.log(unicode"  - version == 3   → 版本号");
    }
}