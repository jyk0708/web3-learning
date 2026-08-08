<template>
  <div class="detail" v-loading="loading">
    <el-container>
      <el-header>
        <div class="header-content">
          <el-button @click="$router.back()">
            <el-icon><ArrowLeft /></el-icon>返回
          </el-button>
          <h1>拍卖详情</h1>
        </div>
      </el-header>

      <el-main v-if="auction">
        <el-row :gutter="20">
          <!-- 左侧：NFT 信息 -->
          <el-col :span="12">
            <el-card class="nft-card">
              <div class="nft-image">
                <el-image :src="getNftImage(auction)" fit="cover" class="image" />
              </div>
              <el-divider />
              <el-descriptions :column="1" border>
                <el-descriptions-item label="拍卖 ID">{{ auction.auctionId }}</el-descriptions-item>
                <el-descriptions-item label="NFT 合约">{{ auction.nftContract }}</el-descriptions-item>
                <el-descriptions-item label="Token ID">{{ auction.tokenId }}</el-descriptions-item>
                <el-descriptions-item label="卖家">{{ auction.seller }}</el-descriptions-item>
                <el-descriptions-item label="起拍价">{{ formatPrice(auction.startingPriceUSD) }} USD</el-descriptions-item>
                <el-descriptions-item label="状态">
                  <el-tag :type="getStatusTagType(auction.status)">
                    {{ getStatusText(auction.status) }}
                  </el-tag>
                </el-descriptions-item>
                <el-descriptions-item label="开始时间">{{ formatTime(auction.startTime) }}</el-descriptions-item>
                <el-descriptions-item label="结束时间">{{ formatTime(auction.endTime) }}</el-descriptions-item>
              </el-descriptions>
            </el-card>
          </el-col>

          <!-- 右侧：出价历史 + 操作 -->
          <el-col :span="12">
            <el-card class="bids-card">
              <template #header>
                <div class="card-header">
                  <span>出价历史</span>
                  <span v-if="auction.highestBidInUSD !== '0'" class="highest-bid">
                    当前最高: {{ formatPrice(auction.highestBidInUSD) }} USD
                  </span>
                </div>
              </template>
              
              <el-timeline v-if="bids.length > 0">
                <el-timeline-item
                  v-for="bid in bids"
                  :key="bid.id"
                  :timestamp="formatTimeStr(bid.createdAt)"
                  placement="top"
                  :color="'#409eff'"
                >
                  <div class="bid-item">
                    <el-avatar :size="32" :style="{ backgroundColor: '#409eff' }">
                      {{ formatAddress(bid.bidder).slice(2, 4) }}
                    </el-avatar>
                    <div class="bid-info">
                      <div class="bidder">{{ bid.bidder }}</div>
                      <div class="bid-amount">
                        <strong>{{ formatPrice(bid.bidPriceUSD) }} USD</strong>
                        <span class="amount-raw">({{ bid.bidAmount }} tokens)</span>
                      </div>
                    </div>
                  </div>
                </el-timeline-item>
              </el-timeline>
              <el-empty v-else description="暂无出价记录" />
            </el-card>

            <!-- 操作区 -->
            <el-card v-if="canInteract" class="action-card">
              <h3>参与操作</h3>
              
              <!-- 参与出价 -->
              <div v-if="auction.status === 1" class="bid-section">
                <h4>参与出价</h4>
                <el-form :model="bidForm" label-width="100px">
                  <el-form-item label="出价金额 (USD)">
                    <el-input-number v-model="bidForm.bidPrice" :min="minBidPrice" :step="10" />
                  </el-form-item>
                  <el-form-item label="代币地址">
                    <el-input v-model="bidForm.tokenAddress" placeholder="支付代币地址 (如 WETH)" />
                  </el-form-item>
                  <el-form-item>
                    <el-button type="primary" :loading="bidding" @click="handleBid">确认出价</el-button>
                  </el-form-item>
                </el-form>
              </div>

              <!-- 开始拍卖 -->
              <div v-if="auction.status === 0 && isOwner" class="action-section">
                <el-button type="success" :loading="starting" @click="handleStart">开始拍卖</el-button>
                <el-button :loading="canceling" @click="handleCancel">取消拍卖</el-button>
              </div>

              <!-- 结束拍卖 -->
              <div v-if="auction.status === 1 && isOwner" class="action-section">
                <el-button type="warning" :loading="ending" @click="handleEnd">结束拍卖</el-button>
              </div>
            </el-card>
          </el-col>
        </el-row>
      </el-main>
    </el-container>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { ArrowLeft } from '@element-plus/icons-vue'
import { getAuction, startAuction, endAuction, cancelAuction, bidAuction } from '../api/auction'

const route = useRoute()
const router = useRouter()
const loading = ref(false)
const auction = ref<any>(null)
const bids = ref<any[]>([])

