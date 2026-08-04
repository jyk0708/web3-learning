import React, { useState, useEffect } from 'react'
import { Card, Table, Button, Modal, Form, Input, InputNumber, Space, message, Popconfirm } from 'antd'
import { PlusOutlined, EditOutlined, DeleteOutlined, ReloadOutlined } from '@ant-design/icons'
import { ownerApi } from '../services/api'

function Owners() {
  const [loading, setLoading] = useState(false)
  const [owners, setOwners] = useState([])
  const [threshold, setThreshold] = useState(0)
  const [isAddModalOpen, setIsAddModalOpen] = useState(false)
  const [isEditModalOpen, setIsEditModalOpen] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [form] = Form.useForm()

  const loadData = async () => {
    setLoading(true)
    try {
      const [ownersList, thresholdVal] = await Promise.all([
        ownerApi.getOwners(),
        ownerApi.getThreshold(),
      ])
      setOwners(ownersList.map((addr, index) => ({ key: index, address: addr })))
      setThreshold(thresholdVal)
    } catch (e) {
      message.error('加载数据失败: ' + e.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadData()
  }, [])

  const handleAddOwner = async (values) => {
    setSubmitting(true)
    try {
      console.log('Adding owner with value:', values)
      const result = await ownerApi.addOwner(values.owner)
      console.log('Add owner result:', result)
      message.success('添加所有者成功')
      setIsAddModalOpen(false)
      form.resetFields()
      loadData()
    } catch (e) {
      console.error('Add owner error:', e)
      message.error('添加失败: ' + (e.response?.data?.msg || e.message))
    } finally {
      setSubmitting(false)
    }
  }

  const handleRemoveOwner = async (address) => {
    try {
      await ownerApi.removeOwner(address)
      message.success('移除所有者成功')
      loadData()
    } catch (e) {
      message.error('移除失败: ' + (e.response?.data?.msg || e.message))
    }
  }

  const handleChangeThreshold = async (values) => {
    setSubmitting(true)
    try {
      await ownerApi.changeThreshold(values.threshold)
      message.success('修改阈值成功')
      setIsEditModalOpen(false)
      form.resetFields()
      loadData()
    } catch (e) {
      message.error('修改失败: ' + (e.response?.data?.msg || e.message))
    } finally {
      setSubmitting(false)
    }
  }

  const columns = [
    {
      title: '序号',
      key: 'index',
      render: (_, __, index) => index + 1,
    },
    {
      title: '所有者地址',
      dataIndex: 'address',
      key: 'address',
      render: (text) => <code style={{ fontSize: '12px' }}>{text}</code>,
    },
    {
      title: '操作',
      key: 'action',
      render: (_, record) => (
        <Popconfirm
          title="确定移除此所有者？"
          onConfirm={() => handleRemoveOwner(record.address)}
          okText="确定"
          cancelText="取消"
        >
          <Button danger icon={<DeleteOutlined />}>移除</Button>
        </Popconfirm>
      ),
    },
  ]

  return (
    <div>
      <div style={{ marginBottom: '16px', display: 'flex', justifyContent: 'space-between' }}>
        <h2 style={{ margin: 0 }}>所有者管理</h2>
        <Space>
          <Button icon={<ReloadOutlined />} onClick={loadData}>刷新</Button>
          <Button type="primary" icon={<EditOutlined />} onClick={() => { form.setFieldsValue({ threshold }); setIsEditModalOpen(true) }}>
            修改阈值 (当前: {threshold})
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={() => { form.resetFields(); setIsAddModalOpen(true) }}>
            添加所有者
          </Button>
        </Space>
      </div>

      <Card>
        <Table
          columns={columns}
          dataSource={owners}
          loading={loading}
          rowKey="key"
          pagination={false}
        />
      </Card>

      {/* 添加所有者弹窗 */}
      <Modal
        title="添加所有者"
        open={isAddModalOpen}
        onCancel={() => { setIsAddModalOpen(false); form.resetFields() }}
        footer={null}
        destroyOnClose
      >
        <Form form={form} onFinish={handleAddOwner} layout="vertical" preserve={false}>
          <Form.Item
            name="owner"
            label="以太坊地址"
            rules={[
              { required: true, message: '请输入以太坊地址' },
              { pattern: /^0x[a-fA-F0-9]{40}$/, message: '请输入有效的以太坊地址' }
            ]}
          >
            <Input placeholder="0x..." />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block loading={submitting}>
              {submitting ? '添加中...' : '确认添加'}
            </Button>
          </Form.Item>
        </Form>
      </Modal>

      {/* 修改阈值弹窗 */}
      <Modal
        title="修改确认阈值"
        open={isEditModalOpen}
        onCancel={() => { setIsEditModalOpen(false); form.resetFields() }}
        footer={null}
        destroyOnClose
      >
        <Form form={form} onFinish={handleChangeThreshold} layout="vertical" preserve={false}>
          <Form.Item
            name="threshold"
            label="确认阈值（需要多少人确认才能执行）"
            rules={[{ required: true, message: '请输入阈值' }]}
          >
            <InputNumber min={1} max={owners.length} style={{ width: '100%' }} />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" block loading={submitting}>
              {submitting ? '修改中...' : '确认修改'}
            </Button>
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

export default Owners
