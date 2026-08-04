import React, { useState, useEffect } from 'react'
import { Card, Row, Col, Descriptions, Tag, Spin } from 'antd'
import { InfoCircleOutlined, LinkOutlined } from '@ant-design/icons'
import { walletApi, ownerApi } from '../services/api'

function Info({ version, balance }) {
  const [loading, setLoading] = useState(true)
  const [threshold, setThreshold] = useState(0)
  const [ownerCount, setOwnerCount] = useState(0)
  const [isPaused, setIsPaused] = useState(false)

  // 转换 wei 为 ETH（使用 BigInt 避免精度丢失）
  const balanceETH = (() => {
    if (balance === null || balance === undefined) return 0
    try {
      const wei = BigInt(String(balance))
      return Number(wei) / 1e18
    } catch (e) {
      return Number(balance) / 1e18
    }
  })()

  useEffect(() => {
    loadData()
  }, [])

  const loadData = async () => {
    setLoading(true)
    try {
      const [thresholdVal, count, paused] = await Promise.all([
        ownerApi.getThreshold().catch(() => 0),
        ownerApi.getOwnerCount().catch(() => 0),
        walletApi.isPaused().catch(() => false),
      ])
      setThreshold(thresholdVal)
      setOwnerCount(count)
      setIsPaused(paused)
    } catch (e) {
      console.error('Failed to load data:', e)
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return <div style={{ textAlign: 'center', padding: '100px' }}><Spin size="large" /></div>
  }

  return (
    <div>
      <h2 style={{ marginBottom: '24px' }}>合约信息</h2>

      <Row gutter={[16, 16]}>
        <Col xs={24} lg={12}>
          <Card title="基本信息">
            <Descriptions column={1} bordered size="small">
              <Descriptions.Item label="合约版本">
                <Tag color="blue">V{version || 'N/A'}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="运行状态">
                {isPaused ? <Tag color="red">已暂停</Tag> : <Tag color="green">运行中</Tag>}
              </Descriptions.Item>
              <Descriptions.Item label="合约余额">
                {balanceETH.toFixed(6)} ETH
              </Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>

        <Col xs={24} lg={12}>
          <Card title="多签配置">
            <Descriptions column={1} bordered size="small">
              <Descriptions.Item label="所有者数量">
                <Tag color="purple">{ownerCount}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="确认阈值">
                <Tag color="orange">{threshold} 人确认</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="安全模式">
                <Tag color="green">多签保护</Tag>
              </Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
      </Row>

      <Row style={{ marginTop: '16px' }}>
        <Col span={24}>
          <Card title="合约地址">
            <Descriptions column={1} bordered size="small">
              <Descriptions.Item label="代理合约（Proxy）">
                <code style={{ wordBreak: 'break-all' }}>0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512</code>
              </Descriptions.Item>
              <Descriptions.Item label="实现合约（Implementation）">
                <code style={{ wordBreak: 'break-all' }}>0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0</code>
              </Descriptions.Item>
              <Descriptions.Item label="网络">
                <Tag color="cyan">Anvil 本地测试网</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="RPC 节点">
                <LinkOutlined /> <code>http://127.0.0.1:8545</code>
              </Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
      </Row>

      <Row style={{ marginTop: '16px' }}>
        <Col span={24}>
          <Card title="功能说明">
            <div style={{ lineHeight: '2' }}>
              <p><strong>1. 多签保护：</strong>所有敏感操作（添加/移除所有者、创建提案、执行交易等）均需多签确认。</p>
              <p><strong>2. 提案机制：</strong>任何所有者可创建交易提案，需达到阈值确认后才能执行。</p>
              <p><strong>3. 可升级性：</strong>合约采用 UUPS 模式，支持升级到新版本实现。</p>
              <p><strong>4. 访问控制：</strong>仅所有者可调用受保护的函数。</p>
            </div>
          </Card>
        </Col>
      </Row>
    </div>
  )
}

export default Info