// 表单状态
const bidForm = ref({
  bidPrice: 10,
  tokenAddress: '0x7cEb23fd6BC0Ad45D8E7BAe69B46C0BD06D2efEE' // WETH
})

// 加载状态
const bidding = ref(false)
const starting = ref(false)
const ending = ref(false)
const canceling = ref(false)

// 计算属性
const minBidPrice = computed(() => {
  if (!auction.value) return 0
  return parseFloat(auction.value.highestBidInUSD || '0') + 1
})

const isOwner = computed(() => {
  // 实际应从钱包连接状态判断，这里简化处理
  return true
})

const canInteract = computed(() => {
  return auction.value && (auction.value.status === 0 || auction.value.status === 1)
})

// 获取拍卖详情
const fetchAuction = async () => {
  const id = route.params.id as string
  loading.value = true
  try {
    const data = await getAuction(id)
    auction.value = data.auction
    bids.value = data.bids
  } catch (error) {
    ElMessage.error('获取拍卖详情失败')
    router.back()
  } finally {
    loading.value = false
  }
}

// 开始拍卖
const handleStart = async () => {
  try {
    await ElMessageBox.confirm('确认开始此拍卖？', '提示', {
      type: 'warning'
    })
    starting.value = true
    await startAuction(auction.value.auctionId)
    ElMessage.success('拍卖已开始')
    fetchAuction()
  } catch (error) {
    if (error !== 'cancel') {
      ElMessage.error('开始拍卖失败')
    }
  } finally {
    starting.value = false
  }
}

// 结束拍卖
const handleEnd = async () => {
  try {
    await ElMessageBox.confirm('确认结束此拍卖？', '提示', {
      type: 'warning'
    })
    ending.value = true
    await endAuction(auction.value.auctionId)
    ElMessage.success('拍卖已结束')
    fetchAuction()
  } catch (error) {
    if (error !== 'cancel') {
      ElMessage.error('结束拍卖失败')
    }
  } finally {
    ending.value = false
  }
}

// 取消拍卖
const handleCancel = async () => {
  try {
    await ElMessageBox.confirm('确认取消此拍卖？此操作不可恢复！', '警告', {
      type: 'error'
    })
    canceling.value = true
    await cancelAuction(auction.value.auctionId)
    ElMessage.success('拍卖已取消')
    fetchAuction()
  } catch (error) {
    if (error !== 'cancel') {
      ElMessage.error('取消拍卖失败')
    }
  } finally {
    canceling.value = false
  }
}

// 参与出价
const handleBid = async () => {
  if (bidForm.value.bidPrice <= minBidPrice.value) {
    ElMessage.warning(`出价必须高于当前最高价 ${minBidPrice.value} USD`)
    return
  }
  try {
    await ElMessageBox.confirm(`确认出价 ${bidForm.value.bidPrice} USD？`, '提示', {
      type: 'warning'
    })
    bidding.value = true
    // 转换为代币数量（简化处理，实际应调用 getPrice2USD 或使用链上逻辑）
    // 这里假设 1 USD = 1 token (decimals=8)
    const bidAmount = (bidForm.value.bidPrice * 100000000).toString()
    
    await bidAuction({
      auctionId: auction.value.auctionId,
      tokenAddress: bidForm.value.tokenAddress,
      bidPrice: bidAmount
    })
    ElMessage.success('出价成功')
    fetchAuction()
  } catch (error) {
    if (error !== 'cancel') {
      ElMessage.error('出价失败')
    }
  } finally {
    bidding.value = false
  }
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

const formatTimeStr = (timeStr: string) => {
  if (!timeStr) return ''
  return new Date(timeStr).toLocaleString()
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

const getNftImage = (auction: any) => {
  return `https://picsum.photos/seed/${auction.auctionId}/400/400`
}

onMounted(fetchAuction)
</script>

<style scoped>
.detail {
  min-height: 100vh;
  background-color: #f5f7fa;
}

.header-content {
  display: flex;
  align-items: center;
  gap: 20px;
}

.nft-card,
.bids-card,
.action-card {
  margin-bottom: 20px;
}

.nft-image {
  width: 100%;
  height: 300px;
  overflow: hidden;
}

.nft-image .image {
  width: 100%;
  height: 100%;
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.highest-bid {
  color: #e6a23c;
  font-weight: bold;
}

.bid-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 0;
}

.bid-info {
  flex: 1;
}

.bidder {
  font-size: 12px;
  color: #909399;
  word-break: break-all;
}

.bid-amount {
  margin-top: 5px;
}

.amount-raw {
  font-size: 12px;
  color: #909399;
  margin-left: 10px;
}

.action-card h3,
.action-card h4 {
  margin-top: 0;
}

.action-section {
  margin-top: 15px;
}

.action-section .el-button + .el-button {
  margin-left: 10px;
}
</style>
