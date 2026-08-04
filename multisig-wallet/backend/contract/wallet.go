package contract

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"

	"multisig-wallet/back/config"
)

// WalletService 多签钱包服务
type WalletService struct {
	client     *ethclient.Client
	address    common.Address
	privateKey *ecdsa.PrivateKey
	walletABI  abi.ABI
	chainID    *big.Int
	// 多 owner 支持
	ownerKeys map[string]*ecdsa.PrivateKey
	ownerInfo []OwnerInfo
}

// OwnerInfo owner 信息
type OwnerInfo struct {
	Address string `json:"address"`
	Name    string `json:"name"`
}

// NewWalletService 创建钱包服务
func NewWalletService() (*WalletService, error) {
	cfg := config.GetConfig()

	// 连接以太坊客户端
	client, err := ethclient.Dial(cfg.RPCURL)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RPC: %v", err)
	}

	// 解析默认私钥
	privateKey, err := crypto.HexToECDSA(strings.TrimPrefix(cfg.PrivateKey, "0x"))
	if err != nil {
		return nil, fmt.Errorf("failed to parse private key: %v", err)
	}

	// 获取链 ID
	chainID, err := client.ChainID(context.Background())
	if err != nil {
		return nil, fmt.Errorf("failed to get chain ID: %v", err)
	}

	address := common.HexToAddress(cfg.ProxyAddress)

	// 解析 ABI
	walletABI, err := abi.JSON(strings.NewReader(walletABIJSON))
	if err != nil {
		return nil, fmt.Errorf("failed to parse ABI: %v", err)
	}

	// 加载所有 owner keys
	ownerKeys := make(map[string]*ecdsa.PrivateKey)
	ownerInfo := make([]OwnerInfo, 0)

	for _, ok := range cfg.OwnerKeys {
		pk, err := crypto.HexToECDSA(strings.TrimPrefix(ok.PrivateKey, "0x"))
		if err != nil {
			continue
		}
		addr := strings.ToLower(ok.Address)
		ownerKeys[addr] = pk
		ownerInfo = append(ownerInfo, OwnerInfo{
			Address: ok.Address,
			Name:    ok.Name,
		})
	}

	return &WalletService{
		client:     client,
		address:    address,
		privateKey: privateKey,
		walletABI:  walletABI,
		chainID:    chainID,
		ownerKeys:  ownerKeys,
		ownerInfo:  ownerInfo,
	}, nil
}

// GetAvailableOwners 获取可用的 owner 列表（从合约动态获取）
func (w *WalletService) GetAvailableOwners() ([]OwnerInfo, error) {
	// 从合约读取 owner 列表
	owners, err := w.getOwnersFromContract()
	if err != nil {
		return nil, fmt.Errorf("failed to get owners from contract: %v", err)
	}

	// 把配置中的私钥与合约中的 owner 地址进行匹配
	var availableOwners []OwnerInfo
	for _, ownerAddr := range owners {
		addrLower := strings.ToLower(ownerAddr.Hex())
		if pk, ok := w.ownerKeys[addrLower]; ok {
			// 在配置中找到对应的私钥
			_ = pk // 确认有私钥
			// 查找配置中的名称
			name := "Owner"
			for _, okConfig := range config.GetConfig().OwnerKeys {
				if strings.ToLower(okConfig.Address) == addrLower {
					name = okConfig.Name
					break
				}
			}
			availableOwners = append(availableOwners, OwnerInfo{
				Address: ownerAddr.Hex(),
				Name:    name,
			})
		}
		// 注意：如果合约中的 owner 没有对应的私钥配置，则不添加（因为无法操作）
	}

	return availableOwners, nil
}

// getOwnersFromContract 从合约获取 owner 列表
func (w *WalletService) getOwnersFromContract() ([]common.Address, error) {
	// 编码 getOwners() 函数调用
	data, err := w.walletABI.Pack("getOwners")
	if err != nil {
		return nil, fmt.Errorf("failed to pack getOwners: %v", err)
	}

	// 调用合约
	result, err := w.client.CallContract(context.Background(), ethereum.CallMsg{
		To:   &w.address,
		Data: data,
	}, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to call getOwners: %v", err)
	}

	// 解码结果
	owners, err := w.walletABI.Unpack("getOwners", result)
	if err != nil {
		return nil, fmt.Errorf("failed to unpack getOwners: %v", err)
	}

	if len(owners) > 0 {
		if addrs, ok := owners[0].([]common.Address); ok {
			return addrs, nil
		}
	}

	return []common.Address{}, nil
}

