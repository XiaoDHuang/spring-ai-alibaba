# Admin 总览页 — 改造点清单 & 影响分析

> 关联：`overview-page.md`（需求）· `overview-page-solution.md`（技术方案）

---

## 改造点清单

### 后端

| 编号 | 类型 | 文件 | 改什么 |
|------|------|------|--------|
| O01 | 新增 | `dto/OverviewResponse.java` | 新建 DTO，含内嵌 `OverviewStats`、`StatItem`、`TopPromptVersion`、`RecentActivity`、`DocIndexStatus` |
| O02 | 新增 | `service/OverviewService.java` | 接口：`OverviewResponse getOverview()` |
| O03 | 新增 | `service/impl/OverviewServiceImpl.java` | 实现：双库分查 → 内存聚合 → 返回 |
| O04 | 新增 | `controller/OverviewController.java` | `@GetMapping("/console/v1/overview")` → `Result<OverviewResponse>` |
| O05 | 无需改动 | `builder/interceptor/InterceptorConfig.java` | `/console/v1/overview` 已在 `/console/v1/**` 拦截范围内 |

### 前端

| 编号 | 类型 | 文件 | 改什么 |
|------|------|------|--------|
| O06 | 新增 | `pages/Overview/index.tsx` | 总览页组件：6 卡片 + 饼图 + 柱图 + Timeline + 进度条 |
| O07 | 修改 | `layouts/SideMenuLayout.tsx` | 菜单数组追加 `{ path: '/overview', name: '总览', icon: <DashboardOutlined /> }` |
| O08 | 新增 | `services/overview.ts` | `getOverview()` → `GET /console/v1/overview` |

### 测试

| 编号 | 类型 | 文件 | 改什么 |
|------|------|------|--------|
| O09 | 新增 | `test/.../controller/OverviewIntegrationTest.java` | 黑盒集成测试：正常返回 200 + stats 字段非空 |

### 文档

| 编号 | 类型 | 文件 | 改什么 |
|------|------|------|--------|
| O10 | 修改 | `docs/api-list.md` | 新增平台总览接口 |

---

## 影响分析

| 维度 | 风险 | 说明 |
|------|------|------|
| 现有接口 | 🟢 低 | 新增独立 Controller + 路径，零冲突 |
| 现有调用链 | 🟢 低 | 新增 Service，不修改任何现有类 |
| 数据库 | 🟢 低 | 纯只读 `SELECT COUNT(*)` / `GROUP BY`，无锁无事务 |
| 跨库查询 | 🟡 中 | agentscope 库独立 DataSource，需确认 `KnowledgeBaseMapper` 和 `ModelConfigMapper` 在当前 DataSource 路由下可正常注入 |
| 前端 | 🟢 低 | 新增路由 + 页面组件，不改已有页面；不引入新 npm 依赖 |
| 鉴权 | 🟢 低 | `/console/v1/**` 已被 `TokenAuthInterceptor` 覆盖 |

---

## 前端依赖确认

- antd `Card` `Statistic` `Timeline` `Progress` `Row` `Col` `Spin` → 项目已依赖 ✅
- `@ant-design/icons` `DashboardOutlined` → 项目已依赖 ✅
- `@ant-design/charts` → **未确认**。如不可用，用 antd `Progress` 环形 + 纯 CSS 柱条替代，零新依赖

---

## 总预估

| 层 | 改造点 | 工时 |
|------|--------|------|
| 后端 | 4 个（3 新增 + 1 无需改） | 1.5h |
| 前端 | 3 个（2 新增 + 1 修改） | 2h |
| 测试 | 1 个新增 | 0.5h |
| 文档 | 1 个修改 | 0.2h |
| **总计** | **9 个实改** | **~4h** |
