package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"
)

// EthEventListenerConfig 事件监听器配置
type EthEventListenerConfig struct {
	// RPC 节点 URL 列表（支持多个节点容灾）
	RPCURLs []string
	// 合约地址
	ContractAddr string
	// 合约 ABI JSON
	ContractAPI string
	// 重连间隔（可选，默认 10 秒）
	ReconnectInterval time.Duration
}

// EthEventListener 启动以太坊事件监听器
//
//	Returns:
//	  - chan LogEvent: 事件通道
//	  - func(): 清理函数，调用后停止监听并释放资源
//	  - error: 初始化错误
//
//	Usage:
//	  eventCh, cleanup, err := EthEventListener(&EthEventListenerConfig{
//	      RPCURLs:      []string{"wss://..."},
//	      ContractAddr: "0x...",
//	      ContractAPI:  `[...]`,
//	  })
//	  defer cleanup()
//	  for event := range eventCh {
//	      fmt.Println(event.name)
//	  }
func EthEventListener(cfg *EthEventListenerConfig) (chan *LogEvent, func(), error) {
	// 参数校验
	if cfg == nil {
		return nil, nil, fmt.Errorf("config cannot be nil")
	}
	if len(cfg.RPCURLs) == 0 {
		return nil, nil, fmt.Errorf("at least one RPC URL is required")
	}
	if cfg.ContractAddr == "" {
		return nil, nil, fmt.Errorf("contract address is required")
	}
	if cfg.ContractAPI == "" {
		return nil, nil, fmt.Errorf("contract ABI is required")
	}

	// 创建上下文
	ctx, cancel := context.WithCancel(context.Background())

	// 创建连接池
	clientPool, err := NewEthClientPool(ctx, cfg.RPCURLs)
	if err != nil {
		cancel()
		return nil, nil, fmt.Errorf("failed to create client pool: %w", err)
	}

	// 自定义重连间隔
	if cfg.ReconnectInterval > 0 {
		clientPool.reconnectInterval = cfg.ReconnectInterval
	}

	// 启动重连机制
	clientPool.StartReconnect(ctx)

	log.Printf("EthEventListener started with %d RPC nodes", len(cfg.RPCURLs))

	// 订阅日志事件
	eventCh := clientPool.SubscribeLogs(ctx, cfg.ContractAddr, cfg.ContractAPI)

	// 清理函数：停止所有资源
	cleanup := func() {
		log.Printf("EthEventListener shutting down...")
		cancel()           // 取消上下文（停止订阅和重连）
		clientPool.Close() // 关闭连接池
		log.Printf("EthEventListener stopped")
	}

	return eventCh, cleanup, nil
}

// EthEventListenerFromEnv 从环境变量配置创建事件监听器
//
//	Env Vars:
//	  - ETH_RPC_URL: RPC 节点 URL（支持多个，逗号分隔）
//	  - CONTRACT_ADDR: 合约地址
//	  - CONTRACT_ABI: 合约 ABI JSON
func EthEventListenerFromEnv() (chan *LogEvent, func(), error) {
	rpcURL := os.Getenv("ETH_RPC_URL")
	if rpcURL == "" {
		return nil, nil, fmt.Errorf("ETH_RPC_URL must be set")
	}

	// 支持逗号分隔的多个 URL
	urls := splitAndTrim(rpcURL, ",")

	contractAddr := os.Getenv("CONTRACT_ADDR")
	if contractAddr == "" {
		return nil, nil, fmt.Errorf("CONTRACT_ADDR must be set")
	}

	contractABI := os.Getenv("CONTRACT_ABI")
	if contractABI == "" {
		return nil, nil, fmt.Errorf("CONTRACT_ABI must be set")
	}

	return EthEventListener(&EthEventListenerConfig{
		RPCURLs:      urls,
		ContractAddr: contractAddr,
		ContractAPI:  contractABI,
	})
}

// splitAndTrim 分割字符串并去除空格
func splitAndTrim(s string, sep string) []string {
	var result []string
	for _, item := range splitString(s, sep) {
		item = trimSpace(item)
		if item != "" {
			result = append(result, item)
		}
	}
	return result
}

// splitString 简单的字符串分割
func splitString(s string, sep string) []string {
	var result []string
	current := ""
	for _, c := range s {
		if string(c) == sep {
			result = append(result, current)
			current = ""
		} else {
			current += string(c)
		}
	}
	result = append(result, current)
	return result
}

// trimSpace 去除字符串首尾空格
func trimSpace(s string) string {
	start := 0
	end := len(s)
	for start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n') {
		end--
	}
	return s[start:end]
}
