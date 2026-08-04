// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/StorageSlot.sol";

/**
 * @dev NFT拍卖合约，支持升级提案和投票
 */
contract NftAuctionUpgradeable is Initializable, ContextUpgradeable, UUPSUpgradeable {

    /**
     * @dev 拍卖结构体，包含拍卖的相关信息
     * @note tokenId 是NFT的唯一标识符，比如：nftContract如果是小区名字，则tokenId是房间号
     */
    struct Auction {
        address nftContract; // NFT合约地址
        uint256 tokenId; // NFT Token ID
        address seller; // 卖家地址
        uint256 startTime; // 拍卖开始时间
        uint256 endTime; // 拍卖结束时间
        uint256 startingBid; // 起拍价
        address highestBidder; // 最高出价者地址
        uint256 highestBid; // 最高出价金额
        bool settled; // 是否已结算
    }

    // 合约所有者地址
    address public owner;
    // 拍卖数量
    uint256 public auctionCount;
    // 拍卖列表
    Auction[] public auctions;
    // NFT合约地址 => NFT Token ID => 拍卖ID 
    mapping(address => mapping(uint256 => uint256)) public nftToken2AuctionId;
    // 拍卖ID => 拍卖数据
    mapping(uint256 => Auction) public auctionData;

    /**
     * @dev 仅允许所有者调用的修饰符
     */
    modifier onlyOwner() {
        require(owner == _msgSender(), "caller is not the owner");
        _;
    }

    /**
     * @dev 发送合约升级事件
     * @param newImplementation 新的实现合约地址
     */
    event ContractUpgrade(address indexed newImplementation);

    /**
     * @dev 发送拍卖创建事件
     * @param auctionId 拍卖ID
     * @param nftContract NFT合约地址
     * @param tokenId NFT Token ID
     */
    event AuctionCreated(uint256 indexed auctionId, address indexed nftContract, uint256 tokenId);
    /**
     * @dev 发送出价事件
     * @param auctionId 拍卖ID
     * @param bidder 出价者地址
     * @param bidAmount 出价金额
     */
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount);
    
    constructor() {
        // 禁用初始化器，防止合约被意外初始化
        _disableInitializers();
    }

    
    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {
        // 使用StorageSlot存储新的实现合约地址
	    StorageSlot.getAddressSlot(ERC1967_IMPLEMENTATION_SLOT).value = newImplementation;
        // 发送合约升级事件
        emit ContractUpgrade(newImplementation);
    }

    /**
     * @dev 初始化函数，设置合约所有者
     */
    function initialize() external initializer {
        __Context_init();
        owner = _msgSender();
    }

    /**
     * @dev 创建新的NFT拍卖
     * @param nftContract NFT合约地址
     * @param tokenId NFT Token ID
     * @param startTime 拍卖开始时间
     * @param endTime 拍卖结束时间
     * @param startingBid 起拍价
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startTime,
        uint256 endTime,
        uint256 startingBid
    ) external virtual {
        // 拍卖开始时间必须大于当前时间
        require(startTime > block.timestamp, "startTime must be in the future");
        // 检查拍卖时间是否合法
        require(startTime < endTime, "startTime must be less than endTime");
        // 拍卖时间必须大于5天
        require(endTime - startTime >= 5 days, "Auction duration must be at least 5 days");
        // 检查是否已经存在该NFT的拍卖
        require(nftToken2AuctionId[nftContract][tokenId] == 0, "Auction already exists for this NFT");

        // 创建一个临时的拍卖ID，并将其加1（节省gas费用）
        uint256 tempAuctionCount = auctionCount;
        tempAuctionCount += 1; 
        Auction memory newAuction = Auction({
            nftContract: nftContract,
            tokenId: tokenId,
            seller: _msgSender(),
            startTime: startTime,
            endTime: endTime,
            startingBid: startingBid,
            highestBidder: address(0),
            highestBid: 0,
            settled: false
        });

        auctions.push(newAuction);
        nftToken2AuctionId[nftContract][tokenId] = tempAuctionCount;
        auctionData[tempAuctionCount] = newAuction;
        auctionCount = tempAuctionCount;
        emit AuctionCreated(tempAuctionCount, nftContract, tokenId);
    }


    /**
     * @dev 参与拍卖出价
     * @param auctionId 拍卖ID
     */
    function bidAuction(uint256 auctionId) external payable virtual {
        uint256 currentTimestamp = block.timestamp;
        Auction storage auction = auctionData[auctionId];
        address bidder = _msgSender();
        uint256 bidAmount = msg.value;
        // 检查拍卖是否存在
        require(auction.seller != address(0), "Auction does not exist");
        // 检查拍卖是否已结算
        require(!auction.settled, "Auction has been settled");
        // 检查拍卖是否已开始且未结束
        require(currentTimestamp >= auction.startTime, "Auction has not started yet");
        // 检查拍卖是否已结束
        require(currentTimestamp <= auction.endTime, "Auction has ended");
        // 检查出价金额不低于起拍价
        require(bidAmount >= auction.startingBid, "Less than starting bid");
        // 检查出价金额是否高于当前最高出价
        require(bidAmount > auction.highestBid, "Not higher than current bid");

        // 退还之前最高出价者
        address oldBidder = auction.highestBidder;
        uint256 oldAmount = auction.highestBid;
        // 退还之前的最高出价者
        if (oldBidder != address(0)) {
            // 退还旧最高出价者
            (bool success, ) = payable(oldBidder).call{value: oldAmount}("");
            require(success, "Failed to refund previous highest bid");
        }
        // 更新拍卖信息
        auction.highestBidder = bidder;
        // 更新最高出价金额
        auction.highestBid = bidAmount;
        emit BidPlaced(auctionId, bidder, bidAmount);
    }

    /**
     * @dev 结束拍卖并结算
     * @param auctionId 拍卖ID
     */
    function endAuction(uint256 auctionId) external virtual {
        uint256 currentTimestamp = block.timestamp;
        Auction storage auction = auctionData[auctionId];
        // 检查拍卖是否存在
        require(auction.seller != address(0), "Auction does not exist");
        // 检查拍卖是否已结算
        require(!auction.settled, "Auction has been settled");
        // 检查拍卖是否已结束
        require(currentTimestamp > auction.endTime, "Auction has not ended yet");
        // 标记拍卖为已结算
        auction.settled = true;
        // 如果有最高出价者，则将资金转给卖家
        if (auction.highestBidder != address(0)) {
            (bool success, ) = payable(auction.seller).call{value: auction.highestBid}("");
            require(success, "Failed to transfer funds to seller");
        }
    }

    /**
     * @dev 取消拍卖
     * @param auctionId 拍卖ID
     */
    function cancelAuction(uint256 auctionId) external virtual {
        uint256 currentTimestamp = block.timestamp;
        Auction storage auction = auctionData[auctionId];
        // 仅允许卖家取消拍卖
        require(_msgSender() == auction.seller, "Only seller can cancel the auction");
        // 检查拍卖是否存在
        require(auction.seller != address(0), "Auction does not exist");
        // 检查拍卖是否已开始
        require(currentTimestamp < auction.startTime, "Auction has already started");
        // 检查拍卖是否已结算
        require(!auction.settled, "Auction has been settled");
        // 标记拍卖为已结算
        auction.settled = true;
        // 如果有最高出价者，则退还资金
        if (auction.highestBidder != address(0)) {
            (bool success, ) = payable(auction.highestBidder).call{value: auction.highestBid}("");
            require(success, "Failed to refund highest bidder");
        }
    }



    uint256[256] private __gap;
}