package main

import (
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"

	"multisig-wallet/back/api"
	"multisig-wallet/back/config"
	"multisig-wallet/back/contract"
)

func init() {
	// 当前工作目录如果是 back 文件夹，直接写 .env
	err := godotenv.Load(".env")
	if err != nil {
		log.Printf("⚠️ load .env failed: %v", err)
	}
}

func main() {
	rpc := os.Getenv("RPC_URL")
	log.Println(rpc)
	// 加载配置
	cfg := config.GetConfig()

	fmt.Println("=== 多签钱包后端服务 ===")
	fmt.Printf("RPC URL: %s\n", cfg.RPCURL)
	fmt.Printf("Proxy Address: %s\n", cfg.ProxyAddress)
	fmt.Printf("Impl Address: %s\n", cfg.ImplAddress)
	fmt.Printf("Port: %s\n", cfg.Port)

	// 初始化合约服务
	wallet, err := contract.NewWalletService()
	if err != nil {
		log.Fatalf("Failed to initialize wallet service: %v", err)
	}

	// 创建处理器
	handler := api.NewHandler(wallet)

	// 创建 Gin 路由
	r := gin.Default()

	// CORS 中间件
	r.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Owner-Address")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})

	// API 路由组
	v1 := r.Group("/api/v1")
	{
		// 系统接口
		v1.GET("/available-owners", handler.GetAvailableOwners)

		// 所有者管理
		owners := v1.Group("/owners")
		{
			owners.GET("", handler.GetOwners)
			owners.GET("/count", handler.GetOwnerCount)
			owners.GET("/is-owner", handler.IsOwner)
			owners.GET("/threshold", handler.GetThreshold)
			owners.POST("", handler.AddOwner)
			owners.DELETE("", handler.RemoveOwner)
			owners.PUT("/threshold", handler.ChangeThreshold)
		}

		// 提案管理
		proposals := v1.Group("/proposals")
		{
			proposals.GET("/count", handler.GetProposalCount)
			proposals.GET("/:index", handler.GetProposal)
			proposals.POST("", handler.CreateProposal)
		}

		// 确认与执行
		proposals.PUT("/:index/confirm", handler.ConfirmTx)
		proposals.PUT("/:index/revoke", handler.RevokeConfirmTx)
		proposals.GET("/:index/confirmed", handler.IsTransactionConfirmed)
		proposals.GET("/:index/confirmations", handler.GetConfirmationCount)
		proposals.GET("/:index/confirmers", handler.GetConfirmers)
		proposals.GET("/:index/can-execute", handler.CanExecute)
		proposals.POST("/:index/execute", handler.ExecuteTx)

		// 其他接口
		v1.GET("/balance", handler.GetBalance)
		v1.GET("/version", handler.Version)
		v1.GET("/paused", handler.IsPaused)
	}

	// 启动服务
	fmt.Printf("\n服务启动成功: http://localhost:%s\n", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
