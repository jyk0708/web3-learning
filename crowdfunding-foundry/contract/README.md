在本地使用anvi进行测试

## 第一步： 启动anvil
```bash
# 启动
anvil
```

```plaintext
Available Accounts
==================

(0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
(1) 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000.000000000000000000 ETH)
(2) 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC (10000.000000000000000000 ETH)
(3) 0x90F79bf6EB2c4f870365E785982E1f101E93b906 (10000.000000000000000000 ETH)
(4) 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 (10000.000000000000000000 ETH)
(5) 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc (10000.000000000000000000 ETH)
(6) 0x976EA74026E726554dB657fA54763abd0C3a0aa9 (10000.000000000000000000 ETH)
(7) 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955 (10000.000000000000000000 ETH)
(8) 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f (10000.000000000000000000 ETH)
(9) 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720 (10000.000000000000000000 ETH)

Private Keys
==================

(0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
(1) 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
(2) 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
(3) 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
(4) 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
(5) 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba
(6) 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e
(7) 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356
(8) 0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97
(9) 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6

Wallet
==================
Mnemonic:          test test test test test test test test test test test junk
Derivation path:   m/44'/60'/0'/0/


Chain ID
==================

31337

Base Fee
==================

1000000000

Gas Limit
==================

30000000

Genesis Timestamp
==================

1785218597

Genesis Number
==================

0

Listening on 127.0.0.1:8545
```

## 第二步：发布合约
```bash
export SEPOLIA_RPC="127.0.0.1:8545"
export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
forge create --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY src/CrowdfundingFactory.sol:CrowdfundingFactory --broadcast
```

```log
[⠒] Compiling...
No files changed, compilation skipped
Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Deployed to: 0x5FbDB2315678afecb367f032d93F642f64180aa3
Transaction hash: 0xfbd1761a93b30e408ad72943472a33c4e40fd5ba2703be4ead7d4df8c7cf1e90
```
此时合约地址是：0x5FbDB2315678afecb367f032d93F642f64180aa3

## 第三步：启动合约事件监听器
```bash
# 进入后端代码目录
cd back
# 设置环境变量
export ETH_RPC_URL="ws://127.0.0.1:8545"    
export CONTRACT_ADDR="0x5FbDB2315678afecb367f032d93F642f64180aa3"
# 调用代码启动合约事件监听器
go run .
```

```log
RPC URL: ws://127.0.0.1:8545
合约地址: 0x5FbDB2315678afecb367f032d93F642f64180aa3
2026/07/28 15:08:12 reconnect mechanism started, interval: 10s
2026/07/28 15:08:12 EthEventListener started with 1 RPC nodes
事件监听器已启动，按 Ctrl+C 退出
2026/07/28 15:08:12 subscribing logs on node ws://127.0.0.1:8545
```

## 第四步：测试API接口

启动服务
```bash
cd back/api

# 设置环境变量
export ETH_RPC_URL="ws://127.0.0.1:8545"
export CONTRACT_ADDR="0x5FbDB2315678afecb367f032d93F642f64180aa3"
export PRIVATE_KEY="0x你的私钥"
export API_PORT="8080"

# 启动
go run .
```

