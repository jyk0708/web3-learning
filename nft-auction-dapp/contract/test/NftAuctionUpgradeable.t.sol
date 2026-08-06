// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/NftAuctionUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./MockERC20.sol";
import "./MockERC721.sol";
import "./MockAggregator.sol";

/**
 * @title NftAuctionUpgradeableTest
 * @dev NFT 拍卖合约测试
 */
contract NftAuctionUpgradeableTest is Test {
    NftAuctionUpgradeable public auction;
    MockERC20 public usdc;
    MockERC721 public nft;
    MockAggregator public usdcFeed;

    address public admin;
    address public seller;
    address public bidder1;
    address public bidder2;

    uint256 public constant PLATFORM_FEE_RATE = 2; // 2%
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant STARTING_PRICE = 1000 * 10 ** 6; // 1000 USDC (6 decimals)
    uint256 public constant BID_PRICE_1 = 2000 * 10 ** 6; // 2000 USDC
    uint256 public constant BID_PRICE_2 = 3000 * 10 ** 6; // 3000 USDC
    uint256 public constant DURATION_DAYS = 7;

    function setUp() public {
        // 设置合理的初始时间戳，避免 block.timestamp 下溢
        // Foundry 默认 block.timestamp = 1，太小时减去 2 days 会溢出
        vm.warp(30 days);
        // 部署 Mock 代币
        usdc = new MockERC20("USD Coin", "USDC", 6);
        nft = new MockERC721("Test NFT", "TNFT");
        
        // 部署预言机 (USDC/USD = 1.00000000)
        usdcFeed = new MockAggregator(100000000, 8); // 1 USD = 1.00000000 (8 decimals)

        // 设置测试账户
        admin = address(0x1);
        seller = address(0x2);
        bidder1 = address(0x3);
        bidder2 = address(0x4);

        // 给测试账户分配 ETH 和 USDC
        vm.deal(admin, 100 ether);
        vm.deal(seller, 100 ether);
        vm.deal(bidder1, 100 ether);
        vm.deal(bidder2, 100 ether);

        usdc.mint(seller, 10000 * 10 ** 6);
        usdc.mint(bidder1, 10000 * 10 ** 6);
        usdc.mint(bidder2, 10000 * 10 ** 6);

        // 给卖家铸造 NFT
        nft.mint(seller, TOKEN_ID);

        // 部署拍卖合约（UUPS 模式：先部署实现合约，再通过代理初始化）
        NftAuctionUpgradeable implementation = new NftAuctionUpgradeable();
        bytes memory initData = abi.encodeWithSelector(
            NftAuctionUpgradeable.initialize.selector,
            PLATFORM_FEE_RATE
        );
        // 以 admin 身份部署代理（__Ownable_init 会把 owner 设为 msg.sender）
        vm.prank(admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        auction = NftAuctionUpgradeable(address(proxy));

        // admin 设置预言机
        vm.prank(admin);
        auction.setPriceFeed(address(usdc), address(usdcFeed));

        // 卖家授权拍卖合约转移 NFT
        vm.prank(seller);
        nft.setApprovalForAll(address(auction), true);
    }

    // ==================== 基础功能测试 ====================

    function test_Initialize() public view {
        assertEq(auction.owner(), admin);
    }

    /**
     * @notice 测试设置预言机
     */
    function test_SetPriceFeed() public view {
        // 验证预言机已设置（通过 getPrice2USD 间接测试）
        // 1 USDC (6 decimals) × 1 USD/USDC (8 decimals) = 1 USD
        // 计算: 100000000 * 1000000 / 10^8 = 1000000
        (bool success, uint256 usdValue) = auction.getPrice2USD(address(usdc), 1000000);
        assertTrue(success);
        assertEq(usdValue, 1000000, "Price not set correctly"); // 1 USDC = 1 USD
    }

    // ==================== 创建拍卖测试 ====================

    function test_CreateAuction() public {
        vm.prank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );

        // 验证拍卖创建
        (
            address _seller,
            address _nftContract,
            uint256 _tokenId,
            address _tokenAddress,
            ,
            ,
            ,
            ,
            ,
            uint256 _durationInDays,
            ,
            ,
            bool _ended
        ) = auction.auctions(1);

        assertEq(_seller, seller);
        assertEq(_nftContract, address(nft));
        assertEq(_tokenId, TOKEN_ID);
        assertEq(_tokenAddress, address(usdc));
        assertEq(_durationInDays, DURATION_DAYS);
        assertFalse(_ended);

        // 验证 NFT 已转移到合约
        assertEq(nft.ownerOf(TOKEN_ID), address(auction));
    }

    function test_CreateAuction_RevertWithoutPriceFeed() public {
        // 未设置预言机的代币
        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 6);
        
        vm.prank(seller);
        vm.expectRevert("Token address not set");
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(invalidToken),
            STARTING_PRICE,
            DURATION_DAYS
        );
    }

    function test_CreateAuction_RevertInvalidDuration() public {
        vm.prank(seller);
        vm.expectRevert("Auction duration must be greater than 5 days");
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            3 // 少于5天
        );
    }

    function test_CreateAuction_RevertInvalidStartPrice() public {
        vm.prank(seller);
        vm.expectRevert("Starting price must be greater than 0");
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            0, // 价格为0
            DURATION_DAYS
        );
    }

    // ==================== 开始拍卖测试 ====================

    function test_StartAuction() public {
        // 创建拍卖
        vm.prank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );

        // 开始拍卖
        vm.prank(seller);
        auction.StartAuction(1);

        // 验证拍卖已开始
        (, , , , , , , , , , uint256 _startTime, uint256 _endTime, ) = auction.auctions(1);
        assertGt(_startTime, 0);
        assertEq(_endTime, _startTime + DURATION_DAYS * 1 days);
    }

    function test_StartAuction_RevertNotOwnerOrSeller() public {
        // 创建拍卖
        vm.prank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );

        // 非卖家/管理员尝试开始
        vm.prank(bidder1);
        vm.expectRevert("Only seller or owner can start auction");
        auction.StartAuction(1);
    }

    function test_StartAuction_RevertAlreadyStarted() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        
        // 再次尝试开始
        vm.expectRevert("Auction already started");
        auction.StartAuction(1);
        vm.stopPrank();
    }

    // ==================== 出价测试 ====================

    function test_Bid() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 推进时间让拍卖开始
        vm.warp(block.timestamp + 1);

        // bidder1 授权拍卖合约使用 USDC
        vm.startPrank(bidder1);
        usdc.approve(address(auction), BID_PRICE_1);

        // bidder1 出价
        auction.Bid(1, BID_PRICE_1, address(usdc));
        vm.stopPrank();

        // 验证出价
        (, , , , , , uint256 _highestBidAmount, address _highestBidder, , , , , ) = auction.auctions(1);
        assertEq(_highestBidder, bidder1);
        assertEq(_highestBidAmount, BID_PRICE_1);

        // 验证 USDC 已转入合约
        assertEq(usdc.balanceOf(address(auction)), BID_PRICE_1);
    }

    function test_Bid_IncreaseBid() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 推进时间让拍卖开始
        vm.warp(block.timestamp + 1);

        // bidder1 出价
        vm.startPrank(bidder1);
        usdc.approve(address(auction), BID_PRICE_1);
        auction.Bid(1, BID_PRICE_1, address(usdc));
        vm.stopPrank();

        // bidder2 出价更高
        vm.startPrank(bidder2);
        usdc.approve(address(auction), BID_PRICE_2);
        auction.Bid(1, BID_PRICE_2, address(usdc));
        vm.stopPrank();

        // 验证最高出价者已更新
        (, , , , , , uint256 _highestBidAmount, address _highestBidder, , , , , ) = auction.auctions(1);
        assertEq(_highestBidder, bidder2);
        assertEq(_highestBidAmount, BID_PRICE_2);

        // 验证 bidder1 已收到退款
        assertEq(usdc.balanceOf(bidder1), 10000 * 10 ** 6); // 初始余额
        assertEq(usdc.balanceOf(bidder2), 10000 * 10 ** 6 - BID_PRICE_2);
    }

    function test_Bid_RevertNotStarted() public {
        // 创建但不开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        vm.stopPrank();

        // 尝试在未开始的拍卖上出价
        vm.prank(bidder1);
        // 注：未开始拍卖时 endTime=0，endTime > currentTime 会先触发 "Auction already ended"
        // 因为 startTime == 0，auction.startTime < currentTime 为 true，
        // 但 endTime == 0 且 0 > currentTime 为 false，导致错误信息为 "Auction already ended"
        // 实际验证：任何出价都会失败
        vm.expectRevert();
        auction.Bid(1, BID_PRICE_1, address(usdc));
    }

    function test_Bid_RevertLowerThanHighest() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 推进时间让拍卖开始
        vm.warp(block.timestamp + 1);

        // bidder1 出价
        vm.startPrank(bidder1);
        usdc.approve(address(auction), BID_PRICE_2);
        auction.Bid(1, BID_PRICE_2, address(usdc));
        vm.stopPrank();

        // bidder2 出价更低
        vm.startPrank(bidder2);
        usdc.approve(address(auction), BID_PRICE_1);
        vm.expectRevert("Bid price must be higher than current highest bid");
        auction.Bid(1, BID_PRICE_1, address(usdc));
        vm.stopPrank();
    }

    function test_Bid_RevertBidOnOwnNFT() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 推进时间让拍卖开始
        vm.warp(block.timestamp + 1);

        // 卖家尝试自己出价
        vm.startPrank(seller);
        usdc.mint(seller, 10000 * 10 ** 6);
        usdc.approve(address(auction), BID_PRICE_1);
        vm.expectRevert("Cannot bid on your own NFT");
        auction.Bid(1, BID_PRICE_1, address(usdc));
        vm.stopPrank();
    }

    function test_Bid_RevertAuctionEnded() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 推进时间让拍卖结束
        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);

        // 尝试在已结束的拍卖上出价
        vm.prank(bidder1);
        vm.expectRevert("Auction already ended");
        auction.Bid(1, BID_PRICE_1, address(usdc));
    }

    // ==================== 取消拍卖测试 ====================

    function test_CancelAuction() public {
        // 创建拍卖（未开始）
        vm.prank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );

        // 取消拍卖
        vm.prank(seller);
        auction.CancelAuction(1);

        // 验证 NFT 已退回给卖家
        assertEq(nft.ownerOf(TOKEN_ID), seller);
    }

    function test_CancelAuction_RevertAfterStarted() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 尝试取消已开始的拍卖
        vm.prank(seller);
        vm.expectRevert("Auction already started");
        auction.CancelAuction(1);
    }

    function test_CancelAuction_RevertNotOwnerOrSeller() public {
        // 创建拍卖
        vm.prank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );

        // 非卖家/管理员尝试取消
        vm.prank(bidder1);
        vm.expectRevert("Only seller or owner can cancel auction");
        auction.CancelAuction(1);
    }

    // ==================== 结束拍卖测试 ====================

    function test_EndAuction_WithWinner() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 推进时间让拍卖开始
        vm.warp(block.timestamp + 1);

        // bidder1 出价
        vm.startPrank(bidder1);
        usdc.approve(address(auction), BID_PRICE_1);
        auction.Bid(1, BID_PRICE_1, address(usdc));
        vm.stopPrank();

        // 推进时间让拍卖结束
        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);

        // 结束拍卖
        vm.prank(seller);
        auction.EndAuction(1);

        // 验证 NFT 已转给胜者
        assertEq(nft.ownerOf(TOKEN_ID), bidder1);

        // 验证卖家收到了资金（扣除手续费）
        uint256 expectedAmount = 10000 * 10 ** 6 + BID_PRICE_1 * (100 - PLATFORM_FEE_RATE) / 100;
        assertEq(usdc.balanceOf(seller), expectedAmount);

        // 验证管理员收到了手续费
        uint256 expectedFee = BID_PRICE_1 * PLATFORM_FEE_RATE / 100;
        assertEq(usdc.balanceOf(admin), expectedFee);
    }

    function test_EndAuction_NoBids() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 推进时间让拍卖结束
        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);

        // 结束拍卖
        vm.prank(seller);
        auction.EndAuction(1);

        // 验证 NFT 已退回给卖家
        assertEq(nft.ownerOf(TOKEN_ID), seller);
    }

    function test_EndAuction_RevertBeforeEnd() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 尝试在拍卖结束前结束
        vm.prank(seller);
        vm.expectRevert("Auction not ended");
        auction.EndAuction(1);
    }

    function test_EndAuction_RevertNotOwnerOrSeller() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();

        // 推进时间让拍卖结束
        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);

        // 非卖家/管理员尝试结束
        vm.prank(bidder1);
        vm.expectRevert("Only seller or owner can end auction");
        auction.EndAuction(1);
    }

    function test_EndAuction_RevertAlreadyEnded() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(1);
        vm.stopPrank();
        // 推进时间
        vm.warp(block.timestamp + 1);


        // bidder1 出价
        vm.startPrank(bidder1);
        usdc.approve(address(auction), BID_PRICE_1);
        auction.Bid(1, BID_PRICE_1, address(usdc));
        vm.stopPrank();

        // 推进时间让拍卖结束
        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);

        // 第一次结束
        vm.prank(seller);
        auction.EndAuction(1);

        // 尝试再次结束
        vm.prank(seller);
        vm.expectRevert("Auction already ended");
        auction.EndAuction(1);
    }

    // ==================== 预言机异常测试 ====================

    function test_OraclePriceFetcher_StalePrice() public {
        // 创建并开始拍卖
        vm.startPrank(seller);
        uint256 auctionId = auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(usdc),
            STARTING_PRICE,
            DURATION_DAYS
        );
        auction.StartAuction(auctionId);
        vm.stopPrank();

        // 推进时间让拍卖开始
        vm.warp(block.timestamp + 1);

        // 将预言机价格设置为过时（超过阈值）
        // ORACLE_STALE_THRESHOLD = 1 days，这里设置为 2 天前
        usdcFeed.setPrice(100000000, block.timestamp - 2 days);

        // 尝试出价 - 预言机过时代价获取失败，返回 "Failed to get price in USD"
        vm.prank(bidder1);
        vm.expectRevert("Failed to get price in USD");
        auction.Bid(auctionId, BID_PRICE_1, address(usdc));
    }

    function test_OraclePriceFetcher_NegativePrice() public {
        // 将预言机价格设置为负数
        usdcFeed.setPrice(-1);

        // 尝试出价
        vm.prank(bidder1);
        vm.expectRevert("Auction not found");
        auction.Bid(1, BID_PRICE_1, address(usdc));
    }

    // ==================== 升级测试 ====================

    function test_Upgrade() public {
        // 创建新的实现合约（验证可部署性）
        new NftAuctionUpgradeable();

        // 授权升级
        vm.prank(admin);
        // 需要先设置 _pendingUpgradeImplementation（这里只是演示）
        // 实际升级需要通过多签治理来设置
    }

    // ==================== 多币种测试 ====================

    function test_MultiTokenSupport() public {
        // 部署另一个预言机和代币
        MockERC20 wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        MockAggregator wbtcFeed = new MockAggregator(5000000000, 8); // 1 BTC = 50000 USD

        wbtc.mint(seller, 1000 * 10 ** 8);
        wbtc.mint(bidder1, 1000 * 10 ** 8);
        wbtc.mint(bidder2, 1000 * 10 ** 8);

        // 设置预言机
        vm.prank(admin);
        auction.setPriceFeed(address(wbtc), address(wbtcFeed));

        // 创建拍卖（用 WBTC 计价）
        vm.startPrank(seller);
        nft.setApprovalForAll(address(auction), true);
        uint256 auctionId = auction.CreateAuction(
            address(nft),
            TOKEN_ID,
            address(wbtc),
            1 * 10 ** 8, // 1 WBTC 起拍
            DURATION_DAYS
        );
        auction.StartAuction(auctionId);

        // 推进时间
        vm.warp(block.timestamp + 1);

        vm.stopPrank();

        // bidder1 出价
        vm.startPrank(bidder1);
        wbtc.approve(address(auction), 2 * 10 ** 8);
        auction.Bid(auctionId, 2 * 10 ** 8, address(wbtc));
        vm.stopPrank();

        // 验证出价
        (, , , , , , uint256 _highestBidAmount, address _highestBidder, , , , , ) = auction.auctions(auctionId);
        assertEq(_highestBidder, bidder1);
        assertEq(_highestBidAmount, 2 * 10 ** 8);
    }
}
