import React, { useState, useEffect } from 'react'
import { Card, Row, Col, Statistic, Spin, message } from 'antd'
import { UserOutlined, FileTextOutlined, CheckCircleOutlined, WalletOutlined } from '@ant-design/icons'
import { ownerApi, proposalApi, walletApi } from '../services/api'

function Dashboard({ onRefresh }) {
  const [loading, setLoading] = useState(true)
  const [data, setData] = useState({
    ownerCount: 0,
    proposalCount: 0,
    confirmedCount: 0,
    balance: 0,
  })

  const loadData = async () => {
    setLoading(true)
    try {
      const [ownerCount, proposalCount, balance] = await Promise.all([
        ownerApi.getOwnerCount(),
        proposalApi.getProposalCount(),
        walletApi.getBalance().catch(() => 0),
      ])
      console.log("balance raw:", balance)
      
      // 使用 BigInt 避免精度丢失
      let ethBalance = 0
      try {
        const wei = BigInt(String(balance || 0))
        ethBalance = Number(wei) / 1e18
      } catch (e) {
        ethBalance = Number(balance || 0) / 1e18
      }
      console.log("balance ETH:", ethBalance)
      
      setData({
        ownerCount,
        proposalCount,
        confirmedCount: 0,
        balance: ethBalance,
      })

      if (onRefresh) onRefresh()
    } catch (e) {
      message.error('加载数据失败: ' + e.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadData()
  }, [])

  if (loading) {
    return <div style={{ textAlign: 'center', padding: '100px' }}><Spin size="large" /></div>
  }

  return (
    <div>
      <h2 style={{ marginBottom: '24px' }}>仪表盘</h2>
      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} lg={6}>
          <Card className="stat-card">
            <Statistic
              title="所有者数量"
              value={data.ownerCount}
              prefix={<UserOutlined style={{ color: '#1890ff' }} />}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card className="stat-card">
            <Statistic
              title="提案数量"
              value={data.proposalCount}
              prefix={<FileTextOutlined style={{ color: '#52c41a' }} />}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card className="stat-card">
            <Statistic
              title="合约余额"
              value={data.balance}
              precision={20}
              suffix=" ETH"
              prefix={<WalletOutlined style={{ color: '#faad14' }} />}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card className="stat-card">
            <Statistic
              title="状态"
              value="正常"
              prefix={<CheckCircleOutlined style={{ color: '#52c41a' }} />}
              valueStyle={{ color: '#52c41a', fontSize: '24px' }}
            />
          </Card>
        </Col>
      </Row>

      <Row style={{ marginTop: '24px' }}>
        <Col span={24}>
          <Card title="系统状态">
            <p><strong>合约地址：</strong>0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512</p>
            <p><strong>实现版本：</strong>V2</p>
            <p><strong>网络：</strong>Anvil (本地测试网)</p>
            <p><strong>后端服务：</strong>运行中</p>
          </Card>
        </Col>
      </Row>
    </div>
  )
}

export default Dashboard
