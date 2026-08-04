import axios from 'axios'

const api = axios.create({
  baseURL: '/api/v1',
  timeout: 30000,
})

// 当前 owner 地址（通过 header 传递给后端）
let currentOwner = ''

// 设置当前 owner
export const setCurrentOwner = (owner) => {
  currentOwner = owner
  // 保存到 localStorage
  if (owner) {
    localStorage.setItem('currentOwner', owner)
  } else {
    localStorage.removeItem('currentOwner')
  }
}

// 获取当前 owner
export const getCurrentOwner = () => {
  if (currentOwner) {
    return currentOwner
  }
  // 从 localStorage 恢复
  return localStorage.getItem('currentOwner') || ''
}

// 请求拦截器 - 添加 owner header
api.interceptors.request.use(
  (config) => {
    const owner = getCurrentOwner()
    if (owner) {
      config.headers['X-Owner-Address'] = owner
    }
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

// 响应拦截器
api.interceptors.response.use(
  (response) => {
    const res = response.data
    if (res.code !== 0) {
      return Promise.reject(new Error(res.msg || '请求失败'))
    }
    return res.data
  },
  (error) => {
    // 处理 HTTP 错误响应
    if (error.response) {
      const errorData = error.response.data
      if (errorData && errorData.msg) {
        return Promise.reject(new Error(errorData.msg))
      }
      return Promise.reject(new Error(`请求失败 (${error.response.status})`))
    }
    // 处理网络错误
    if (error.request) {
      return Promise.reject(new Error('网络连接失败，请检查后端服务是否启动'))
    }
    return Promise.reject(error)
  }
)

// 系统 API
export const systemApi = {
  getAvailableOwners: () => api.get('/available-owners'),
}

// 所有者管理 API
export const ownerApi = {
  getOwners: () => api.get('/owners'),
  getOwnerCount: () => api.get('/owners/count'),
  isOwner: (address) => api.get('/owners/is-owner', { params: { address } }),
  getThreshold: () => api.get('/owners/threshold'),
  addOwner: (owner, sender) => {
    const data = { owner }
    if (sender) data.sender = sender
    return api.post('/owners', data)
  },
  removeOwner: (owner, sender) => {
    const data = { owner }
    if (sender) data.sender = sender
    return api.delete('/owners', { data })
  },
  changeThreshold: (threshold, sender) => {
    const data = { threshold }
    if (sender) data.sender = sender
    return api.put('/owners/threshold', data)
  },
}

// 提案管理 API
export const proposalApi = {
  getProposalCount: () => api.get('/proposals/count'),
  getProposal: (index) => api.get(`/proposals/${index}`),
  createProposal: (data) => {
    const payload = {
      to: data.to,
      value: data.value,
      data: data.txData,
    }
    if (data.sender) payload.sender = data.sender
    return api.post('/proposals', payload)
  },
  confirmTx: (index, sender) => {
    const data = {}
    if (sender) data.sender = sender
    return api.put(`/proposals/${index}/confirm`, data)
  },
  revokeConfirmTx: (index, sender) => {
    const data = {}
    if (sender) data.sender = sender
    return api.put(`/proposals/${index}/revoke`, data)
  },
  isTransactionConfirmed: (index, confirmer) =>
    api.get(`/proposals/${index}/confirmed`, { params: { index, confirmer } }),
  getConfirmationCount: (index) => api.get(`/proposals/${index}/confirmations`),
  getConfirmers: (index) => api.get(`/proposals/${index}/confirmers`),
  canExecute: (index) => api.get(`/proposals/${index}/can-execute`),
  executeTx: (index, sender) => {
    const data = {}
    if (sender) data.sender = sender
    return api.post(`/proposals/${index}/execute`, data)
  },
}

// 其他 API
export const walletApi = {
  getBalance: () => api.get('/balance'),
  getVersion: () => api.get('/version'),
  isPaused: () => api.get('/paused'),
}

export default api