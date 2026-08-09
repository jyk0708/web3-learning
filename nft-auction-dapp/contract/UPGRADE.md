# NFT 拍卖合约 UUPS 升级指南 (V1 → V2)

本文档说明如何将已部署的 NftAuction 代理合约从 V1 (`NftAuctionUpgradeable`) 升级到 V2 (`NftAuctionV2`)，包括升级机制、操作步骤、存储兼容性原理和常见陷阱。

---

## 一、升级架构概览

项目采用 **UUPS (Universal Upgradeable Proxy Standard)** 升级模式：

```
┌─────────────────────────────────────────────────────────┐
│  用户 / DApp                                             │
└────────────────────────┬────────────────────────────────┘
                         │ 调用业务方法 (CreateAuction/Bid/...)
                         ▼
┌─────────────────────────────────────────────────────────┐
│  ERC1967Proxy (代理合约，地址不变)                         │
│  - 存储所有状态数据 (owner / auctions / priceFeeds ...)   │
│  - 通过 delegatecall 转发到当前实现合约                    │
│  - EIP-1967 slot 保存当前实现地址                          │
└────────────────────────┬────────────────────────────────┘
                         │ delegatecall
                         ▼
┌─────────────────────────────────────────────────────────┐
│  实现合约 (可替换)                                        │
│  V1: NftAuctionUpgradeable  →  V2: NftAuctionV2          │
│  - 只包含逻辑代码，不存状态                                │
│  - constructor 调用 _disableInitializers() 禁止直接初始化  │
└─────────────────────────────────────────────────────────┘
```

**核心思想**：代理合约地址永远不变，用户始终与代理交互；升级时只更换代理指向的实现合约地址，状态数据原封不动保留在代理的存储中。

---

## 二、两步升级安全机制

本合约在 OZ 标准 UUPS 之上增加了**两步升级**防护，防止实现合约被恶意替换后直接升级：

| 步骤 | 调用方法 | 作用 | 权限 |
|------|---------|------|------|
| 1. 提议 | `proposeUpgrade(newImpl)` | 设置 `_pendingUpgradeImplementation` | onlyOwner |
| 2. 执行 | `upgradeToAndCall(newImpl, "")` | 校验 pending → 切换实现 → 清零 pending | onlyOwner |
| 3. 初始化 | `initializeV2(bps)` | 设置 V2 新增的存储变量 | onlyOwner |

**安全保证**：
- 即使实现合约地址泄露，攻击者无法绕过 `proposeUpgrade` 直接升级（`_authorizeUpgrade` 会校验 pending）
- 升级成功后 `_pendingUpgradeImplementation` 立即清零，防止重放
- `initializeV2` 有 `require(_minBidIncrementBps == 0)` 守卫，只能调用一次

