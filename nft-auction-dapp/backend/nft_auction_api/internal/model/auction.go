package model

import "time"

// AuctionStatus 拍卖状态枚举
type AuctionStatus uint8

const (
	AuctionStatusCreated  AuctionStatus = 0 // 已创建，未开始
	AuctionStatusActive   AuctionStatus = 1 // 进行中
	AuctionStatusEnded    AuctionStatus = 2 // 已结束
	AuctionStatusCanceled AuctionStatus = 3 // 已取消
)

// Auction 拍卖数据模型，对应链上 Auction 结构体
type Auction struct {
	ID                   uint64    `gorm:"column:id;primaryKey;autoIncrement" json:"id"`
	AuctionID            string    `gorm:"column:auction_id;type:varchar(78);uniqueIndex;not null" json:"auctionId"` // 链上 auctionId (uint256 as string)
	Seller               string    `gorm:"column:seller;type:varchar(42);index;not null" json:"seller"`
	NftContract          string    `gorm:"column:nft_contract;type:varchar(42);index;not null" json:"nftContract"`
	TokenID              string    `gorm:"column:token_id;type:varchar(78);index;not null" json:"tokenId"`
	TokenAddress         string    `gorm:"column:token_address;type:varchar(42);index;not null" json:"tokenAddress"`
	StartingPriceUSD     string    `gorm:"column:starting_price_usd;type:varchar(78);not null" json:"startingPriceUSD"`
	HighestBidInUSD      string    `gorm:"column:highest_bid_in_usd;type:varchar(78);default:'0'" json:"highestBidInUSD"`
	HighestBidAmount     string    `gorm:"column:highest_bid_amount;type:varchar(78);default:'0'" json:"highestBidAmount"`
	HighestBidder        string    `gorm:"column:highest_bidder;type:varchar(42);default:''" json:"highestBidder"`
	HighestBidderToken   string    `gorm:"column:highest_bidder_token;type:varchar(42);default:''" json:"highestBidderToken"`
	DurationInDays       uint64    `gorm:"column:duration_in_days;not null" json:"durationInDays"`
	StartTime            uint64    `gorm:"column:start_time;default:0" json:"startTime"`
	EndTime              uint64    `gorm:"column:end_time;default:0" json:"endTime"`
	Status               AuctionStatus `gorm:"column:status;not null;default:0;index" json:"status"`
	TxHash               string    `gorm:"column:tx_hash;type:varchar(66);not null" json:"txHash"`
	BlockNumber          uint64    `gorm:"column:block_number;index" json:"blockNumber"`
	CreatedAt            time.Time `gorm:"column:created_at;autoCreateTime" json:"createdAt"`
	UpdatedAt            time.Time `gorm:"column:updated_at;autoUpdateTime" json:"updatedAt"`
}

func (Auction) TableName() string {
	return "auctions"
}
