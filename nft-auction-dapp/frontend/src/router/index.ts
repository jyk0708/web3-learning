import { createRouter, createWebHistory } from 'vue-router'
import type { RouteRecordRaw } from 'vue-router'
import Home from '../views/Home.vue'
import Detail from '../views/Detail.vue'
import Create from '../views/Create.vue'
import Profile from '../views/Profile.vue'

const routes: Array<RouteRecordRaw> = [
  {
    path: '/',
    name: 'Home',
    component: Home,
    meta: { title: '首页' }
  },
  {
    path: '/auction/:id',
    name: 'Detail',
    component: Detail,
    meta: { title: '拍卖详情' }
  },
  {
    path: '/create',
    name: 'Create',
    component: Create,
    meta: { title: '创建拍卖' }
  },
  {
    path: '/profile',
    name: 'Profile',
    component: Profile,
    meta: { title: '个人中心' }
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
