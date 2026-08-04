package main

import (
	"context"
	"fmt"
	"log"
	"math/big"
	"strings"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

/**
 * @brief 节点状态
 */
type NodeStatus struct {
	// 节点URL
	URL string
	// ETH客户端
	Client *ethclient.Client
	// 是否存活
	Alive bool
}

/**
 * @brief ETH客户端池
 */
type EthClientPool struct {
	// 互斥锁
	mu sync.RWMutex
	// 节点列表
	nodes []*NodeStatus
	// 主节点索引
	primaryIdx int
	// 读取索引
	readIdx int
	// 重连间隔
	reconnectInterval time.Duration
	// 停止重连的通道
	stopReconnect chan struct{}
	// 确保只启动一次重连
	once sync.Once
}

type LogEventType int

const (
	LogEventTypeSuccess LogEventType = iota
	LogEventTypeFailed
	LogEventTypeClose
)

/**
 * @brief 日志事件
 */
type LogEvent struct {
	eventType   LogEventType
	name        string
	indexed0    interface{}
	indexed1    interface{}
	indexed2    interface{}
	data        []interface{}
	blockNumber uint64
	txHash      common.Hash
	logIndex    uint64
	topicCount  int
}

/**
 * @brief 创建ETH客户端池
 * @param ctx 上下文
 * @param urls 节点URL列表
 * @return *EthClientPool
 */
func NewEthClientPool(ctx context.Context, urls []string) (*EthClientPool, error) {
	if len(urls) == 0 {
		return nil, fmt.Errorf("urls must be set")
	}
	nodes := make([]*NodeStatus, 0, len(urls))
	for _, raw := range urls {
		url := strings.TrimSpace(raw)
		if url == "" {
			continue
		}
		client, err := ethclient.DialContext(ctx, url)
		if err != nil {
			log.Printf("failed to connect: %v", err)
			nodes = append(nodes, &NodeStatus{
				URL:    url,
				Client: nil,
				Alive:  false,
			})
			continue
		}
		nodes = append(nodes, &NodeStatus{
			URL:    url,
			Client: client,
			Alive:  true,
		})
	}

	if len(nodes) == 0 {
		return nil, fmt.Errorf("no alive node")
	}

	return &EthClientPool{
		nodes:             nodes,
		primaryIdx:        0,
		readIdx:           0,
		reconnectInterval: 10 * time.Second,
		stopReconnect:     make(chan struct{}),
	}, nil
}

/**
 * @brief 获取读取节点
 * @note 读取节点会按顺序循环读取，直到找到一个存活的节点
 * @return *NodeStatus
 */
func (p *EthClientPool) GetReadNode() *NodeStatus {
	p.mu.RLock()
	defer p.mu.RUnlock()
	nodeCount := len(p.nodes)
	if nodeCount == 0 {
		return nil
	}
	for i := 0; i < nodeCount; i++ {
		idx := (p.readIdx + i) % nodeCount
		node := p.nodes[idx]
		if node.Alive && node.Client != nil {
			// 下次从找到的节点的下一个开始检查
			p.readIdx = (idx + 1) % nodeCount
			return node
		}
	}
	return nil
}

/**
 * @brief 获取主节点
 * @note 主节点会按顺序循环读取，直到找到一个存活的节点
 * @return *NodeStatus
 */
func (p *EthClientPool) GetPrimaryNode() *NodeStatus {
	p.mu.RLock()
	defer p.mu.RUnlock()
	nodeCount := len(p.nodes)
	if nodeCount == 0 {
		return nil
	}

	// 先检查当前主节点
	if p.primaryIdx < nodeCount {
		node := p.nodes[p.primaryIdx]
		if node.Alive && node.Client != nil {
			return node
		}
	}

	// 主节点不可用，找到下一个可用节点并更新索引
	for i := 0; i < nodeCount; i++ {
		idx := (p.primaryIdx + i) % nodeCount
		node := p.nodes[idx]
		if node.Alive && node.Client != nil {
			p.primaryIdx = idx
			return node
		}
	}
	return nil
}

/**
 * @brief 标记节点为不可用
 * @param url 节点URL
 * @param cause 不可用原因
 */
func (p *EthClientPool) markNodeUnavailable(url string, cause error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, node := range p.nodes {
		if node.URL == url {
			if node.Alive {
				log.Printf("node %s is unavailable, cause: %v", url, cause)
			}
			node.Alive = false
			if node.Client != nil {
				// 尝试关闭客户端，忽略错误
				node.Client.Close()
				node.Client = nil
			}
			break
		}
	}
}

/**
 * @brief 标记节点为可用
 * @param url 节点URL
 * @param client ETH客户端
 */
func (p *EthClientPool) markNodeAvailable(url string, client *ethclient.Client) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, node := range p.nodes {
		if node.URL == url {
			if !node.Alive {
				log.Printf("node %s is available, cause: %v", url, nil)
			}
			node.Alive = true
			node.Client = client
			break
		}
	}
}

