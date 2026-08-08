package handler

import (
	"context"
	"net/http"

	"nft_auction_api/internal/svc"

	"github.com/zeromicro/go-zero/rest/httpx"
)

// Handle 统一封装 go-zero handler 模板代码：
//  1. 解析请求 (httpx.Parse)
//  2. 创建 logic 实例
//  3. 调用 logic 方法
//  4. 返回统一格式的响应（配合 main 中的 setupUnifiedResponse 自动包装为 ApiResponse）
//
// 类型参数：
//   - Req  请求结构体（需带 path/form/json tag）
//   - Resp 响应数据结构体
//   - L    logic 实例类型
//
// 参数：
//   - svcCtx   服务上下文
//   - newLogic logic 构造函数，签名 func(ctx, svcCtx) L
//   - fn       logic 方法（method expression），签名 func(L, *Req) (*Resp, error)
//
// 示例：
//
//	Handle[types.GetPrice2USDReq, types.GetPrice2USDData](
//	    svcCtx, logic.NewPriceLogic, (*logic.PriceLogic).GetPrice2USD)

/**
 * @brief 统一封装 go-zero handler 模板代码
 * @param svcCtx 服务上下文
 * @param newLogic logic 构造函数，签名 func(ctx, svcCtx) L
 * @param fn logic 方法（method expression），签名 func(L, *Req) (*Resp, error)
 * @return http.HandlerFunc
 * @note 泛型参数 Req, Resp, L 分别对应请求结构体、响应数据结构体、logic 实例类型
 */
func Handle[Req any, Resp any, L any](
	svcCtx *svc.ServiceContext,
	newLogic func(context.Context, *svc.ServiceContext) L,
	fn func(L, *Req) (*Resp, error),
) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req Req
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		l := newLogic(r.Context(), svcCtx)
		resp, err := fn(l, &req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}
		httpx.OkJsonCtx(r.Context(), w, resp)
	}
}

// HandleNoReq 与 Handle 类似，但用于无请求体的接口（如 mock 数据生成）。
// fn 签名为 func(L) (*Resp, error)，不接收请求参数。
//
// 示例：
//
//	HandleNoReq[types.MockNftData](
//	    svcCtx, service.NewMockNftService, (*service.MockNftService).MockNft)
func HandleNoReq[Resp any, L any](
	svcCtx *svc.ServiceContext,
	newLogic func(context.Context, *svc.ServiceContext) L,
	fn func(L) (*Resp, error),
) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		l := newLogic(r.Context(), svcCtx)
		resp, err := fn(l)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}
		httpx.OkJsonCtx(r.Context(), w, resp)
	}
}
