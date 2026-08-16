// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MetaNode} from "../src/MetaNode.sol";
import {MetaNodeStake} from "../src/MetaNodeStake.sol";

/**
 * ============================================================================
 *  MetaNodeStake 全量部署脚本
 * ============================================================================
 *
 *  部署顺序（全部在同一个广播块内）：
 *    1. 部署 MetaNode（ERC20 奖励代币，构造时 mint 1000 万 MTN 给 deployer）
 *    2. 部署 MetaNodeStake 实现合约（UUPS implementation，不通过代理调用 initialize）
 *    3. 部署 ERC1967 代理，构造时通过 data 字段调用 initialize(metaNode, startBlock, endBlock, perBlock)
 *    4. 通过代理调用 addStakePool 添加 ETH 质押池（pid=0）
 *
 *  代理地址 = ERC1967 代理地址，用户和后端只需要保存这一个地址。
 *  MetaNode 和实现合约地址通过日志输出，用于 Etherscan 验证。
 *
 *  环境变量：
 *    DEPLOY_配置项见 _parseConfig()，全部有默认值，可在命令行用 --sig 传参或直接改下方常量
 *
 * 使用方式:
 *   # 本地 anvil
 *   anvil --port 8545
 *
 *   forge script script/Deploy.s.sol \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 *
 *   # 测试网（需要本地有 ETH 余额的私钥）
 *   forge script script/Deploy.s.sol \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     --verify --etherscan-api-key $API_KEY
 * ============================================================================
 */
contract DeployScript is Script {
    // ==================== 可配置参数（默认值，可通过环境变量覆盖）====================
    uint256 internal constant DEFAULT_META_NODE_PER_BLOCK = 100;    // 每区块奖励 100 MTN（最小单位 wei）
    uint256 internal constant DEFAULT_DURATION_BLOCKS = 10_000;     // 质押周期持续 10000 个区块
    uint256 internal constant DEFAULT_ETH_POOL_WEIGHT = 5;          // ETH 池权重
    uint256 internal constant DEFAULT_ETH_MIN_DEPOSIT = 1e15;       // ETH 最小质押 0.001 ether
    uint256 internal constant DEFAULT_UNSTAKE_LOCKED_BLOCKS = 10;   // 解质押锁定 10 个区块

    // ==================== 部署结果（供脚本内日志使用）====================
    MetaNode public metaNode;
    MetaNodeStake public implementation;
    MetaNodeStake public proxy; // 通过代理地址访问，类型是 MetaNodeStake 但实际指向代理

    function run() public {
        // 1. 解析配置（startBlock 在广播开始后才能确定，先读其它参数）
        uint256 metaNodePerBlock = vm.envOr("META_NODE_PER_BLOCK", DEFAULT_META_NODE_PER_BLOCK);
        uint256 durationBlocks = vm.envOr("DURATION_BLOCKS", DEFAULT_DURATION_BLOCKS);
        uint256 ethPoolWeight = vm.envOr("ETH_POOL_WEIGHT", DEFAULT_ETH_POOL_WEIGHT);
        uint256 ethMinDeposit = vm.envOr("ETH_MIN_DEPOSIT", DEFAULT_ETH_MIN_DEPOSIT);
        uint256 unstakeLockedBlocks = vm.envOr("UNSTAKE_LOCKED_BLOCKS", DEFAULT_UNSTAKE_LOCKED_BLOCKS);

        vm.startBroadcast();

        // 2. 部署 MetaNode ERC20（构造时 mint 1000 万 MTN 给 msg.sender/deployer）
        metaNode = new MetaNode();

        // 3. 部署 MetaNodeStake 实现合约（纯实现，不调用 initialize）
        implementation = new MetaNodeStake();

        // 4. 部署 ERC1967 代理，构造时通过 data 字段调用 initialize
        //    startBlock = 当前 block.number + 10（给点缓冲，避免 addStakePool 的 Already ended 检查）
        //    endBlock = startBlock + durationBlocks
        uint256 startBlock = block.number + 10;
        uint256 endBlock = startBlock + durationBlocks;

        bytes memory initData = abi.encodeWithSelector(
            MetaNodeStake.initialize.selector,
            IERC20(address(metaNode)),
            startBlock,
            endBlock,
            metaNodePerBlock
        );

        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxy = MetaNodeStake(address(proxyContract));

        // 5. 通过代理调用 addStakePool 添加 ETH 池（pid=0）
        //    第一个池必须 tokenAddress == address(0)
        proxy.addStakePool(
            address(0),
            ethPoolWeight,
            ethMinDeposit,
            unstakeLockedBlocks,
            false // 不需要 massUpdatePools（刚初始化，没有用户质押）
        );

        vm.stopBroadcast();

        // 6. 日志输出（必须在 startBroadcast 之外，避免被当成广播交易）
        console.log("=== Deployment Complete ===");
        console.log("Deployer (owner):", msg.sender);
        console.log("");
        console.log("MetaNode (ERC20):", address(metaNode));
        console.log("  - Name:   MetaNode");
        console.log("  - Symbol: MTN");
        console.log("  - Total:  10,000,000 MTN minted to deployer");
        console.log("");
        console.log("MetaNodeStake Implementation:", address(implementation));
        console.log("MetaNodeStake Proxy (use this):", address(proxy));
        console.log("");
        console.log("=== Staking Config ===");
        console.log("  startBlock:           ", startBlock);
        console.log("  endBlock:             ", endBlock);
        console.log("  metaNodePerBlock:     ", metaNodePerBlock);
        console.log("  ETH pool weight:      ", ethPoolWeight);
        console.log("  ETH min deposit:      ", ethMinDeposit);
        console.log("  unstakeLockedBlocks:  ", unstakeLockedBlocks);
        console.log("");

        // 7. 链上状态验证
        console.log("=== Verification ===");
        console.log("  proxy.startBlock():       ", proxy.startBlock());
        console.log("  proxy.endBlock():         ", proxy.endBlock());
        console.log("  proxy.metaNodePerBlock(): ", proxy.metaNodePerBlock());
        console.log("  proxy.meatNodeToken():    ", address(proxy.meatNodeToken()));
        console.log("  proxy.poolLength():       ", proxy.poolLength());
        console.log("  proxy.totalPoolWeight():  ", proxy.totalPoolWeight());

        // 角色验证
        bytes32 defaultAdminRole = 0x00;
        console.log("  deployer has DEFAULT_ADMIN_ROLE:", proxy.hasRole(defaultAdminRole, msg.sender));
        console.log("  deployer has ADMIN_ROLE:        ", proxy.hasRole(proxy.ADMIN_ROLE(), msg.sender));
        console.log("  deployer has UPGRADER_ROLE:     ", proxy.hasRole(proxy.UPGRADER_ROLE(), msg.sender));
    }
}
