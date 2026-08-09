package service

import (
	"context"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi/bind/v2"
	ethtypes "github.com/ethereum/go-ethereum/core/types"
	"github.com/zeromicro/go-zero/core/logx"

	"nft_auction_api/internal/model"
	"nft_auction_api/internal/repository"
	"nft_auction_api/internal/svc"
	"nft_auction_api/internal/types"
	"nft_auction_api/internal/util"
)

type ContractService struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewContractService(ctx context.Context, svcCtx *svc.ServiceContext) *ContractService {
	return &ContractService{
		Logger: logx.WithContext(ctx),
		ctx:    ctx,
		svcCtx: svcCtx,
	}
}

/**
 * @Description: 设置代币价格源
 *   等价于: cast send $AUCTION_ADDRESS "setPriceFeed(address,address)" \
 *           $TOKEN_ADDRESS $PRICE_FEED_ADDRESS --rpc-url $RPC_URL
 * @param req: 设置代币价格源请求
 * @return: 设置代币价格源结果
 */
func (s *ContractService) SetPriceFeed(req *types.SetPriceFeedReq) (*types.SetPriceFeedData, error) {
	tokenAddr, err := util.Hex2Address(req.TokenAddress)
	if err != nil {
		return nil, err
	}

	priceFeeAddr, err := util.Hex2Address(req.PriceFeedAddress)
	if err != nil {
		return nil, err
	}

	cc := s.svcCtx.ContractClient
	tx, _, err := cc.TransactAndWaitMined(s.ctx, cc.Contract, cc.ContractAddr, "setPriceFeed", "setPriceFeed", tokenAddr, priceFeeAddr)
	if err != nil {
		return nil, err
	}
	return &types.SetPriceFeedData{TxHash: tx.Hash().Hex()}, nil
}

// GetPrice2USD 调用合约查询代币兑换USD价格
// 等价于: cast call $AUCTION_ADDRESS "getPrice2USD(address,uint256)" $TOKEN_ADDRESS $AMOUNT --rpc-url $RPC_URL
func (s *ContractService) GetPrice2USD(req *types.GetPrice2USDReq) (*types.GetPrice2USDData, error) {
	// 校验代币地址
	tokenAddr, err := util.Hex2Address(req.TokenAddress)
	if err != nil {
		return nil, err
	}

	// 解析金额（uint256 可能超出 int64 范围，用 *big.Int）
	amount, err := util.GetUbigInt(req.Amount, 10)
	if err != nil {
		return nil, err
	}

	// 调用合约 view 方法: getPrice2USD(address,uint256) returns (bool, uint256)
	var results []any
	err = s.svcCtx.ContractClient.Contract.Call(
		&bind.CallOpts{Context: s.ctx},
		&results,
		"getPrice2USD",
		tokenAddr,
		amount,
	)
	if err != nil {
		return nil, fmt.Errorf("call getPrice2USD failed: %w", err)
	}
	if len(results) < 2 {
		return nil, fmt.Errorf("unexpected result length: %d", len(results))
	}

	// 解析返回值: results[0]=bool, results[1]=*big.Int
	success, ok := results[0].(bool)
	if !ok {
		return nil, fmt.Errorf("unexpected success type: %T", results[0])
	}
	price, ok := results[1].(*big.Int)
	if !ok {
		return nil, fmt.Errorf("unexpected price type: %T", results[1])
	}

	s.Infof("getPrice2USD token=%s amount=%s success=%v price=%s",
		req.TokenAddress, req.Amount, success, price.String())

	return &types.GetPrice2USDData{
		Success: success,
		Price:   price.String(),
	}, nil
}

/**
 * @Description: 创建拍卖
 *   等价于: cast send $AUCTION_ADDRESS "CreateAuction(address,uint256,address,uint256,uint256)" \
 *           $NFT_CONTRACT $TOKEN_ID $TOKEN_ADDRESS $STARTING_PRICE $DURATION_IN_DAYS --rpc-url $RPC_URL
 * @param req: 创建拍卖请求
 * @return: 创建拍卖数据（含交易哈希与拍卖ID）
 */
