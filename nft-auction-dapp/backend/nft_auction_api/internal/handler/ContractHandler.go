package handler

import (
	"net/http"
	"nft_auction_api/internal/service"
	"nft_auction_api/internal/svc"
	"nft_auction_api/internal/types"
)

// ==================== 查询接口 ====================

// ListAuctionsHandler 获取拍卖列表
// GET /api/auctions
func ListAuctionsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return Handle[types.ListAuctionsReq, types.ListAuctionsData](
		svcCtx, service.NewAuctionQueryService, (*service.AuctionQueryService).ListAuctions)
}

// GetAuctionHandler 获取拍卖详情
// GET /api/auctions/:auctionId
func GetAuctionHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return Handle[types.GetAuctionReq, types.GetAuctionData](
		svcCtx, service.NewAuctionQueryService, (*service.AuctionQueryService).GetAuction)
}

// GetPrice2USDHandler 查询代币兑换USD价格
// GET /api/price2usd/:tokenAddress/:amount
func GetPrice2USDHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return Handle[types.GetPrice2USDReq, types.GetPrice2USDData](
		svcCtx, service.NewContractService, (*service.ContractService).GetPrice2USD)
}

// ==================== 写操作接口 ====================

// CreateAuctionHandler 创建拍卖
// POST /api/createAuction
func CreateAuctionHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return Handle[types.CreateAuctionReq, types.CreateAuctionData](
		svcCtx, service.NewContractService, (*service.ContractService).CreateAuction)
}

// StartAuctionHandler 开始拍卖
// POST /api/startAuction
func StartAuctionHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return Handle[types.StartAuctionReq, types.StartAuctionData](
		svcCtx, service.NewContractService, (*service.ContractService).StartAuction)
}

// EndAuctionHandler 结束拍卖
// POST /api/endAuction
func EndAuctionHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return Handle[types.EndAuctionReq, types.EndAuctionData](
		svcCtx, service.NewContractService, (*service.ContractService).EndAuction)
}

// CancelAuctionHandler 取消拍卖
// POST /api/cancelAuction
func CancelAuctionHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return Handle[types.CancelAuctionReq, types.CancelAuctionData](
		svcCtx, service.NewContractService, (*service.ContractService).CancelAuction)
}

// BidAuctionHandler 竞拍
// POST /api/bidAuction
func BidAuctionHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return Handle[types.BidAuctionReq, types.BidAuctionData](
		svcCtx, service.NewContractService, (*service.ContractService).BidAuction)
}

// ==================== 配置接口 ====================

// SetPriceFeedHandler 设置代币价格源
// POST /api/setPriceFeed
func SetPriceFeedHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return Handle[types.SetPriceFeedReq, types.SetPriceFeedData](
		svcCtx, service.NewContractService, (*service.ContractService).SetPriceFeed)
}

/**
 * 获取合约版本
 */
func GetVersionHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return HandleNoReq[types.GetVersionData](
		svcCtx, service.NewContractService, (*service.ContractService).GetVersion)
}

// ==================== Mock 接口 ====================

// MockNftHandler 生成 NFT 测试数据（mint + approve），返回可直接用于 CreateAuction 的参数
// POST /api/mock/nft
func MockNftHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return HandleNoReq[types.MockNftData](
		svcCtx, service.NewMockNftService, (*service.MockNftService).MockNft)
}
