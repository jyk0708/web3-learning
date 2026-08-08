package repository

import (
	"context"

	"gorm.io/gorm"

	"nft_auction_api/internal/model"
)

type BidRepository struct {
	db *gorm.DB
}

func NewBidRepository(db *gorm.DB) *BidRepository {
	return &BidRepository{db: db}
}

func (r *BidRepository) Create(ctx context.Context, bid *model.Bid) error {
	return r.db.WithContext(ctx).Create(bid).Error
}

func (r *BidRepository) ListByAuctionID(ctx context.Context, auctionID string) ([]*model.Bid, error) {
	var bids []*model.Bid
	if err := r.db.WithContext(ctx).
		Where("auction_id = ?", auctionID).
		Order("created_at desc").
		Find(&bids).Error; err != nil {
		return nil, err
	}
	return bids, nil
}