func (s *ContractService) CreateAuction(req *types.CreateAuctionReq) (*types.CreateAuctionData, error) {
	// 校验 NFT 合约地址
	nftContract, err := util.Hex2Address(req.NftContract)
	if err != nil {
		return nil, err
	}

	// 解析 tokenId（uint256 可能超出 int64 范围，用 *big.Int）
	tokenId, err := util.GetUbigInt(req.TokenId, 10)
	if err != nil {
		return nil, err
	}

	// 校验支付代币地址
	tokenAddress, err := util.Hex2Address(req.TokenAddress)
	if err != nil {
		return nil, err
	}

	// 解析起拍价（uint256）
	startingPrice, err := util.GetUbigInt(req.StartingPrice, 10)
	if err != nil {
		return nil, err
	}

	// 持续天数转 *big.Int
	durationInDays := new(big.Int).SetUint64(req.DurationInDays)

	// 发送交易并等待确认
	cc := s.svcCtx.ContractClient
	tx, receipt, err := cc.TransactAndWaitMined(s.ctx, cc.Contract, cc.ContractAddr, "CreateAuction", "CreateAuction",
		nftContract, tokenId, tokenAddress, startingPrice, durationInDays)
	if err != nil {
		return nil, err
	}

	// 从回执 logs 中解析 AuctionCreated 事件，提取 auctionId
	auctionId, err := s.parseAuctionId(receipt)
	if err != nil {
		return nil, fmt.Errorf("parse AuctionCreated event failed: %w", err)
	}

	txHash := tx.Hash().Hex()
	s.Infof("CreateAuction nftContract=%s tokenId=%s tokenAddress=%s price=%s days=%d tx=%s auctionId=%s",
		req.NftContract, req.TokenId, req.TokenAddress, req.StartingPrice, req.DurationInDays,
		txHash, auctionId)

	// 立即将拍卖数据写入数据库（同步方式，可靠），同时事件监听器也会写入，使用 OnConflict 处理
	auction := &model.Auction{
		AuctionID:          auctionId,
		Seller:             cc.Auth.From.Hex(),
		NftContract:        req.NftContract,
		TokenID:            req.TokenId,
		TokenAddress:       req.TokenAddress,
		StartingPriceUSD:   req.StartingPrice,
		HighestBidInUSD:    "0",
		HighestBidAmount:   "0",
		HighestBidder:      "",
		HighestBidderToken: "",
		DurationInDays:     req.DurationInDays,
		Status:             model.AuctionStatusCreated,
		TxHash:             txHash,
		BlockNumber:        receipt.BlockNumber.Uint64(),
	}
	auctionRepo := repository.NewAuctionRepository(s.svcCtx.DB)
	if err := auctionRepo.Upsert(s.ctx, auction); err != nil {
		s.Errorf("Failed to save auction to DB: %v (auctionId=%s)", err, auctionId)
		// 不返回错误，因为交易已经成功上链，只是本地存储失败
	} else {
		s.Infof("Auction saved to DB: auctionId=%s", auctionId)
	}

	// 记录事件日志
	s.saveEventLog("AuctionCreated", txHash, receipt.BlockNumber.Uint64(),
		fmt.Sprintf(`{"auctionId":"%s","seller":"%s","nftContract":"%s","tokenId":"%s","tokenAddress":"%s","startingPriceUSD":"%s"}`,
			auctionId, cc.Auth.From.Hex(), req.NftContract, req.TokenId, req.TokenAddress, req.StartingPrice))

	return &types.CreateAuctionData{
		AuctionId: auctionId,
		TxHash:    txHash,
	}, nil
}

// parseAuctionId 从交易回执的 logs 中解析 AuctionCreated 事件，提取 auctionId
func (s *ContractService) parseAuctionId(receipt *ethtypes.Receipt) (string, error) {
	for _, vlog := range receipt.Logs {
		// 跳过非本合约地址的 log（一个交易可能触发多个合约的事件）
		if vlog.Address != s.svcCtx.ContractClient.ContractAddr {
			continue
		}

		valuesMap := make(map[string]any)
		if err := s.svcCtx.ContractClient.Contract.UnpackLogIntoMap(valuesMap, "AuctionCreated", *vlog); err != nil {
			// 不是 AuctionCreated 事件，跳过
			continue
		}

		id, ok := valuesMap["auctionId"].(*big.Int)
		if !ok {
			continue
		}
		return id.String(), nil
	}
	return "", fmt.Errorf("AuctionCreated event not found in receipt logs, tx=%s", receipt.TxHash.Hex())
}

