// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";

contract MultiSigWalletScript is Script {
    MultiSigWallet public multiSigWallet;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address owner1 = vm.envAddress("OWNER1");
        address owner2 = vm.envAddress("OWNER2");
        address owner3 = vm.envAddress("OWNER3");
        uint256 threshold = vm.envUint("THRESHOLD");

        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;

        multiSigWallet = new MultiSigWallet(owners, threshold);

        vm.stopBroadcast();
    }
}
