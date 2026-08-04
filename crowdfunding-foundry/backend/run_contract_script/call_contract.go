package main

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"log"
	"math/big"
	"os"
	"strings"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

// 环境变量示例：
// export ETH_RPC_URL="http://127.0.0.1:8545"
// export CONTRACT_ADDR="0x5FbDB2315678afecb367f032d93F642f64180aa3"
// export PRIVATE_KEY="0x你的私钥"

const abiFile = "../CrowdfundingCampaign.abi.json"

func main() {
	rpcURL := os.Getenv("ETH_RPC_URL")
	contractAddr := os.Getenv("CONTRACT_ADDR")
	privateKeyHex := os.Getenv("PRIVATE_KEY")

	if rpcURL == "" || contractAddr == "" {
		log.Fatal("请设置 ETH_RPC_URL 和 CONTRACT_ADDR 环境变量")
	}

	// 1. 连接节点
	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		log.Fatalf("连接节点失败: %v", err)
	}
	defer client.Close()

	ctx := context.Background()

	// 2. 读取并解析 ABI
	abiJSON, err := os.ReadFile(abiFile)
	if err != nil {
		log.Fatalf("读取 ABI 失败: %v", err)
	}
	parsedABI, err := abi.JSON(strings.NewReader(string(abiJSON)))
	if err != nil {
		log.Fatalf("解析 ABI 失败: %v", err)
	}

	contractAddress := common.HexToAddress(contractAddr)

	// 3. 查询示例（只读，无需私钥）
	fmt.Println("========== 查询合约信息 ==========")
	queryContractInfo(ctx, client, parsedABI, contractAddress)

	// 4. 写操作示例（需要私钥签名）
	if privateKeyHex != "" {
		fmt.Println("\n========== 执行写操作 ==========")
		privateKey, err := crypto.HexToECDSA(privateKeyHex)
		if err != nil {
			log.Fatalf("解析私钥失败: %v", err)
		}
		executeContractCalls(ctx, client, parsedABI, contractAddress, privateKey)
	} else {
		fmt.Println("\n[跳过] 未设置 PRIVATE_KEY，无法执行写操作")
	}
}

// queryContractInfo 查询合约信息（只读）
func queryContractInfo(ctx context.Context, client *ethclient.Client, parsedABI abi.ABI, addr common.Address) {
	// 查询 campaignName
	result, err := parsedABI.Pack("campaignName")
	if err != nil {
		log.Printf("打包 campaignName 失败: %v", err)
	} else {
		output, err := client.CallContract(ctx, ethereum.CallMsg{
			To:   &addr,
			Data: result,
		}, nil)
		if err != nil {
			log.Printf("调用 campaignName 失败: %v", err)
		} else {
			name, err := parsedABI.Unpack("campaignName", output)
			if err == nil {
				fmt.Printf("众筹名称: %v\n", name[0])
			}
		}
	}

	// 查询 campaignGoal
	result, _ = parsedABI.Pack("campaignGoal")
	output, err := client.CallContract(ctx, ethereum.CallMsg{To: &addr, Data: result}, nil)
	if err == nil {
		goal, _ := parsedABI.Unpack("campaignGoal", output)
		fmt.Printf("目标金额: %v wei\n", goal[0])
	}

	// 查询 campaignRaised
	result, _ = parsedABI.Pack("campaignRaised")
	output, err = client.CallContract(ctx, ethereum.CallMsg{To: &addr, Data: result}, nil)
	if err == nil {
		raised, _ := parsedABI.Unpack("campaignRaised", output)
		fmt.Printf("已筹金额: %v wei\n", raised[0])
	}

	// 查询 status
	result, _ = parsedABI.Pack("status")
	output, err = client.CallContract(ctx, ethereum.CallMsg{To: &addr, Data: result}, nil)
	if err == nil {
		status, _ := parsedABI.Unpack("status", output)
		statusNames := map[uint8]string{0: "Created", 1: "Active", 2: "Ended", 3: "Funded", 4: "Failed"}
		s := status[0].(uint8)
		fmt.Printf("状态: %s (%d)\n", statusNames[s], s)
	}

	// 查询 isActive
	result, _ = parsedABI.Pack("isActive")
	output, err = client.CallContract(ctx, ethereum.CallMsg{To: &addr, Data: result}, nil)
	if err == nil {
		active, _ := parsedABI.Unpack("isActive", output)
		fmt.Printf("是否活跃: %v\n", active[0])
	}

	// 查询 getProgress（百分比）
	result, _ = parsedABI.Pack("getProgress")
	output, err = client.CallContract(ctx, ethereum.CallMsg{To: &addr, Data: result}, nil)
	if err == nil {
		progress, _ := parsedABI.Unpack("getProgress", output)
		fmt.Printf("完成进度: %v%%\n", progress[0])
	}
}

