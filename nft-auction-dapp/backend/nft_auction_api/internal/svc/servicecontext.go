// Code scaffolded by goctl. Safe to edit.
// goctl 1.10.2

package svc

import (
	"context"
	"fmt"
	"nft_auction_api/internal/chain"
	"nft_auction_api/internal/config"
	"nft_auction_api/internal/repository"
	"os"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind/v2"
	"github.com/ethereum/go-ethereum/common"
	ethtypes "github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/zeromicro/go-zero/core/logx"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

/**
 * @Description: 服务上下文
 */
type ServiceContext struct {
	Config         config.Config
	DB             *gorm.DB
	ContractClient *ContractClient
}

/**
 * @Description: 合约客户端
 */
type ContractClient struct {
	// RPC节点URL列表
	RpcUrls []string
	// 弹性RPC后端（重试+重连+健康检查）
	Backend *chain.ResilientBackend
	// 合约地址
	ContractAddr common.Address
	// 解析后的ABI
	ParsedABI abi.ABI
	// 通用合约对象
	Contract *bind.BoundContract
	// 转账交易授权
	Auth *bind.TransactOpts
}

/**
 * @Description: 创建服务上下文
 * @param c: 配置
 * @return: *ServiceContext
 */
func NewServiceContext(c config.Config) *ServiceContext {
	db := mustNewPgDB(c.Postgres)

	// 自动迁移数据库表结构
	if err := repository.InitDB(db); err != nil {
		logx.Severe(fmt.Sprintf("Failed to init database tables: %v", err))
		panic("database initialization failed, check permissions or run cmd/fix-db")
	}
	logx.Info("Database tables initialized successfully")

	contractClient := mustNewChainClient(c.Chain)
	return &ServiceContext{
		Config:         c,
		DB:             db,
		ContractClient: contractClient,
	}
}

/**
 * @Description: 创建postgres数据库连接
 * @param c: postgres配置
 * @return: *gorm.DB
 */
func mustNewPgDB(c config.PgConfig) *gorm.DB {
	db, err := gorm.Open(postgres.Open(c.Dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info), //打印sql日志
	})
	if err != nil {
		panic("postgres connect failed:" + err.Error())
	}
	sqlDB, err := db.DB()
	if err != nil {
		panic("get sql db error:" + err.Error())
	}
	// 设置连接池
	sqlDB.SetMaxOpenConns(c.MaxOpenConns)
	sqlDB.SetMaxIdleConns(c.MaxIdleConns)
	return db
}

/**
 * @Description: 创建链客户端
 * @param chainCfg: 链配置
 * @return: *ContractClient
 */
func mustNewChainClient(chainCfg config.ChainConfig) *ContractClient {
	// 兼容单URL配置（转换为列表）
	rpcUrls := chainCfg.RpcUrls
	if len(rpcUrls) == 0 && chainCfg.RpcUrl != "" {
		rpcUrls = []string{chainCfg.RpcUrl}
	}

	backend, err := chain.NewResilientBackend(chain.Config{
		RpcUrls:             rpcUrls,
		MaxRetries:          chainCfg.MaxRetries,
		RetryInterval:       time.Duration(chainCfg.RetryIntervalMs) * time.Millisecond,
		Timeout:             time.Duration(chainCfg.TimeoutSec) * time.Second,
		HealthCheckInterval: time.Duration(chainCfg.HealthCheckIntervalSec) * time.Second,
	})
	if err != nil {
		panic("chain.NewResilientBackend failed:" + err.Error())
	}

	contractAddr := common.HexToAddress(chainCfg.AuctionContractAddr)

	abiJSON, err := os.ReadFile(chainCfg.AbiFile)
	if err != nil {
		panic("os.ReadFile failed:" + err.Error())
	}

	parsedABI, err := abi.JSON(strings.NewReader(string(abiJSON)))
	if err != nil {
		panic("abi.JSON failed:" + err.Error())
	}

	privateKeyHex := strings.TrimPrefix(chainCfg.PrivateKey, "0x")
	privateKeyHex = strings.TrimPrefix(privateKeyHex, "0X")
	logx.Infof("PrivateKey raw=%s, stripped=%s, len=%d", chainCfg.PrivateKey, privateKeyHex, len(privateKeyHex))
	privateKey, err := crypto.HexToECDSA(privateKeyHex)
	if err != nil {
		panic("crypto.HexToECDSA failed:" + err.Error())
	}

	auth := bind.NewKeyedTransactor(privateKey, backend.ChainID())
	contract := backend.NewBoundContract(contractAddr, parsedABI)

	return &ContractClient{
		RpcUrls:      rpcUrls,
		Backend:      backend,
		ContractAddr: contractAddr,
		ParsedABI:    parsedABI,
		Contract:     contract,
		Auth:         auth,
	}
}

/**
 * @Description: 基于全局 Auth 模板克隆一个绑定了请求 ctx 的新 TransactOpts。
 *   Auth 作为模板保存不变的配置（From/Signer/chainID 等），
 *   每次写交易调用此方法获取独立实例，避免并发覆盖全局 Auth.Context。
 * @param ctx: 请求上下文（用于超时/取消/链路追踪）
 * @return: 新的 TransactOpts，已绑定 ctx
 */
