import React, { useState, useEffect } from 'react'
import { Card, Table, Button, Modal, Form, Input, InputNumber, Space, message, Tag, Descriptions, List, Spin } from 'antd'
import { PlusOutlined, ReloadOutlined, CheckCircleOutlined, CloseCircleOutlined, PlayCircleOutlined, EyeOutlined } from '@ant-design/icons'
import { proposalApi } from '../services/api'

function Proposals() {
  const [loading, setLoading] = useState(false)
  const [proposals, setProposals] = useState([])
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false)
  const [isDetailModalOpen, setIsDetailModalOpen] = useState(false)
  const [selectedProposal, setSelectedProposal] = useState(null)
  const [confirmers, setConfirmers] = useState([])
  const [confirmersLoading, setConfirmersLoading] = useState(false)
  const [form] = Form.useForm()

  const loadData = async () => {
    setLoading(true)
    try {
      const count = await proposalApi.getProposalCount()
      const list = []
      for (let i = 0; i < count; i++) {
        try {
          const proposal = await proposalApi.getProposal(i)
          list.push({
            key: i,
            index: i,
            ...proposal,
          })
        } catch (e) {
          console.error(`Failed to load proposal ${i}:`, e)
        }
      }
      setProposals(list)
    } catch (e) {
      message.error('加载提案失败: ' + e.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadData()
  }, [])

  const handleCreateProposal = async (values) => {
    try {
      await proposalApi.createProposal({
        to: values.to,
        value: values.value || 0,
        data: values.data || '0x',
      })
      message.success('创建提案成功')
      setIsCreateModalOpen(false)
      form.resetFields()
      loadData()
    } catch (e) {
      message.error('创建失败: ' + e.message)
    }
  }

  const handleConfirm = async (index) => {
    try {
      await proposalApi.confirmTx(index)
      message.success('确认成功')
      loadData()
    } catch (e) {
      message.error('确认失败: ' + e.message)
    }
  }

  const handleExecute = async (index) => {
    try {
      await proposalApi.executeTx(index)
      message.success('执行成功')
      loadData()
    } catch (e) {
      message.error('执行失败: ' + e.message)
    }
  }

  const handleViewDetail = async (proposal) => {
    setSelectedProposal(proposal)
    setIsDetailModalOpen(true)
    setConfirmersLoading(true)
    try {
      const confList = await proposalApi.getConfirmers(proposal.index)
      setConfirmers(confList)
    } catch (e) {
      console.error('Failed to load confirmers:', e)
      setConfirmers([])
    } finally {
      setConfirmersLoading(false)
    }
  }

  const getStatusTag = (proposal) => {
    if (proposal.executed) {
      return <Tag color="green">已执行</Tag>
    }
    return <Tag color="orange">待执行</Tag>
  }

  const getCanExecuteTag = async (index) => {
    try {
      const canExec = await proposalApi.canExecute(index)
      return canExec ? <Tag color="blue">可执行</Tag> : <Tag color="default">不可执行</Tag>
    } catch {
      return <Tag color="default">-</Tag>
    }
  }

  const columns = [
    {
      title: '提案索引',
      dataIndex: 'index',
      key: 'index',
    },
    {
      title: '目标地址',
      dataIndex: 'to',
      key: 'to',
      render: (text) => <code style={{ fontSize: '12px' }}>{text}</code>,
    },
    {
      title: '金额 (Wei)',
      dataIndex: 'value',
      key: 'value',
      render: (text) => text?.toLocaleString() || '0',
    },
    {
      title: '确认数',
      dataIndex: 'confirmations',
      key: 'confirmations',
    },
    {
      title: '状态',
      key: 'status',
      render: (_, record) => getStatusTag(record),
    },
    {
      title: '操作',
      key: 'action',
      render: (_, record) => (
        <Space>
          <Button
            size="small"
            icon={<EyeOutlined />}
            onClick={() => handleViewDetail(record)}
          >
            详情
          </Button>
          {!record.executed && (
            <>
              <Button
                size="small"
                icon={<CheckCircleOutlined />}
                onClick={() => handleConfirm(record.index)}
              >
                确认
              </Button>
              <Button
                size="small"
                type="primary"
                icon={<PlayCircleOutlined />}
                onClick={() => handleExecute(record.index)}
              >
                执行
              </Button>
            </>
          )}
        </Space>
      ),
    },
  ]

  return (
    <div>
      <div style={{ marginBottom: '16px', display: 'flex', justifyContent: 'space-between' }}>
        <h2 style={{ margin: 0 }}>提案管理</h2>
        <Space>
          <Button icon={<ReloadOutlined />} onClick={loadData}>刷新</Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setIsCreateModalOpen(true)}>
            创建提案
          </Button>
        </Space>
      </div>

      <Card>
        <Table
          columns={columns}
          dataSource={proposals}
          loading={loading}
          rowKey="key"
          pagination={{ pageSize: 10 }}
        />
      </Card>

      {/* 创建提案弹窗 */}
      <Modal
        title="创建提案"
        open={isCreateModalOpen}
        onCancel={() => { setIsCreateModalOpen(false); form.resetFields() }}
        footer={null}
      >
        <Form form={form} onFinish={handleCreateProposal} layout="vertical">
          <Form.Item
            name="to"
            label="目标地址"
            rules={[{ required: true, message: '请输入目标地址' }]}
          >
            <Input placeholder="0x..." />
          </Form.Item>
          <Form.Item
            name="value"
            label="金额 (Wei)"
            initialValue={0}
          >
            <InputNumber min={0} style={{ width: '100%' }} />
          </Form.Item>
          <Form.Item
            name="data"
            label="数据 (hex)"
            initialValue="0x"
          >
            <Input placeholder="0x... (可选)" />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block>创建提案</Button>
          </Form.Item>
        </Form>
      </Modal>

      {/* 提案详情弹窗 */}
      <Modal
        title="提案详情"
        open={isDetailModalOpen}
        onCancel={() => setIsDetailModalOpen(false)}
        footer={[
          <Button key="close" onClick={() => setIsDetailModalOpen(false)}>关闭</Button>,
        ]}
        width={700}
      >
        {selectedProposal && (
          <>
            <Descriptions column={1} bordered size="small">
              <Descriptions.Item label="提案索引">{selectedProposal.index}</Descriptions.Item>
              <Descriptions.Item label="目标地址">
                <code>{selectedProposal.to}</code>
              </Descriptions.Item>
              <Descriptions.Item label="金额">
                {Number(selectedProposal.value).toLocaleString()} Wei
              </Descriptions.Item>
              <Descriptions.Item label="数据">
                <code style={{ fontSize: '12px', wordBreak: 'break-all' }}>
                  {selectedProposal.data}
                </code>
              </Descriptions.Item>
              <Descriptions.Item label="确认数">
                <Tag color="blue">{selectedProposal.confirmations}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="状态">
                {getStatusTag(selectedProposal)}
              </Descriptions.Item>
            </Descriptions>

            <div style={{ marginTop: '16px' }}>
              <h4 style={{ marginBottom: '8px' }}>确认人列表</h4>
              {confirmersLoading ? (
                <div style={{ textAlign: 'center', padding: '20px' }}>
                  <Spin />
                </div>
              ) : confirmers.length > 0 ? (
                <List
                  size="small"
                  bordered
                  dataSource={confirmers}
                  renderItem={(item) => (
                    <List.Item>
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
                        <code style={{ fontSize: '12px' }}>{item.address}</code>
                        {item.confirmed ? (
                          <Tag color="green" icon={<CheckCircleOutlined />}>已确认</Tag>
                        ) : (
                          <Tag color="default" icon={<CloseCircleOutlined />}>未确认</Tag>
                        )}
                      </div>
                    </List.Item>
                  )}
                />
              ) : (
                <div style={{ textAlign: 'center', padding: '20px', color: '#999' }}>
                  暂无所有者
                </div>
              )}
            </div>
          </>
        )}
      </Modal>
    </div>
  )
}

export default Proposals
