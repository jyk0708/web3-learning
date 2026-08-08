package repository

import (
	"context"
	"fmt"

	"gorm.io/gorm"

	"nft_auction_api/internal/model"
)

type EventLogRepository struct {
	db *gorm.DB
}

func NewEventLogRepository(db *gorm.DB) *EventLogRepository {
	return &EventLogRepository{db: db}
}

func (r *EventLogRepository) Create(ctx context.Context, log *model.EventLog) error {
	return r.db.WithContext(ctx).Create(log).Error
}

// InitDB 自动迁移所有表结构
func InitDB(db *gorm.DB) error {
	// 检查表是否已存在
	var tableCount int64
	db.Raw("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('auctions', 'bids', 'event_logs')").Scan(&tableCount)

	if tableCount == 3 {
		return nil // 所有表都存在，跳过迁移
	}

	// 运行迁移
	if err := db.AutoMigrate(
		&model.Auction{},
		&model.Bid{},
		&model.EventLog{},
	); err != nil {
		return fmt.Errorf("auto migrate failed (tableCount=%d): %w. If this is a permission issue, run cmd/fix-db to grant permissions first", tableCount, err)
	}

	return nil
}
