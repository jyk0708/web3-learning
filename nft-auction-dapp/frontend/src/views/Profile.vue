<template>
  <div class="profile">
    <el-container>
      <el-header>
        <div class="header-content">
          <h1>个人中心</h1>
          <el-button @click="$router.push('/create')">
            <el-icon><Plus /></el-icon>创建拍卖
          </el-button>
        </div>
      </el-header>

      <el-main>
        <!-- 用户信息 -->
        <el-card class="user-card">
          <div class="user-info">
            <el-avatar :size="80" style="background-color: #409eff;">
              U
            </el-avatar>
            <div class="user-details">
              <h2>{{ walletAddress || '未连接钱包' }}</h2>
              <p>连接状态: {{ isConnected ? '已连接' : '未连接' }}</p>
              <el-button size="small" @click="connectWallet" :disabled="isConnected">
                {{ isConnected ? '已连接' : '连接钱包' }}
              </el-button>
            </div>
          </div>
        </el-card>

        <!-- 我的拍卖 -->
        <el-card class="my-auctions-card" style="margin-top: 20px;">
          <template #header>
            <div class="card-header">
              <span>我的拍卖</span>
            </div>
          </template>
          
          <el-tabs v-model="activeTab">
            <el-tab-pane label="进行中" name="active">
              <el-empty v-if="activeAuctions.length === 0" description="暂无进行中的拍卖" />
              <div v-else class="auction-list">
                <el-card v-for="auction in activeAuctions" :key="auction.auctionId" class="auction-item">
                  <div class="auction-info">
                    <h3>NFT #{{ auction.tokenId }}</h3>
                    <p>ID: {{ auction.auctionId }}</p>
                    <p>当前最高: {{ formatPrice(auction.highestBidInUSD) }} USD</p>
                    <p>结束时间: {{ formatTime(auction.endTime) }}</p>
                  </div>
                  <div class="auction-actions">
                    <el-button type="warning" @click="handleEnd(auction)" :disabled="!canEnd(auction)">
                      结束拍卖
                    </el-button>
                  </div>
                </el-card>
              </div>
            </el-tab-pane>

            <el-tab-pane label="待开始" name="pending">
              <el-empty v-if="pendingAuctions.length === 0" description="暂无待开始的拍卖" />
              <div v-else class="auction-list">
                <el-card v-for="auction in pendingAuctions" :key="auction.auctionId" class="auction-item">
                  <div class="auction-info">
                    <h3>NFT #{{ auction.tokenId }}</h3>
                    <p>ID: {{ auction.auctionId }}</p>
                    <p>起拍价: {{ formatPrice(auction.startingPriceUSD) }} USD</p>
                    <p>持续时间: {{ auction.durationInDays }} 天</p>
                  </div>
                  <div class="auction-actions">
                    <el-button type="success" @click="handleStart(auction)">开始拍卖</el-button>
                    <el-button @click="handleCancel(auction)">取消拍卖</el-button>
                  </div>
                </el-card>
              </div>
            </el-tab-pane>

            <el-tab-pane label="已结束/取消" name="ended">
              <el-empty v-if="endedAuctions.length === 0" description="暂无历史拍卖" />
              <div v-else class="auction-list">
                <el-card v-for="auction in endedAuctions" :key="auction.auctionId" class="auction-item">
                  <div class="auction-info">
                    <h3>NFT #{{ auction.tokenId }}</h3>
                    <p>ID: {{ auction.auctionId }}</p>
                    <p>状态: {{ getStatusText(auction.status) }}</p>
                    <p v-if="auction.status === 2">最终成交价: {{ formatPrice(auction.highestBidInUSD) }} USD</p>
                  </div>
                  <div class="auction-actions">
                    <el-button @click="$router.push(`/auction/${auction.auctionId}`)">查看详情</el-button>
                  </div>
                </el-card>
              </div>
            </el-tab-pane>
          </el-tabs>
        </el-card>
      </el-main>
    </el-container>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus } from '@element-plus/icons-vue'
import { listAuctions, startAuction, endAuction, cancelAuction } from '../api/auction'

const router = useRouter()
const activeTab = ref('active')
const walletAddress = ref('')
const allAuctions = ref<any[]>([])

const isConnected = computed(() => !!walletAddress.value)