// getPrivateKey 根据地址获取私钥
func (w *WalletService) getPrivateKey(ownerAddress string) *ecdsa.PrivateKey {
	if ownerAddress != "" {
		if pk, ok := w.ownerKeys[strings.ToLower(ownerAddress)]; ok {
			return pk
		}
	}
	return w.privateKey
}

// getAuth 获取交易授权
func (w *WalletService) getAuth(ownerAddress string) (*bind.TransactOpts, *ecdsa.PrivateKey, error) {
	privateKey := w.getPrivateKey(ownerAddress)
	fromAddress := crypto.PubkeyToAddress(privateKey.PublicKey)

	nonce, err := w.client.PendingNonceAt(context.Background(), fromAddress)
	if err != nil {
		return nil, nil, err
	}

	gasPrice, err := w.client.SuggestGasPrice(context.Background())
	if err != nil {
		return nil, nil, err
	}

	auth, err := bind.NewKeyedTransactorWithChainID(privateKey, w.chainID)
	if err != nil {
		return nil, nil, err
	}

	auth.Nonce = big.NewInt(int64(nonce))
	auth.GasLimit = 300000 // 300k gas
	auth.GasPrice = gasPrice

	return auth, privateKey, nil
}

// Call 调用只读函数
func (w *WalletService) Call(method string, args ...interface{}) (interface{}, error) {
	input, err := w.walletABI.Pack(method, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to pack input: %v", err)
	}

	result, err := w.client.CallContract(context.Background(), ethereum.CallMsg{
		To:   &w.address,
		Data: input,
	}, nil)
	if err != nil {
		return nil, fmt.Errorf("contract call failed: %v", err)
	}

	output, err := w.walletABI.Unpack(method, result)
	if err != nil {
		return nil, fmt.Errorf("failed to unpack output: %v", err)
	}

	if len(output) == 1 {
		return output[0], nil
	}
	return output, nil
}

// SendTx 发送交易（指定 owner）
func (w *WalletService) SendTx(ownerAddress, method string, args ...interface{}) (*types.Receipt, error) {
	auth, privateKey, err := w.getAuth(ownerAddress)
	if err != nil {
		return nil, fmt.Errorf("failed to get auth: %v", err)
	}

	input, err := w.walletABI.Pack(method, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to pack input: %v", err)
	}

	tx := types.NewTransaction(
		auth.Nonce.Uint64(),
		w.address,
		big.NewInt(0),
		300000,
		auth.GasPrice,
		input,
	)

	signedTx, err := types.SignTx(tx, types.LatestSignerForChainID(w.chainID), privateKey)
	if err != nil {
		return nil, fmt.Errorf("failed to sign tx: %v", err)
	}

	err = w.client.SendTransaction(context.Background(), signedTx)
	if err != nil {
		return nil, fmt.Errorf("failed to send tx: %v", err)
	}

	receipt, err := bind.WaitMined(context.Background(), w.client, signedTx)
	if err != nil {
		return nil, fmt.Errorf("failed to wait for tx: %v", err)
	}

	// 检查交易是否成功执行（revert 时 Status 为 0）
	if receipt.Status == 0 {
		return nil, fmt.Errorf("transaction reverted: execution failed")
	}

	return receipt, nil
}

// ------------------ 所有者管理方法 ------------------

// GetOwners 获取所有所有者
func (w *WalletService) GetOwners() ([]string, error) {
	result, err := w.Call("getOwners")
	if err != nil {
		return nil, err
	}
	if owners, ok := result.([]common.Address); ok {
		strs := make([]string, len(owners))
		for i, o := range owners {
			strs[i] = o.Hex()
		}
		return strs, nil
	}
	return nil, fmt.Errorf("unexpected result type")
}

// GetOwnerCount 获取所有者数量
func (w *WalletService) GetOwnerCount() (uint64, error) {
	result, err := w.Call("getOwnerCount")
	if err != nil {
		return 0, err
	}
	if count, ok := result.(*big.Int); ok {
		return count.Uint64(), nil
	}
	return 0, fmt.Errorf("unexpected result type")
}

