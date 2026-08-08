<template>
  <div class="create">
    <el-container>
      <el-header>
        <div class="header-content">
          <el-button @click="$router.back()">
            <el-icon><ArrowLeft /></el-icon>返回
          </el-button>
          <h1>创建拍卖</h1>
        </div>
      </el-header>

      <el-main>
        <el-card class="form-card">
          <template #header>
            <div class="card-header">
              <span>拍卖信息</span>
              <el-button @click="handleMockNft" :loading="mocking">
                <el-icon><MagicStick /></el-icon>一键 Mock NFT
              </el-button>
            </div>
          </template>

          <el-form :model="form" :rules="rules" ref="formRef" label-width="140px">
            <el-form-item label="NFT 合约地址" prop="nftContract">
              <el-input v-model="form.nftContract" placeholder="NFT 智能合约地址" />
            </el-form-item>

            <el-form-item label="Token ID" prop="tokenId">
              <el-input v-model="form.tokenId" placeholder="NFT Token ID (uint256)" />
            </el-form-item>

            <el-form-item label="支付代币地址" prop="tokenAddress">
              <el-select v-model="form.tokenAddress" placeholder="选择支付代币" filterable>
                <el-option label="WETH (Wrapped Ether)" value="0x7cEb23fd6BC0Ad45D8E7BAe69B46C0BD06D2efEE" />
                <el-option label="USDC (USD Coin)" value="0x1c7d4b196AA478d0ee648F487818A9BB45DFe59d" />
                <el-option label="自定义" value="" />
              </el-select>
            </el-form-item>

            <el-form-item label="起拍价 (代币数量)" prop="startingPrice">
              <el-input v-model="form.startingPrice" placeholder="起拍价格 (uint256)" />
              <div class="form-tip">
                <el-tag size="small" type="info">单位: 代币 (例如 1e18 = 1 WETH)</el-tag>
              </div>
            </el-form-item>

            <el-form-item label="持续时间 (天)" prop="durationInDays">
              <el-slider v-model="form.durationInDays" :min="5" :max="30" show-input />
              <div class="form-tip">
                <el-tag size="small" type="warning">最少 5 天，最多 30 天</el-tag>
              </div>
            </el-form-item>

            <el-form-item>
              <el-button type="primary" :loading="submitting" @click="handleSubmit">
                <el-icon><Check /></el-icon>创建拍卖
              </el-button>
              <el-button @click="resetForm">重置</el-button>
            </el-form-item>
          </el-form>
        </el-card>

        <!-- 预览卡片 -->
        <el-card v-if="preview" class="preview-card">
          <template #header>
            <span>预览信息</span>
          </template>
          <el-descriptions :column="1" border>
            <el-descriptions-item label="拍卖 ID">{{ preview.auctionId }}</el-descriptions-item>
            <el-descriptions-item label="交易哈希">{{ preview.txHash }}</el-descriptions-item>
          </el-descriptions>
          <el-button type="success" style="margin-top: 15px;" @click="goToDetail(preview.auctionId)">
            查看拍卖详情
          </el-button>
        </el-card>
      </el-main>
    </el-container>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { ArrowLeft, MagicStick, Check } from '@element-plus/icons-vue'
import { createAuction, mockNft } from '../api/auction'

const router = useRouter()
const formRef = ref<FormInstance>()
const submitting = ref(false)
const mocking = ref(false)
const preview = ref<any>(null)

const form = reactive({
  nftContract: '',
  tokenId: '',
  tokenAddress: '0x7cEb23fd6BC0Ad45D8E7BAe69B46C0BD06D2efEE', // WETH
  startingPrice: '1000000000000000000', // 1 WETH (假设价格源已配置)
  durationInDays: 7
})

const rules: FormRules = {
  nftContract: [{ required: true, message: '请输入 NFT 合约地址', trigger: 'blur' }],
  tokenId: [{ required: true, message: '请输入 Token ID', trigger: 'blur' }],
  tokenAddress: [{ required: true, message: '请选择支付代币', trigger: 'change' }],
  startingPrice: [{ required: true, message: '请输入起拍价', trigger: 'blur' }],
  durationInDays: [{ required: true, message: '请选择持续时间', trigger: 'change' }]
}

// 一键 Mock NFT
const handleMockNft = async () => {
  mocking.value = true
  try {
    const data = await mockNft()
    form.nftContract = data.nftContract
    form.tokenId = data.tokenId
    form.tokenAddress = data.tokenAddress
    form.startingPrice = data.startingPrice
    form.durationInDays = data.durationInDays
    ElMessage.success('Mock NFT 成功，请核对信息后创建')
  } catch (error) {
    ElMessage.error('Mock NFT 失败')
  } finally {
    mocking.value = false
  }
}

// 提交创建
const handleSubmit = async () => {
  if (!formRef.value) return
  
  await formRef.value.validate(async (valid) => {
    if (valid) {
      submitting.value = true
      try {
        const data = await createAuction({
          nftContract: form.nftContract,
          tokenId: form.tokenId,
          tokenAddress: form.tokenAddress,
          startingPrice: form.startingPrice,
          durationInDays: form.durationInDays
        })
        ElMessage.success('拍卖创建成功！')
        preview.value = data
      } catch (error) {
        ElMessage.error('创建拍卖失败')
      } finally {
        submitting.value = false
      }
    }
  })
}

// 重置表单
const resetForm = () => {
  formRef.value?.resetFields()
  preview.value = null
}

// 跳转到详情
const goToDetail = (id: string) => {
  router.push(`/auction/${id}`)
}
</script>

<style scoped>
.create {
  min-height: 100vh;
  background-color: #f5f7fa;
}

.header-content {
  display: flex;
  align-items: center;
  gap: 20px;
}

.form-card {
  max-width: 700px;
  margin: 0 auto 20px;
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.form-tip {
  margin-top: 5px;
}

.preview-card {
  max-width: 500px;
  margin: 0 auto;
  text-align: center;
}
</style>
