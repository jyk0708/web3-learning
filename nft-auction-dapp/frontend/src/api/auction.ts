import request from '../utils/request'

// 获取拍卖列表
export function listAuctions(params?: { status?: number; page?: number; pageSize?: number }) {
  return request.get('/api/auctions', { params })
}

// 获取拍卖详情
export function getAuction(id: string) {
  return request.get(`/api/auctions/${id}`)
}

// 创建拍卖
export function createAuction(data: {
  nftContract: string
  tokenId: string
  tokenAddress: string
  startingPrice: string
  durationInDays: number
}) {
  return request.post('/api/createAuction', data)
}

// 开始拍卖
export function startAuction(auctionId: string) {
  return request.post('/api/startAuction', { auctionId })
}

// 结束拍卖
export function endAuction(auctionId: string) {
  return request.post('/api/endAuction', { auctionId })
}

// 取消拍卖
export function cancelAuction(auctionId: string) {
  return request.post('/api/cancelAuction', { auctionId })
}

// 竞拍
export function bidAuction(data: { auctionId: string; tokenAddress: string; bidPrice: string }) {
  return request.post('/api/bidAuction', data)
}

// Mock NFT
export function mockNft() {
  return request.post('/api/mock/nft')
}

// 查询代币 USD 价格
export function getPrice2Usd(tokenAddress: string, amount: string) {
  return request.get(`/api/price2usd/${tokenAddress}/${amount}`)
}

// 设置价格源
export function setPriceFeed(data: { tokenAddress: string; priceFeedAddress: string }) {
  return request.post('/api/setPriceFeed', data)
}