// IsOwner 检查是否是所有者
func (w *WalletService) IsOwner(address string) (bool, error) {
	result, err := w.Call("isOwner", common.HexToAddress(address))
	if err != nil {
		return false, err
	}
	if isOwner, ok := result.(bool); ok {
		return isOwner, nil
	}
	return false, fmt.Errorf("unexpected result type")
}

// GetThreshold 获取确认阈值
func (w *WalletService) GetThreshold() (uint64, error) {
	result, err := w.Call("getThreshold")
	if err != nil {
		return 0, err
	}
	if threshold, ok := result.(*big.Int); ok {
		return threshold.Uint64(), nil
	}
	return 0, fmt.Errorf("unexpected result type")
}

// AddOwner 添加所有者
func (w *WalletService) AddOwner(owner, senderAddress string) (string, error) {
	receipt, err := w.SendTx(senderAddress, "addOwner", common.HexToAddress(owner))
	if err != nil {
		return "", err
	}
	return receipt.TxHash.Hex(), nil
}

// RemoveOwner 移除所有者
func (w *WalletService) RemoveOwner(owner, senderAddress string) (string, error) {
	receipt, err := w.SendTx(senderAddress, "removeOwner", common.HexToAddress(owner))
	if err != nil {
		return "", err
	}
	return receipt.TxHash.Hex(), nil
}

// ChangeThreshold 改变阈值
func (w *WalletService) ChangeThreshold(newThreshold uint64, senderAddress string) (string, error) {
	receipt, err := w.SendTx(senderAddress, "changeThreshold", big.NewInt(int64(newThreshold)))
	if err != nil {
		return "", err
	}
	return receipt.TxHash.Hex(), nil
}

// ------------------ 提案管理方法 ------------------

// GetProposalCount 获取提案数量
func (w *WalletService) GetProposalCount() (uint64, error) {
	result, err := w.Call("getProposalCount")
	if err != nil {
		return 0, err
	}
	if count, ok := result.(*big.Int); ok {
		return count.Uint64(), nil
	}
	return 0, fmt.Errorf("unexpected result type")
}

// GetProposal 获取提案详情
func (w *WalletService) GetProposal(txIndex uint64) (*Proposal, error) {
	result, err := w.Call("getProposal", big.NewInt(int64(txIndex)))
	if err != nil {
		return nil, err
	}

	// 处理返回的元组
	if results, ok := result.([]interface{}); ok && len(results) == 5 {
		proposal := &Proposal{
			TxIndex: txIndex,
		}
		if to, ok := results[0].(common.Address); ok {
			proposal.To = to.Hex()
		}
		if value, ok := results[1].(*big.Int); ok {
			proposal.Value = value.Uint64()
		}
		if data, ok := results[2].([]byte); ok {
			proposal.Data = fmt.Sprintf("0x%x", data)
		}
		if confirmations, ok := results[3].(*big.Int); ok {
			proposal.Confirmations = confirmations.Uint64()
		}
		if executed, ok := results[4].(bool); ok {
			proposal.Executed = executed
		}
		return proposal, nil
	}
	return nil, fmt.Errorf("unexpected result type")
}

// Proposal 提案结构
type Proposal struct {
	TxIndex       uint64 `json:"txIndex"`
	To            string `json:"to"`
	Value         uint64 `json:"value"`
	Data          string `json:"data"`
	Confirmations uint64 `json:"confirmations"`
	Executed      bool   `json:"executed"`
}

// CreateProposal 创建提案
func (w *WalletService) CreateProposal(to string, value uint64, data, senderAddress string) (string, error) {
	toAddr := common.HexToAddress(to)
	valueBig := big.NewInt(int64(value))

	var dataBytes []byte
	if data != "" && data != "0x" {
		var err error
		dataBytes, err = hexToBytes(data)
		if err != nil {
			return "", fmt.Errorf("invalid data hex: %v", err)
		}
	}

	receipt, err := w.SendTx(senderAddress, "createProposal", toAddr, valueBig, dataBytes)
	if err != nil {
		return "", err
	}
	return receipt.TxHash.Hex(), nil
}

// ------------------ 确认与执行方法 ------------------

// ConfirmTx 确认交易
func (w *WalletService) ConfirmTx(txIndex uint64, senderAddress string) (string, error) {
	receipt, err := w.SendTx(senderAddress, "confirmTx", big.NewInt(int64(txIndex)))
	if err != nil {
		return "", err
	}
	return receipt.TxHash.Hex(), nil
}

