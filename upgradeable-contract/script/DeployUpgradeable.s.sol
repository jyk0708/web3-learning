// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MultiSigWalletUpgradeable} from "../src/MultiSigWalletUpgradeable.sol";

/**
 * @dev 首次部署脚本：部署实现合约 + ERC1967 代理
 *
 * 步骤说明：
 * 1. 部署 MultiSigWalletUpgradeable 实现合约（V1）
 * 2. 部署 ERC1967Proxy，指向实现合约，并在构造函数中调用 initialize
 * 3. 之后所有交互都通过代理地址进行
 */
contract DeployUpgradeable is Script {
    MultiSigWalletUpgradeable public implementation;
    ERC1967Proxy public proxy;
    MultiSigWalletUpgradeable public wrappedProxy;

    function setUp() public {}

    function run() public {
        // ---- 读取配置 ----
        address owner1 = vm.envAddress("OWNER1");
        address owner2 = vm.envAddress("OWNER2");
        address owner3 = vm.envAddress("OWNER3");
        uint256 threshold = vm.envUint("THRESHOLD");

        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;

        // ---- 1. 准备 initialize 的 calldata ----
        bytes memory initData = abi.encodeWithSelector(
            MultiSigWalletUpgradeable.initialize.selector,
            owners,
            threshold
        );

        vm.startBroadcast();

        // ---- 2. 部署实现合约 ----
        implementation = new MultiSigWalletUpgradeable();
        console.log("Implementation deployed at:", address(implementation));

        // ---- 3. 部署 ERC1967Proxy（同时调用 initialize） ----
        // 构造函数参数：implementation, data
        proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed at:", address(proxy));

        vm.stopBroadcast();

        // ---- 验证 ----
        wrappedProxy = MultiSigWalletUpgradeable(payable(address(proxy)));
        console.log("Owner count:", wrappedProxy.getOwnerCount());
        console.log("Threshold:", wrappedProxy.getThreshold());
        console.log("---");
        console.log(">>> IMPORTANT: Use Proxy address for all interactions:", address(proxy));
    }
}