// saveEventLog 保存事件日志到数据库
func (s *ContractService) saveEventLog(eventName, txHash string, blockNumber uint64, logData string) {
	eventLog := &model.EventLog{
		EventName:   eventName,
		PoolAddress: s.svcCtx.ContractClient.ContractAddr.Hex(),
		TxHash:      txHash,
		BlockNumber: blockNumber,
		LogData:     logData,
	}
	repo := repository.NewEventLogRepository(s.svcCtx.DB)
	if err := repo.Create(s.ctx, eventLog); err != nil {
		s.Errorf("Failed to save event log: %v (event=%s, tx=%s)", err, eventName, txHash)
	}
}

// UpdateAuctionStatus 更新拍卖状态
func (s *ContractService) UpdateAuctionStatus(auctionId string, status model.AuctionStatus, extra map[string]any) {
	auctionRepo := repository.NewAuctionRepository(s.svcCtx.DB)
	updates := map[string]any{
		"status": status,
	}
	for k, v := range extra {
		updates[k] = v
	}
	if err := auctionRepo.UpdateFields(s.ctx, auctionId, updates); err != nil {
		s.Errorf("Failed to update auction status: %v (auctionId=%s)", err, auctionId)
	}
}

/**
 * @Description: 竞拍
 *   等价于: cast send $AUCTION_ADDRESS "BidAuction(uint256,address,uint256)" \
 *           $AUCTION_ID $TOKEN_ADDRESS $BID_PRICE --rpc-url $RPC_URL
 * @param req: 竞拍请求
 * @return: 竞拍数据（含交易哈希）
 */
func (s *ContractService) BidAuction(req *types.BidAuctionReq) (*types.BidAuctionData, error) {
	// 解析拍卖ID
	auctionId, err := util.GetUbigInt(req.AuctionId, 10)
	if err != nil {
		return nil, err
	}

	// 校验支付代币地址
	tokenAddress, err := util.Hex2Address(req.TokenAddress)
	if err != nil {
		return nil, err
	}

	// 解析出价金额
	bidPrice, err := util.GetUbigInt(req.BidPrice, 10)
	if err != nil {
		return nil, err
	}

	// 合约方法名为 Bid(uint256,uint256,address)
	cc := s.svcCtx.ContractClient
	tx, receipt, err := cc.TransactAndWaitMined(s.ctx, cc.Contract, cc.ContractAddr, "Bid", "Bid",
		auctionId, bidPrice, tokenAddress)
	if err != nil {
		return nil, err
	}

	txHash := tx.Hash().Hex()
	s.Infof("BidAuction auctionId=%s bidPrice=%s tokenAddress=%s tx=%s",
		req.AuctionId, req.BidPrice, req.TokenAddress, txHash)

	// 同步更新数据库：记录出价、更新拍卖最高出价
	bidRepo := repository.NewBidRepository(s.svcCtx.DB)
	bid := &model.Bid{
		AuctionID:   req.AuctionId,
		Bidder:      cc.Auth.From.Hex(),
		BidAmount:   req.BidPrice,
		BidPriceUSD: req.BidPrice,
		TxHash:      txHash,
		BlockNumber: receipt.BlockNumber.Uint64(),
	}
	if err := bidRepo.Create(s.ctx, bid); err != nil {
		s.Errorf("Failed to save bid to DB: %v", err)
	}

	s.UpdateAuctionStatus(req.AuctionId, model.AuctionStatusActive, map[string]any{
		"highest_bid_amount":   req.BidPrice,
		"highest_bid_in_usd":   req.BidPrice,
		"highest_bidder":       cc.Auth.From.Hex(),
		"highest_bidder_token": req.TokenAddress,
	})

	s.saveEventLog("BidAuction", txHash, receipt.BlockNumber.Uint64(),
		fmt.Sprintf(`{"auctionId":"%s","bidder":"%s","bidAmount":"%s","tokenAddress":"%s"}`,
			req.AuctionId, cc.Auth.From.Hex(), req.BidPrice, req.TokenAddress))

	return &types.BidAuctionData{
		TxHash: txHash,
	}, nil
}

/**
 * @Description: 开始拍卖
 *   等价于: cast send $AUCTION_ADDRESS "StartAuction(uint256)" $AUCTION_ID --rpc-url $RPC_URL
 * @param req: 开始拍卖请求
 * @return: 开始拍卖数据（含交易哈希）
 */
