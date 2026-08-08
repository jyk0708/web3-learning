package model

import "time"

// EventLog 事件日志模型，用于记录所有接收到的合约事件，便于审计和重放
type EventLog struct {
	ID          uint64    `gorm:"column:id;primaryKey;autoIncrement" json:"id"`
	EventName   string    `gorm:"column:event_name;type:varchar(100);index;not null" json:"eventName"`
	PoolAddress string    `gorm:"column:pool_address;type:varchar(42);index;not null" json:"poolAddress"`
	TxHash      string    `gorm:"column:tx_hash;type:varchar(66);uniqueIndex;not null" json:"txHash"`
	BlockNumber uint64    `gorm:"column:block_number;index;not null" json:"blockNumber"`
	LogData     string    `gorm:"column:log_data;type:text" json:"logData"` // 解析后的事件数据 JSON
	RawData     string    `gorm:"column:raw_data;type:text" json:"rawData"` // 原始 log 数据 JSON
	CreatedAt   time.Time `gorm:"column:created_at;autoCreateTime" json:"createdAt"`
}

func (EventLog) TableName() string {
	return "event_logs"
}