关键代码（[NftAuctionUpgradeable.sol](file:///e:/Workspace/web3-learning/nft-auction-dapp/contract/src/NftAuctionUpgradeable.sol)）：

```solidity
function proposeUpgrade(address newImplementation) external onlyOwner {
    require(newImplementation != address(0), "Invalid implementation address");
    _pendingUpgradeImplementation = newImplementation;
    emit UpgradeProposed(newImplementation);
}

function _authorizeUpgrade(address newImplementation) internal onlyOwner override {
    require(_pendingUpgradeImplementation == newImplementation,
            "Upgrade must be approved by proposeUpgrade first");
    _pendingUpgradeImplementation = address(0); // 清零防重放
}
```

---

## 三、V2 新增功能

V2 在 V1 基础上新增：

1. **`version()`** — 返回 `"V2"`，用于链上验证升级是否成功
2. **最小加价比例** — 每次新出价必须比当前最高出价高出 `bps/10000`（如 500 = 5%），防止恶意微小加价
   - `initializeV2(bps)` — 升级后初始化（一次性）
   - `setMinBidIncrement(bps)` — 后续调整（可多次）
   - `getMinBidIncrement()` — 查询当前值
   - `getMinBidStep(highestBid)` — 计算最小加价金额
3. **重写 `Bid()`** — 在 V1 出价逻辑基础上增加最小加价校验

---

## 四、存储兼容性原理（关键）

升级时**绝对不能**改变已有存储变量的顺序和类型，否则会破坏现有数据。V2 的存储布局策略：

```
V1 存储布局 (代理实际持有的状态):
  slot 0..N    : Initializable / Ownable / UUPS / ReentrancyGuard 等继承变量
  slot N+1     : _pendingUpgradeImplementation
  slot N+2     : _auctionIdCounter
  slot N+3     : auctions (mapping)
  slot N+4     : _priceFeeds (mapping)
  slot N+5     : _platformFeeRate
  slot N+6..N+261 : __gap[256]  ← V1 预留的空槽位

V2 存储布局 (仅追加，不修改 V1):
  slot 0..N+261 : 与 V1 完全一致 (V1 的所有变量 + __gap[256] 原样继承)
  slot N+262    : _minBidIncrementBps  ← V2 新增变量
  slot N+263..  : __gap[255]  ← V2 为未来 V3 预留
```

**要点**：
- Solidity **不允许子合约修改父合约已声明的存储变量**，所以 V2 无法"缩减"V1 的 `__gap`
- V2 只能**追加**新变量到 V1 存储末尾之后
- `_minBidIncrementBps` 位于 V1 从未写入的新槽位，初始值为 0，由 `initializeV2` 设置
- V1 的旧数据（owner / 拍卖记录 / 预言机配置 / NFT 托管）完全不受影响

> ⚠️ **未来 V3 升级注意**：V3 只能在 V2 的 `__gap[255]` 之后追加新变量，不要插入到 V2 已有变量之前。

---

## 五、升级操作步骤

### 前置条件

- 已部署 V1 代理合约（通过 [Deploy.s.sol](file:///e:/Workspace/web3-learning/nft-auction-dapp/contract/script/Deploy.s.sol) 部署）
- 持有 owner 私钥（部署时 `initialize` 的调用者）
- 已运行 `forge test` 确认 V2 测试全部通过

### 方式一：使用升级脚本（推荐）

[UpgradeToV2.s.sol](file:///e:/Workspace/web3-learning/nft-auction-dapp/contract/script/UpgradeToV2.s.sol) 封装了完整的升级流程：

```bash
# 1. 启动本地测试链（或连接到目标网络）
anvil --mnemonic "test test test test test test test test test test test junk"

# 2. 设置环境变量
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export PROXY_ADDRESS=0x...   # 已部署的 V1 代理地址

# 3. 执行升级（脚本会自动完成：部署V2实现 → proposeUpgrade → upgradeToAndCall → initializeV2）
forge script script/UpgradeToV2.s.sol \
  --broadcast \
  --rpc-url http://localhost:8545 \
  --sig "run(address)" $PROXY_ADDRESS \
  --private-key $PRIVATE_KEY
```

脚本执行后会自动验证：版本号、实现地址 slot、最小加价配置、owner 保留情况。

### 方式二：手动 cast 命令逐步执行

如果想逐步观察每一步，可以用 `cast` 手动执行：

```bash
# 步骤 1：部署 V2 实现合约
V2_IMPL=$(forge create src/NftAuctionV2.sol:NftAuctionV2 \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY | grep "Deployed to:" | awk '{print $3}')
echo "V2 implementation: $V2_IMPL"

# 步骤 2：提议升级（owner 调用）
cast send $PROXY_ADDRESS "proposeUpgrade(address)" $V2_IMPL \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY

# 步骤 3：执行升级（通过 upgradeToAndCall，第二个参数传空 bytes）
cast send $PROXY_ADDRESS "upgradeToAndCall(address,bytes)" $V2_IMPL "0x" \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY

# 步骤 4：初始化 V2 新增存储变量（500 = 5%）
cast send $PROXY_ADDRESS "initializeV2(uint256)" 500 \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY
```

### 升级后验证

```bash
# 1. 验证版本号
cast call $PROXY_ADDRESS "version()(string)" --rpc-url http://localhost:8545
# 期望输出: V2

# 2. 验证最小加价比例
cast call $PROXY_ADDRESS "getMinBidIncrement()(uint256)" --rpc-url http://localhost:8545
# 期望输出: 500

# 3. 验证 owner 保留
cast call $PROXY_ADDRESS "owner()(address)" --rpc-url http://localhost:8545
# 期望输出: 升级前的 owner 地址

# 4. 验证实现地址已更新（读取 EIP-1967 slot）
IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e209a38731159862c2821194979c3
cast storage $PROXY_ADDRESS $IMPL_SLOT --rpc-url http://localhost:8545
# 期望输出: V2 实现合约地址（去掉左侧 0 填充）

# 5. 验证已有拍卖数据保留
cast call $PROXY_ADDRESS "auctions(uint256)" 1 --rpc-url http://localhost:8545
# 期望输出: 升级前创建的拍卖记录仍然存在
```

---

## 六、运行测试

### 运行 V2 升级测试

```bash
# 只运行 V2 测试套件
forge test --match-contract NftAuctionV2Test -vv

# 运行单个测试用例
forge test --match-test test_E2E_FullUpgradeFlow -vvvv

# 运行全部测试（V1 + V2）
forge test
```

### V2 测试覆盖范围

[NftAuctionV2.t.sol](file:///e:/Workspace/web3-learning/nft-auction-dapp/contract/test/NftAuctionV2.t.sol) 包含 24 个测试用例：

| 分类 | 测试用例 | 说明 |
|------|---------|------|
| 升级流程 | `test_Version` | 版本号返回 "V2" |
| | `test_Upgrade_PreservesOwner` | owner 保留 |
| | `test_Upgrade_PreservesAuctionData` | 拍卖数据保留 |
| | `test_Upgrade_PreservesPriceFeed` | 预言机配置保留 |
| | `test_Upgrade_PreservesNftEscrow` | NFT 托管状态保留 |
| | `test_ImplementationSlotUpdated` | EIP-1967 slot 已更新 |
| V2 新功能 | `test_InitializeV2_SetsMinBidIncrement` | 初始化设置 bps |
| | `test_InitializeV2_RevertAlreadyInitialized` | 重复初始化回滚 |
| | `test_SetMinBidIncrement` | 调整 bps |
| | `test_SetMinBidIncrement_RevertNotOwner` | 权限校验 |
| | `test_SetMinBidIncrement_RevertInvalidBps` | 边界校验 |
| | `test_GetMinBidStep` | 加价计算 |
| | `test_GetMinBidStep_FirstBid` | 首次出价不受限 |
| Bid 校验 | `test_Bid_FirstBidNotAffectedByMinIncrement` | 首次出价不受最小加价约束 |
| | `test_Bid_WithSufficientIncrement` | 满足加价的出价成功 |
| | `test_Bid_RevertBelowMinIncrement` | 低于加价的出价回滚 |
| | `test_Bid_MinIncrementBoundary` | 边界值正好满足 |
| 权限安全 | `test_ProposeUpgrade_RevertNotOwner` | 非 owner 提议失败 |
| | `test_ProposeUpgrade_RevertInvalidAddress` | 非法地址失败 |
| | `test_UpgradeTo_RevertWithoutPropose` | 未提议直接升级失败 |
| | `test_UpgradeTo_RevertNotOwner` | 非 owner 升级失败 |
| | `test_ProposeUpgrade_CanOverwrite` | 提议可覆盖 |
| | `test_Upgrade_PendingClearedAfterUpgrade` | 升级后 pending 清零 |
| 端到端 | `test_E2E_FullUpgradeFlow` | 升级后创建拍卖→出价→加价校验完整流程 |

---

## 七、常见陷阱

### 1. OZ 5.x 没有 `upgradeTo(address)`

OpenZeppelin 5.x 的 `UUPSUpgradeable` **移除了 `upgradeTo(address)`**，只保留 `upgradeToAndCall(address, bytes)`。升级时必须传空 bytes：

```solidity
// ❌ 错误：OZ 5.x 中此函数不存在
abi.encodeWithSignature("upgradeTo(address)", newImpl)

// ✅ 正确：使用 upgradeToAndCall，传空 bytes
abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, "")
```

### 2. 不能用 `sload` 读代理存储

在测试中读取代理的 EIP-1967 slot 时，`sload` 读的是**当前合约（测试合约）**的存储，不是代理的存储。必须用 Foundry 的 `vm.load`：

```solidity
// ❌ 错误：读的是测试合约自己的存储
assembly { currentImpl := sload(implSlot) }

// ✅ 正确：读代理地址的存储
address currentImpl = address(uint160(uint256(vm.load(proxyAddress, implSlot))));
```

### 3. `vm.prank` 只对下一次调用生效

`vm.prank(admin)` 设置的 `msg.sender` 只作用于**紧接着的第一次外部调用**。如果后续还有需要 admin 身份的调用，必须再次 `vm.prank` 或使用 `vm.startPrank`/`vm.stopPrank`：

```solidity
// ❌ 错误：第二个调用不是 admin 身份
vm.prank(admin);
proxy.proposeUpgrade(newImpl);
proxy.upgradeToAndCall(newImpl, "");  // msg.sender 已恢复为测试合约

// ✅ 正确：用 startPrank 包裹多个调用
vm.startPrank(admin);
proxy.proposeUpgrade(newImpl);
proxy.upgradeToAndCall(newImpl, "");
vm.stopPrank();
```

### 4. 存储布局不能修改已有变量

升级时只能**追加**新变量，不能：
- 修改已有变量的类型
- 删除已有变量
- 在已有变量之间插入新变量
- 改变已有变量的顺序

如果需要修改已有变量，只能通过新增变量 + 迁移逻辑来间接实现。

### 5. 实现合约的 constructor 不能初始化状态

实现合约的 `constructor()` 调用 `_disableInitializers()`，禁止在任何非代理上下文中调用 `initialize`。所有状态初始化必须通过代理进行。

---

## 八、回滚方案

UUPS 升级**不可自动回滚**。如果 V2 有问题，只能再次升级回 V1：

```bash
# 1. 重新提议升级回 V1 实现
cast send $PROXY_ADDRESS "proposeUpgrade(address)" $V1_IMPL \
  --rpc-url $RPC --private-key $KEY

# 2. 执行升级回 V1
cast send $PROXY_ADDRESS "upgradeToAndCall(address,bytes)" $V1_IMPL "0x" \
  --rpc-url $RPC --private-key $KEY
```

> ⚠️ 注意：回滚到 V1 后，V2 设置的 `_minBidIncrementBps` 仍保留在存储中（V1 的 `__gap` 区域），但 V1 代码不会读取它，因此不影响 V1 行为。再次升级到 V2 时，`initializeV2` 会因 `_minBidIncrementBps != 0` 而失败，需要通过 `setMinBidIncrement` 调整。

**因此，升级前务必在测试网充分验证。**
