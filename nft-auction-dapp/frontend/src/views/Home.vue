<template>
  <div class="home">
    <el-container>
      <el-header>
        <div class="header-content">
          <h1>NFT 拍卖市场</h1>
          <div class="header-actions">
            <el-input
              v-model="searchQuery"
              placeholder="搜索..."
              style="width: 200px; margin-right: 10px;"
              clearable
            >
              <template #prefix>
                <el-icon><Search /></el-icon>
              </template>
            </el-input>
            <el-select v-model="statusFilter" placeholder="状态筛选" style="width: 120px; margin-right: 10px;" @change="fetchAuctions">
              <el-option label="全部" :value="0" />
              <el-option label="进行中" :value="1" />
              <el-option label="已结束" :value="2" />
              <el-option label="已取消" :value="3" />
            </el-select>
            <el-button type="primary" @click="$router.push('/create')">
              <el-icon><Plus /></el-icon>创建拍卖
            </el-button>
            <el-button @click="connectWallet">
              <el-icon><User /></el-icon>{{ walletAddress || '连接钱包' }}
            </el-button>
          </div>
        </div>
      </el-header>

      <el-main>
        <!-- 统计信息 -->
        <el-row :gutter="20" class="stats-row">
          <el-col :span="6">
            <el-card class="stat-card">
              <div class="stat-value">{{ stats.totalAuctions }}</div>
              <div class="stat-label">拍卖总数</div>
            </el-card>
          </el-col>
          <el-col :span="6">
            <el-card class="stat-card">
              <div class="stat-value">{{ stats.activeAuctions }}</div>
              <div class="stat-label">进行中</div>
            </el-card>
          </el-col>
          <el-col :span="6">
            <el-card class="stat-card">
              <div class="stat-value">{{ stats.totalBids }}</div>
              <div class="stat-label">出价总数</div>
            </el-card>
          </el-col>
          <el-col :span="6">
            <el-card class="stat-card">
              <div class="stat-value">${{ stats.tvl.toLocaleString() }}</div>
              <div class="stat-label">TVL</div>
            </el-card>
          </el-col>
        </el-row>

        <!-- 拍卖列表 -->
        <el-row :gutter="20" class="auctions-row" v-loading="loading">
          <el-col :span="8" v-for="auction in auctions" :key="auction.auctionId">
            <el-card class="auction-card" shadow="hover" @click="goToDetail(auction.auctionId)">
              <div class="nft-image">
                <el-image :src="getNftImage(auction)" fit="cover" class="image" />
              </div>
              <div class="auction-info">
                <h3>NFT #{{ auction.tokenId }}</h3>
                <p class="nft-contract">{{ formatAddress(auction.nftContract) }}</p>
                <el-divider />
                <div class="info-row">
                  <span class="label">起拍价</span>
                  <span class="value">{{ formatPrice(auction.startingPriceUSD) }} USD</span>
                </div>
                <div class="info-row highest" v-if="auction.highestBidInUSD !== '0'">
                  <span class="label">当前最高</span>
                  <span class="value">{{ formatPrice(auction.highestBidInUSD) }} USD</span>
                </div>
                <div class="info-row">
                  <span class="label">状态</span>
                  <el-tag :type="getStatusTagType(auction.status)" size="small">
                    {{ getStatusText(auction.status) }}
                  </el-tag>
                </div>
                <div class="info-row" v-if="auction.status === 1">
                  <span class="label">结束时间</span>
                  <span class="value">{{ formatTime(auction.endTime) }}</span>
                </div>
              </div>
            </el-card>
          </el-col>
        </el-row>

        <!-- 空状态 -->
        <el-empty v-if="!loading && auctions.length === 0" description="暂无拍卖" />

        <!-- 分页 -->
        <el-pagination
          v-if="total > 0"
          class="pagination"
          v-model:current-page="currentPage"
          v-model:page-size="pageSize"
          :page-sizes="[12, 24, 48]"
          layout="total, sizes, prev, pager, next, jumper"
          :total="total"
          @size-change="fetchAuctions"
          @current-change="fetchAuctions"
        />
      </el-main>
    </el-container>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { Search, Plus, User } from '@element-plus/icons-vue'
import { listAuctions, mockNft } from '../api/auction'

const router = useRouter()
const loading = ref(false)
const auctions = ref<any[]>([])
const total = ref(0)
const currentPage = ref(1)
const pageSize = ref(12)
const statusFilter = ref(0)
const searchQuery = ref('')
const walletAddress = ref('')

