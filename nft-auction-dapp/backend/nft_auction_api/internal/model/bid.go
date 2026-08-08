package model

import "time"

// Bid 出价记录模型，记录每次出价行为
type Bid struct {
	ID          uint64    `gorm:"column:id;primaryKey;autoIncrement" json:"id"`
	AuctionID   string    `gorm:"column:auction_id;type:varchar(78);index;not null" json:"auctionId"`
	Bidder      string    `gorm:"column:bidder;type:varchar(42);index;not null" json:"bidder"`
	BidAmount   string    `gorm:"column:bid_amount;type:varchar(78);not null" json:"bidAmount"` // 代币数量 (uint256)
	BidPriceUSD string    `gorm:"column:bid_price_usd;type:varchar(78);not null" json:"bidPriceUSD"` // 美元价格
	TxHash      string    `gorm:"column:tx_hash;type:varchar(66);uniqueIndex;not null" json:"txHash"`
	BlockNumber uint64    `gorm:"column:block_number;index" json:"blockNumber"`
	CreatedAt   time.Time `gorm:"column:created_at;autoCreateTime" json:"createdAt"`
}

func (Bid) TableName() string {
	return "bids"
}
