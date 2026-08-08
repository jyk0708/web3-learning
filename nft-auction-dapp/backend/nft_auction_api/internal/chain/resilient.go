package chain

import (
	"context"
	"errors"
	"fmt"
	"math/big"
	"net"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind/v2"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/zeromicro/go-zero/core/logx"
)

// Config holds the configuration for ResilientBackend.
type Config struct {
	RpcUrls             []string
	MaxRetries          int
	RetryInterval       time.Duration
	Timeout             time.Duration
	HealthCheckInterval time.Duration
}

// ResilientBackend wraps ethclient with retry, reconnection, and health-check capabilities.
// It implements bind.ContractCaller, bind.ContractTransactor, bind.ContractFilterer,
// bind.PendingContractCaller, and bind.BlockHashContractCaller interfaces.
type ResilientBackend struct {
	cfg     Config
	clients []*ethclient.Client
	current int
	mu      sync.RWMutex
	chainID *big.Int

	stopCh  chan struct{}
	stopMu  sync.Mutex
	stopped bool
}

// NewResilientBackend creates and dials a new ResilientBackend.
func NewResilientBackend(cfg Config) (*ResilientBackend, error) {
	if len(cfg.RpcUrls) == 0 {
		return nil, errors.New("at least one RPC URL is required")
	}
	if cfg.MaxRetries <= 0 {
		cfg.MaxRetries = 3
	}
	if cfg.RetryInterval <= 0 {
		cfg.RetryInterval = 500 * time.Millisecond
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 30 * time.Second
	}

	rb := &ResilientBackend{
		cfg:     cfg,
		clients: make([]*ethclient.Client, len(cfg.RpcUrls)),
		stopCh:  make(chan struct{}),
	}

	if err := rb.Dial(context.Background()); err != nil {
		return nil, err
	}

	if cfg.HealthCheckInterval > 0 {
		go rb.healthCheckLoop()
	}

	return rb, nil
}

// Dial connects to the RPC URL at the current index.
func (rb *ResilientBackend) Dial(ctx context.Context) error {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	url := rb.cfg.RpcUrls[rb.current]
	client, err := ethclient.DialContext(ctx, url)
	if err != nil {
		return fmt.Errorf("dial RPC %s failed: %w", url, err)
	}

	rb.clients[rb.current] = client

	if rb.chainID == nil {
		chainID, err := client.ChainID(ctx)
		if err != nil {
			return fmt.Errorf("get chain ID from %s failed: %w", url, err)
		}
		rb.chainID = chainID
	}

	logx.Infof("Connected to RPC node: %s", url)
	return nil
}

// Reconnect closes the current connection and re-dials, optionally switching to the next RPC URL.
func (rb *ResilientBackend) Reconnect(ctx context.Context) error {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	oldClient := rb.clients[rb.current]
	if oldClient != nil {
		oldClient.Close()
	}

	rb.current = (rb.current + 1) % len(rb.cfg.RpcUrls)
	url := rb.cfg.RpcUrls[rb.current]

	client, err := ethclient.DialContext(ctx, url)
	if err != nil {
		return fmt.Errorf("reconnect to RPC %s failed: %w", url, err)
	}

	rb.clients[rb.current] = client
	logx.Infof("Reconnected to RPC node: %s", url)
	return nil
}

// GetClient returns the current ethclient.Client.
func (rb *ResilientBackend) GetClient() *ethclient.Client {
	rb.mu.RLock()
	defer rb.mu.RUnlock()
	return rb.clients[rb.current]
}

// ChainID returns the chain ID.
func (rb *ResilientBackend) ChainID() *big.Int {
	rb.mu.RLock()
	defer rb.mu.RUnlock()
	return rb.chainID
}

// Stop terminates the health check goroutine and closes all connections.
func (rb *ResilientBackend) Stop() {
	rb.stopMu.Lock()
	defer rb.stopMu.Unlock()

	if rb.stopped {
		return
	}
	rb.stopped = true
	close(rb.stopCh)

	rb.mu.Lock()
	defer rb.mu.Unlock()
	for _, c := range rb.clients {
		if c != nil {
			c.Close()
		}
	}
}

// healthCheckLoop periodically pings the RPC node and triggers reconnection on failure.
func (rb *ResilientBackend) healthCheckLoop() {
	ticker := time.NewTicker(rb.cfg.HealthCheckInterval)
	defer ticker.Stop()

	for {
		select {
		case <-rb.stopCh:
			return
		case <-ticker.C:
			rb.doHealthCheck()
		}
	}
}