// executeContractCalls 执行合约写操作
func executeContractCalls(ctx context.Context, client *ethclient.Client, parsedABI abi.ABI, addr common.Address, privateKey *ecdsa.PrivateKey) {
	fromAddr := crypto.PubkeyToAddress(privateKey.PublicKey)
	fmt.Printf("调用者地址: %s\n", fromAddr.Hex())

	// 获取网络 ID
	chainID, err := client.NetworkID(ctx)
	if err != nil {
		log.Fatalf("获取链 ID 失败: %v", err)
	}

	// 创建 TransactOpts（自动处理 nonce、gas 估算）
	auth, err := bind.NewKeyedTransactorWithChainID(privateKey, chainID)
	if err != nil {
		log.Fatalf("创建交易签名器失败: %v", err)
	}
	auth.Context = ctx
	// 在新版本 go-ethereum 中，ChainID 字段已移除，改为通过 NewKeyedTransactorWithChainID 设置
	// 此处移除 ChainID 设置，链 ID 将自动从交易中获取

	// ===== 示例1: startCampaign（开始众筹）=====
	fmt.Println("\n--- startCampaign ---")
	callNoArg(ctx, client, parsedABI, addr, auth, "startCampaign")

	// ===== 示例2: contribute（捐赠 0.01 ETH）=====
	// 注意：contribute 是 payable 函数，需要设置 Value
	fmt.Println("\n--- contribute (0.01 ETH) ---")
	oneEth := big.NewInt(1000000000000000000)
	contributeAmount := new(big.Int).Div(oneEth, big.NewInt(100)) // 0.01 ETH
	callPayable(ctx, client, parsedABI, addr, auth, "contribute", contributeAmount)

	// ===== 示例3: 查询捐赠后的状态 =====
	fmt.Println("\n--- 再次查询状态 ---")
	result, _ := parsedABI.Pack("campaignRaised")
	output, err := client.CallContract(ctx, ethereum.CallMsg{To: &addr, Data: result}, nil)
	if err == nil {
		raised, _ := parsedABI.Unpack("campaignRaised", output)
		fmt.Printf("已筹金额: %v wei\n", raised[0])
	}
}

// callNoArg 调用无参数的 nonpayable 函数
func callNoArg(ctx context.Context, client *ethclient.Client, parsedABI abi.ABI, addr common.Address, auth *bind.TransactOpts, name string) {
	data, err := parsedABI.Pack(name)
	if err != nil {
		log.Printf("打包 %s 失败: %v", name, err)
		return
	}

	tx, err := bind.NewBoundContract(addr, parsedABI, client, client, client).Transact(auth, name)
	if err != nil {
		log.Printf("调用 %s 失败: %v", name, err)
		return
	}

	fmt.Printf("交易已提交: %s\n", tx.Hash().Hex())
	receipt, err := bind.WaitMined(ctx, client, tx)
	if err != nil {
		log.Printf("等待交易确认失败: %v", err)
		return
	}
	fmt.Printf("交易成功！区块: %d\n", receipt.BlockNumber)
	_ = data // 保留供调试
}

// callPayable 调用 payable 函数（需传入 ETH）
func callPayable(ctx context.Context, client *ethclient.Client, parsedABI abi.ABI, addr common.Address, auth *bind.TransactOpts, name string, value *big.Int) {
	auth.Value = value // 设置要发送的 ETH 数量

	tx, err := bind.NewBoundContract(addr, parsedABI, client, client, client).Transact(auth, name)
	if err != nil {
		log.Printf("调用 %s 失败: %v", name, err)
		return
	}

	fmt.Printf("交易已提交: %s\n", tx.Hash().Hex())
	receipt, err := bind.WaitMined(ctx, client, tx)
	if err != nil {
		log.Printf("等待交易确认失败: %v", err)
		return
	}
	fmt.Printf("交易成功！区块: %d\n", receipt.BlockNumber)
}
