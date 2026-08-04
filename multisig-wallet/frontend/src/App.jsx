import React, { useState, useEffect } from 'react'
import { Layout, Menu, message, Tabs, ConfigProvider, Select, Space, Tag } from 'antd'
import { WalletOutlined, UserOutlined, FileTextOutlined, InfoCircleOutlined, SwapOutlined } from '@ant-design/icons'
import Dashboard from './components/Dashboard'
import Owners from './components/Owners'
import Proposals from './components/Proposals'
import Info from './components/Info'
import { walletApi, systemApi, getCurrentOwner, setCurrentOwner } from './services/api'

const { Header, Sider, Content } = Layout

function App() {
  const [version, setVersion] = useState(null)
  const [balance, setBalance] = useState(null)
  const [selectedKey, setSelectedKey] = useState('dashboard')
  const [availableOwners, setAvailableOwners] = useState([])
  const [currentOwnerState, setCurrentOwnerState] = useState('')

  useEffect(() => {
    loadBasicInfo()
    loadOwners()
    // 恢复保存的 owner
    const savedOwner = getCurrentOwner()
    if (savedOwner) {
      setCurrentOwnerState(savedOwner)
    }
  }, [])

  const loadOwners = async () => {
    try {
      const owners = await systemApi.getAvailableOwners()
      setAvailableOwners(owners)
      // 如果有 owner 但没设置，默认选择第一个
      if (owners.length > 0 && !currentOwnerState) {
        setCurrentOwnerState(owners[0].Address)
        setCurrentOwner(owners[0].Address)
      }
    } catch (e) {
      console.error('Failed to load available owners:', e)
    }
  }

  const handleOwnerChange = (address) => {
    setCurrentOwnerState(address)
    setCurrentOwner(address)
    message.success(`已切换到 ${address === currentOwnerState ? '当前' : '新的'} owner`)
    // 重新加载基本信息
    loadBasicInfo()
  }

  const loadBasicInfo = async () => {
    try {
      const [ver, bal] = await Promise.all([
        walletApi.getVersion().catch(() => null),
        walletApi.getBalance().catch(() => null),
      ])
      setVersion(ver)
      if (bal !== null && bal !== undefined) {
        // 使用 BigInt 避免精度丢失
        try {
          const wei = BigInt(String(bal))
          setBalance((Number(wei) / 1e18).toFixed(6))
        } catch (e) {
          setBalance((Number(bal) / 1e18).toFixed(6))
        }
      } else {
        setBalance(null)
      }
    } catch (e) {
      console.error('Failed to load basic info:', e)
    }
  }

  const menuItems = [
    { key: 'dashboard', icon: <InfoCircleOutlined />, label: '仪表盘' },
    { key: 'owners', icon: <UserOutlined />, label: '所有者管理' },
    { key: 'proposals', icon: <FileTextOutlined />, label: '提案管理' },
    { key: 'info', icon: <WalletOutlined />, label: '合约信息' },
  ]

  const renderContent = () => {
    switch (selectedKey) {
      case 'dashboard':
        return <Dashboard onRefresh={loadBasicInfo} />
      case 'owners':
        return <Owners />
      case 'proposals':
        return <Proposals />
      case 'info':
        return <Info version={version} balance={balance} />
      default:
        return <Dashboard />
    }
  }

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Header style={{ background: '#fff', padding: '0 24px', boxShadow: '0 2px 8px rgba(0,0,0,0.06)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'center', height: '100%' }}>
          <WalletOutlined style={{ fontSize: '24px', color: '#1890ff', marginRight: '12px' }} />
          <h1 style={{ color: '#1890ff', margin: 0, fontSize: '20px' }}>多签钱包管理系统</h1>
          {version !== null && (
            <span style={{ marginLeft: '16px', color: '#999', fontSize: '14px' }}>
              V{version}
            </span>
          )}
        </div>
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <Space>
            <span style={{ color: '#666', fontSize: '13px' }}>当前 Owner：</span>
            <Select
              style={{ width: '320px' }}
              value={currentOwnerState || undefined}
              onChange={handleOwnerChange}
              placeholder="选择 Owner"
              options={availableOwners.map(owner => {
                const addr = owner.address || ''
                const name = owner.name || 'Unknown'
                return {
                  value: addr,
                  label: (
                    <div style={{ display: 'flex', alignItems: 'center' }}>
                      <span style={{ marginRight: '8px' }}>{name}</span>
                      <Tag color="blue" style={{ fontSize: '11px' }}>
                        {addr ? `${addr.slice(0, 6)}...${addr.slice(-4)}` : ''}
                      </Tag>
                    </div>
                  ),
                }
              })}
            />
          </Space>
        </div>
      </Header>
      <Layout>
        <Sider width={200} style={{ background: '#fff' }}>
          <Menu
            mode="inline"
            selectedKeys={[selectedKey]}
            items={menuItems}
            onClick={({ key }) => setSelectedKey(key)}
            style={{ height: '100%', borderRight: 0 }}
          />
        </Sider>
        <Content style={{ margin: '16px', padding: '24px', background: '#fff', borderRadius: '8px', minHeight: 'calc(100vh - 64px - 32px)' }}>
          {renderContent()}
        </Content>
      </Layout>
    </Layout>
  )
}

export default App