func (c *ContractClient) NewAuth(ctx context.Context) *bind.TransactOpts {
	tmpl := c.Auth
	return &bind.TransactOpts{
		From:       tmpl.From,
		Signer:     tmpl.Signer,
		Value:      tmpl.Value,
		GasPrice:   tmpl.GasPrice,
		GasFeeCap:  tmpl.GasFeeCap,
		GasTipCap:  tmpl.GasTipCap,
		GasLimit:   tmpl.GasLimit,
		AccessList: tmpl.AccessList,
		Context:    ctx,
	}
}

/**
 * @Description: 封装写交易(nonpayable)的标准流程：
 *   克隆 Auth（绑定请求 ctx）→ Transact 发交易 → WaitMined 等打包 → 检查回执状态（含 revert 原因）
 *   统一所有 nonpayable 方法的样板代码。支持任意 BoundContract（拍卖合约、MockERC721 等）。
 * @param ctx:        请求上下文（超时/取消/链路追踪）
 * @param bound:      目标合约的 BoundContract
 * @param to:         目标合约地址（用于 checkReceipt 重放 eth_call 拿 revert 原因）
 * @param actionName: 方法名（错误信息中展示，便于定位）
 * @param methodName: 合约 ABI 方法名
 * @param args:       方法参数（顺序、类型与 ABI 一致）
 * @return: tx, receipt, error。成功时 tx/receipt 非 nil；失败时错误带具体 revert 原因
 */
func (c *ContractClient) TransactAndWaitMined(
	ctx context.Context,
	bound *bind.BoundContract,
	to common.Address,
	actionName string,
	methodName string,
	args ...interface{},
) (*ethtypes.Transaction, *ethtypes.Receipt, error) {
	// 每次写交易克隆独立的 Auth（绑定请求 ctx），避免并发覆盖全局 Auth.Context
	auth := c.NewAuth(ctx)

	tx, err := bound.Transact(auth, methodName, args...)
	if err != nil {
		return nil, nil, fmt.Errorf("call %s failed: %w", actionName, err)
	}

	receipt, err := bind.WaitMined(ctx, c.Backend, tx.Hash())
	if err != nil {
		return tx, nil, fmt.Errorf("wait %s mined failed: %w", actionName, err)
	}

	if err := c.checkReceipt(ctx, actionName, tx.Hash(), receipt, auth.From, to, tx.Data()); err != nil {
		return tx, receipt, err
	}
	return tx, receipt, nil
}

/**
 * @Description: 检查交易回执状态，revert 时通过 eth_call 重放拿具体 revert 原因。
 *   比单纯判断 receipt.Status==0 信息多得多（是 onlyOwner？还是参数非法？一目了然）。
 * @param ctx:        请求上下文
 * @param actionName: 方法名（错误信息中展示）
 * @param txHash:     交易哈希
 * @param receipt:    交易回执
 * @param from:       交易发送方（auth.From）
 * @param to:         目标合约地址
 * @param txData:     交易 input data（用于 eth_call 重放）
 */
func (c *ContractClient) checkReceipt(
	ctx context.Context,
	actionName string,
	txHash common.Hash,
	receipt *ethtypes.Receipt,
	from common.Address,
	to common.Address,
	txData []byte,
) error {
	if receipt.Status == ethtypes.ReceiptStatusSuccessful {
		return nil
	}

	// 在回执所在 block 上用相同参数重放 eth_call，节点会返回带 revert reason 的错误
	callMsg := ethereum.CallMsg{
		From:     from,
		To:       &to,
		Gas:      receipt.GasUsed * 120 / 100, // 留 20% 余量，保证 eth_call 不缺 gas
		Data:     txData,
		GasPrice: receipt.EffectiveGasPrice,
	}
	var reason string
	if _, err := c.Backend.CallContract(ctx, callMsg, receipt.BlockNumber); err != nil {
		reason = extractRevertReason(err)
	}
	if reason == "" {
		reason = "unknown revert reason"
	}
	return fmt.Errorf("%s transaction reverted, tx=%s reason=%q",
		actionName, txHash.Hex(), reason)
}

// extractRevertReason 从 CallContract 返回的错误里提取可读的 revert 字符串。
// Geth/Anvil 返回的错误通常是 json-rpc 的 data 字段，形如：
//
//	"execution reverted: Ownable: caller is not the owner"
//	或带 abi 编码前缀 "0x08c379a0..."，需去掉前缀 + 解码。
func extractRevertReason(err error) string {
	if err == nil {
		return ""
	}
	msg := err.Error()

	// 1. 节点已经解析好："execution reverted: XXX" 直接取后面部分
	if idx := strings.Index(msg, "execution reverted: "); idx >= 0 {
		return strings.TrimSpace(msg[idx+len("execution reverted: "):])
	}
	if idx := strings.Index(msg, "reverted: "); idx >= 0 {
		return strings.TrimSpace(msg[idx+len("reverted: "):])
	}

	// 2. 包含 revert 字样的 JSON rpc 错误片段，尽量剥出简短字符串
	if strings.Contains(msg, "revert") || strings.Contains(msg, "Revert") {
		trimmed := msg
		if len(trimmed) > 240 {
			trimmed = trimmed[:240] + "..."
		}
		return trimmed
	}

	return msg
}
