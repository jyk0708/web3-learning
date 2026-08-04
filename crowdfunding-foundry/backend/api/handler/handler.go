package handler

import (
	"context"
	"math/big"
	"net/http"
	"time"

	"crowdfunding-foundry/api/service"

	"github.com/gin-gonic/gin"
)

type Handler struct {
	svc *service.ContractService
}

func NewHandler(svc *service.ContractService) *Handler {
	return &Handler{svc: svc}
}

type ApiResponse struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

func withTimeout(c *gin.Context, d time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(c.Request.Context(), d)
}

func (h *Handler) GetCampaignInfo(c *gin.Context) {
	ctx, cancel := withTimeout(c, 15*time.Second)
	defer cancel()

	info, err := h.svc.GetCampaignInfo(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ApiResponse{Code: 500, Message: err.Error()})
		return
	}

	c.JSON(http.StatusOK, ApiResponse{Code: 0, Message: "success", Data: info})
}

func (h *Handler) GetContributors(c *gin.Context) {
	ctx, cancel := withTimeout(c, 15*time.Second)
	defer cancel()

	contributors, err := h.svc.GetContributors(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ApiResponse{Code: 500, Message: err.Error()})
		return
	}

	c.JSON(http.StatusOK, ApiResponse{
		Code:    0,
		Message: "success",
		Data:    gin.H{"contributors": contributors, "count": len(contributors)},
	})
}

func (h *Handler) GetDonations(c *gin.Context) {
	ctx, cancel := withTimeout(c, 30*time.Second)
	defer cancel()

	donations, err := h.svc.GetDonations(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ApiResponse{Code: 500, Message: err.Error()})
		return
	}

	c.JSON(http.StatusOK, ApiResponse{Code: 0, Message: "success", Data: donations})
}

func (h *Handler) StartCampaign(c *gin.Context) {
	ctx, cancel := withTimeout(c, 60*time.Second)
	defer cancel()

	result, err := h.svc.StartCampaign(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ApiResponse{Code: 500, Message: err.Error()})
		return
	}

	c.JSON(http.StatusOK, ApiResponse{Code: 0, Message: "success", Data: result})
}

func (h *Handler) Contribute(c *gin.Context) {
	var req service.ContributeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ApiResponse{Code: 400, Message: "参数格式错误: " + err.Error()})
		return
	}

	amount, ok := new(big.Int).SetString(req.Amount, 10)
	if !ok {
		c.JSON(http.StatusBadRequest, ApiResponse{Code: 400, Message: "金额格式错误，应为数字字符串"})
		return
	}
	if amount.Sign() <= 0 {
		c.JSON(http.StatusBadRequest, ApiResponse{Code: 400, Message: "捐赠金额必须大于0"})
		return
	}

	ctx, cancel := withTimeout(c, 60*time.Second)
	defer cancel()

	result, err := h.svc.Contribute(ctx, amount)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ApiResponse{Code: 500, Message: err.Error()})
		return
	}

	c.JSON(http.StatusOK, ApiResponse{Code: 0, Message: "success", Data: result})
}

func (h *Handler) EndCampaign(c *gin.Context) {
	ctx, cancel := withTimeout(c, 60*time.Second)
	defer cancel()

	result, err := h.svc.EndCampaign(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ApiResponse{Code: 500, Message: err.Error()})
		return
	}

	c.JSON(http.StatusOK, ApiResponse{Code: 0, Message: "success", Data: result})
}

func (h *Handler) WithdrawFunds(c *gin.Context) {
	ctx, cancel := withTimeout(c, 60*time.Second)
	defer cancel()

	result, err := h.svc.WithdrawFunds(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ApiResponse{Code: 500, Message: err.Error()})
		return
	}

	c.JSON(http.StatusOK, ApiResponse{Code: 0, Message: "success", Data: result})
}

func (h *Handler) RefundDonations(c *gin.Context) {
	ctx, cancel := withTimeout(c, 60*time.Second)
	defer cancel()

	result, err := h.svc.RefundDonations(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ApiResponse{Code: 500, Message: err.Error()})
		return
	}

	c.JSON(http.StatusOK, ApiResponse{Code: 0, Message: "success", Data: result})
}

func (h *Handler) HealthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, ApiResponse{
		Code:    0,
		Message: "ok",
		Data:    gin.H{"timestamp": time.Now().Unix(), "version": "1.0.0"},
	})
}