启动日志
```log
go: downloading golang.org/x/net v0.51.0
go: downloading github.com/leodido/go-urn v1.4.0
go: downloading golang.org/x/net v0.51.0
go: downloading github.com/leodido/go-urn v1.4.0
go: downloading golang.org/x/net v0.51.0
go: downloading github.com/leodido/go-urn v1.4.0
go: downloading golang.org/x/net v0.51.0                                           ate
go: downloading github.com/leodido/go-urn v1.4.0
root@DESKTOP-7MNN49T:/mnt/e/Workspace/crowdfunding-foundry/back/api# go run .
[GIN-debug] [WARNING] Creating an Engine instance with the Logger and Recovery middleware already attached.

[GIN-debug] [WARNING] Running in "debug" mode. Switch to "release" mode in production. - using env:   export GIN_MODE=release
 - using code:  gin.SetMode(gin.ReleaseMode)

[GIN-debug] GET    /api/health               --> crowdfunding-foundry/api/handler.(*Handler).HealthCheck-fm (4 handlers)
[GIN-debug] GET    /api/campaign             --> crowdfunding-foundry/api/handler.(*Handler).GetCampaignInfo-fm (4 handlers)
[GIN-debug] GET    /api/campaign/contributors --> crowdfunding-foundry/api/handler.(*Handler).GetContributors-fm (4 handlers)
[GIN-debug] GET    /api/campaign/donations   --> crowdfunding-foundry/api/handler.(*Handler).GetDonations-fm (4 handlers)
[GIN-debug] POST   /api/campaign/start       --> crowdfunding-foundry/api/handler.(*Handler).StartCampaign-fm (4 handlers)
[GIN-debug] POST   /api/campaign/contribute  --> crowdfunding-foundry/api/handler.(*Handler).Contribute-fm (4 handlers)
[GIN-debug] POST   /api/campaign/end         --> crowdfunding-foundry/api/handler.(*Handler).EndCampaign-fm (4 handlers)
[GIN-debug] POST   /api/campaign/withdraw    --> crowdfunding-foundry/api/handler.(*Handler).WithdrawFunds-fm (4 handlers)
[GIN-debug] POST   /api/campaign/refund      --> crowdfunding-foundry/api/handler.(*Handler).RefundDonations-fm (4 handlers)
2026/07/31 10:27:27 ============================================
2026/07/31 10:27:27  众筹合约 API 服务已启动
2026/07/31 10:27:27 ============================================
2026/07/31 10:27:27 ============================================
2026/07/31 10:27:27  端口: http://localhost:8080
2026/07/31 10:27:27  节点: ws://127.0.0.1:8545
2026/07/31 10:27:27  合约: 0xa16e02e87b7454126e5e10d957a927a7f5b5d2be
2026/07/31 10:27:27
2026/07/31 10:27:27  GET  /api/campaign          查询众筹信息
2026/07/31 10:27:27  GET  /api/campaign/contributors  查询贡献者列表
2026/07/31 10:27:27  GET  /api/campaign/donations     查询捐赠记录
2026/07/31 10:27:27  POST /api/campaign/start         开始众筹
2026/07/31 10:27:27  POST /api/campaign/contribute    捐赠 ETH
2026/07/31 10:27:27  POST /api/campaign/end           结束众筹
2026/07/31 10:27:27  POST /api/campaign/withdraw      提取资金
2026/07/31 10:27:27  POST /api/campaign/refund       退款
2026/07/31 10:27:27  GET  /api/health                 健康检查
2026/07/31 10:27:27 ============================================
[GIN-debug] [WARNING] You trusted all proxies, this is NOT safe. We recommend you to set a value.
Please check https://github.com/gin-gonic/gin/blob/master/docs/doc.md#dont-trust-all-proxies for details.
[GIN-debug] Listening and serving HTTP on :8080

```



测试API接口示例
```bash
# 查询众筹信息
curl http://localhost:8080/api/campaign
# 响应
{
  "code": 0,
  "message": "success",
  "data": {
    "name": "Test Campaign",
    "goal": "1000000000000000000",
    "raised": "500000000000000000",
    "status": "Active",
    "status_code": 1,
    "is_active": true,
    "progress": 50,
    "owner": "0x...",
    "deadline": "1700000000",
    "contributors": 10
  }
}

# 先启动众筹

curl -X POST http://localhost:8080/api/campaign/start





# 捐赠 1 ETH（金额单位：wei）
curl -X POST http://localhost:8080/api/campaign/contribute \
  -H "Content-Type: application/json" \
  -d '{"amount": "1000000000000000000"}'

# 响应
{
  "code": 0,
  "message": "success",
  "data": {
    "tx_hash": "0xabc123...",
    "block_number": 123,
    "status": 1
  }
}


# 获取贡献者列表
curl http://localhost:8080/api/campaign/contributors
# 响应
{
	"code": 0,
	"message": "success",
	"data": {
		"contributors": [
			"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
		],
		"count": 1
	}
}
```