const activeAuctions = computed(() => allAuctions.value.filter(a => a.status === 1))
const pendingAuctions = computed(() => allAuctions.value.filter(a => a.status === 0))
const endedAuctions = computed(() => allAuctions.value.filter(a => a.status === 2 || a.status === 3))
// 连接钱包
const connectWallet = async () => {
  if (typeof window.ethereum !== 'undefined') {
    try {
      const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' })
      walletAddress.value = accounts[0]
      ElMessage.success('钱包连接成功')
      fetchMyAuctions()
    } catch (error) {
      ElMessage.error('连接钱包失败')
    }
  } else {
    // Mock 模式
    walletAddress.value = '0x' + '1'.repeat(40)
    ElMessage.info('已连接模拟钱包')
    fetchMyAuctions()
  }
}

// 获取我的拍卖（简化处理，实际应按 seller 筛选）
const fetchMyAuctions = async () => {
  try {
    // 实际应添加 seller 筛选参数，这里暂时获取所有
    const data = await listAuctions({ status: 0, page: 1, pageSize: 100 })
    allAuctions.value = data.auctions.filter(a => walletAddress.value && a.seller.toLowerCase() === walletAddress.value.toLowerCase())
  } catch (error) {
    console.error('Failed to fetch auctions:', error)
    // 如果 API 不支持 seller 筛选，展示所有作为演示
    try {
      const data = await listAuctions({ page: 1, pageSize: 50 })
      allAuctions.value = data.auctions
    } catch (e) {
      ElMessage.error('获取拍卖列表失败')
    }
  }
}

// 操作方法
const handleStart = async (auction: any) => {
  try {
    await ElMessageBox.confirm('确认开始此拍卖？', '提示', { type: 'warning' })
    await startAuction(auction.auctionId)
    ElMessage.success('拍卖已开始')
    fetchMyAuctions()
  } catch (error) {
    if (error !== 'cancel') ElMessage.error('操作失败')
  }
}

const handleEnd = async (auction: any) => {
  try {
    await ElMessageBox.confirm('确认结束此拍卖？', '提示', { type: 'warning' })
    await endAuction(auction.auctionId)
    ElMessage.success('拍卖已结束')
    fetchMyAuctions()
  } catch (error) {
    if (error !== 'cancel') ElMessage.error('操作失败')
  }
}

const handleCancel = async (auction: any) => {
  try {
    await ElMessageBox.confirm('确认取消此拍卖？', '警告', { type: 'error' })
    await cancelAuction(auction.auctionId)
    ElMessage.success('拍卖已取消')
    fetchMyAuctions()
  } catch (error) {
    if (error !== 'cancel') ElMessage.error('操作失败')
  }
}

// 辅助函数
const canEnd = (auction: any) => {
  if (auction.status !== 1) return false
  const now = Math.floor(Date.now() / 1000)
  return now >= auction.endTime
}

const formatPrice = (price: string) => {
  if (!price || price === '0') return '0'
  const num = parseFloat(price)
  return isNaN(num) ? price : num.toFixed(2)
}

const formatTime = (timestamp: number) => {
  if (!timestamp) return '-'
  return new Date(timestamp * 1000).toLocaleString()
}

const getStatusText = (status: number) => {
  const map: any = { 0: '待开始', 1: '进行中', 2: '已结束', 3: '已取消' }
  return map[status] || '未知'
}

onMounted(() => {
  // 自动连接模拟钱包
  walletAddress.value = '0x' + '1'.repeat(40)
  fetchMyAuctions()
})
</script>

<style scoped>
.profile {
  min-height: 100vh;
  background-color: #f5f7fa;
}

.header-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.user-card {
  max-width: 600px;
  margin: 0 auto;
}

.user-info {
  display: flex;
  align-items: center;
  gap: 20px;
}

.user-details h2 {
  margin: 0 0 10px 0;
}

.my-auctions-card {
  max-width: 900px;
  margin: 0 auto;
}

.card-header {
  font-weight: bold;
}

.auction-list {
  display: flex;
  flex-direction: column;
  gap: 15px;
}

.auction-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.auction-info h3 {
  margin: 0 0 5px 0;
}

.auction-info p {
  margin: 2px 0;
  color: #606266;
  font-size: 13px;
}

.auction-actions {
  display: flex;
  gap: 10px;
}
</style>
