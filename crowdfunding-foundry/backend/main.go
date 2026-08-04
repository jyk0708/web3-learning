package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"
)

const abiFileName = "CrowdfundingCampaign.abi.json"

func main() {
	rpcURL := os.Getenv("ETH_RPC_URL")
	contractAddr := os.Getenv("CONTRACT_ADDR")

	if rpcURL == "" || contractAddr == "" {
		log.Fatal("请设置环境变量 ETH_RPC_URL 和 CONTRACT_ADDR")
	}

	abiJSON, err := os.ReadFile(abiFileName)
	if err != nil {
		log.Fatalf("读取 ABI 文件失败: %v", err)
	}

	fmt.Printf("RPC URL: %s\n", truncateString(rpcURL, 50))
	fmt.Printf("合约地址: %s\n", contractAddr)

	eventCh, cleanup, err := EthEventListener(&EthEventListenerConfig{
		RPCURLs:      []string{rpcURL},
		ContractAddr: contractAddr,
		ContractAPI:  string(abiJSON),
	})
	if err != nil {
		log.Fatalf("初始化失败: %v", err)
	}
	defer cleanup()

	fmt.Println("事件监听器已启动，按 Ctrl+C 退出")

	eventCount := 0
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	for {
		select {
		case event, ok := <-eventCh:
			if !ok {
				fmt.Println("事件通道已关闭")
				return
			}
			if event.eventType == LogEventTypeSuccess {
				eventCount++
				printEvent(event)
			}
		case <-sigCh:
			fmt.Println("\n收到退出信号，程序退出")
			return
		}
	}
}

func printEvent(event *LogEvent) {
	fmt.Printf("%s\n", strings.Repeat("=", 50))
	fmt.Printf("[事件] %s\n", event.name)
	fmt.Printf("%s\n", strings.Repeat("-", 50))
	fmt.Printf("区块号: %d\n", event.blockNumber)
	fmt.Printf("交易哈希: %s\n", truncateString(event.txHash.Hex(), 20))

	switch event.name {
	case "CampaignDonated":
		printCampaignDonated(event)
	case "CampaignRefunded":
		printCampaignRefunded(event)
	case "CampaignStatusChanged":
		printCampaignStatusChanged(event)
	case "CampaignWithdrawn":
		printCampaignWithdrawn(event)
	default:
		printGenericEvent(event)
	}
	fmt.Printf("%s\n", strings.Repeat("=", 50))
}

func printCampaignDonated(event *LogEvent) {
	if event.indexed0 != nil {
		fmt.Printf("众筹合约: %v\n", formatIndexed(event.indexed0))
	}
	if event.indexed1 != nil {
		fmt.Printf("捐赠者: %v\n", formatIndexed(event.indexed1))
	}
	if len(event.data) > 0 {
		fmt.Printf("捐赠金额: %v\n", event.data[0])
	}
}

func printCampaignRefunded(event *LogEvent) {
	if event.indexed0 != nil {
		fmt.Printf("众筹合约: %v\n", formatIndexed(event.indexed0))
	}
	if len(event.data) > 0 {
		fmt.Printf("退款金额: %v\n", event.data[0])
	}
}

func printCampaignStatusChanged(event *LogEvent) {
	statusNames := map[uint8]string{0: "Created", 1: "Active", 2: "Ended", 3: "Funded", 4: "Failed"}
	if len(event.data) >= 2 {
		oldStatus, ok1 := event.data[0].(uint8)
		newStatus, ok2 := event.data[1].(uint8)
		if ok1 && ok2 {
			fmt.Printf("状态变更: %s(%d) → %s(%d)\n", statusNames[oldStatus], oldStatus, statusNames[newStatus], newStatus)
		}
	}
}

func printCampaignWithdrawn(event *LogEvent) {
	if event.indexed0 != nil {
		fmt.Printf("众筹合约: %v\n", formatIndexed(event.indexed0))
	}
	if len(event.data) > 0 {
		fmt.Printf("提取金额: %v\n", event.data[0])
	}
}

func printGenericEvent(event *LogEvent) {
	for i, idx := range []interface{}{event.indexed0, event.indexed1, event.indexed2} {
		if idx != nil {
			fmt.Printf("[Indexed %d]: %v\n", i, formatIndexed(idx))
		}
	}
	if len(event.data) > 0 {
		fmt.Printf("[Data]: ")
		for i, d := range event.data {
			if i > 0 {
				fmt.Print(", ")
			}
			fmt.Printf("%v", d)
		}
		fmt.Println()
	}
}

func formatIndexed(v interface{}) string {
	if s, ok := v.(string); ok && len(s) > 20 {
		return s[:20] + "..."
	}
	return fmt.Sprintf("%v", v)
}

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
