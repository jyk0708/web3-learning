package service

import (
	"context"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/zeromicro/go-zero/core/logx"

	"nft_auction_api/internal/svc"
	"nft_auction_api/internal/types"
	"nft_auction_api/internal/util"
)

// mockERC721ABI 是 MockERC721 的精简 ABI（仅 mock 接口需要的方法）。
// 与 test/MockERC721.sol 的方法签名保持一致。
const mockERC721ABI = `[
  {"type":"function","name":"mint","inputs":[{"name":"to","type":"address"},{"name":"tokenId","type":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},
  {"type":"function","name":"setApprovalForAll","inputs":[{"name":"operator","type":"address"},{"name":"approved","type":"bool"}],"outputs":[],"stateMutability":"nonpayable"},
  {"type":"function","name":"ownerOf","inputs":[{"name":"tokenId","type":"uint256"}],"outputs":[{"name":"","type":"address"}],"stateMutability":"view"},
  {"type":"function","name":"isApprovedForAll","inputs":[{"name":"owner","type":"address"},{"name":"operator","type":"address"}],"outputs":[{"name":"","type":"bool"}],"stateMutability":"view"}
]`

// 测试环境默认支付代币与建议参数（WETH，部署脚本已为其配置价格源）
const (
	defaultTokenAddress   = "0x7cEb23fd6BC0Ad45D8E7BAe69B46C0BD06D2efEE"
	defaultStartingPrice  = "1000000000000000000" // 1 代币（最小单位数量）
	defaultDurationInDays = uint64(7)             // ≥5，满足合约 require
)

type MockNftService struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewMockNftService(ctx context.Context, svcCtx *svc.ServiceContext) *MockNftService {
	return &MockNftService{
		Logger: logx.WithContext(ctx),
		ctx:    ctx,
		svcCtx: svcCtx,
	}
}

/**
 * @Description: 生成一份可直接用于 CreateAuction 的 NFT 测试数据。
 *
 * 流程：
 *  1. 在已部署的 MockERC721 上铸造一个新 tokenId 给后端账户
 *  2. 授权拍卖合约操作后端账户的 NFT（CreateAuction 会 safeTransferFrom）
 *  3. 返回 NFT 合约地址、tokenId 及建议的支付参数
 *
 * 前置条件：yaml 中 Chain.MockNftContractAddr 已配置为 cast 部署的 MockERC721 地址。
 *
 * @return: MockNftData，字段可直接作为 CreateAuction 请求体
 */
func (s *MockNftService) MockNft() (*types.MockNftData, error) {
	mockAddr := s.svcCtx.Config.Chain.MockNftContractAddr
	if mockAddr == "" {
		return nil, fmt.Errorf("Chain.MockNftContractAddr 未配置，请先 cast 部署 MockERC721 并填入 yaml")
	}

	// 解析 MockERC721 合约地址
	mockContract, err := util.Hex2Address(mockAddr)
	if err != nil {
		return nil, err
	}

	// 解析精简 ABI 并创建 BoundContract（复用后端的弹性 Backend）
	parsed, err := abi.JSON(strings.NewReader(mockERC721ABI))
	if err != nil {
		return nil, fmt.Errorf("parse mock ERC721 ABI failed: %w", err)
	}
	mockBound := s.svcCtx.ContractClient.Backend.NewBoundContract(mockContract, parsed)

	// 用纳秒时间戳生成唯一 tokenId，避免与已 mint 的冲突
	tokenId := new(big.Int).SetUint64(uint64(time.Now().UnixNano()))

	cc := s.svcCtx.ContractClient
	backend := cc.Auth.From    // 后端账户 = NFT owner = CreateAuction 的 msg.sender（只读模板，安全）
	auction := cc.ContractAddr // 拍卖合约地址（被授权方）

	// 1. mint tokenId 给后端账户（TransactAndWaitMined 内部克隆 Auth + 等回执 + 查 revert 原因）
	if _, _, err := cc.TransactAndWaitMined(s.ctx, mockBound, mockContract, "mint", "mint", backend, tokenId); err != nil {
		return nil, err
	}

	// 2. 授权拍卖合约操作后端账户的所有 NFT（幂等，重复调用无副作用）
	if _, _, err := cc.TransactAndWaitMined(s.ctx, mockBound, mockContract, "setApprovalForAll", "setApprovalForAll", auction, true); err != nil {
		return nil, err
	}

	s.Infof("MockNft minted tokenId=%s to=%s nftContract=%s approved auction=%s",
		tokenId.String(), backend.Hex(), mockContract.Hex(), auction.Hex())

	return &types.MockNftData{
		NftContract:    mockContract.Hex(),
		TokenId:        tokenId.String(),
		TokenAddress:   defaultTokenAddress,
		StartingPrice:  defaultStartingPrice,
		DurationInDays: defaultDurationInDays,
	}, nil
}
