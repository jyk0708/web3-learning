package service

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"math/big"
	"os"
	"strings"
	"sync"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

var statusNames = map[uint8]string{0: "Created", 1: "Active", 2: "Ended", 3: "Funded", 4: "Failed"}

type ContractService struct {
	client       *ethclient.Client
	abi          abi.ABI
	contractAddr common.Address
	privateKey   *ecdsa.PrivateKey
	chainID      *big.Int
	mu           sync.RWMutex
}

type CampaignInfo struct {
	Name         string `json:"name"`
	Goal         string `json:"goal"`
	Raised       string `json:"raised"`
	Status       string `json:"status"`
	StatusCode   uint8  `json:"status_code"`
	IsActive     bool   `json:"is_active"`
	Progress     uint64 `json:"progress"`
	Owner        string `json:"owner"`
	Deadline     string `json:"deadline"`
	Contributors int    `json:"contributors"`
}

type ContributeRequest struct {
	Amount string `json:"amount"`
}

type DonationInfo struct {
	Donor  string `json:"donor"`
	Amount string `json:"amount"`
}

type TransactionResult struct {
	TxHash      string `json:"tx_hash"`
	BlockNumber uint64 `json:"block_number,omitempty"`
	Status      uint64 `json:"status,omitempty"`
}

func NewContractService(rpcURL, contractAddr, privateKeyHex, abiFile string) (*ContractService, error) {
	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		return nil, fmt.Errorf("连接节点失败: %w", err)
	}

	abiJSON, err := os.ReadFile(abiFile)
	if err != nil {
		return nil, fmt.Errorf("读取 ABI 失败: %w", err)
	}

	parsedABI, err := abi.JSON(strings.NewReader(string(abiJSON)))
	if err != nil {
		return nil, fmt.Errorf("解析 ABI 失败: %w", err)
	}

	ctx := context.Background()
	chainID, err := client.NetworkID(ctx)
	if err != nil {
		return nil, fmt.Errorf("获取链 ID 失败: %w", err)
	}

	svc := &ContractService{
		client:       client,
		abi:          parsedABI,
		contractAddr: common.HexToAddress(contractAddr),
		chainID:      chainID,
	}

	if privateKeyHex != "" {
		privateKeyHex = strings.TrimPrefix(privateKeyHex, "0x")
		pk, err := crypto.HexToECDSA(privateKeyHex)
		if err != nil {
			return nil, fmt.Errorf("解析私钥失败: %w", err)
		}
		svc.privateKey = pk
	}

	return svc, nil
}

func (s *ContractService) Close() {
	s.client.Close()
}

func (s *ContractService) getAuth(ctx context.Context) (*bind.TransactOpts, error) {
	if s.privateKey == nil {
		return nil, fmt.Errorf("未配置私钥，无法执行写操作")
	}
	auth, err := bind.NewKeyedTransactorWithChainID(s.privateKey, s.chainID)
	if err != nil {
		return nil, err
	}
	auth.Context = ctx
	return auth, nil
}

func (s *ContractService) callView(ctx context.Context, funcName string, args ...interface{}) ([]interface{}, error) {
	data, err := s.abi.Pack(funcName, args...)
	if err != nil {
		return nil, fmt.Errorf("打包 %s 失败: %w", funcName, err)
	}

	output, err := s.client.CallContract(ctx, ethereum.CallMsg{
		To:   &s.contractAddr,
		Data: data,
	}, nil)
	if err != nil {
		return nil, fmt.Errorf("调用 %s 失败: %w", funcName, err)
	}

	result, err := s.abi.Unpack(funcName, output)
	if err != nil {
		return nil, fmt.Errorf("解包 %s 失败: %w", funcName, err)
	}

	return result, nil
}