func (rb *ResilientBackend) doHealthCheck() {
	client := rb.GetClient()
	if client == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), rb.cfg.Timeout)
	defer cancel()

	if _, err := client.BlockNumber(ctx); err != nil {
		logx.Errorf("RPC health check failed: %v, attempting reconnect", err)
		if err := rb.Reconnect(context.Background()); err != nil {
			logx.Errorf("RPC reconnect failed: %v", err)
		}
	}
}

// isRetryableError checks if an error is a network-level error that may succeed on retry.
func isRetryableError(err error) bool {
	if err == nil {
		return false
	}
	var netErr *net.OpError
	if errors.As(err, &netErr) {
		return true
	}
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		return true
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	if errors.Is(err, context.Canceled) {
		return false
	}
	return false
}

// retryWithBackoff executes fn with exponential backoff retry for read operations.
func (rb *ResilientBackend) retryWithBackoff(ctx context.Context, opName string, fn func() error) error {
	var lastErr error
	for attempt := 0; attempt <= rb.cfg.MaxRetries; attempt++ {
		if attempt > 0 {
			backoff := rb.cfg.RetryInterval * time.Duration(1<<uint(attempt-1))
			if backoff > 5*time.Second {
				backoff = 5 * time.Second
			}
			logx.Infof("Retrying %s (attempt %d/%d) after %v", opName, attempt, rb.cfg.MaxRetries, backoff)
			time.Sleep(backoff)

			if err := rb.Reconnect(ctx); err != nil {
				logx.Errorf("Reconnect failed during retry of %s: %v", opName, err)
			}
		}

		if err := fn(); err != nil {
			lastErr = err
			if !isRetryableError(err) {
				return err
			}
			continue
		}
		return nil
	}
	return fmt.Errorf("%s failed after %d retries: %w", opName, rb.cfg.MaxRetries, lastErr)
}

// withTimeout wraps a context with the configured timeout.
func (rb *ResilientBackend) withTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	if ctx == nil {
		ctx = context.Background()
	}
	return context.WithTimeout(ctx, rb.cfg.Timeout)
}

// Ensure ResilientBackend implements all required interfaces.
var (
	_ bind.ContractCaller          = (*ResilientBackend)(nil)
	_ bind.PendingContractCaller   = (*ResilientBackend)(nil)
	_ bind.ContractTransactor      = (*ResilientBackend)(nil)
	_ bind.ContractFilterer        = (*ResilientBackend)(nil)
	_ bind.BlockHashContractCaller = (*ResilientBackend)(nil)
	_ bind.DeployBackend           = (*ResilientBackend)(nil)
)

// ---- bind.ContractCaller ----

func (rb *ResilientBackend) CodeAt(ctx context.Context, contract common.Address, blockNumber *big.Int) ([]byte, error) {
	var result []byte
	err := rb.retryWithBackoff(ctx, "CodeAt", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.CodeAt(ctx2, contract, blockNumber)
		return err
	})
	return result, err
}

func (rb *ResilientBackend) CallContract(ctx context.Context, call ethereum.CallMsg, blockNumber *big.Int) ([]byte, error) {
	var result []byte
	err := rb.retryWithBackoff(ctx, "CallContract", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.CallContract(ctx2, call, blockNumber)
		return err
	})
	return result, err
}

// ---- bind.PendingContractCaller ----

func (rb *ResilientBackend) PendingCodeAt(ctx context.Context, contract common.Address) ([]byte, error) {
	var result []byte
	err := rb.retryWithBackoff(ctx, "PendingCodeAt", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.PendingCodeAt(ctx2, contract)
		return err
	})
	return result, err
}

func (rb *ResilientBackend) PendingCallContract(ctx context.Context, call ethereum.CallMsg) ([]byte, error) {
	var result []byte
	err := rb.retryWithBackoff(ctx, "PendingCallContract", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.PendingCallContract(ctx2, call)
		return err
	})
	return result, err
}

// ---- bind.BlockHashContractCaller ----

func (rb *ResilientBackend) CodeAtHash(ctx context.Context, contract common.Address, blockHash common.Hash) ([]byte, error) {
	var result []byte
	err := rb.retryWithBackoff(ctx, "CodeAtHash", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.CodeAtHash(ctx2, contract, blockHash)
		return err
	})
	return result, err
}

