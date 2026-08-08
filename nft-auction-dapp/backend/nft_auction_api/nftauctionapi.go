// Code scaffolded by goctl. Safe to edit.
// goctl 1.10.2

package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"regexp"
	"syscall"

	"nft_auction_api/internal/config"
	"nft_auction_api/internal/event"
	"nft_auction_api/internal/handler"
	"nft_auction_api/internal/svc"
	"nft_auction_api/internal/types"

	"github.com/joho/godotenv"
	"github.com/zeromicro/go-zero/core/conf"
	"github.com/zeromicro/go-zero/core/logx"
	"github.com/zeromicro/go-zero/rest"
	"github.com/zeromicro/go-zero/rest/httpx"
)

var configFile = flag.String("f", "etc/nftauctionapi-api.yaml", "the config file")

var envVarRegex = regexp.MustCompile(`\$\{([^}:]+)(?::([^}]*))?\}`)

func resolveEnvVars(content string) string {
	return envVarRegex.ReplaceAllStringFunc(content, func(match string) string {
		submatches := envVarRegex.FindStringSubmatch(match)
		if len(submatches) < 2 {
			return match
		}
		varName := submatches[1]
		defaultValue := ""
		if len(submatches) >= 3 {
			defaultValue = submatches[2]
		}
		if val, ok := os.LookupEnv(varName); ok {
			return val
		}
		return defaultValue
	})
}

func main() {
	flag.Parse()

	err := godotenv.Load(".env")
	if err != nil {
		fmt.Printf("warning: .env file not found, using system env vars: %v\n", err)
	}

	rawContent, err := os.ReadFile(*configFile)
	if err != nil {
		logx.Severe(fmt.Sprintf("failed to read config file: %v", err))
		os.Exit(1)
	}
	resolvedContent := resolveEnvVars(string(rawContent))

	tmpFile, err := os.CreateTemp("", "nftauctionapi-*.yaml")
	if err != nil {
		logx.Severe(fmt.Sprintf("failed to create temp file: %v", err))
		os.Exit(1)
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)

	if _, err := tmpFile.WriteString(resolvedContent); err != nil {
		tmpFile.Close()
		logx.Severe(fmt.Sprintf("failed to write temp config: %v", err))
		os.Exit(1)
	}
	tmpFile.Close()

	var c config.Config
	conf.MustLoad(tmpPath, &c)

	setupUnifiedResponse()

	// init() 中已自动注册所有 Listener，无需手动注册

	server := rest.MustNewServer(c.RestConf)
	server.Use(corsMiddleware)
	defer server.Stop()

	ctx := svc.NewServiceContext(c)
	handler.RegisterHandlers(server, ctx)

	// 初始化事件监听
	dispatcher := initEventDispatcher(c, ctx)
	if dispatcher != nil {
		defer dispatcher.Stop()
	}

	// 优雅关闭
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-quit
		logx.Info("Shutting down...")
		if dispatcher != nil {
			dispatcher.Stop()
		}
		server.Stop()
	}()

	fmt.Printf("Starting server at %s:%d...\n", c.Host, c.Port)
	server.Start()
}

// initEventDispatcher 根据注册表自动初始化事件分发器
func initEventDispatcher(c config.Config, svcCtx *svc.ServiceContext) *event.EventDispatcher {
	client := svcCtx.ContractClient
	dispatcher := event.NewEventDispatcher(
		client.Backend,
		client.Contract,
		client.ParsedABI,
		client.ContractAddr,
		nil,
		client.Backend.ChainID(),
	)

	// 注册所有监听器（注入 svcCtx）
	listeners := event.RegisterAllListeners(svcCtx)
	if len(listeners) == 0 {
		logx.Info("No event listeners registered")
		return nil
	}

	for eventName, listener := range listeners {
		dispatcher.RegisterListener(eventName, listener)
	}

	if err := dispatcher.Start(); err != nil {
		logx.Errorf("Failed to start event dispatcher: %v", err)
		return nil
	}

	return dispatcher
}

func setupUnifiedResponse() {
	httpx.SetOkHandler(func(ctx context.Context, v any) any {
		return types.ApiResponse{
			Status: "ok",
			Data:   v,
		}
	})

	httpx.SetErrorHandlerCtx(func(ctx context.Context, err error) (int, any) {
		logx.WithContext(ctx).Errorf("API error: %v", err)
		return http.StatusInternalServerError, types.ApiResponse{
			Status: "error",
			Err:    err.Error(),
		}
	})
}

func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With, Accept, Origin")
		w.Header().Set("Access-Control-Max-Age", "86400")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next(w, r)
	}
}
