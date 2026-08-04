# 多签钱包管理系统

基于区块链多签钱包合约的前后端管理系统。

## 项目结构

```
multisig-wallet/
├── src/                    # Solidity 合约
│   ├── MultiSigWalletUpgradeable.sol
│   ├── MultiSigWalletV2.sol
│   └── MultiSigWalletV3.sol
├── script/                 # 部署脚本
├── back/                   # Go 后端
│   ├── main.go
│   ├── go.mod
│   ├── config/
│   │   └── config.go
│   ├── contract/
│   │   ├── wallet.go
│   │   └── abi.go
│   ├── api/
│   │   └── handler.go
│   └── .env
└── frontend/              # React 前端
    ├── src/
    │   ├── App.jsx
    │   ├── main.jsx
    │   ├── services/
    │   │   └── api.js
    │   └── components/
    │       ├── Dashboard.jsx
    │       ├── Owners.jsx
    │       ├── Proposals.jsx
    │       └── Info.jsx
    ├── package.json
    └── vite.config.js
```

## 快速开始

### 前置条件

- [Go](https://go.dev/dl/) 1.21+
- [Node.js](https://nodejs.org/) 18+
- [Anvil](https://book.getfoundry.sh/anvil/) 本地节点
- Foundry 工具链

### 1. 启动 Anvil 本地节点

```bash
# 启动 Anvil
anvil --reset

# 在另一个终端中部署合约
cd multisig-wallet
FOUNDRY_PROFILE=dev forge script script/DeployBaseUpgradeableScript.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 2. 启动 Go 后端

```bash
cd back

# 安装依赖
go mod tidy

# 复制环境变量文件并修改配置
cp .env .env.local
# 编辑 .env.local 设置正确的合约地址

# 启动后端服务
go run main.go
```

后端将在 `http://localhost:8080` 运行。

### 3. 启动 React 前端

```bash
cd frontend

# 安装依赖
npm install

# 启动开发服务器
npm run dev
```

前端将在 `http://localhost:5173` 运行。

## API 接口

### 所有者管理

| 方法 | 路径 | 描述 |
|------|------|------|
| GET | /api/v1/owners | 获取所有所有者 |
| GET | /api/v1/owners/count | 获取所有者数量 |
| GET | /api/v1/owners/is-owner?address=0x... | 检查是否是所有者 |
| GET | /api/v1/owners/threshold | 获取确认阈值 |
| POST | /api/v1/owners | 添加所有者 |
| DELETE | /api/v1/owners | 移除所有者 |
| PUT | /api/v1/owners/threshold | 修改阈值 |

### 提案管理

| 方法 | 路径 | 描述 |
|------|------|------|
| GET | /api/v1/proposals/count | 获取提案数量 |
| GET | /api/v1/proposals/:index | 获取提案详情 |
| POST | /api/v1/proposals | 创建提案 |
| PUT | /api/v1/proposals/:index/confirm | 确认交易 |
| PUT | /api/v1/proposals/:index/revoke | 撤销确认 |
| GET | /api/v1/proposals/:index/confirmed | 检查是否已确认 |
| GET | /api/v1/proposals/:index/confirmations | 获取确认数量 |
| GET | /api/v1/proposals/:index/can-execute | 检查是否可执行 |
| POST | /api/v1/proposals/:index/execute | 执行交易 |

### 其他

| 方法 | 路径 | 描述 |
|------|------|------|
| GET | /api/v1/balance | 获取合约余额 |
| GET | /api/v1/version | 获取版本号 |
| GET | /api/v1/paused | 检查是否暂停 |

## 技术栈

### 后端
- [Go](https://go.dev/) 编程语言
- [Gin](https://gin-gonic.com/) Web 框架
- [go-ethereum](https://github.com/ethereum/go-ethereum) Ethereum 客户端

### 前端
- [React 18](https://react.dev/) UI 框架
- [Vite](https://vitejs.dev/) 构建工具
- [Ant Design](https://ant.design/) UI 组件库
- [Axios](https://axios-http.com/) HTTP 客户端

## 安全说明

**注意**：当前实现中后端直接使用私钥发送交易，这仅用于学习目的。在生产环境中，应使用更安全的签名方案（如硬件钱包、远程签名服务等）。

## 许可证

MIT License
