<template>
  <div id="app">
    <el-container class="layout-container">
      <el-header class="layout-header">
        <div class="header-inner">
          <div class="logo" @click="$router.push('/')">
            <el-icon :size="24"><Present /></el-icon>
            <span>NFT Auction</span>
          </div>
          <el-menu
            :default-active="$route.path"
            mode="horizontal"
            router
            background-color="transparent"
            class="nav-menu"
          >
            <el-menu-item index="/">首页</el-menu-item>
            <el-menu-item index="/profile">个人中心</el-menu-item>
            <el-menu-item index="/create">创建拍卖</el-menu-item>
          </el-menu>
          <div class="header-right">
            <el-button v-if="!walletConnected" type="primary" @click="connectWallet">
              <el-icon><User /></el-icon>连接钱包
            </el-button>
            <el-dropdown v-else @command="handleCommand">
              <el-button>
                <el-icon><User /></el-icon>
                {{ shortAddress }}
                <el-icon class="el-icon--right"><ArrowDown /></el-icon>
              </el-button>
              <template #dropdown>
                <el-dropdown-menu>
                  <el-dropdown-item command="profile">个人中心</el-dropdown-item>
                  <el-dropdown-item command="disconnect" divided>断开连接</el-dropdown-item>
                </el-dropdown-menu>
              </template>
            </el-dropdown>
          </div>
        </div>
      </el-header>
      
      <el-main class="layout-main">
        <router-view />
      </el-main>

      <el-footer class="layout-footer">
        <p>NFT Auction Platform &copy; {{ new Date().getFullYear() }}</p>
      </el-footer>
    </el-container>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { Present, User, ArrowDown } from '@element-plus/icons-vue'

const router = useRouter()
const walletAddress = ref('')

const walletConnected = computed(() => !!walletAddress.value)
const shortAddress = computed(() => {
  if (!walletAddress.value) return ''
  return walletAddress.value.slice(0, 6) + '...' + walletAddress.value.slice(-4)
})

// 连接钱包
const connectWallet = async () => {
  if (typeof window.ethereum !== 'undefined') {
    try {
      const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' })
      walletAddress.value = accounts[0]
      ElMessage.success('钱包连接成功')
    } catch (error) {
      ElMessage.error('连接钱包失败')
    }
  } else {
    // 模拟模式
    walletAddress.value = '0x' + '1'.repeat(40)
    ElMessage.info('已连接模拟钱包')
  }
}

// 下拉菜单命令
const handleCommand = (command: string) => {
  if (command === 'profile') {
    router.push('/profile')
  } else if (command === 'disconnect') {
    walletAddress.value = ''
    ElMessage.info('已断开连接')
  }
}
</script>

<style>
#app {
  font-family: Avenir, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

.layout-container {
  min-height: 100vh;
}

.layout-header {
  background-color: #ffffff;
  border-bottom: 1px solid #e6e6e6;
  display: flex;
  align-items: center;
  padding: 0;
}

.header-inner {
  width: 100%;
  max-width: 1200px;
  margin: 0 auto;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 20px;
}

.logo {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 20px;
  font-weight: bold;
  cursor: pointer;
  color: #409eff;
}

.nav-menu {
  border-bottom: none;
  flex: 1;
  margin: 0 40px;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 10px;
}

.layout-main {
  padding: 0;
  min-height: calc(100vh - 140px);
}

.layout-footer {
  background-color: #f5f7fa;
  text-align: center;
  color: #909399;
  font-size: 14px;
}
</style>
