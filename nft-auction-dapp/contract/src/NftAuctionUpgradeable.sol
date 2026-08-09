// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @dev NFT拍卖合约，支持升级提案和投票
 */
contract NftAuctionUpgradeable is Initializable, ContextUpgradeable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, IERC721Receiver {

    struct Auction {
        // 卖家地址
        address seller;
        // NFT合约地址
        address nftContract;
        // NFT的Token ID
        uint256 tokenId;
        // 币种地址（NFT合约地址）
        address tokenAddress;
        // 起拍价格（单位：美元）
        uint256 startingPriceInUSD;
        // 当前最高出价（单位：美元）, 用于比较出价者是否是最高出价者
        uint256 highestBidInUSD;
        // 当前最高出价（单位：NFT合约地址）
        uint256 highestBidAmount;
        // 当前最高出价者地址
        address highestBidder;
        // 当前最高出价者的币种地址
        address highestBidderTokenAddress;
        // 拍卖持续时间（单位：天）
        uint256 durationInDays; 
        // 开始时间
        uint256 startTime;
        // 结束时间
        uint256 endTime;
        // 是否结束
        bool ended;
    }

    // 当前已授权升级的实现地址（一次性，防止重放）
    address private _pendingUpgradeImplementation;
    // 拍卖ID计数器
    uint256 private _auctionIdCounter;
    // 拍卖ID到拍卖的映射
    mapping(uint256 => Auction) public auctions;
    // 币种地址到价格预言机的映射
    mapping(address => AggregatorV3Interface) private _priceFeeds;
    // 平台手续费比例（单位：百分比）
    uint256 private _platformFeeRate;
    // 预言机最大允许价格陈旧时间，单位秒，根据feed心跳设置
    // ETH/USD心跳 ~3600s(1小时)；稳定币心跳86400(24h)，建议取保守值 4小时 = 14400
    uint256 public constant ORACLE_STALE_THRESHOLD = 14400;
    /**
     * @dev 创建拍卖事件
     * @param auctionId 拍卖ID
     * @param nftContract NFT合约地址
     * @param seller 卖家地址
     * @param tokenId NFT的Token ID
     * @param tokenAddress 币种地址（NFT合约地址）
     * @param startingPriceInUSD 起拍价格（单位：美元）
     * @param durationInDays 拍卖持续时间（单位：天）
     */
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed nftContract, 
        address seller, 
        uint256 tokenId, 
        address tokenAddress, 
        uint256 startingPriceInUSD, 
        uint256 durationInDays);
    
    /**
     * @dev 开始拍卖事件
     * @param auctionId 拍卖ID
     * @param startTime 开始时间
     * @param endTime 结束时间
     */
    event AuctionStarted(
        uint256 indexed auctionId,
        uint256 startTime, 
        uint256 endTime);

    /**
     * @dev 取消拍卖事件
     * @param auctionId 拍卖ID
     * @param seller 卖家地址
     * @param tokenId NFT的Token ID
     */
    event AuctionCanceled(
        uint256 indexed auctionId,
        address seller, 
        uint256 tokenId);

    /**
     * @dev 出价事件
     * @param auctionId 拍卖ID
     * @param bidder 出价者地址
     * @param bidPriceInUSD 出价金额（单位：美元）
     */
    event BidAuction(
        uint256 indexed auctionId,
        address bidder, 
        uint256 bidPriceInUSD);
    
    /**
     * @dev 退款事件
     * @param auctionId 拍卖ID
     * @param bidder 退款地址
     * @param refundAmount 退款金额（单位：NFT合约地址）
     */
    event RefundAuction(
        uint256 indexed auctionId,
        address bidder, 
        uint256 refundAmount);

    /**
     * @dev 结束拍卖事件
     * @param auctionId 拍卖ID
     * @param winner 胜者地址
     * @param highestBidInUSD 最高出价（单位：美元）
     */
    event AuctionEnded(
        uint256 indexed auctionId,
        address winner, 
        uint256 highestBidInUSD);
    /**
     * @dev 构造函数，禁用初始化器
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 所有者提议升级，设置 _pendingUpgradeImplementation 供 _authorizeUpgrade 校验
     * @param newImplementation 新的实现合约地址
     */
    // function proposeUpgrade(address newImplementation) external onlyOwner {
    //     require(newImplementation != address(0), "Invalid implementation address");
    //     _pendingUpgradeImplementation = newImplementation;
    // }

    /**
     * @dev 授权升级提案
     * @param newImplementation 新的实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {
        // require(_pendingUpgradeImplementation == newImplementation, "Upgrade must be approved by multi-sig proposal");
        // 清除授权标记，防止重放攻击
	    // _pendingUpgradeImplementation = address(0);
    }

    /**
     * @dev 初始化合约，设置所有者和确认数
     * @param platformFeeRate 平台手续费比例（单位：百分比）
     */
    function initialize(uint256 platformFeeRate) public initializer {
        __Context_init();
        __Ownable_init(_msgSender());
        _platformFeeRate = platformFeeRate;
    }

    /**
     * @dev 设置指定币种的价格预言机
     * @param tokenAddress 币种地址（NFT合约地址）
     * @param priceFeed 价格预言机地址
     */
    function setPriceFeed(address tokenAddress, address priceFeed) external onlyOwner {
        _priceFeeds[tokenAddress] = AggregatorV3Interface(priceFeed);
    }

    /**
     * @dev 获取指定币种的当前价格（单位：美元）
     * @param tokenAddress 币种地址（NFT合约地址）
     * @param amount 金额（单位：币种）
     * @return success 是否成功获取价格
     * @return usdAmount 美元金额（单位：美元）
     */
    function getPrice2USD(address tokenAddress, uint256 amount) public view returns (bool, uint256) {
        // 1. 判断该代币是否配置预言机，未配置直接返回false，避免DoS
        if (address(_priceFeeds[tokenAddress]) == address(0)) {
            return (false, 0);
        }

        uint8 decimals;
        int256 answer;
        uint256 updatedAt;
        uint80 roundId;
        uint80 answeredInRound;

        // try‑catch捕获预言机合约调用异常
        try _priceFeeds[tokenAddress].latestRoundData() returns (
            uint80 _roundId, int256 _answer, uint256, uint256 _updatedAt, uint80 _answeredInRound
        ) {
            roundId = _roundId;
            answer = _answer;
            updatedAt = _updatedAt;
            answeredInRound = _answeredInRound;
            decimals = _priceFeeds[tokenAddress].decimals();
        } catch {
            return (false, 0);
        }

        // 2. 校验价格有效
        if (answer <= 0) return (false, 0);
        if (answeredInRound < roundId) return (false, 0);
        // 使用 block.timestamp 检查预言机数据是否过时
        // 矿工仅可±数秒篡改时间戳；本处阈值很大，扰动不影响预言机过期判断
        // forge-lint: disable-next-line(block-timestamp)
        uint256 currentTime = block.timestamp;
        if (currentTime < updatedAt || currentTime - updatedAt > ORACLE_STALE_THRESHOLD) return (false, 0);
        // 3. 计算usd金额（answer已校验>0，安全转换为uint256）
        // casting to 'uint256' is safe because [explain why]
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 price = uint256(answer);
        return (true, price * amount / (10 ** decimals));
    }

    /**
     * @dev 创建拍卖
     * @param nftContract NFT合约地址
     * @param tokenId NFT的Token ID
     * @param tokenAddress 币种地址（NFT合约地址）
     * @param startingPrice 起拍价格
     * @param durationInDays 拍卖持续时间（单位：天）
     */
    function CreateAuction(
        address nftContract, 
        uint256 tokenId, 
        address tokenAddress, 
        uint256 startingPrice, 
        uint256 durationInDays) external returns (uint256) {
        require(address(_priceFeeds[tokenAddress]) != address(0), "Token address not set");
        require(startingPrice > 0, "Starting price must be greater than 0");
        require(durationInDays >= 5, "Auction duration must be greater than 5 days");
        // 计算起拍价格（单位：美元）
        (bool success, uint256 startingPriceInUSD) = getPrice2USD(tokenAddress, startingPrice);
        require(success, "Failed to get price in USD");
        // 生成拍卖ID
        uint256 auctionId = _auctionIdCounter + 1;
        address _seller = _msgSender();
        auctions[auctionId] = Auction({
            seller: _seller, 
            nftContract: nftContract,
            tokenId: tokenId,
            tokenAddress: tokenAddress,
            startingPriceInUSD: startingPriceInUSD,
            highestBidInUSD: 0,
            highestBidAmount: 0,
            highestBidder: address(0),
            highestBidderTokenAddress: tokenAddress,
            durationInDays: durationInDays,
            startTime: 0,
            endTime: 0,
            ended: false
        });
        _auctionIdCounter = auctionId;
        // 从卖家地址转移NFT到拍卖合约地址(托管NFT)
        IERC721(nftContract).safeTransferFrom(_seller, address(this), tokenId);
        emit AuctionCreated(auctionId, nftContract, _seller, tokenId, tokenAddress, startingPriceInUSD, durationInDays); 
        return auctionId;
    }

    /**
     * @dev ERC721 安全转账回调。拍卖合约作为 NFT 托管方，需实现此接口
     *      才能接收 safeTransferFrom 转入的 NFT，否则 CreateAuction 会 revert。
     *      始终允许接收（返回 selector），不做额外校验。
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev 开始拍卖
     * @param auctionId 拍卖ID
     */
    function StartAuction(uint256 auctionId) external {
        require(auctionId > 0, "Auction ID must be greater than 0");
        Auction storage auction = auctions[auctionId];
        address sender = _msgSender();
        require(auction.seller == sender || owner() == sender, "Only seller or owner can start auction");
        require(auction.startTime == 0, "Auction already started");
        require(!auction.ended, "Auction already ended");
        uint256 currentTime = block.timestamp;
        auction.startTime = currentTime;
        auction.endTime = currentTime + auction.durationInDays * 1 days;
        emit AuctionStarted(auctionId, auction.startTime, auction.endTime);
    }


    /**
     * @dev 投价
     * @param auctionId 拍卖ID
     * @param bidPrice 拍卖金额
     * @param tokenAddress 币种地址（NFT合约地址）
     */
    function Bid(uint256 auctionId, uint256 bidPrice, address tokenAddress) external nonReentrant {
        require(auctionId > 0, "Auction ID must be greater than 0");
        Auction storage auction = auctions[auctionId];
        require(auction.seller != address(0), "Auction not found");
        uint256 currentTime = block.timestamp;
        require(auction.startTime < currentTime, "Auction not started");
        require(auction.endTime > currentTime, "Auction already ended");
        require(!auction.ended, "Auction already ended");

        // 计算拍卖价格（单位：美元）
        (bool success, uint256 bidPriceInUSD) = getPrice2USD(tokenAddress, bidPrice);
        require(success, "Failed to get price in USD");
        require(bidPriceInUSD >= auction.startingPriceInUSD, "Bid price must be higher than starting price");

        address bidder = _msgSender();
        address oldHighestBidder = auction.highestBidder;
        address oldHighestBidderTokenAddress = auction.highestBidderTokenAddress;
        uint256 oldHighestBidInUSD = auction.highestBidInUSD;
        uint256 oldHighestBidAmount = auction.highestBidAmount;

        require(auction.seller != bidder, "Cannot bid on your own NFT");
        require(oldHighestBidInUSD < bidPriceInUSD, "Bid price must be higher than current highest bid");
        // 更新最高出价者
        auction.highestBidder = bidder;
        auction.highestBidderTokenAddress = tokenAddress;
        auction.highestBidInUSD = bidPriceInUSD;
        auction.highestBidAmount = bidPrice;

         // 如果有上一个最高出价者，退款上一个最高出价者的钱
        if (oldHighestBidder != address(0)) {
            // 退款上一个最高出价者的钱
            _refund(auctionId, oldHighestBidder, oldHighestBidderTokenAddress, oldHighestBidAmount);
        }
        // 从出价者的钱转到合约中
        success = IERC20(tokenAddress).transferFrom(bidder, address(this), bidPrice);
        require(success, "Failed to transfer tokens");
        // 触发出价事件
        emit BidAuction(auctionId, bidder, bidPriceInUSD);
    }


    // 在拍卖开始前，可以取消拍卖
    function CancelAuction(uint256 auctionId) external {
        require(auctionId > 0, "Auction ID must be greater than 0");
        Auction storage auction = auctions[auctionId];
        address sender = _msgSender();
        require(auction.seller == sender || owner() == sender, "Only seller or owner can cancel auction");
        require(auction.startTime == 0, "Auction already started");
        require(!auction.ended, "Auction already ended");
        // 从托管NFT合约地址转移NFT到卖家地址
        IERC721(auction.nftContract).safeTransferFrom(address(this), auction.seller, auction.tokenId);
        // 触发取消拍卖事件
        emit AuctionCanceled(auctionId, auction.seller, auction.tokenId);
    }

    /**
     * @dev 结束拍卖
     * @param auctionId 拍卖ID
     */
    function EndAuction(uint256 auctionId) external nonReentrant {
        require(auctionId > 0, "Auction ID must be greater than 0");
        Auction storage auction = auctions[auctionId];
        require(auction.startTime > 0, "Auction not started");
        address sender = _msgSender();
        // 只有卖家或合约管理员才能结束拍卖
        require(auction.seller == sender || owner() == sender, "Only seller or owner can end auction");
        uint256 currentTime = block.timestamp;
        require(auction.endTime <= currentTime, "Auction not ended");
        require(!auction.ended, "Auction already ended");
        // 更新拍卖状态
        auction.ended = true;
        address winner = auction.highestBidder;
        if (winner != address(0)) {
            // 计算平台手续费
            uint256 platformFeeAmount = auction.highestBidAmount * _platformFeeRate / 100;
            // 把钱转给seller
            bool success = IERC20(auction.highestBidderTokenAddress).transfer(auction.seller, auction.highestBidAmount - platformFeeAmount);
            require(success, "Failed to transfer money");
            // 把平台手续费转给平台管理员
            success = IERC20(auction.highestBidderTokenAddress).transfer(owner(), platformFeeAmount);
            require(success, "Failed to transfer platform fee");
            // 从托管NFT合约地址转移NFT到胜者地址
            IERC721(auction.nftContract).safeTransferFrom(address(this), winner, auction.tokenId);
            // 触发结束拍卖事件
            emit AuctionEnded(auctionId, winner, auction.highestBidInUSD);
        } else {
            // 没有出价者，卖家保留NFT
            IERC721(auction.nftContract).safeTransferFrom(address(this), auction.seller, auction.tokenId);
            emit AuctionCanceled(auctionId, auction.seller, auction.tokenId);
        }
    }

    /**
     * @dev 退款金额（单位：NFT合约地址）
     * @notice 从本合约地址退款金额给退款地址
     * @param auctionId 拍卖ID
     * @param bidder 出价者地址
     * @param tokenAddress 币种地址（NFT合约地址）
     * @param amount 退款金额（单位：NFT合约地址）
     */
    function _refund(uint256 auctionId, address bidder, address tokenAddress, uint256 amount) internal {
        if (amount == 0) return;
        // 从本合约地址退款金额给出价者
        bool success = IERC20(tokenAddress).transfer(bidder, amount);
        require(success, "Failed to transfer money");
        // 触发退款事件
        emit RefundAuction(auctionId, bidder, amount);
    }

    // 保留空间
    uint256[256] private __gap;
}