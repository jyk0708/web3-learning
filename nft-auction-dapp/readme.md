## Step1 启动anvil
```bash
anvil
```
启动日志：
```log
                             _   _ 
                            (_) | |
      __ _   _ __   __   __  _  | |
     / _` | | '_ \  \ \ / / | | | |
    | (_| | | | | |  \ V /  | | | |
     \__,_| |_| |_|   \_/   |_| |_|

    1.7.1 (4072e48705 2026-05-08T07:50:55.527285345Z)
    https://github.com/foundry-rs/foundry

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

1786069486

Genesis Number
==================

0

Listening on 127.0.0.1:8545
```


## Step 2 发布合约
```bash
# cd到合约目录
cd contract
# .env 配置
source .env
# 部署合约
forge create src/NftAuctionUpgradeable.sol:NftAuctionUpgradeable --broadcast --rpc-url $LOCAL_RPC_URL --private-key $PRIVATE_KEY --constructor-args $ETH_USD_FEED $USDC_USD_FEED
```
```log
== Logs ==
  Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  Implementation deployed: 0x5FbDB2315678afecb367f032d93F642f64180aa3
  Deploying Mock Aggregators...
  Proxy deployed: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
  ETH/USD feed set for: 0x7cEb23fd6BC0Ad45D8E7BAe69B46C0BD06D2efEE
  USDC/USD feed set for: 0x1c7d4b196AA478d0ee648F487818A9BB45DFe59d
  Owner verified: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  ETH/USD price feed working, 1 WETH = 20000000000000 USD
  USDC/USD price feed working, 1 USDC = 1 USD

   Deployment completed successfully!

## Setting up 1 EVM.

==========================

Chain 31337

Estimated gas price: 2.000000001 gwei

Estimated total gas used for script: 6781410

Estimated amount required: 0.01356282000678141 ETH

==========================

##### anvil-hardhat
✅  [Success] Hash: 0x3e96a20d97246216e4685d1c7fd8b44dfb815dd025551c2f2bf2c801587c8255     ⠂ [Pending] 0x22e4ed47f9d062bd6e9a3c3171cc234841498b7baa724a7a2d2de03ad338e821     
Contract: MockAggregator
Block: 4
Paid: 0.000037496107987624 ETH (53471 gas * 0.701241944 gwei)


##### anvil-hardhat
✅  [Success] Hash: 0x22e4ed47f9d062bd6e9a3c3171cc234841498b7baa724a7a2d2de03ad338e821     ⠂ [Pending] 0x9dc3e7d96ea9472052e693dba9e58a3d46bf9ccc7c6657d2c59af1536cffd885     
Contract: MockAggregator
Contract Address: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
Block: 2
Paid: 0.0005577087364608 ETH (616080 gas * 0.90525376 gwei)


##### anvil-hardhat
✅  [Success] Hash: 0x416489ef060acd7880a6f9a27b5d1533ebf8efa86e674ef7c3686c3ea3f0a994     ⠂ [Pending] 0x416489ef060acd7880a6f9a27b5d1533ebf8efa86e674ef7c3686c3ea3f0a994     
Contract: ERC1967Proxy
Contract Address: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
Block: 3
Paid: 0.000490848860241684 ETH (616068 gas * 0.796744613 gwei)


##### anvil-hardhat
✅  [Success] Hash: 0x92a1dc8a4c9911be395b646f82cf51ecf42246793eb68eb2ad0ff277cf423793     ⠂ [Pending] 0x92a1dc8a4c9911be395b646f82cf51ecf42246793eb68eb2ad0ff277cf423793     
Contract: ERC1967Proxy
Contract Address: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
Block: 4
Paid: 0.000168471974562112 ETH (240248 gas * 0.701241944 gwei)


##### anvil-hardhat
✅  [Success] Hash: 0x836c1190409c3966ab807ba5c774c96ab460b69ff3bb2019bb4231c4cbe207bf     ⠁ [00:00:00] [----------------------------------------------------] 0/6 txes (0.0s)Contract: NftAuctionUpgradeable
Contract Address: 0x5FbDB2315678afecb367f032d93F642f64180aa3
Block: 1
Paid: 0.003630451003630451 ETH (3630451 gas * 1.000000001 gwei)


##### anvil-hardhat
✅  [Success] Hash: 0x9dc3e7d96ea9472052e693dba9e58a3d46bf9ccc7c6657d2c59af1536cffd885  
Contract: ERC1967Proxy
Block: 4
Paid: 0.000037496107987624 ETH (53471 gas * 0.701241944 gwei)

✅ Sequence #1 on anvil-hardhat | Total Paid: 0.004922472790870295 ETH (5209789 gas * av 0.800954034 gwei)
g 0.800954034 gwei)


==========================

ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.

Transactions saved to: /mnt/e/Workspace/web3-learning/nft-auction-dapp/contract/broadcast/Deploy.s.sol/31337/run-latest.json

Sensitive values saved to: /mnt/e/Workspace/web3-learning/nft-auction-dapp/contract/cache/Deploy.s.sol/31337/run-latest.json
```

## Step 3 部署测试Nft代币
```bash
forge create test/MockERC721.sol:MockERC721 --broadcast --private-key $PRIVATE_KEY --rpc-url $LOCAL_RPC_URL --constructor-args "Test NFT" "TNFT"
```
```log
[⠢] Compiling...
No files changed, compilation skipped
Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Deployed to: 0x0165878A594ca255338adfa4d48449f69242Eb8F
Transaction hash: 0x9fea55af50ada7f2f2dd8c006e31b4e81c01b37127b6dceb073177f4ad3da93b
```

## Step 4 部署测试预言机
```bash
forge create test/MockAggregator.sol:MockAggregator --broadcast --private-key $PRIVATE_KEY --rpc-url $LOCAL_RPC_URL --constructor-args "100000000" "8"
```
```log
[⠢] Compiling...
No files changed, compilation skipped
Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Deployed to: 0x8A791620dd6260079BF849Dc5567aDC3F2FdC318
Transaction hash: 0x27631a513b63be5a980d7dc8b024070340487e985c1748d65b0b902dbbfe0771
```

## Step 5 后端服务，修改配置、启动服务
```bash
cd backend/nft_auction_api
cp .env.example .env
# 修改配置文件中的环境变量

# 启动服务
go run nft-auction-service.go
```

## Step 6 启动前端服务
```bash
cd frontend
pnpm install && pnpm dev
```






