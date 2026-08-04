package api

import (
	"fmt"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"multisig-wallet/back/contract"
)

// Handler API 处理器
type Handler struct {
	wallet *contract.WalletService
}

// NewHandler 创建处理器
func NewHandler(wallet *contract.WalletService) *Handler {
	return &Handler{wallet: wallet}
}

// Response 通用响应
type Response struct {
	Code int         `json:"code"`
	Data interface{} `json:"data,omitempty"`
	Msg  string      `json:"msg,omitempty"`
}

func respondSuccess(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, Response{Code: 0, Data: data, Msg: "success"})
}

func respondError(c *gin.Context, httpCode int, err error) {
	c.JSON(httpCode, Response{Code: -1, Msg: err.Error()})
}

// getSenderAddress 从请求中获取发送者地址（优先从 header，其次从 query，最后使用默认）
func (h *Handler) getSenderAddress(c *gin.Context) string {
	// 从 header 获取
	address := c.GetHeader("X-Owner-Address")
	if address != "" {
		return address
	}
	// 从 query 获取
	address = c.Query("owner")
	if address != "" {
		return address
	}
	// 从 body 获取（如果有 owner 字段）
	// 返回空字符串，让 wallet 服务使用默认 key
	return ""
}

// ------------------ 系统 API ------------------

// GetAvailableOwners 获取可用的 owner 列表（从合约动态获取，匹配配置的私钥）
func (h *Handler) GetAvailableOwners(c *gin.Context) {
	owners, err := h.wallet.GetAvailableOwners()
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, owners)
}

// ------------------ 所有者管理 API ------------------

// GetOwners 获取所有所有者
func (h *Handler) GetOwners(c *gin.Context) {
	owners, err := h.wallet.GetOwners()
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, owners)
}

// GetOwnerCount 获取所有者数量
func (h *Handler) GetOwnerCount(c *gin.Context) {
	count, err := h.wallet.GetOwnerCount()
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, count)
}

// IsOwner 检查是否是所有者
func (h *Handler) IsOwner(c *gin.Context) {
	address := c.Query("address")
	if address == "" {
		respondError(c, http.StatusBadRequest, fmt.Errorf("address is required"))
		return
	}
	isOwner, err := h.wallet.IsOwner(address)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, isOwner)
}

// GetThreshold 获取确认阈值
func (h *Handler) GetThreshold(c *gin.Context) {
	threshold, err := h.wallet.GetThreshold()
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, threshold)
}

// AddOwnerRequest 添加所有者请求
type AddOwnerRequest struct {
	Owner  string `json:"owner" binding:"required"`
	Sender string `json:"sender"` // 可选，发送者地址
}

// AddOwner 添加所有者
func (h *Handler) AddOwner(c *gin.Context) {
	var req AddOwnerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}
	senderAddress := req.Sender
	if senderAddress == "" {
		senderAddress = h.getSenderAddress(c)
	}
	txHash, err := h.wallet.AddOwner(req.Owner, senderAddress)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, gin.H{"txHash": txHash})
}

// RemoveOwnerRequest 移除所有者请求
type RemoveOwnerRequest struct {
	Owner  string `json:"owner" binding:"required"`
	Sender string `json:"sender"` // 可选，发送者地址
}

// RemoveOwner 移除所有者
func (h *Handler) RemoveOwner(c *gin.Context) {
	var req RemoveOwnerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}
	senderAddress := req.Sender
	if senderAddress == "" {
		senderAddress = h.getSenderAddress(c)
	}
	txHash, err := h.wallet.RemoveOwner(req.Owner, senderAddress)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, gin.H{"txHash": txHash})
}

// ChangeThresholdRequest 改变阈值请求
type ChangeThresholdRequest struct {
	Threshold uint64 `json:"threshold" binding:"required"`
	Sender    string `json:"sender"` // 可选，发送者地址
}

// ChangeThreshold 改变阈值
func (h *Handler) ChangeThreshold(c *gin.Context) {
	var req ChangeThresholdRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}
	senderAddress := req.Sender
	if senderAddress == "" {
		senderAddress = h.getSenderAddress(c)
	}
	txHash, err := h.wallet.ChangeThreshold(req.Threshold, senderAddress)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, gin.H{"txHash": txHash})
}

// ------------------ 提案管理 API ------------------

// GetProposalCount 获取提案数量
func (h *Handler) GetProposalCount(c *gin.Context) {
	count, err := h.wallet.GetProposalCount()
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, count)
}

// GetProposal 获取提案详情
func (h *Handler) GetProposal(c *gin.Context) {
	indexStr := c.Param("index")
	index, err := strconv.ParseUint(indexStr, 10, 64)
	if err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}
	proposal, err := h.wallet.GetProposal(index)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, proposal)
}

