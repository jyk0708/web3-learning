package event

import (
	"encoding/json"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/zeromicro/go-zero/core/logx"

	"nft_auction_api/internal/model"
	"nft_auction_api/internal/repository"
	"nft_auction_api/internal/svc"
)

// ============================================================================
// 辅助方法
// ============================================================================

// saveEventLog 统一保存事件日志到 event_logs 表
func saveEventLog(svcCtx *svc.ServiceContext, ctx *EventContext, logData string) {
	logEvent := &model.EventLog{
		EventName:   ctx.EventName,
		PoolAddress: ctx.Log.Address.Hex(),
		TxHash:      ctx.Log.TxHash.Hex(),
		BlockNumber: ctx.Log.BlockNumber,
		LogData:     logData,
		RawData:     fmt.Sprintf(`{"tx":"%s","block":%d}`, ctx.Log.TxHash.Hex(), ctx.Log.BlockNumber),
	}
	repo := repository.NewEventLogRepository(svcCtx.DB)
	if err := repo.Create(ctx.Context, logEvent); err != nil {
		logx.Errorf("[%s] Failed to save event log: %v", ctx.EventName, err)
	}
}

// ============================================================================
// AuctionCreatedListener 拍卖创建事件
// ============================================================================
type AuctionCreatedListener struct {
	svcCtx *svc.ServiceContext
}

func (l *AuctionCreatedListener) Name() string { return "AuctionCreatedListener" }

func (l *AuctionCreatedListener) Handle(ctx *EventContext) error {
	if l.svcCtx == nil {
		return fmt.Errorf("svcCtx is nil")
	}
	values := ctx.Values
	if len(values) < 7 {
		return fmt.Errorf("invalid event values length: %d", len(values))
	}

	auctionID := values[0].(*big.Int)
	nftContract := values[1].(common.Address)
	seller := values[2].(common.Address)
	tokenID := values[3].(*big.Int)
	tokenAddress := values[4].(common.Address)
	startingPriceInUSD := values[5].(*big.Int)
	durationInDays := values[6].(*big.Int)

	auctionIDStr := auctionID.String()
	nftContractStr := nftContract.Hex()
	tokenIDStr := tokenID.String()
	tokenAddressStr := tokenAddress.Hex()
	startingPriceStr := startingPriceInUSD.String()
	durationInDaysStr := durationInDays.String()

	logx.Infof("[%s] auctionId=%s, seller=%s, nft=%s, tokenId=%s, tokenAddr=%s, startPrice=%s, duration=%s days",
		l.Name(), auctionIDStr, seller.Hex(), nftContractStr, tokenIDStr, tokenAddressStr, startingPriceStr, durationInDaysStr)

	auction := &model.Auction{
		AuctionID:          auctionIDStr,
		Seller:             seller.Hex(),
		NftContract:        nftContractStr,
		TokenID:            tokenIDStr,
		TokenAddress:       tokenAddressStr,
		StartingPriceUSD:   startingPriceStr,
		DurationInDays:     durationInDays.Uint64(),
		Status:             model.AuctionStatusCreated,
		TxHash:             ctx.Log.TxHash.Hex(),
		BlockNumber:        ctx.Log.BlockNumber,
		HighestBidInUSD:    "0",
		HighestBidAmount:   "0",
		HighestBidder:      "",
		HighestBidderToken: "",
	}

	repo := repository.NewAuctionRepository(l.svcCtx.DB)
	if err := repo.Create(ctx.Context, auction); err != nil {
		logx.Errorf("[%s] Failed to save auction: %v", l.Name(), err)
		return err
	}

	logData := fmt.Sprintf(`{"auctionId":"%s","seller":"%s","nftContract":"%s","tokenId":"%s","tokenAddress":"%s","startingPriceUSD":"%s","durationInDays":%s}`,
		auctionIDStr, seller.Hex(), nftContractStr, tokenIDStr, tokenAddressStr, startingPriceStr, durationInDaysStr)
	saveEventLog(l.svcCtx, ctx, logData)

	return nil
}

// ============================================================================
// AuctionStartedListener 拍卖开始事件
// ============================================================================
type AuctionStartedListener struct {
	svcCtx *svc.ServiceContext
}

func (l *AuctionStartedListener) Name() string { return "AuctionStartedListener" }

