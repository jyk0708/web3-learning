package repository

import (
	"context"
	"fmt"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"nft_auction_api/internal/model"
)

type AuctionRepository struct {
	db *gorm.DB
}

func NewAuctionRepository(db *gorm.DB) *AuctionRepository {
	return &AuctionRepository{db: db}
}

func (r *AuctionRepository) Create(ctx context.Context, auction *model.Auction) error {
	return r.db.WithContext(ctx).Create(auction).Error
}

func (r *AuctionRepository) GetByAuctionID(ctx context.Context, auctionID string) (*model.Auction, error) {
	var auction model.Auction
	if err := r.db.WithContext(ctx).Where("auction_id = ?", auctionID).First(&auction).Error; err != nil {
		return nil, err
	}
	return &auction, nil
}

func (r *AuctionRepository) UpdateStatus(ctx context.Context, auctionID string, status model.AuctionStatus) error {
	result := r.db.WithContext(ctx).Model(&model.Auction{}).
		Where("auction_id = ?", auctionID).
		Update("status", status)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("auction %s not found", auctionID)
	}
	return nil
}

func (r *AuctionRepository) UpdateHighestBid(ctx context.Context, auctionID, bidAmount, bidPriceUSD, bidder, bidderToken string) error {
	result := r.db.WithContext(ctx).Model(&model.Auction{}).
		Where("auction_id = ?", auctionID).
		Updates(map[string]interface{}{
			"highest_bid_amount":   bidAmount,
			"highest_bid_in_usd":   bidPriceUSD,
			"highest_bidder":       bidder,
			"highest_bidder_token": bidderToken,
		})
	return result.Error
}

func (r *AuctionRepository) UpdateStart(ctx context.Context, auctionID string, startTime, endTime uint64) error {
	result := r.db.WithContext(ctx).Model(&model.Auction{}).
		Where("auction_id = ?", auctionID).
		Updates(map[string]interface{}{
			"start_time": startTime,
			"end_time":   endTime,
		})
	return result.Error
}

func (r *AuctionRepository) List(ctx context.Context, status model.AuctionStatus, page, pageSize int) ([]*model.Auction, int64, error) {
	var auctions []*model.Auction
	var total int64

	query := r.db.WithContext(ctx).Model(&model.Auction{})
	if status != 0 { // 0 表示全部
		query = query.Where("status = ?", status)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	if err := query.Order("created_at desc").Offset(offset).Limit(pageSize).Find(&auctions).Error; err != nil {
		return nil, 0, err
	}
	return auctions, total, nil
}

// UpdateOnConflict 处理事件乱序：如果更新冲突，使用 ON CONFLICT 进行更新
func (r *AuctionRepository) UpdateOnConflict(ctx context.Context, auction *model.Auction) error {
	result := r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "auction_id"}},
		DoUpdates: clause.AssignmentColumns([]string{"status", "highest_bid_amount", "highest_bid_in_usd", "highest_bidder", "highest_bidder_token", "start_time", "end_time", "updated_at"}),
	}).Create(auction)
	return result.Error
}

// Upsert 创建或更新拍卖（基于 auction_id 唯一键冲突处理）
func (r *AuctionRepository) Upsert(ctx context.Context, auction *model.Auction) error {
	result := r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "auction_id"}},
		DoUpdates: clause.AssignmentColumns([]string{"seller", "nft_contract", "token_id", "token_address", "starting_price_usd", "highest_bid_in_usd", "highest_bid_amount", "highest_bidder", "highest_bidder_token", "duration_in_days", "start_time", "end_time", "status", "updated_at"}),
	}).Create(auction)
	return result.Error
}

// UpdateFields 批量更新拍卖字段
func (r *AuctionRepository) UpdateFields(ctx context.Context, auctionID string, updates map[string]any) error {
	result := r.db.WithContext(ctx).Model(&model.Auction{}).
		Where("auction_id = ?", auctionID).
		Updates(updates)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("auction %s not found", auctionID)
	}
	return nil
}