func (rb *ResilientBackend) CallContractAtHash(ctx context.Context, call ethereum.CallMsg, blockHash common.Hash) ([]byte, error) {
	var result []byte
	err := rb.retryWithBackoff(ctx, "CallContractAtHash", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.CallContractAtHash(ctx2, call, blockHash)
		return err
	})
	return result, err
}

// ---- bind.ContractTransactor ----

func (rb *ResilientBackend) HeaderByNumber(ctx context.Context, number *big.Int) (*types.Header, error) {
	var result *types.Header
	err := rb.retryWithBackoff(ctx, "HeaderByNumber", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.HeaderByNumber(ctx2, number)
		return err
	})
	return result, err
}

func (rb *ResilientBackend) PendingNonceAt(ctx context.Context, account common.Address) (uint64, error) {
	var result uint64
	err := rb.retryWithBackoff(ctx, "PendingNonceAt", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.PendingNonceAt(ctx2, account)
		return err
	})
	return result, err
}

func (rb *ResilientBackend) SuggestGasPrice(ctx context.Context) (*big.Int, error) {
	var result *big.Int
	err := rb.retryWithBackoff(ctx, "SuggestGasPrice", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.SuggestGasPrice(ctx2)
		return err
	})
	return result, err
}

func (rb *ResilientBackend) SuggestGasTipCap(ctx context.Context) (*big.Int, error) {
	var result *big.Int
	err := rb.retryWithBackoff(ctx, "SuggestGasTipCap", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.SuggestGasTipCap(ctx2)
		return err
	})
	return result, err
}

func (rb *ResilientBackend) EstimateGas(ctx context.Context, call ethereum.CallMsg) (uint64, error) {
	var result uint64
	err := rb.retryWithBackoff(ctx, "EstimateGas", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.EstimateGas(ctx2, call)
		return err
	})
	return result, err
}

// SendTransaction does NOT retry because it's a write operation that could cause double-spend.
func (rb *ResilientBackend) SendTransaction(ctx context.Context, tx *types.Transaction) error {
	c := rb.GetClient()
	ctx2, cancel := rb.withTimeout(ctx)
	defer cancel()
	return c.SendTransaction(ctx2, tx)
}

func (rb *ResilientBackend) TransactionByHash(ctx context.Context, hash common.Hash) (*types.Transaction, bool, error) {
	var result *types.Transaction
	var isPending bool
	err := rb.retryWithBackoff(ctx, "TransactionByHash", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, isPending, err = c.TransactionByHash(ctx2, hash)
		return err
	})
	return result, isPending, err
}

// TransactionReceipt returns the receipt of a transaction by hash. Implements bind.DeployBackend.
func (rb *ResilientBackend) TransactionReceipt(ctx context.Context, txHash common.Hash) (*types.Receipt, error) {
	var result *types.Receipt
	err := rb.retryWithBackoff(ctx, "TransactionReceipt", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.TransactionReceipt(ctx2, txHash)
		return err
	})
	return result, err
}

// ---- bind.ContractFilterer ----

func (rb *ResilientBackend) FilterLogs(ctx context.Context, query ethereum.FilterQuery) ([]types.Log, error) {
	var result []types.Log
	err := rb.retryWithBackoff(ctx, "FilterLogs", func() error {
		c := rb.GetClient()
		ctx2, cancel := rb.withTimeout(ctx)
		defer cancel()
		var err error
		result, err = c.FilterLogs(ctx2, query)
		return err
	})
	return result, err
}

func (rb *ResilientBackend) SubscribeFilterLogs(ctx context.Context, query ethereum.FilterQuery, ch chan<- types.Log) (ethereum.Subscription, error) {
	c := rb.GetClient()
	ctx2, cancel := rb.withTimeout(ctx)
	defer cancel()
	return c.SubscribeFilterLogs(ctx2, query, ch)
}

// ---- Convenience: create a BoundContract using this backend ----

// NewBoundContract creates a bind.BoundContract with this backend as all three interfaces.
func (rb *ResilientBackend) NewBoundContract(addr common.Address, parsedABI abi.ABI) *bind.BoundContract {
	return bind.NewBoundContract(addr, parsedABI, rb, rb, rb)
}