/**
 * @brief 启动重连机制
 * @param ctx 上下文
 */
func (p *EthClientPool) StartReconnect(ctx context.Context) {
	p.once.Do(func() {
		go p.reconnectLoop(ctx)
		log.Printf("reconnect mechanism started, interval: %v", p.reconnectInterval)
	})
}

/**
 * @brief 停止重连机制
 */
func (p *EthClientPool) StopReconnect() {
	select {
	case <-p.stopReconnect:
		log.Printf("stop reconnect mechanism")
		return
	default:
		close(p.stopReconnect)
		log.Printf("reconnect mechanism stopped")
	}
}

/**
 * @brief 重连节点
 * @param ctx 上下文
 */
func (p *EthClientPool) reconnectLoop(ctx context.Context) {
	ticker := time.NewTicker(p.reconnectInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			log.Printf("context cancelled, stop reconnect loop")
			return
		case <-ticker.C:
			p.tryReconnectNodes(ctx)
		case <-p.stopReconnect:
			log.Printf("stop reconnect mechanism")
			return
		}
	}
}

/**
 * @brief 尝试重连节点
 * @param ctx 上下文
 */
func (p *EthClientPool) tryReconnectNodes(ctx context.Context) {
	p.mu.RLock()
	var deadNodes []string
	for _, node := range p.nodes {
		if !node.Alive {
			deadNodes = append(deadNodes, node.URL)
		}
	}
	p.mu.RUnlock()

	for _, url := range deadNodes {
		if ctx.Err() != nil {
			log.Printf("context cancelled, stop reconnect node %s", url)
			return
		}
		log.Printf("attempting to reconnect node: %s", url)
		client, err := ethclient.DialContext(ctx, url)
		if err != nil {
			log.Printf("failed to reconnect node %s: %v", url, err)
			continue
		}
		p.markNodeAvailable(url, client)
	}
}

/**
 * @brief 订阅日志事件
 * @param ctx 上下文
 * @param contractAddress 合约地址
 * @param contractApiJson 合约ABI JSON字符串
 * @return chan *LogEvent
 */
func (p *EthClientPool) SubscribeLogs(ctx context.Context, contractAddress string, contractApiJson string) chan *LogEvent {
	eventCh := make(chan *LogEvent, 100) // 增加缓冲区，防止阻塞

	parsedABI, err := abi.JSON(strings.NewReader(contractApiJson))
	if err != nil {
		log.Printf("failed to parse abi: %v", err)
		eventCh <- &LogEvent{eventType: LogEventTypeClose}
		return nil
	}

	go func() {
		defer close(eventCh)

		for {
			select {
			case <-ctx.Done():
				log.Printf("context cancelled, stop subscribe logs")
				eventCh <- &LogEvent{eventType: LogEventTypeClose}
				return
			default:
			}

			// 获取一个可用的节点（带重试）
			node := p.GetReadNode()
			if node == nil || node.Client == nil {
				log.Printf("no available node, waiting...")
				time.Sleep(2 * time.Second)
				continue
			}

			log.Printf("subscribing logs on node %s", node.URL)

			logsCh := make(chan types.Log)
			subscription, err := node.Client.SubscribeFilterLogs(ctx, ethereum.FilterQuery{
				Addresses: []common.Address{common.HexToAddress(contractAddress)},
			}, (chan<- types.Log)(logsCh))
			if err != nil {
				log.Printf("failed to subscribe logs on %s: %v", node.URL, err)
				p.markNodeUnavailable(node.URL, err)
				time.Sleep(2 * time.Second)
				continue
			}

			// 订阅成功，处理事件
			for {
				select {
				case <-ctx.Done():
					subscription.Unsubscribe()
					log.Printf("context cancelled, stop subscribe logs")
					eventCh <- &LogEvent{eventType: LogEventTypeClose}
					return

				case vlog, ok := <-logsCh:
					if !ok {
						// logsCh 被关闭，需要重新订阅
						log.Printf("logs channel closed, resubscribing...")
						goto NEXT_NODE
					}
					event := p.parseLogEvent(vlog, &parsedABI)
					if event != nil {
						eventCh <- event
					}

				case subErr := <-subscription.Err():
					log.Printf("subscription error on %s: %v", node.URL, subErr)
					p.markNodeUnavailable(node.URL, subErr)
					goto NEXT_NODE
				}
			}

		NEXT_NODE:
			subscription.Unsubscribe()
			log.Printf("switching to next node...")
			time.Sleep(1 * time.Second)
		}
	}()

	return eventCh
}

