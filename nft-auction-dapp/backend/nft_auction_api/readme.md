# 生成 ABI 文件
```bash
# cd 到backend目录
jq '.abi' ../contract/out/NftAuctionUpgradeable.sol/NftAuctionUpgradeable.json > nft_auction_api/internal/contract/NftAuctionUpgradeable.abi.json
```
