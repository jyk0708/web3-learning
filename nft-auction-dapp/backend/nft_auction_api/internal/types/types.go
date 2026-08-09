package types

// ApiResponse 统一响应格式
type ApiResponse struct {
	Status string `json:"status"`         // "ok" 或 "error"
	Err    string `json:"err,omitempty"`  // 异常信息，成功时为空
	Data   any    `json:"data,omitempty"` // 业务数据
}

// GetPrice2USDReq 查询代币兑换USD价格的请求
type GetPrice2USDReq struct {
	TokenAddress string `path:"tokenAddress"` // 代币合约地址（十六进制）
	Amount       string `path:"amount"`       // 代币数量（uint256，十进制字符串避免溢出）
}

// GetPrice2USDData 查询代币兑换USD价格的响应数据
type GetPrice2USDData struct {
	Success bool   `json:"success"` // 价格查询是否成功
	Price   string `json:"price"`   // USD 价格（uint256，十进制字符串）
}

/**
 * @Description: 创建拍卖请求
 */
type CreateAuctionReq struct {
	NftContract    string `json:"nftContract"`    // NFT 合约地址（十六进制）
	TokenId        string `json:"tokenId"`        // NFT tokenId（uint256，十进制字符串避免溢出）
	TokenAddress   string `json:"tokenAddress"`   // 支付代币地址（十六进制）
	StartingPrice  string `json:"startingPrice"`  // 起拍价（USD，uint256 十进制字符串）
	DurationInDays uint64 `json:"durationInDays"` // 拍卖持续天数
}

type CreateAuctionData struct {
	AuctionId string `json:"auctionId"` // 新建的拍卖 ID（uint256，十进制字符串）
	TxHash    string `json:"txHash"`    // 交易哈希
}

type SetPriceFeedReq struct {
	TokenAddress     string `json:"tokenAddress"`     // 币种地址（NFT合约地址）
	PriceFeedAddress string `json:"priceFeedAddress"` // 价格预言机地址
}

type SetPriceFeedData struct {
	TxHash string `json:"txHash"` // 交易哈希
}

type BidAuctionReq struct {
	AuctionId    string `json:"auctionId"`    // 拍卖 ID（uint256，十进制字符串）
	BidPrice     string `json:"bidPrice"`     // 竞拍价（uint256，十进制字符串）
	TokenAddress string `json:"tokenAddress"` // 支付代币地址（十六进制）
}

type BidAuctionData struct {
	TxHash string `json:"txHash"` // 交易哈希
}

// MockNftData mock NFT 测试数据，字段可直接用于 CreateAuction 请求
type MockNftData struct {
	NftContract    string `json:"nftContract"`    // MockERC721 合约地址
	TokenId        string `json:"tokenId"`        // 新铸造的 tokenId（uint256 十进制字符串）
	TokenAddress   string `json:"tokenAddress"`   // 建议支付代币地址（已配价格源）
	StartingPrice  string `json:"startingPrice"`  // 建议起拍价（代币数量）
	DurationInDays uint64 `json:"durationInDays"` // 建议持续天数
}

// ==================== 拍卖操作请求/响应 ====================

// StartAuctionReq 开始拍卖请求
type StartAuctionReq struct {
	AuctionId string `json:"auctionId"` // 拍卖 ID
}

type StartAuctionData struct {
	TxHash string `json:"txHash"` // 交易哈希
}

// EndAuctionReq 结束拍卖请求
type EndAuctionReq struct {
	AuctionId string `json:"auctionId"` // 拍卖 ID
}

type EndAuctionData struct {
	TxHash string `json:"txHash"` // 交易哈希
}

// CancelAuctionReq 取消拍卖请求
type CancelAuctionReq struct {
	AuctionId string `json:"auctionId"` // 拍卖 ID
}

type CancelAuctionData struct {
	TxHash string `json:"txHash"` // 交易哈希
}

// ==================== 查询请求/响应 ====================

// ListAuctionsReq 拍卖列表请求
type ListAuctionsReq struct {
	Status   uint8 `form:"status,default=0"`    // 状态筛选: 0=全部, 1=进行中, 2=已结束, 3=已取消
	Page     int   `form:"page,default=1"`      // 页码
	PageSize int   `form:"pageSize,default=10"` // 每页数量
}

// AuctionItem 拍卖列表项
type AuctionItem struct {
	AuctionID        string `json:"auctionId"`
	Seller           string `json:"seller"`
	NftContract      string `json:"nftContract"`
	TokenID          string `json:"tokenId"`
	TokenAddress     string `json:"tokenAddress"`
	StartingPriceUSD string `json:"startingPriceUSD"`
	HighestBidInUSD  string `json:"highestBidInUSD"`
	HighestBidAmount string `json:"highestBidAmount"`
	HighestBidder    string `json:"highestBidder"`
	DurationInDays   uint64 `json:"durationInDays"`
	StartTime        uint64 `json:"startTime"`
	EndTime          uint64 `json:"endTime"`
	Status           uint8  `json:"status"`
	TxHash           string `json:"txHash"`
	BlockNumber      uint64 `json:"blockNumber"`
	CreatedAt        string `json:"createdAt"`
}

// ListAuctionsData 拍卖列表响应
type ListAuctionsData struct {
	Total    int64          `json:"total"`
	Auctions []*AuctionItem `json:"auctions"`
	Page     int            `json:"page"`
	PageSize int            `json:"pageSize"`
}

// GetAuctionReq 拍卖详情请求
type GetAuctionReq struct {
	AuctionId string `path:"auctionId"` // 拍卖 ID
}

// GetAuctionData 拍卖详情响应
type GetAuctionData struct {
	Auction *AuctionItem `json:"auction"`
	Bids    []*BidItem   `json:"bids"`
}

// BidItem 出价记录项
type BidItem struct {
	ID          uint64 `json:"id"`
	AuctionID   string `json:"auctionId"`
	Bidder      string `json:"bidder"`
	BidAmount   string `json:"bidAmount"`
	BidPriceUSD string `json:"bidPriceUSD"`
	TxHash      string `json:"txHash"`
	BlockNumber uint64 `json:"blockNumber"`
	CreatedAt   string `json:"createdAt"`
}

type GetVersionData struct {
	Version string `json:"version"`
}
