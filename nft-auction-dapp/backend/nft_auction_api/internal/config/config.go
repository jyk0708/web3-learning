// Code scaffolded by goctl. Safe to edit.
// goctl 1.10.2

package config

import "github.com/zeromicro/go-zero/rest"

type Config struct {
	rest.RestConf
	Postgres PgConfig
	Chain    ChainConfig
}

/**
 * @Description: postgres数据库配置
 */
type PgConfig struct {
	// Dsn 数据库连接字符串
	Dsn string
	// MaxOpenConns 最大打开连接数
	MaxOpenConns int
	// MaxIdleConns 最大空闲连接数
	MaxIdleConns int
}

/**
 * @Description: 链配置
 */
type ChainConfig struct {
	// 链节点RPC地址（兼容单URL配置）
	RpcUrl string `json:",optional"`
	// 链节点RPC地址列表，支持主备自动切换
	RpcUrls []string `json:",optional"`
	// 合约地址
	AuctionContractAddr string
	// Mock NFT(ERC721)合约地址，仅用于测试环境 mock 数据接口
	MockNftContractAddr string `json:",optional"`
	// 私钥
	PrivateKey string
	// 合约ABI文件路径
	AbiFile string
	// 最大重试次数（读操作）
	MaxRetries int `json:",default=3"`
	// 重试初始间隔（毫秒）
	RetryIntervalMs int `json:",default=500"`
	// RPC请求超时（秒）
	TimeoutSec int `json:",default=30"`
	// 健康检查间隔（秒），0表示不开启
	HealthCheckIntervalSec int `json:",default=10"`
}
