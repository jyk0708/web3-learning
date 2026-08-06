# 多签钱包 UUPS 可升级合约 — 部署 & 升级文档

## 目录
- [架构概述](#架构概述)
- [环境准备](#环境准备)
- [首次部署（V1 + 代理）](#首次部署v1--代理)
- [日常使用](#日常使用)
- [合约升级（V1 → V2）](#合约升级v1--v2)
- [升级注意事项](#升级注意事项)
- [脚本说明](#脚本说明)
- [常见问题](#常见问题)

---

## 架构概述

采用 **UUPS (Universal Upgradeable Proxy System)** 模式，合约分为三层：

```
用户 ──→ ERC1967Proxy ──(delegatecall)──→ 实现合约 V1
                    │
                    └──(delegatecall)──→ 实现合约 V2  ← 升级后
```

| 组件 | 说明 |
|------|------|
| **ERC1967Proxy** | 代理合约，用户始终与这个地址交互。存储所有状态数据。地址**永远不变** |
| **实现合约 V1** | 包含纯逻辑代码，不存储状态。部署后通过代理交互 |
| **实现合约 V2** | 升级后的新逻辑合约，替换 V1 继续服务 |

关键原则：
- **代理地址 = 钱包地址**，所有用户只认这一个地址
- 升级只改变逻辑层，**状态（owners、阈值、提案、余额）全部保留**
- 升级本身受**多签治理**约束：必须达到签名阈值才能执行

---

## 环境准备

### 1. 创建 `.env` 文件

```bash
# 多签 Owner 地址（至少 3 个）
OWNER1=0x...
OWNER2=0x...
OWNER3=0x...

# 多签确认阈值（需要 N 个 owner 签名才能执行交易/升级）
THRESHOLD=2

# RPC 地址（根据目标网络选择）
LOCAL_RPC_URL=http://localhost:8545
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY

# 部署私钥（请勿提交到 Git）
PRIVATE_KEY=0x...
```

### 2. 安装依赖 & 编译

```bash
cd multisig-wallet
forge install
forge build
```

---

## 首次部署（V1 + 代理）

首次部署需要同时部署**实现合约**和**代理合约**。

### 命令

```bash
# 本地/测试网（Anvil）
forge script script/DeployUpgradeable.s.sol \
  --rpc-url local \
  --broadcast \
  -vvvv

# Sepolia 测试网
forge script script/DeployUpgradeable.s.sol \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv

# 主网（生产环境，建议用 ledger/keystore）
forge script script/DeployUpgradeable.s.sol \
  --rpc-url mainnet \
  --account YOUR_ACCOUNT \
  --broadcast \
  --verify \
  -vvvv
```

### 脚本做了什么

```
┌───────────────────────────────────────────────┐
│ ① 读取 .env 中的 OWNER1/2/3 和 THRESHOLD     │
│ ② 编码 initialize(owners, threshold) calldata │
│ ③ 部署 实现合约 V1           → 输出地址 A     │
│ ④ 部署 ERC1967Proxy(A, calldata) → 输出地址 B │
│    代理在构造时自动调用 initialize              │
│ ⑤ 验证：读取代理的 getOwnerCount/getThreshold │
└───────────────────────────────────────────────┘
```

### 部署后的输出

```
Implementation deployed at: 0xAAAA...  ← V1 逻辑地址（记录备用）
Proxy deployed at:          0xBBBB...  ← ★ 多签钱包地址，之后一直用这个
Owner count: 3
Threshold:   2
```

> ⚠️ **Proxy 地址 (`0xBBBB...`) 就是你的多签钱包！** 所有转账提案、确认、执行操作都通过这个地址。实现合约 (`0xAAAA...`) 只用于后续升级时指定新版本。

---

## 日常使用

所有操作通过 **Proxy 地址** 进行。

### 1. 给多签钱包充值

直接向 Proxy 地址转账 ETH：

```bash
cast send <PROXY_ADDRESS> --value 1ether --private-key $PRIVATE_KEY --rpc-url sepolia
```

### 2. 创建转账提案

```bash
cast send <PROXY_ADDRESS> \
  "createProposal(address,uint256,bytes)" \
  <接收地址> <金额(wei)> 0x \
  --from <owner地址> --private-key $OWNER1_KEY --rpc-url sepolia
```

### 3. 确认提案

```bash
# 各 owner 依次确认
cast send <PROXY_ADDRESS> \
  "confirmTx(uint256)" <proposalId> \
  --from <owner地址> --private-key $OWNER2_KEY --rpc-url sepolia
```

### 4. 执行提案

```bash
# 达到阈值后，任意 owner 可执行
cast send <PROXY_ADDRESS> \
  "executeTx(uint256)" <proposalId> \
  --from <owner地址> --private-key $OWNER1_KEY --rpc-url sepolia
```

### 5. 查询

```bash
# 查看所有 owner
cast call <PROXY_ADDRESS> "getOwners()" --rpc-url sepolia

# 查看确认阈值
cast call <PROXY_ADDRESS> "getThreshold()" --rpc-url sepolia

# 查看某个提案详情
cast call <PROXY_ADDRESS> "getProposal(uint256)" <proposalId> --rpc-url sepolia

# 查看合约余额
cast call <PROXY_ADDRESS> "getBalance()" --rpc-url sepolia
```

---

## 合约升级（V1 → V2）

当你需要修改合约逻辑时（修 bug、加功能等）：

### 完整流程图

```
1. 修改 MultiSigWalletUpgradeable.sol 代码
       │
2. forge build  ← 确保编译通过
       │
3. 部署 V2 实现合约         ← 得到新地址
       │
4. owner → createUpgradeProposal(V2地址)
       │   └→ 得到 proposalId
5. 各 owner → confirmUpgradeProposal(proposalId)
       │   └→ 达到 THRESHOLD 后可以执行
6. 任意 owner → executeUpgradeProposal(proposalId)
       │   ├→ 设置临时授权 token
       │   ├→ 调用 upgradeTo(V2地址)
       │   │   ├→ _authorizeUpgrade 验证 token ✓
       │   │   └→ 清除 token，写入新实现地址
       │   └→ 完成！
       │
7. 验证：Proxy 地址不变，逻辑已切换
```

### 命令（使用自动化脚本）

```bash
# 先设置代理地址
export PROXY_ADDRESS=0x<你的Proxy地址>

# 运行升级脚本（自动执行步骤 3-6）
forge script script/UpgradeToV2.s.sol \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

### 手动执行（适用于分批多签）

自动化脚本适合测试。生产环境通常各 owner 独立签名，需要分步手动操作：

```bash
# 步骤 1: 部署 V2 实现合约
forge create src/MultiSigWalletUpgradeable.sol:MultiSigWalletUpgradeable \
  --rpc-url sepolia --private-key $PRIVATE_KEY

# 输出: Deployed to: 0xCCCC...  (V2 实现地址)

# 步骤 2: 创建升级提案
cast send $PROXY_ADDRESS \
  "createUpgradeProposal(address)" 0xCCCC... \
  --from <owner1> --private-key $OWNER1_KEY --rpc-url sepolia

# 输出: SubmitUpgradeProposal(proposalId=0, newImplementation=0xCCCC...)

# 步骤 3: 各 owner 分别确认
cast send $PROXY_ADDRESS \
  "confirmUpgradeProposal(uint256)" 0 \
  --from <owner2> --private-key $OWNER2_KEY --rpc-url sepolia

cast send $PROXY_ADDRESS \
  "confirmUpgradeProposal(uint256)" 0 \
  --from <owner3> --private-key $OWNER3_KEY --rpc-url sepolia

# 步骤 4: 检查是否可以执行
cast call $PROXY_ADDRESS "canExecuteUpgrade(uint256)" 0 --rpc-url sepolia
# 返回 true 即可执行

# 步骤 5: 执行升级
cast send $PROXY_ADDRESS \
  "executeUpgradeProposal(uint256)" 0 \
  --from <owner1> --private-key $OWNER1_KEY --rpc-url sepolia

# 输出: ExecuteUpgradeProposal(proposalId=0, newImplementation=0xCCCC...)
```

### 验证升级成功

```bash
# Proxy 地址不变
echo $PROXY_ADDRESS
# 但内部逻辑已切换到 V2

# 确认功能正常
cast call $PROXY_ADDRESS "getOwners()" --rpc-url sepolia
cast call $PROXY_ADDRESS "getThreshold()" --rpc-url sepolia
```

---

## 升级注意事项

### ✅ 可以做的事

| 操作 | 说明 |
|------|------|
| 新增函数 | 完全安全，随意添加 |
| 修改函数实现 | 改动已有函数内部逻辑，不影响存储 |
| 新增事件 | 安全 |
| 新增状态变量 | **只能追加在最后**，且必须预留 gap 空间 |
| 修改错误信息 | 纯文本修改，安全 |

### ❌ 不能做的事

| 操作 | 后果 |
|------|------|
| **改变已有状态变量的顺序** | 存储错乱，数据损坏 |
| **删除已有状态变量** | 后续变量的存储槽偏移，数据损坏 |
| **改变已有状态变量的类型** | 存储布局不兼容 |
| **移除 `__gap`** | 未来升级空间被压缩 |
| **修改继承链（改变父合约顺序）** | 存储布局改变 |

### 存储布局示例

```solidity
// V1 中的状态变量（顺序不可变！）
address[] public owners;              // slot 0
uint256 public numConfirmationsRequired; // slot 1
mapping(address => bool) public ownerMapping; // slot 2
Proposal[] public proposals;          // slot 3
mapping(uint256 => mapping(...)) public confirmers; // slot 4
UpgradeProposal[] public upgradeProposals; // slot 5
mapping(uint256 => mapping(...)) public upgradeConfirmers; // slot 6
address private _pendingUpgradeImplementation; // slot 7
uint256[256] private __gap;           // slot 8 ~ 263 (预留)

// V2 新增变量只能加在 __gap 之前：
// uint256 public newVar;           // slot 8
// uint256[255] private __gap;      // slot 9 ~ 263 (缩小 gap)
```

### 升级安全检查清单

- [ ] `forge build` 编译通过
- [ ] `forge test` 全部通过
- [ ] 未修改已有状态变量的声明顺序和类型
- [ ] 新变量追加在 `__gap` 之前，gap 大小相应减少
- [ ] 先在测试网完整走一遍升级流程
- [ ] 部署 V2 后，先在测试网验证功能正常

---

## 脚本说明

| 文件 | 用途 |
|------|------|
| [script/DeployUpgradeable.s.sol](script/DeployUpgradeable.s.sol) | 首次部署：部署 V1 实现 + ERC1967Proxy |
| [script/UpgradeToV2.s.sol](script/UpgradeToV2.s.sol) | 升级流程：部署 V2 → 提案 → 多签确认 → 执行升级 |
| [script/MultiSigWalletScript.s.sol](script/MultiSigWalletScript.s.sol) | 普通（非升级）版多签钱包部署脚本 |

---

## 常见问题

### Q: 为什么不直接用 `upgradeTo` 而要搞多签提案？

直接用 `upgradeTo` 意味着单个人就能升级合约——如果这个人的私钥泄露，攻击者可以把合约升级成恶意版本偷走所有资金。

本合约通过重写 `_authorizeUpgrade`，强制升级必须经过**多签提案 + 达到阈值**，防止单点作恶。

### Q: `_pendingUpgradeImplementation` 是干什么的？

这是一个一次性授权 token，防止**签名重放攻击**。流程：

```
executeUpgradeProposal → 设置 _pendingUpgradeImplementation = V2地址
                       → 调用 upgradeTo(V2地址)
                       → _authorizeUpgrade 校验 token == V2地址 ✓
                       → 清除 token（_pendingUpgradeImplementation = 0）

如果有人再次调用 upgradeTo → token 已清除 → 校验失败 → 拒绝
```

### Q: 升级后旧提案还在吗？

在。所有数据（owners、提案历史、余额）都存储在 Proxy 中，升级只替换逻辑层。

### Q: 代理合约部署后 `initialize` 能被再次调用吗？

不能。`initialize` 加了 `initializer` 修饰符，只能被调用一次。代理在构造时已调用过，之后任何人都无法再次调用。

### Q: 如果升级脚本执行到一半失败了怎么办？

由于合约使用多签治理：
- **提案已创建但确认不够** → 继续追加确认即可
- **确认数够了但执行失败** → 提案还是未执行状态，可以重新调用 `executeUpgradeProposal`
- **执行成功但没人确认** → 不可能的，`executed = true` 只在执行成功后设置

### Q: 可以销毁旧实现合约吗？

不建议。虽然 Proxy 不依赖旧实现合约运行，但保留旧版本有助于：
- 验证历史交易
- Etherscan 上查看合约代码
- 审计回溯

---

## 部署命令速查

```bash
# ===== 首次部署 =====
forge script script/DeployUpgradeable.s.sol \
  --rpc-url sepolia --private-key $PRIVATE_KEY --broadcast --verify -vvvv

# ===== 升级合约 =====
export PROXY_ADDRESS=0x<你的代理地址>
forge script script/UpgradeToV2.s.sol \
  --rpc-url sepolia --private-key $PRIVATE_KEY --broadcast -vvvv

# ===== 手动升级（分步） =====
# 1. 部署 V2
forge create src/MultiSigWalletUpgradeable.sol:MultiSigWalletUpgradeable \
  --rpc-url sepolia --private-key $PRIVATE_KEY

# 2. 提提案
cast send $PROXY_ADDRESS "createUpgradeProposal(address)" <V2_ADDRESS> \
  --from <owner> --private-key $OWNER_KEY --rpc-url sepolia

# 3. 各 owner 确认
cast send $PROXY_ADDRESS "confirmUpgradeProposal(uint256)" <ID> \
  --from <owner> --private-key $OWNER_KEY --rpc-url sepolia

# 4. 检查阈值
cast call $PROXY_ADDRESS "canExecuteUpgrade(uint256)" <ID> --rpc-url sepolia

# 5. 执行升级
cast send $PROXY_ADDRESS "executeUpgradeProposal(uint256)" <ID> \
  --from <owner> --private-key $OWNER_KEY --rpc-url sepolia

# ===== 日常查询 =====
cast call $PROXY_ADDRESS "getOwners()" --rpc-url sepolia
cast call $PROXY_ADDRESS "getProposal(uint256)" <ID> --rpc-url sepolia
cast call $PROXY_ADDRESS "getBalance()" --rpc-url sepolia
```