func (p *EthClientPool) parseLogEvent(vlog types.Log, parsedABI *abi.ABI) *LogEvent {
	if len(vlog.Topics) == 0 {
		return nil
	}

	logEvent := &LogEvent{
		eventType:   LogEventTypeSuccess,
		blockNumber: vlog.BlockNumber,
		txHash:      vlog.TxHash,
		logIndex:    uint64(vlog.Index),
		topicCount:  len(vlog.Topics),
	}

	eventTopic := vlog.Topics[0]
	var eventName string
	var eventSig abi.Event

	// 遍历abi事件，找到匹配的事件
	for name, event := range parsedABI.Events {
		eventSigHash := crypto.Keccak256Hash([]byte(event.Sig))
		if eventSigHash == eventTopic {
			eventName = name
			eventSig = event
			break
		}
	}

	if eventName == "" {
		logEvent.eventType = LogEventTypeFailed
		return logEvent
	}

	logEvent.name = eventName

	// 解析 indexed 参数 (从 Topics[1] 开始，最多3个 indexed)
	indexedIdx := 0
	for _, input := range eventSig.Inputs {
		if !input.Indexed {
			continue
		}

		topicIndex := 1 + indexedIdx
		if topicIndex >= len(vlog.Topics) {
			break
		}

		topic := vlog.Topics[topicIndex]
		var value interface{}

		switch input.Type.T {
		case abi.AddressTy:
			value = common.BytesToAddress(topic.Bytes())
		case abi.IntTy, abi.UintTy:
			value = new(big.Int).SetBytes(topic.Bytes())
		case abi.BoolTy:
			value = topic[31] != 0
		case abi.BytesTy, abi.FixedBytesTy:
			value = topic.Bytes()
		default:
			value = topic
		}

		switch indexedIdx {
		case 0:
			logEvent.indexed0 = value
		case 1:
			logEvent.indexed1 = value
		case 2:
			logEvent.indexed2 = value
		}
		indexedIdx++
	}

	// 解析非 indexed 参数 (从 Data 字段)
	if len(vlog.Data) > 0 {
		dataValues, err := parsedABI.Unpack(eventName, vlog.Data)
		if err != nil {
			log.Printf("failed to unpack event data: %v", err)
		} else {
			// 只保留非 indexed 的参数
			nonIndexedIdx := 0
			for _, input := range eventSig.Inputs {
				if !input.Indexed {
					if nonIndexedIdx < len(dataValues) {
						logEvent.data = append(logEvent.data, dataValues[nonIndexedIdx])
						nonIndexedIdx++
					}
				}
			}
		}
	}

	return logEvent
}

/**
 * @brief 获取可用节点数量
 * @return int 可用节点数量
 */
func (p *EthClientPool) GetAliveNodeCount() int {
	p.mu.RLock()
	defer p.mu.RUnlock()
	count := 0
	for _, node := range p.nodes {
		if node.Alive && node.Client != nil {
			count++
		}
	}
	return count
}

/**
 * @brief 关闭连接池
 */
func (p *EthClientPool) Close() {
	p.StopReconnect()
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, node := range p.nodes {
		if node.Client != nil {
			node.Client.Close()
			node.Client = nil
			node.Alive = false
		}
	}
	log.Printf("eth client pool closed")
}

/**
 * @brief 健康检查
 * @return bool 是否健康
 */
func (p *EthClientPool) HealthCheck() bool {
	node := p.GetPrimaryNode()
	if node == nil || node.Client == nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, err := node.Client.BlockNumber(ctx)
	return err == nil
}
