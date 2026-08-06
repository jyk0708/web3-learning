# NFT Auction Contract - Deployment Guide

## 目录结构

```
contract/
├── src/
│   └── NftAuctionUpgradeable.sol    # 主合约
├── test/
│   ├── MockERC20.sol                 # ERC20 Mock 合约
│   ├── MockERC721.sol                # ERC721 Mock 合约
│   ├── MockAggregator.sol            # Chainlink 预言机 Mock
│   └── NftAuctionUpgradeable.t.sol   # 测试文件
├── script/
│   ├── Deploy.s.sol                  # 通用部署脚本
│   ├── DeployLocal.s.sol             # 本地测试环境部署
│   ├── DeployMainnet.s.sol           # 主网部署脚本
│   └── ChainlinkFeeds.sol            # 预言机地址配置
└── foundry.toml
```

## 快速开始

### 1. 本地测试

```bash
# 启动 Anvil 本地测试链
anvil --mnemonic "test test test test test test test test test test test junk"

# .env 配置
```plaintext
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ETH_USD_FEED=0x694AA1769357215DE4FAC081bf1f309aC33333333
USDC_USD_FEED=0x8A753747A1Fa494EC936cE39Bc223Dc0A033333333
LOCAL_RPC_URL=http://localhost:8545
```

# 部署到本地
forge script script/Deploy.s.sol --broadcast --rpc-url $LOCAL_RPC_URL --private-key $PRIVATE_KEY

# 运行测试
forge test

# 运行特定测试
forge test -m test_CreateAuction
```

### 2. Sepolia 测试网

```bash
# 部署
export PRIVATE_KEY=your_private_key
forge script script/Deploy.s.sol --broadcast --rpc-url https://sepolia.infura.io/v3/YOUR_KEY
```

### 3. 主网部署

```bash
export PRIVATE_KEY=your_private_key
forge script script/DeployMainnet.s.sol --broadcast --rpc-url https://mainnet.infura.io/v3/YOUR_KEY
```

## 测试用例列表

### 基础功能
- `test_Initialize` - 合约初始化
- `test_SetPriceFeed` - 设置预言机

### 创建拍卖
- `test_CreateAuction` - 创建拍卖
- `test_CreateAuction_RevertWithoutPriceFeed` - 无预言机时回滚
- `test_CreateAuction_RevertInvalidDuration` - 无效时间回滚
- `test_CreateAuction_RevertInvalidStartPrice` - 无效价格回滚

### 开始拍卖
- `test_StartAuction` - 开始拍卖
- `test_StartAuction_RevertNotOwnerOrSeller` - 权限检查
- `test_StartAuction_RevertAlreadyStarted` - 重复开始回滚

### 出价
- `test_Bid` - 成功出价
- `test_Bid_IncreaseBid` - 提高出价并退款
- `test_Bid_RevertNotStarted` - 未开始出价回滚
- `test_Bid_RevertLowerThanHighest` - 低价回滚
- `test_Bid_RevertBidOnOwnNFT` - 自投回滚
- `test_Bid_RevertAuctionEnded` - 已结束出价回滚

### 取消拍卖
- `test_CancelAuction` - 成功取消
- `test_CancelAuction_RevertAfterStarted` - 已开始取消回滚
- `test_CancelAuction_RevertNotOwnerOrSeller` - 权限检查

### 结束拍卖
- `test_EndAuction_WithWinner` - 有胜者结束
- `test_EndAuction_NoBids` - 无出价结束
- `test_EndAuction_RevertBeforeEnd` - 提前结束回滚
- `test_EndAuction_RevertNotOwnerOrSeller` - 权限检查
- `test_EndAuction_RevertAlreadyEnded` - 重复结束回滚

### 预言机异常
- `test_OraclePriceFetcher_StalePrice` - 过时价格处理
- `test_OraclePriceFetcher_NegativePrice` - 负数价格处理

### 多币种
- `test_MultiTokenSupport` - 多币种支持

## 合约交互命令

### 查询合约状态
```bash
# 查询 owner
cast call $AUCTION_ADDRESS "owner()" --rpc-url $LOCAL_RPC_URL

# 查询拍卖信息
cast call $AUCTION_ADDRESS "auctions(uint256)" 1 --rpc-url $LOCAL_RPC_URL

# 查询价格预言机
cast call $AUCTION_ADDRESS "getPrice2USD(address,uint256)" $TOKEN_ADDRESS 1000000 --rpc-url $LOCAL_RPC_URL
```

### 交易命令
```bash
# 创建拍卖
cast send $AUCTION_ADDRESS "CreateAuction(address,uint256,address,uint256,uint256)" \
  $NFT_ADDRESS 1 $TOKEN_ADDRESS $START_PRICE 7 \
  --rpc-url http://localhost:8545

# 开始拍卖
cast send $AUCTION_ADDRESS "StartAuction(uint256)" 1 --rpc-url http://localhost:8545

# 出价
cast send $AUCTION_ADDRESS "Bid(uint256,uint256,address)" 1 $AMOUNT $TOKEN_ADDRESS \
  --rpc-url http://localhost:8545

# 结束拍卖
cast send $AUCTION_ADDRESS "EndAuction(uint256)" 1 --rpc-url http://localhost:8545
```

## 预言机地址

Chainlink 预言机地址参考 `script/ChainlinkFeeds.sol`:

### 主网 (Ethereum)
- ETH/USD: 0x5f4eC3Df9cbd4C477D24210F603a834b8fDB1a49
- USDC/USD: 0x8fFfFfd4AfB6115b956Fd4056EC72702777c6A09
- WBTC/USD: 0x883bd56429f149245042EEa669F70F4E5d6b2C0D
- DAI/USD: 0xAed0c3fa41a1fb932ba2a0b675fa2eee48890d935

### 测试网 (Sepolia)
- ETH/USD: 0x694AA1769357215DE4FAC081bf1f309aDC3253056

更多预言机地址: https://data.chain.link/feeds

## 安全提示

1. **权限控制**:
   - `CreateAuction`: 任何人可调用
   - `StartAuction`: 卖家或管理员
   - `Bid`: 任何人可调用
   - `CancelAuction`: 仅在拍卖开始前，卖家或管理员
   - `EndAuction`: 卖家或管理员

2. **预言机安全**:
   - 始终使用可信的 Chainlink 预言机
   - 监控预言机价格是否异常
   - 设置合理的 `ORACLE_STALE_THRESHOLD`

3. **升级机制**:
   - 合约使用 UUPS 升级模式
   - 需要通过多签治理授权升级
   - 升级前必须充分测试
