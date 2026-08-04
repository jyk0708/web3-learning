package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"crowdfunding-foundry/api/handler"
	"crowdfunding-foundry/api/service"

	"github.com/gin-gonic/gin"
)

func main() {
	rpcURL := os.Getenv("ETH_RPC_URL")
	contractAddr := os.Getenv("CONTRACT_ADDR")
	privateKeyHex := os.Getenv("PRIVATE_KEY")
	port := os.Getenv("API_PORT")
	if port == "" {
		port = "8080"
	}

	if rpcURL == "" || contractAddr == "" {
		log.Fatal("请设置 ETH_RPC_URL 和 CONTRACT_ADDR 环境变量")
	}

	abiFile := filepath.Join(rootDir(), "CrowdfundingCampaign.abi.json")

	svc, err := service.NewContractService(rpcURL, contractAddr, privateKeyHex, abiFile)
	if err != nil {
		log.Fatalf("初始化服务失败: %v", err)
	}
	defer svc.Close()

	h := handler.NewHandler(svc)

	r := gin.Default()

	r.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})

	api := r.Group("/api")
	{
		// 健康检查
		api.GET("/health", h.HealthCheck)
		// 开始众筹
		api.POST("/campaign/start", h.StartCampaign)
		// 查询众筹信息
		api.GET("/campaign", h.GetCampaignInfo)
		// 查询贡献者列表
		api.GET("/campaign/contributors", h.GetContributors)
		// 查询捐赠记录
		api.GET("/campaign/donations", h.GetDonations)
		// 捐赠 ETH
		api.POST("/campaign/contribute", h.Contribute)
		// 结束众筹
		api.POST("/campaign/end", h.EndCampaign)
		// 提取资金
		api.POST("/campaign/withdraw", h.WithdrawFunds)
		// 退款
		api.POST("/campaign/refund", h.RefundDonations)
	}

	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		fmt.Println("\n正在关闭服务...")
		svc.Close()
		os.Exit(0)
	}()

	log.Printf("============================================")
	log.Printf(" 众筹合约 API 服务已启动")
	log.Printf("============================================")
	log.Printf(" 端口: http://localhost:%s", port)
	log.Printf(" 节点: %s", rpcURL)
	log.Printf(" 合约: %s", contractAddr)
	log.Printf("")
	log.Printf(" GET  /api/campaign          查询众筹信息")
	log.Printf(" GET  /api/campaign/contributors  查询贡献者列表")
	log.Printf(" GET  /api/campaign/donations     查询捐赠记录")
	log.Printf(" POST /api/campaign/start         开始众筹")
	log.Printf(" POST /api/campaign/contribute    捐赠 ETH")
	log.Printf(" POST /api/campaign/end           结束众筹")
	log.Printf(" POST /api/campaign/withdraw      提取资金")
	log.Printf(" POST /api/campaign/refund       退款")
	log.Printf(" GET  /api/health                 健康检查")
	log.Printf("============================================")

	if err := r.Run(":" + port); err != nil {
		log.Fatalf("启动服务失败: %v", err)
	}
}

func rootDir() string {
	wd, err := os.Getwd()
	if err != nil {
		return ".."
	}
	root := filepath.Dir(filepath.Dir(wd))
	abiPath := filepath.Join(root, "CrowdfundingCampaign.abi.json")
	if _, err := os.Stat(abiPath); err == nil {
		return root
	}
	return ".."
}