func (l *AuctionStartedListener) Handle(ctx *EventContext) error {
	if l.svcCtx == nil {
		return fmt.Errorf("svcCtx is nil")
	}
	values := ctx.Values
	if len(values) < 3 {
		return fmt.Errorf("invalid event values length: %d", len(values))
	}

	auctionID := values[0].(*big.Int)
	startTime := values[1].(*big.Int)
	endTime := values[2].(*big.Int)

	auctionIDStr := auctionID.String()
	logx.Infof("[%s] auctionId=%s, startTime=%s, endTime=%s",
		l.Name(), auctionIDStr, startTime.String(), endTime.String())

	repo := repository.NewAuctionRepository(l.svcCtx.DB)
	if err := repo.UpdateStart(ctx.Context, auctionIDStr, startTime.Uint64(), endTime.Uint64()); err != nil {
		logx.Errorf("[%s] Failed to update auction start: %v", l.Name(), err)
		return err
	}

	if err := repo.UpdateStatus(ctx.Context, auctionIDStr, model.AuctionStatusActive); err != nil {
		logx.Errorf("[%s] Failed to update auction status: %v", l.Name(), err)
		return err
	}

	logData := fmt.Sprintf(`{"auctionId":"%s","startTime":%s,"endTime":%s}`,
		auctionIDStr, startTime.String(), endTime.String())
	saveEventLog(l.svcCtx, ctx, logData)

	return nil
}

// ============================================================================
// BidAuctionListener 出价事件
// ============================================================================
type BidAuctionListener struct {
	svcCtx *svc.ServiceContext
}

func (l *BidAuctionListener) Name() string { return "BidAuctionListener" }

func (l *BidAuctionListener) Handle(ctx *EventContext) error {
	if l.svcCtx == nil {
		return fmt.Errorf("svcCtx is nil")
	}
	values := ctx.Values
	if len(values) < 3 {
		return fmt.Errorf("invalid event values length: %d", len(values))
	}

	auctionID := values[0].(*big.Int)
	bidder := values[1].(common.Address)
	bidPriceInUSD := values[2].(*big.Int)

	auctionIDStr := auctionID.String()
	logx.Infof("[%s] auctionId=%s, bidder=%s, bidPriceUSD=%s",
		l.Name(), auctionIDStr, bidder.Hex(), bidPriceInUSD.String())

	// 从交易 input 解析 bidPrice 和 tokenAddress（合约 Bid(uint256,uint256,address) 方法参数）
	var bidAmountStr, tokenAddressStr string
	if len(ctx.TxInput) >= 4 {
		method, ok := ctx.ParsedABI.Methods["Bid"]
		if ok && len(method.Inputs) >= 2 {
			args, err := method.Inputs.Unpack(ctx.TxInput[4:])
			if err == nil && len(args) >= 2 {
				if bp, ok := args[0].(*big.Int); ok {
					bidAmountStr = bp.String()
				}
				if ta, ok := args[1].(common.Address); ok {
					tokenAddressStr = ta.Hex()
				}
			}
		}
	}

	// 如果无法从 input 解析（兜底），从数据库读取拍卖记录中的 tokenAddress
	if tokenAddressStr == "" {
		auctionRepo := repository.NewAuctionRepository(l.svcCtx.DB)
		auction, err := auctionRepo.GetByAuctionID(ctx.Context, auctionIDStr)
		if err == nil && auction != nil {
			tokenAddressStr = auction.TokenAddress
		}
	}

	// 记录出价
	bid := &model.Bid{
		AuctionID:   auctionIDStr,
		Bidder:      bidder.Hex(),
		BidAmount:   bidAmountStr,
		BidPriceUSD: bidPriceInUSD.String(),
		TxHash:      ctx.Log.TxHash.Hex(),
		BlockNumber: ctx.Log.BlockNumber,
	}

	bidRepo := repository.NewBidRepository(l.svcCtx.DB)
	if err := bidRepo.Create(ctx.Context, bid); err != nil {
		logx.Errorf("[%s] Failed to create bid: %v", l.Name(), err)
		return err
	}

	// 同步更新拍卖表的最高出价
	auctionRepo := repository.NewAuctionRepository(l.svcCtx.DB)
	if err := auctionRepo.UpdateHighestBid(ctx.Context, auctionIDStr, bidAmountStr, bidPriceInUSD.String(), bidder.Hex(), tokenAddressStr); err != nil {
		logx.Errorf("[%s] Failed to update highest bid: %v", l.Name(), err)
		return err
	}

	logData := fmt.Sprintf(`{"auctionId":"%s","bidder":"%s","bidPriceUSD":"%s","bidAmount":"%s","tokenAddress":"%s"}`,
		auctionIDStr, bidder.Hex(), bidPriceInUSD.String(), bidAmountStr, tokenAddressStr)
	saveEventLog(l.svcCtx, ctx, logData)

	return nil
}

// ============================================================================
// RefundAuctionListener 退款事件
// ============================================================================
type RefundAuctionListener struct {
	svcCtx *svc.ServiceContext
}

func (l *RefundAuctionListener) Name() string { return "RefundAuctionListener" }

