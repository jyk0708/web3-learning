package service

import (
	"context"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/logx"

	"nft_auction_api/internal/model"
	"nft_auction_api/internal/repository"
	"nft_auction_api/internal/svc"
	"nft_auction_api/internal/types"
)

type AuctionQueryService struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewAuctionQueryService(ctx context.Context, svcCtx *svc.ServiceContext) *AuctionQueryService {
	return &AuctionQueryService{
		Logger: logx.WithContext(ctx),
		ctx:    ctx,
		svcCtx: svcCtx,
	}
}

// ListAuctions 获取拍卖列表
func (s *AuctionQueryService) ListAuctions(req *types.ListAuctionsReq) (*types.ListAuctionsData, error) {
	auctionRepo := repository.NewAuctionRepository(s.svcCtx.DB)

	// 转换状态: 0 表示全部，不传状态筛选；否则传具体状态
	var status model.AuctionStatus
	if req.Status != 0 {
		status = model.AuctionStatus(req.Status)
	}

	auctions, total, err := auctionRepo.List(s.ctx, status, req.Page, req.PageSize)
	if err != nil {
		return nil, fmt.Errorf("list auctions failed: %w", err)
	}

	items := make([]*types.AuctionItem, 0, len(auctions))
	for _, a := range auctions {
		items = append(items, convertAuctionModelToItem(a))
	}

	return &types.ListAuctionsData{
		Total:    total,
		Auctions: items,
		Page:     req.Page,
		PageSize: req.PageSize,
	}, nil
}

// GetAuction 获取拍卖详情和出价历史
func (s *AuctionQueryService) GetAuction(req *types.GetAuctionReq) (*types.GetAuctionData, error) {
	auctionRepo := repository.NewAuctionRepository(s.svcCtx.DB)
	bidRepo := repository.NewBidRepository(s.svcCtx.DB)

	auction, err := auctionRepo.GetByAuctionID(s.ctx, req.AuctionId)
	if err != nil {
		return nil, fmt.Errorf("get auction failed: %w", err)
	}

	bids, err := bidRepo.ListByAuctionID(s.ctx, req.AuctionId)
	if err != nil {
		return nil, fmt.Errorf("list bids failed: %w", err)
	}

	bidItems := make([]*types.BidItem, 0, len(bids))
	for _, b := range bids {
		bidItems = append(bidItems, convertBidModelToItem(b))
	}

	return &types.GetAuctionData{
		Auction: convertAuctionModelToItem(auction),
		Bids:    bidItems,
	}, nil
}

// convertAuctionModelToItem 将 model.Auction 转换为 types.AuctionItem
func convertAuctionModelToItem(a *model.Auction) *types.AuctionItem {
	return &types.AuctionItem{
		AuctionID:        a.AuctionID,
		Seller:           a.Seller,
		NftContract:      a.NftContract,
		TokenID:          a.TokenID,
		TokenAddress:     a.TokenAddress,
		StartingPriceUSD: a.StartingPriceUSD,
		HighestBidInUSD:  a.HighestBidInUSD,
		HighestBidAmount: a.HighestBidAmount,
		HighestBidder:    a.HighestBidder,
		DurationInDays:   a.DurationInDays,
		StartTime:        a.StartTime,
		EndTime:          a.EndTime,
		Status:           uint8(a.Status),
		TxHash:           a.TxHash,
		BlockNumber:      a.BlockNumber,
		CreatedAt:        a.CreatedAt.Format(time.RFC3339),
	}
}

// convertBidModelToItem 将 model.Bid 转换为 types.BidItem
func convertBidModelToItem(b *model.Bid) *types.BidItem {
	return &types.BidItem{
		ID:          b.ID,
		AuctionID:   b.AuctionID,
		Bidder:      b.Bidder,
		BidAmount:   b.BidAmount,
		BidPriceUSD: b.BidPriceUSD,
		TxHash:      b.TxHash,
		BlockNumber: b.BlockNumber,
		CreatedAt:   b.CreatedAt.Format(time.RFC3339),
	}
}
