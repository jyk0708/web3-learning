package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/joho/godotenv"
)

// OwnerKey 所有者密钥信息
type OwnerKey struct {
	Address    string
	PrivateKey string
	Name       string
}

// Config 配置结构
type Config struct {
	// 以太坊节点 RPC 地址
	RPCURL string
	// 合约代理地址
	ProxyAddress string
	// 合约实现地址（V2）
	ImplAddress string
	// 端口
	Port string
	// 默认私钥
	PrivateKey string
	// 多 owner 私钥列表
	OwnerKeys []OwnerKey
}

var (
	cfg  *Config
	once sync.Once
)

// GetConfig 获取配置（单例模式）
func GetConfig() *Config {
	once.Do(func() {
		// 尝试加载 .env 文件
		envFile := ".env"
		if path, err := filepath.Abs(".env.local"); err == nil {
			envFile = path
		}

		if err := godotenv.Load(envFile); err != nil {
			if err2 := godotenv.Load(".env"); err2 != nil {
				// 如果没有 .env 文件，使用默认值
			}
		}

		// 解析 owner keys
		ownerKeys := parseOwnerKeys()

		cfg = &Config{
			RPCURL:       getEnv("RPC_URL", "http://127.0.0.1:8545"),
			ProxyAddress: getEnv("PROXY_ADDRESS", "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"),
			ImplAddress:  getEnv("IMPL_ADDRESS", "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"),
			Port:         getEnv("PORT", "8080"),
			PrivateKey:   getEnv("PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"),
			OwnerKeys:    ownerKeys,
		}
	})
	return cfg
}

// parseOwnerKeys 从环境变量解析 owner keys
func parseOwnerKeys() []OwnerKey {
	var keys []OwnerKey

	// 默认添加 owner1
	defaultKey := OwnerKey{
		Address:    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
		PrivateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
		Name:       "Owner 1",
	}
	keys = append(keys, defaultKey)

	// 尝试从环境变量加载更多 owner（支持 OWNER2, OWNER3... 或 OWNER_2, OWNER_3...）
	for i := 2; i <= 10; i++ {
		// 尝试多种命名格式
		addr := os.Getenv(fmt.Sprintf("OWNER%d_ADDRESS", i))
		if addr == "" {
			addr = os.Getenv(fmt.Sprintf("OWNER_%d_ADDRESS", i))
		}
		key := os.Getenv(fmt.Sprintf("OWNER%d_KEY", i))
		if key == "" {
			key = os.Getenv(fmt.Sprintf("OWNER_%d_KEY", i))
		}
		name := os.Getenv(fmt.Sprintf("OWNER%d_NAME", i))
		if name == "" {
			name = os.Getenv(fmt.Sprintf("OWNER_%d_NAME", i))
		}

		if addr != "" && key != "" {
			if name == "" {
				name = fmt.Sprintf("Owner %d", i)
			}
			keys = append(keys, OwnerKey{
				Address:    strings.TrimSpace(addr),
				PrivateKey: strings.TrimSpace(key),
				Name:       strings.TrimSpace(name),
			})
		}
	}

	return keys
}

// GetOwnerKey 根据地址获取私钥
func (c *Config) GetOwnerKey(address string) *OwnerKey {
	for i := range c.OwnerKeys {
		if strings.EqualFold(c.OwnerKeys[i].Address, address) {
			return &c.OwnerKeys[i]
		}
	}
	// 返回默认 key
	if len(c.OwnerKeys) > 0 {
		return &c.OwnerKeys[0]
	}
	return nil
}

// GetOwnerAddresses 获取所有 owner 地址列表
func (c *Config) GetOwnerAddresses() []string {
	addrs := make([]string, len(c.OwnerKeys))
	for i, k := range c.OwnerKeys {
		addrs[i] = k.Address
	}
	return addrs
}

func getEnv(key, defaultVal string) string {
	val := os.Getenv(key)
	if val == "" {
		return defaultVal
	}
	return val
}