func (l *RefundAuctionListener) Handle(ctx *EventContext) error {
	if l.svcCtx == nil {
		return fmt.Errorf("svcCtx is nil")
	}
	values := ctx.Values
	if len(values) < 3 {
		return fmt.Errorf("invalid event values length: %d", len(values))
	}

	auctionID := values[0].(*big.Int)
	bidder := values[1].(common.Address)
	refundAmount := values[2].(*big.Int)

	logx.Infof("[%s] auctionId=%s, bidder=%s, refundAmount=%s",
		l.Name(), auctionID.String(), bidder.Hex(), refundAmount.String())

	logData := fmt.Sprintf(`{"auctionId":"%s","bidder":"%s","refundAmount":"%s"}`,
		auctionID.String(), bidder.Hex(), refundAmount.String())
	saveEventLog(l.svcCtx, ctx, logData)

	return nil
}

// ============================================================================
// AuctionEndedListener 拍卖结束事件
// ============================================================================
type AuctionEndedListener struct {
	svcCtx *svc.ServiceContext
}

func (l *AuctionEndedListener) Name() string { return "AuctionEndedListener" }

func (l *AuctionEndedListener) Handle(ctx *EventContext) error {
	if l.svcCtx == nil {
		return fmt.Errorf("svcCtx is nil")
	}
	values := ctx.Values
	if len(values) < 3 {
		return fmt.Errorf("invalid event values length: %d", len(values))
	}

	auctionID := values[0].(*big.Int)
	winner := values[1].(common.Address)
	highestBidInUSD := values[2].(*big.Int)

	auctionIDStr := auctionID.String()
	logx.Infof("[%s] auctionId=%s, winner=%s, highestBidUSD=%s",
		l.Name(), auctionIDStr, winner.Hex(), highestBidInUSD.String())

	repo := repository.NewAuctionRepository(l.svcCtx.DB)

	// 更新状态为 Ended
	if err := repo.UpdateStatus(ctx.Context, auctionIDStr, model.AuctionStatusEnded); err != nil {
		logx.Errorf("[%s] Failed to update auction status: %v", l.Name(), err)
		return err
	}

	// 更新最高出价者信息为最终胜者
	auction, err := repo.GetByAuctionID(ctx.Context, auctionIDStr)
	if err == nil && auction != nil {
		_ = repo.UpdateHighestBid(ctx.Context, auctionIDStr, auction.HighestBidAmount,
			highestBidInUSD.String(), winner.Hex(), auction.HighestBidderToken)
	}

	logData := fmt.Sprintf(`{"auctionId":"%s","winner":"%s","highestBidInUSD":"%s"}`,
		auctionIDStr, winner.Hex(), highestBidInUSD.String())
	saveEventLog(l.svcCtx, ctx, logData)

	return nil
}

// ============================================================================
// AuctionCanceledListener 拍卖取消事件
// ============================================================================
type AuctionCanceledListener struct {
	svcCtx *svc.ServiceContext
}

func (l *AuctionCanceledListener) Name() string { return "AuctionCanceledListener" }

func (l *AuctionCanceledListener) Handle(ctx *EventContext) error {
	if l.svcCtx == nil {
		return fmt.Errorf("svcCtx is nil")
	}
	values := ctx.Values
	if len(values) < 3 {
		return fmt.Errorf("invalid event values length: %d", len(values))
	}

	auctionID := values[0].(*big.Int)
	seller := values[1].(common.Address)
	tokenID := values[2].(*big.Int)

	auctionIDStr := auctionID.String()
	logx.Infof("[%s] auctionId=%s, seller=%s, tokenId=%s",
		l.Name(), auctionIDStr, seller.Hex(), tokenID.String())

	repo := repository.NewAuctionRepository(l.svcCtx.DB)
	if err := repo.UpdateStatus(ctx.Context, auctionIDStr, model.AuctionStatusCanceled); err != nil {
		logx.Errorf("[%s] Failed to update auction status: %v", l.Name(), err)
		return err
	}

	logData := fmt.Sprintf(`{"auctionId":"%s","seller":"%s","tokenId":"%s"}`,
		auctionIDStr, seller.Hex(), tokenID.String())
	saveEventLog(l.svcCtx, ctx, logData)

	return nil
}

// ============================================================================
// ListenerInit 用于初始化所有监听器（注入 svcCtx）
// ============================================================================

// RegisterAllListeners 注册所有拍卖相关的监听器
// 返回一个 map，键是事件名，值是监听器实例
func RegisterAllListeners(svcCtx *svc.ServiceContext) map[string]EventListener {
	listeners := make(map[string]EventListener)

	listeners["AuctionCreated"] = &AuctionCreatedListener{svcCtx: svcCtx}
	listeners["AuctionStarted"] = &AuctionStartedListener{svcCtx: svcCtx}
	listeners["BidAuction"] = &BidAuctionListener{svcCtx: svcCtx}
	listeners["RefundAuction"] = &RefundAuctionListener{svcCtx: svcCtx}
	listeners["AuctionEnded"] = &AuctionEndedListener{svcCtx: svcCtx}
	listeners["AuctionCanceled"] = &AuctionCanceledListener{svcCtx: svcCtx}

	return listeners
}

// 确保 json 包被引用（format logData 中使用了）
var _ = json.Marshal