func (s *ContractService) transact(ctx context.Context, funcName string, value *big.Int, args ...interface{}) (*TransactionResult, error) {
	auth, err := s.getAuth(ctx)
	if err != nil {
		return nil, err
	}
	if value != nil {
		auth.Value = value
	}

	contract := bind.NewBoundContract(s.contractAddr, s.abi, s.client, s.client, s.client)
	tx, err := contract.Transact(auth, funcName, args...)
	if err != nil {
		return nil, fmt.Errorf("发送交易失败: %w", err)
	}

	receipt, err := bind.WaitMined(ctx, s.client, tx)
	if err != nil {
		return &TransactionResult{TxHash: tx.Hash().Hex()}, nil
	}

	return &TransactionResult{
		TxHash:      receipt.TxHash.Hex(),
		BlockNumber: receipt.BlockNumber.Uint64(),
		Status:      receipt.Status,
	}, nil
}

func (s *ContractService) GetCampaignInfo(ctx context.Context) (*CampaignInfo, error) {
	info := &CampaignInfo{}

	name, err := s.callView(ctx, "campaignName")
	if err == nil {
		info.Name = fmt.Sprintf("%v", name[0])
	}

	goal, err := s.callView(ctx, "campaignGoal")
	if err == nil {
		info.Goal = fmt.Sprintf("%v", goal[0])
	}

	raised, err := s.callView(ctx, "campaignRaised")
	if err == nil {
		info.Raised = fmt.Sprintf("%v", raised[0])
	}

	status, err := s.callView(ctx, "status")
	if err == nil {
		info.StatusCode = status[0].(uint8)
		info.Status = statusNames[info.StatusCode]
	}

	active, err := s.callView(ctx, "isActive")
	if err == nil {
		info.IsActive = active[0].(bool)
	}

	progress, err := s.callView(ctx, "getProgress")
	if err == nil {
		if p, ok := progress[0].(uint64); ok {
			info.Progress = p
		}
	}

	owner, err := s.callView(ctx, "owner")
	if err == nil {
		info.Owner = fmt.Sprintf("%v", owner[0])
	}

	deadline, err := s.callView(ctx, "campaignDeadline")
	if err == nil {
		info.Deadline = fmt.Sprintf("%v", deadline[0])
	}

	count, err := s.callView(ctx, "getContributorCount")
	if err == nil {
		if c, ok := count[0].(uint64); ok {
			info.Contributors = int(c)
		}
	}

	return info, nil
}

func (s *ContractService) StartCampaign(ctx context.Context) (*TransactionResult, error) {
	return s.transact(ctx, "startCampaign", nil)
}

func (s *ContractService) Contribute(ctx context.Context, amountWei *big.Int) (*TransactionResult, error) {
	return s.transact(ctx, "contribute", amountWei)
}

func (s *ContractService) EndCampaign(ctx context.Context) (*TransactionResult, error) {
	return s.transact(ctx, "endCampaign", nil)
}

func (s *ContractService) WithdrawFunds(ctx context.Context) (*TransactionResult, error) {
	return s.transact(ctx, "withdrawFunds", nil)
}

func (s *ContractService) RefundDonations(ctx context.Context) (*TransactionResult, error) {
	return s.transact(ctx, "refundDonations", nil)
}

func (s *ContractService) GetContributors(ctx context.Context) ([]string, error) {
	result, err := s.callView(ctx, "getContributors")
	if err != nil {
		return nil, err
	}

	var contributors []string
	if addrs, ok := result[0].([]common.Address); ok {
		for _, addr := range addrs {
			contributors = append(contributors, addr.Hex())
		}
	}
	return contributors, nil
}

func (s *ContractService) GetDonations(ctx context.Context) ([]DonationInfo, error) {
	contributors, err := s.GetContributors(ctx)
	if err != nil {
		return nil, err
	}

	var donations []DonationInfo
	for _, donor := range contributors {
		result, err := s.callView(ctx, "campaignDonations", common.HexToAddress(donor))
		if err != nil {
			continue
		}
		amount := fmt.Sprintf("%v", result[0])
		donations = append(donations, DonationInfo{Donor: donor, Amount: amount})
	}
	return donations, nil
}