// CreateProposalRequest 创建提案请求
type CreateProposalRequest struct {
	To     string `json:"to" binding:"required"`
	Value  uint64 `json:"value"`
	Data   string `json:"data"`
	Sender string `json:"sender"` // 可选，发送者地址
}

// CreateProposal 创建提案
func (h *Handler) CreateProposal(c *gin.Context) {
	var req CreateProposalRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}
	senderAddress := req.Sender
	if senderAddress == "" {
		senderAddress = h.getSenderAddress(c)
	}
	txHash, err := h.wallet.CreateProposal(req.To, req.Value, req.Data, senderAddress)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, gin.H{"txHash": txHash})
}

// ------------------ 确认与执行 API ------------------

// ConfirmTxRequest 确认交易请求
type ConfirmTxRequest struct {
	Sender string `json:"sender"` // 可选，发送者地址
}

// ConfirmTx 确认交易
func (h *Handler) ConfirmTx(c *gin.Context) {
	indexStr := c.Param("index")
	index, err := strconv.ParseUint(indexStr, 10, 64)
	if err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}

	var req ConfirmTxRequest
	// 尝试解析 JSON body（可能没有 body）
	_ = c.ShouldBindJSON(&req)

	senderAddress := req.Sender
	if senderAddress == "" {
		senderAddress = h.getSenderAddress(c)
	}

	txHash, err := h.wallet.ConfirmTx(index, senderAddress)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, gin.H{"txHash": txHash})
}

// RevokeConfirmTxRequest 撤销确认请求
type RevokeConfirmTxRequest struct {
	Sender string `json:"sender"` // 可选，发送者地址
}

// RevokeConfirmTx 撤销确认
func (h *Handler) RevokeConfirmTx(c *gin.Context) {
	indexStr := c.Param("index")
	index, err := strconv.ParseUint(indexStr, 10, 64)
	if err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}

	var req RevokeConfirmTxRequest
	_ = c.ShouldBindJSON(&req)

	senderAddress := req.Sender
	if senderAddress == "" {
		senderAddress = h.getSenderAddress(c)
	}

	txHash, err := h.wallet.RevokeConfirmTx(index, senderAddress)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, gin.H{"txHash": txHash})
}

// IsTransactionConfirmed 检查是否已确认
func (h *Handler) IsTransactionConfirmed(c *gin.Context) {
	indexStr := c.Query("index")
	confirmer := c.Query("confirmer")
	index, err := strconv.ParseUint(indexStr, 10, 64)
	if err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}
	confirmed, err := h.wallet.IsTransactionConfirmed(index, confirmer)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, confirmed)
}

// GetConfirmationCount 获取确认数量
func (h *Handler) GetConfirmationCount(c *gin.Context) {
	indexStr := c.Param("index")
	index, err := strconv.ParseUint(indexStr, 10, 64)
	if err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}
	count, err := h.wallet.GetConfirmationCount(index)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, count)
}

// GetConfirmers 获取提案的所有确认人列表
func (h *Handler) GetConfirmers(c *gin.Context) {
	indexStr := c.Param("index")
	index, err := strconv.ParseUint(indexStr, 10, 64)
	if err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}
	confirmers, err := h.wallet.GetConfirmers(index)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, confirmers)
}

// CanExecute 检查是否可执行
func (h *Handler) CanExecute(c *gin.Context) {
	indexStr := c.Param("index")
	index, err := strconv.ParseUint(indexStr, 10, 64)
	if err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}
	canExec, err := h.wallet.CanExecute(index)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, canExec)
}

// ExecuteTxRequest 执行交易请求
type ExecuteTxRequest struct {
	Sender string `json:"sender"` // 可选，发送者地址
}

// ExecuteTx 执行交易
func (h *Handler) ExecuteTx(c *gin.Context) {
	indexStr := c.Param("index")
	index, err := strconv.ParseUint(indexStr, 10, 64)
	if err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}

	var req ExecuteTxRequest
	_ = c.ShouldBindJSON(&req)

	senderAddress := req.Sender
	if senderAddress == "" {
		senderAddress = h.getSenderAddress(c)
	}

	txHash, err := h.wallet.ExecuteTx(index, senderAddress)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, gin.H{"txHash": txHash})
}

// ------------------ 其他 API ------------------

// GetBalance 获取合约余额
func (h *Handler) GetBalance(c *gin.Context) {
	balance, err := h.wallet.GetBalance()
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, balance)
}

// Version 获取版本号
func (h *Handler) Version(c *gin.Context) {
	version, err := h.wallet.Version()
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, version)
}

// IsPaused 检查是否暂停
func (h *Handler) IsPaused(c *gin.Context) {
	paused, err := h.wallet.IsPaused()
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}
	respondSuccess(c, paused)
}