func (s *ContractService) StartAuction(req *types.StartAuctionReq) (*types.StartAuctionData, error) {
	auctionId, err := util.GetUbigInt(req.AuctionId, 10)
	if err != nil {
		return nil, err
	}

	cc := s.svcCtx.ContractClient
	tx, receipt, err := cc.TransactAndWaitMined(s.ctx, cc.Contract, cc.ContractAddr, "StartAuction", "StartAuction", auctionId)
	if err != nil {
		return nil, err
	}

	txHash := tx.Hash().Hex()
	s.Infof("StartAuction auctionId=%s tx=%s", req.AuctionId, txHash)

	// 同步更新数据库：拍卖状态改为 Active
	s.UpdateAuctionStatus(req.AuctionId, model.AuctionStatusActive, map[string]any{
		"start_time": receipt.BlockNumber.Uint64(),
		"end_time":   receipt.BlockNumber.Uint64() + 7*86400, // 默认7天后结束
	})

	s.saveEventLog("AuctionStarted", txHash, receipt.BlockNumber.Uint64(),
		fmt.Sprintf(`{"auctionId":"%s"}`, req.AuctionId))

	return &types.StartAuctionData{
		TxHash: txHash,
	}, nil
}

/**
 * @Description: 结束拍卖
 *   等价于: cast send $AUCTION_ADDRESS "EndAuction(uint256)" $AUCTION_ID --rpc-url $RPC_URL
 * @param req: 结束拍卖请求
 * @return: 结束拍卖数据（含交易哈希）
 */
func (s *ContractService) EndAuction(req *types.EndAuctionReq) (*types.EndAuctionData, error) {
	auctionId, err := util.GetUbigInt(req.AuctionId, 10)
	if err != nil {
		return nil, err
	}

	cc := s.svcCtx.ContractClient
	tx, receipt, err := cc.TransactAndWaitMined(s.ctx, cc.Contract, cc.ContractAddr, "EndAuction", "EndAuction", auctionId)
	if err != nil {
		return nil, err
	}

	txHash := tx.Hash().Hex()
	s.Infof("EndAuction auctionId=%s tx=%s", req.AuctionId, txHash)

	// 同步更新数据库：拍卖状态改为 Ended
	s.UpdateAuctionStatus(req.AuctionId, model.AuctionStatusEnded, map[string]any{
		"end_time": receipt.BlockNumber.Uint64(),
	})

	s.saveEventLog("AuctionEnded", txHash, receipt.BlockNumber.Uint64(),
		fmt.Sprintf(`{"auctionId":"%s"}`, req.AuctionId))

	return &types.EndAuctionData{
		TxHash: txHash,
	}, nil
}

/**
 * @Description: 取消拍卖
 *   等价于: cast send $AUCTION_ADDRESS "CancelAuction(uint256)" $AUCTION_ID --rpc-url $RPC_URL
 * @param req: 取消拍卖请求
 * @return: 取消拍卖数据（含交易哈希）
 */
func (s *ContractService) CancelAuction(req *types.CancelAuctionReq) (*types.CancelAuctionData, error) {
	auctionId, err := util.GetUbigInt(req.AuctionId, 10)
	if err != nil {
		return nil, err
	}

	cc := s.svcCtx.ContractClient
	tx, receipt, err := cc.TransactAndWaitMined(s.ctx, cc.Contract, cc.ContractAddr, "CancelAuction", "CancelAuction", auctionId)
	if err != nil {
		return nil, err
	}

	txHash := tx.Hash().Hex()
	s.Infof("CancelAuction auctionId=%s tx=%s", req.AuctionId, txHash)

	// 同步更新数据库：拍卖状态改为 Canceled
	s.UpdateAuctionStatus(req.AuctionId, model.AuctionStatusCanceled, nil)

	s.saveEventLog("AuctionCanceled", txHash, receipt.BlockNumber.Uint64(),
		fmt.Sprintf(`{"auctionId":"%s"}`, req.AuctionId))

	return &types.CancelAuctionData{
		TxHash: txHash,
	}, nil
}

/**
 * @Description: 获取拍卖合约版本
 * @return: 拍卖合约版本
 */
func (s *ContractService) GetVersion() (*types.GetVersionData, error) {
	var results []any
	err := s.svcCtx.ContractClient.Contract.Call(
		&bind.CallOpts{Context: s.ctx},
		&results,
		"version",
	)
	if err != nil {
		return nil, err
	}
	return &types.GetVersionData{
		Version: results[0].(string),
	}, nil
}