// 统计数据（模拟，实际可通过 API 获取）
const stats = ref({
  totalAuctions: 0,
  activeAuctions: 0,
  totalBids: 0,
  tvl: 0
})

// 获取拍卖列表
const fetchAuctions = async () => {
  loading.value = true
  try {
    const data = await listAuctions({
      status: statusFilter.value,
      page: currentPage.value,
      pageSize: pageSize.value
    })
    auctions.value = data.auctions || []
    total.value = data.total || 0
    // 更新统计数据
    if (statusFilter.value === 0) {
      stats.value.totalAuctions = data.total || 0
      stats.value.activeAuctions = (data.auctions || []).filter((a: any) => a.status === 1).length
      stats.value.totalBids = 0
      stats.value.tvl = 0
    }
  } catch (error) {
    console.error('Failed to fetch auctions:', error)
    ElMessage.error('获取拍卖列表失败')
  } finally {
    loading.value = false
  }
}

// 连接钱包
const connectWallet = async () => {
  // 简单模拟，实际应使用 ethers.js 连接 MetaMask
  if (typeof window.ethereum !== 'undefined') {
    try {
      const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' })
      walletAddress.value = accounts[0]
      ElMessage.success('钱包连接成功')
    } catch (error) {
      ElMessage.error('连接钱包失败')
    }
  } else {
    // 如果没有钱包，生成一个 mock 地址
    walletAddress.value = '0x' + Math.random().toString(16).slice(2, 10) + '...'
    ElMessage.info('已连接模拟钱包')
  }
}

// Mock NFT 功能（用于开发测试）
const handleMockNft = async () => {
  try {
    const data = await mockNft()
    ElMessage.success(`Mock NFT 成功，TokenID: ${data.tokenId}`)
  } catch (error) {
    ElMessage.error('Mock NFT 失败')
  }
}

// 跳转到详情页
const goToDetail = (id: string) => {
  router.push(`/auction/${id}`)
}

// 辅助函数
const formatAddress = (addr: string) => {
  if (!addr || addr.length < 10) return addr
  return addr.slice(0, 6) + '...' + addr.slice(-4)
}

const formatPrice = (price: string) => {
  if (!price || price === '0') return '0'
  const num = parseFloat(price)
  if (isNaN(num)) return price
  return num.toFixed(2)
}

const formatTime = (timestamp: number) => {
  if (!timestamp) return '-'
  const date = new Date(timestamp * 1000)
  return date.toLocaleString()
}

const getStatusText = (status: number) => {
  switch (status) {
    case 0: return '待开始'
    case 1: return '进行中'
    case 2: return '已结束'
    case 3: return '已取消'
    default: return '未知'
  }
}

const getStatusTagType = (status: number) => {
  switch (status) {
    case 0: return 'info'
    case 1: return 'success'
    case 2: return 'warning'
    case 3: return 'danger'
    default: return 'info'
  }
}

// 获取 NFT 占位图
const getNftImage = (auction: any) => {
  // 可以根据合约地址生成特定的图片
  return `https://picsum.photos/seed/${auction.auctionId}/300/300`
}

onMounted(fetchAuctions)
</script>

<style scoped>
.home {
  min-height: 100vh;
  background-color: #f5f7fa;
}

.header-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.header-actions {
  display: flex;
  align-items: center;
}

.stats-row {
  margin-bottom: 20px;
}

.stat-card {
  text-align: center;
}

.stat-value {
  font-size: 28px;
  font-weight: bold;
  color: #409eff;
}

.stat-label {
  font-size: 14px;
  color: #909399;
  margin-top: 5px;
}

.auctions-row {
  margin-bottom: 20px;
}

.auction-card {
  margin-bottom: 20px;
  cursor: pointer;
  transition: transform 0.2s;
  height: 100%;
}

.auction-card:hover {
  transform: translateY(-5px);
}

.nft-image {
  width: 100%;
  height: 200px;
  overflow: hidden;
}

.nft-image .image {
  width: 100%;
  height: 100%;
}

.auction-info {
  padding: 15px;
}

.auction-info h3 {
  margin: 0 0 5px 0;
}

.nft-contract {
  color: #909399;
  font-size: 12px;
}

.info-row {
  display: flex;
  justify-content: space-between;
  margin: 8px 0;
}

.info-row .label {
  color: #909399;
}

.info-row .value {
  font-weight: 500;
}

.info-row.highest .value {
  color: #e6a23c;
  font-weight: bold;
}

.pagination {
  margin-top: 20px;
  justify-content: center;
}
</style>
