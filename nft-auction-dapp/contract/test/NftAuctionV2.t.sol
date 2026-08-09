// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/NftAuctionUpgradeable.sol";
import "../src/NftAuctionV2.sol";
import "./MockERC20.sol";
import "./MockERC721.sol";
import "./MockAggregator.sol";

/**
 * @title NftAuctionV2Test
 * @dev V2 升级合约 demo 测试
 *
 * V2 仅新增 version() 方法。本测试演示：
 *   1. 完整的 V1 → V2 升级流程（UUPS + vm.store 绕过已移除的 proposeUpgrade）
 *   2. 升级后存储数据保留（owner、拍卖记录、预言机配置、NFT 托管）
 *   3. version() 返回 "V2"
 *   4. 升级权限安全检查（_authorizeUpgrade 的 pending 校验、onlyOwner）
 */
contract NftAuctionV2Test is Test {
    // V1 代理合约（升级前）
    NftAuctionUpgradeable internal v1Proxy;
    // V2 代理合约（升级后，与 v1Proxy 同地址）
    NftAuctionV2 internal v2Proxy;

    MockERC20 public usdc;
    MockERC721 public nft;
    MockAggregator public usdcFeed;

    address public admin;
    address public seller;
    address public bidder1;
    address public bidder2;

    uint256 public constant PLATFORM_FEE_RATE = 2; // 2%
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant STARTING_PRICE = 1000 * 10 ** 6; // 1000 USDC
    uint256 public constant BID_PRICE_1 = 2000 * 10 ** 6; // 2000 USDC
    uint256 public constant DURATION_DAYS = 7;

    /// @dev _pendingUpgradeImplementation 存储槽（forge inspect 确认为 slot 0）
    bytes32 internal constant PENDING_UPGRADE_SLOT = bytes32(uint256(0));

    function setUp() public {
        // 避免 block.timestamp 下溢
        vm.warp(30 days);

        // 1. 部署 Mock 资产
        usdc = new MockERC20("USD Coin", "USDC", 6);
        nft = new MockERC721("Test NFT", "TNFT");
        usdcFeed = new MockAggregator(100000000, 8); // 1 USDC = 1 USD

        // 2. 测试账户
        admin = address(0x1);
        seller = address(0x2);
        bidder1 = address(0x3);
        bidder2 = address(0x4);

        vm.deal(admin, 100 ether);
        vm.deal(seller, 100 ether);
        vm.deal(bidder1, 100 ether);
        vm.deal(bidder2, 100 ether);

        usdc.mint(seller, 10000 * 10 ** 6);
        usdc.mint(bidder1, 10000 * 10 ** 6);
        usdc.mint(bidder2, 10000 * 10 ** 6);
        nft.mint(seller, TOKEN_ID);

        // 3. 部署 V1 (UUPS 模式)
        NftAuctionUpgradeable implV1 = new NftAuctionUpgradeable();
        bytes memory initData = abi.encodeWithSelector(
            NftAuctionUpgradeable.initialize.selector,
            PLATFORM_FEE_RATE
        );
        vm.prank(admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), initData);
        v1Proxy = NftAuctionUpgradeable(address(proxy));

        // 4. 配置预言机
        vm.prank(admin);
        v1Proxy.setPriceFeed(address(usdc), address(usdcFeed));

        // 5. 卖家授权并创建一条拍卖记录（用于验证升级后数据保留）
        vm.startPrank(seller);
        nft.setApprovalForAll(address(v1Proxy), true);
        v1Proxy.CreateAuction(address(nft), TOKEN_ID, address(usdc), STARTING_PRICE, DURATION_DAYS);
        vm.stopPrank();

        // 6. 执行升级到 V2
        _upgradeToV2();
    }

    /**
     * @dev 完整的 V1 → V2 升级流程（与 UpgradeToV2.s.sol 脚本逻辑一致）
     *      V1 已移除 proposeUpgrade，通过 vm.store 直接写入 slot 0 设置 pending
     */
    function _upgradeToV2() internal {
        // 1. 部署 V2 实现合约
        NftAuctionV2 implV2 = new NftAuctionV2();

        // 2. 通过 vm.store 设置 _pendingUpgradeImplementation（V1 已移除 proposeUpgrade 函数）
        vm.store(address(v1Proxy), PENDING_UPGRADE_SLOT, bytes32(uint256(uint160(address(implV2)))));

        // 3. 以 admin 身份执行升级（upgradeToAndCall 内部调用 _authorizeUpgrade 校验 pending）
        //    OZ 5.x 移除了 upgradeTo(address)，只保留 upgradeToAndCall(address,bytes)
        vm.prank(admin);
        (bool ok,) = address(v1Proxy).call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(implV2), "")
        );
        require(ok, "upgradeToAndCall failed");

        v2Proxy = NftAuctionV2(address(v1Proxy));
    }

    // ==================== 升级流程测试 ====================

    function test_Version() public view {
        assertEq(v2Proxy.version(), "V2", "version should be V2");
    }

    function test_Upgrade_PreservesOwner() public view {
        assertEq(v2Proxy.owner(), admin, "owner should be preserved");
    }

    function test_Upgrade_PreservesAuctionData() public view {
        // V1 创建的拍卖记录在 V2 中仍然可读
        (address _seller, , , , , , , , , uint256 _durationInDays, , , ) = v2Proxy.auctions(1);
        assertEq(_seller, seller, "auction seller should be preserved");
        assertEq(_durationInDays, DURATION_DAYS, "auction duration should be preserved");
    }

    function test_Upgrade_PreservesPriceFeed() public view {
        // 预言机配置仍然有效
        (bool success, uint256 usdValue) = v2Proxy.getPrice2USD(address(usdc), 1000000);
        assertTrue(success, "price feed should work after upgrade");
        assertEq(usdValue, 1000000, "1 USDC should be 1 USD");
    }

    function test_Upgrade_PreservesNftEscrow() public view {
        // NFT 仍在拍卖合约托管中
        assertEq(nft.ownerOf(TOKEN_ID), address(v2Proxy), "NFT should remain escrowed");
    }

    function test_ImplementationSlotUpdated() public view {
        // 验证 EIP-1967 实现地址 slot 已更新
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        // 注意：必须用 vm.load 读取代理地址的存储，不能用 sload（sload 读的是测试合约自身存储）
        address currentImpl = address(uint160(uint256(vm.load(address(v1Proxy), implSlot))));
        assertTrue(currentImpl != address(0), "impl slot should not be zero");
    }

    // ==================== 升级权限安全测试 ====================

    function test_Upgrade_RevertWithoutPending() public {
        // 不设置 _pendingUpgradeImplementation 直接升级，应该回滚
        // _pendingUpgradeImplementation 在 setUp 升级后已被清零
        NftAuctionV2 newImpl = new NftAuctionV2();

        vm.prank(admin);
        (bool ok, bytes memory ret) = address(v1Proxy).call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(newImpl), "")
        );
        assertFalse(ok, "upgrade should fail without pending set");
        _assertRevertReason(ret, "Upgrade must be approved by multi-sig proposal");
    }

    function test_Upgrade_RevertNotOwner() public {
        // 非 owner 调用升级应失败
        NftAuctionV2 newImpl = new NftAuctionV2();

        // 先设置 pending
        vm.store(address(v1Proxy), PENDING_UPGRADE_SLOT, bytes32(uint256(uint160(address(newImpl)))));

        // bidder1（非 owner）调用升级应失败
        vm.prank(bidder1);
        (bool ok,) = address(v1Proxy).call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(newImpl), "")
        );
        assertFalse(ok, "non-owner upgrade should fail");
    }

    function test_Upgrade_PendingClearedAfterUpgrade() public {
        // 升级成功后 _pendingUpgradeImplementation 应被清零（防重放）
        // 验证方式：升级后直接再调用升级（不重新设置 pending），应失败
        NftAuctionV2 anotherImpl = new NftAuctionV2();

        // 此时 pending 已在 setUp 升级中被清零，不重新设置直接升级应失败
        vm.prank(admin);
        (bool ok, bytes memory ret) = address(v1Proxy).call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(anotherImpl), "")
        );
        assertFalse(ok, "upgrade should fail because pending was cleared after previous upgrade");
        _assertRevertReason(ret, "Upgrade must be approved by multi-sig proposal");
    }

    function test_Upgrade_PendingMismatch() public {
        // pending 指向 implA，但尝试升级到 implB，应失败
        NftAuctionV2 implA = new NftAuctionV2();
        NftAuctionV2 implB = new NftAuctionV2();

        // 设置 pending 指向 implA
        vm.store(address(v1Proxy), PENDING_UPGRADE_SLOT, bytes32(uint256(uint160(address(implA)))));

        // 尝试升级到 implB（与 pending 不匹配）
        vm.prank(admin);
        (bool ok, bytes memory ret) = address(v1Proxy).call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(implB), "")
        );
        assertFalse(ok, "upgrade should fail when pending != newImpl");
        _assertRevertReason(ret, "Upgrade must be approved by multi-sig proposal");
    }

    // ==================== 端到端流程测试 ====================

    function test_E2E_FullUpgradeFlow() public {
        // 演示完整业务流程：升级后创建新拍卖 → 出价 → 结束拍卖
        // （使用 tokenId = 2，因为 tokenId = 1 已在 setUp 中用于拍卖）
        nft.mint(seller, 2);

        vm.startPrank(seller);
        uint256 newAuctionId = v2Proxy.CreateAuction(
            address(nft),
            2,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        v2Proxy.StartAuction(newAuctionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        // bidder1 出价
        vm.startPrank(bidder1);
        usdc.approve(address(v2Proxy), BID_PRICE_1);
        v2Proxy.Bid(newAuctionId, BID_PRICE_1, address(usdc));
        vm.stopPrank();

        // 验证出价
        (, , , , , , uint256 _highestBidAmount, address _highestBidder, , , , , ) = v2Proxy.auctions(newAuctionId);
        assertEq(_highestBidder, bidder1);
        assertEq(_highestBidAmount, BID_PRICE_1);
    }

    /**
     * @dev 解码 low-level call 的 revert data，断言与预期 string 原因完全匹配。
     *      Solidity 的 require(false, "msg") 编码为 Error(string)，
     *      用 abi.encodeWithSignature 生成同样的编码后整体比较，避免手写 ABI 偏移。
     */
    function _assertRevertReason(bytes memory retData, string memory expected) internal pure {
        bytes memory expectedData = abi.encodeWithSignature("Error(string)", expected);
        require(
            keccak256(retData) == keccak256(expectedData),
            "revert reason mismatch"
        );
    }
}
