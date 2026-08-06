#!/bin/bash

# NFT Auction - 本地快速开始脚本
set -e

echo "=== NFT Auction Quick Start ==="
echo ""

# 检查 forge 是否安装
if ! command -v forge &> /dev/null; then
    echo "❌ Error: forge not found"
    echo "Install Foundry: https://book.getfoundry.sh/getting-started/installation.html"
    exit 1
fi

# 检查 anvil 是否安装
if ! command -v anvil &> /dev/null; then
    echo "❌ Error: anvil not found"
    echo "Install Foundry: https://book.getfoundry.sh/getting-started/installation.html"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# 1. 编译
echo "📦 Step 1: Compiling contracts..."
forge build
if [ $? -ne 0 ]; then
    echo "❌ Compilation failed"
    exit 1
fi
echo "✅ Compilation successful"

# 2. 启动 Anvil（后台运行）
echo "🚀 Step 2: Starting Anvil..."
ANVIL_PID=$(anvil --mnemonic "test test test test test test test test test test test junk" --port 8545 &> /dev/null & echo $!)
sleep 2

# 检查 Anvil 是否启动成功
if ! curl -s http://localhost:8545 > /dev/null 2>&1; then
    echo "❌ Anvil failed to start"
    kill $ANVIL_PID 2>/dev/null
    exit 1
fi
echo "✅ Anvil running on http://localhost:8545"

# 3. 部署合约
echo "📝 Step 3: Deploying contracts..."
forge script script/DeployLocal.s.sol --broadcast --rpc-url http://localhost:8545
if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    kill $ANVIL_PID 2>/dev/null
    exit 1
fi
echo "✅ Contracts deployed"

# 4. 运行测试
echo "🧪 Step 4: Running tests..."
forge test
if [ $? -ne 0 ]; then
    echo "❌ Tests failed"
    kill $ANVIL_PID 2>/dev/null
    exit 1
fi
echo "✅ All tests passed"

# 5. 获取部署地址
echo ""
echo "📋 Deployment Summary:"
echo "------------------------"
echo "Anvil HTTP: http://localhost:8545"
echo "Anvil PID: $ANVIL_PID"
echo ""
echo "Default accounts:"
echo "  Account 0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
echo "  Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
echo ""
echo "To stop Anvil: kill $ANVIL_PID"

# 生成 .env 文件
cat > .env.local << EOF
# Anvil Configuration
RPC_URL=http://localhost:8545
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
OWNER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
EOF

echo ""
echo "✅ Environment saved to .env.local"
echo ""
echo "🎉 Quick start completed!"
echo ""
echo "Next steps:"
echo "  1. Interact with contract using cast"
echo "  2. Connect your frontend to http://localhost:8545"
echo "  3. Deploy to testnet when ready"
