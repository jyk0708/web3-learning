package event

import (
	"context"
	"crypto/ecdsa"
	"math/big"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind/v2"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/zeromicro/go-zero/core/logx"

	"nft_auction_api/internal/chain"
)

// EventContext 事件处理上下文
type EventContext struct {
	Context   context.Context
	EventName string
	Log       types.Log
	Values    []any
	TxInput   []byte  // 交易 input data，用于需要解析方法参数的场景（如 Bid 的 bidPrice/tokenAddress）
	ParsedABI abi.ABI // 合约 ABI，用于解析 tx input
}

// EventListener 所有合约事件监听器的统一接口
type EventListener interface {
	Name() string
	Handle(ctx *EventContext) error
}

// EventDispatcher 事件分发器
type EventDispatcher struct {
	backend   *chain.ResilientBackend
	contract  *bind.BoundContract
	parsedABI abi.ABI
	addr      common.Address
	privKey   *ecdsa.PrivateKey
	chainID   *big.Int

	eventListeners map[string]map[string]EventListener

	ch      chan types.Log
	sub     ethereum.Subscription
	stopCh  chan struct{}
	stopMu  sync.Mutex
	stopped bool
}

// NewEventDispatcher 创建事件分发器
func NewEventDispatcher(
	backend *chain.ResilientBackend,
	contract *bind.BoundContract,
	parsedABI abi.ABI,
	addr common.Address,
	privKey *ecdsa.PrivateKey,
	chainID *big.Int,
) *EventDispatcher {
	return &EventDispatcher{
		backend:        backend,
		contract:       contract,
		parsedABI:      parsedABI,
		addr:           addr,
		privKey:        privKey,
		chainID:        chainID,
		eventListeners: make(map[string]map[string]EventListener),
		stopCh:         make(chan struct{}),
	}
}

// RegisterListener 注册事件监听器
func (d *EventDispatcher) RegisterListener(eventName string, listener EventListener) {
	if d.eventListeners[eventName] == nil {
		d.eventListeners[eventName] = make(map[string]EventListener)
	}
	d.eventListeners[eventName][listener.Name()] = listener
	logx.Infof("Registered event listener: event=%s, listener=%s", eventName, listener.Name())
}

// Start 启动事件监听
func (d *EventDispatcher) Start() error {
	if len(d.eventListeners) == 0 {
		logx.Info("No event listeners configured, skipping subscription")
		return nil
	}

	ctx := context.Background()

	for eventName, listeners := range d.eventListeners {
		for listenerName := range listeners {
			logx.Infof("Subscribing to event: %s -> %s", eventName, listenerName)
		}
	}

	query := ethereum.FilterQuery{
		Addresses: []common.Address{d.addr},
	}

	d.ch = make(chan types.Log)
	sub, err := d.backend.SubscribeFilterLogs(ctx, query, d.ch)
	if err != nil {
		logx.Errorf("Failed to subscribe to contract events: %v", err)
		return err
	}
	d.sub = sub

	go d.processLogs(ctx)
	logx.Info("Event dispatcher started, waiting for events...")
	return nil
}

// Stop 停止事件监听
func (d *EventDispatcher) Stop() {
	d.stopMu.Lock()
	defer d.stopMu.Unlock()

	if d.stopped {
		return
	}
	d.stopped = true
	if d.sub != nil {
		d.sub.Unsubscribe()
	}
	close(d.stopCh)
	logx.Info("Event dispatcher stopped")
}

// processLogs 处理接收到的事件日志
func (d *EventDispatcher) processLogs(ctx context.Context) {
	for {
		select {
		case <-d.stopCh:
			return
		case err := <-d.sub.Err():
			if err != nil {
				logx.Errorf("Subscription error: %v, attempting to resubscribe...", err)
				d.resubscribe(ctx)
			}
		case vLog := <-d.ch:
			d.handleLog(ctx, vLog)
		}
	}
}

// handleLog 处理单条事件日志
func (d *EventDispatcher) handleLog(ctx context.Context, vLog types.Log) {
	for eventName := range d.eventListeners {
		event, ok := d.parsedABI.Events[eventName]
		if !ok {
			continue
		}

		if len(vLog.Topics) > 0 && vLog.Topics[0] == event.ID {
			// 使用 UnpackLogIntoMap 解析所有参数（indexed + non-indexed）
			valuesMap := make(map[string]any)
			if err := d.contract.UnpackLogIntoMap(valuesMap, eventName, vLog); err != nil {
				logx.Errorf("Failed to unpack log: event=%s, tx=%s, err=%v",
					eventName, vLog.TxHash.Hex(), err)
				continue
			}

			// 按 Inputs 顺序组装 values 切片
			values := make([]any, 0, len(event.Inputs))
			for _, input := range event.Inputs {
				values = append(values, valuesMap[input.Name])
			}

			logx.Infof("Received event: name=%s, tx=%s, block=%d",
				eventName, vLog.TxHash.Hex(), vLog.BlockNumber)

			// 获取交易 input data，供需要解析方法参数的监听器（如 Bid）使用
			var txInput []byte
			if tx, _, err := d.backend.TransactionByHash(ctx, vLog.TxHash); err == nil && tx != nil {
				txInput = tx.Data()
			}

			listeners := d.eventListeners[eventName]
			eventCtx := &EventContext{
				Context:   ctx,
				EventName: eventName,
				Log:       vLog,
				Values:    values,
				TxInput:   txInput,
				ParsedABI: d.parsedABI,
			}

			for name, listener := range listeners {
				if err := listener.Handle(eventCtx); err != nil {
					logx.Errorf("Listener %s failed for event %s: %v", name, eventName, err)
				}
			}
			return
		}
	}

	logx.Debugf("No matching event for tx=%s", vLog.TxHash.Hex())
}

// resubscribe 重新订阅
func (d *EventDispatcher) resubscribe(ctx context.Context) {
	query := ethereum.FilterQuery{
		Addresses: []common.Address{d.addr},
	}

	newSub, err := d.backend.SubscribeFilterLogs(ctx, query, d.ch)
	if err != nil {
		logx.Errorf("Resubscribe failed: %v, retrying in 5s...", err)
		go func() {
			select {
			case <-d.stopCh:
				return
			case <-time.After(5 * time.Second):
				d.resubscribe(ctx)
			}
		}()
		return
	}

	d.sub = newSub
	logx.Info("Resubscribed to contract events successfully")
}
