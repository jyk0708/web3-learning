import axios from 'axios'

const apiClient = axios.create({
  baseURL: '/',
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json'
  }
})

// 请求拦截器
apiClient.interceptors.request.use(
  config => {
    // 可以在这里添加 token 等认证信息
    return config
  },
  error => {
    return Promise.reject(error)
  }
)

// 响应拦截器
apiClient.interceptors.response.use(
  response => {
    const res = response.data
    // 统一响应格式处理
    if (res.status === 'error') {
      return Promise.reject(new Error(res.err || '未知错误'))
    }
    return res.data // 直接返回 data 字段
  },
  error => {
    return Promise.reject(error)
  }
)

export default apiClient