// RevokeConfirmTx 撤销确认
func (w *WalletService) RevokeConfirmTx(txIndex uint64, senderAddress string) (string, error) {
	receipt, err := w.SendTx(senderAddress, "revokeConfirmTx", big.NewInt(int64(txIndex)))
	if err != nil {
		return "", err
	}
	return receipt.TxHash.Hex(), nil
}

// IsTransactionConfirmed 检查是否已确认
func (w *WalletService) IsTransactionConfirmed(txIndex uint64, confirmer string) (bool, error) {
	result, err := w.Call("isTransactionConfirmed", big.NewInt(int64(txIndex)), common.HexToAddress(confirmer))
	if err != nil {
		return false, err
	}
	if confirmed, ok := result.(bool); ok {
		return confirmed, nil
	}
	return false, fmt.Errorf("unexpected result type")
}

// GetConfirmationCount 获取确认数量
func (w *WalletService) GetConfirmationCount(txIndex uint64) (uint64, error) {
	result, err := w.Call("getConfirmationCount", big.NewInt(int64(txIndex)))
	if err != nil {
		return 0, err
	}
	if count, ok := result.(*big.Int); ok {
		return count.Uint64(), nil
	}
	return 0, fmt.Errorf("unexpected result type")
}

// CanExecute 检查是否可执行
func (w *WalletService) CanExecute(txIndex uint64) (bool, error) {
	result, err := w.Call("canExecute", big.NewInt(int64(txIndex)))
	if err != nil {
		return false, err
	}
	if canExec, ok := result.(bool); ok {
		return canExec, nil
	}
	return false, fmt.Errorf("unexpected result type")
}

// ExecuteTx 执行交易
func (w *WalletService) ExecuteTx(txIndex uint64, senderAddress string) (string, error) {
	receipt, err := w.SendTx(senderAddress, "executeTx", big.NewInt(int64(txIndex)))
	if err != nil {
		return "", err
	}
	return receipt.TxHash.Hex(), nil
}

// ------------------ 其他方法 ------------------

// ConfirmerInfo 确认人信息
type ConfirmerInfo struct {
	Address   string `json:"address"`
	Confirmed bool   `json:"confirmed"`
}

// GetConfirmers 获取提案的所有确认人列表
func (w *WalletService) GetConfirmers(txIndex uint64) ([]ConfirmerInfo, error) {
	// 获取所有 owners
	owners, err := w.GetOwners()
	if err != nil {
		return nil, err
	}

	// 遍历每个 owner，检查是否确认
	confirmers := make([]ConfirmerInfo, len(owners))
	for i, owner := range owners {
		confirmed, err := w.IsTransactionConfirmed(txIndex, owner)
		if err != nil {
			confirmers[i] = ConfirmerInfo{Address: owner, Confirmed: false}
		} else {
			confirmers[i] = ConfirmerInfo{Address: owner, Confirmed: confirmed}
		}
	}

	return confirmers, nil
}

// GetBalance 获取合约余额
func (w *WalletService) GetBalance() (uint64, error) {
	result, err := w.Call("getBalance")
	if err != nil {
		return 0, err
	}
	if balance, ok := result.(*big.Int); ok {
		return balance.Uint64(), nil
	}
	return 0, fmt.Errorf("unexpected result type")
}

// Version 获取版本号（V2）
func (w *WalletService) Version() (uint64, error) {
	result, err := w.Call("version")
	if err != nil {
		return 0, err
	}
	if version, ok := result.(*big.Int); ok {
		return version.Uint64(), nil
	}
	return 0, fmt.Errorf("unexpected result type")
}

// IsPaused 检查是否暂停（V3），V2 及以下版本默认返回 false
func (w *WalletService) IsPaused() (bool, error) {
	result, err := w.Call("paused")
	if err != nil {
		// 如果调用失败（V2 及以下版本没有 paused 函数），默认返回 false
		return false, nil
	}
	if paused, ok := result.(bool); ok {
		return paused, nil
	}
	return false, nil
}

// hexToBytes 将 hex 字符串转换为字节
func hexToBytes(hex string) ([]byte, error) {
	hex = strings.TrimPrefix(hex, "0x")
	if len(hex)%2 != 0 {
		hex = "0" + hex
	}
	return hexutil.Decode(hex)
}
