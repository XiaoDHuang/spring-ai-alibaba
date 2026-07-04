# Admin 总览页 — 需求文档

> 状态：待审核
> 创建时间：2026-07-04
> 关联接口：`GET /console/v1/overview`

**一句话总结：** 新增 Admin 平台总览首页，以指标卡 + 图表 + 时间线形式展示平台核心数据全貌，用户登录后即可一目了然。

---

## 1. 业务目标

管理员 / 平台用户登录后进入首页，一眼看到平台整体运行状态——有多少资源、实验进展如何、最近谁在改什么，无需逐模块进入查看。

---

## 2. 页面布局

```
┌──────────────────────────────────────────────────────┐
│  指标卡 × 6（一排）                                    │
│  Prompt │ Version │ 实验 │ 数据集 │ 知识库 │ 模型      │
├────────────────────────┬─────────────────────────────┤
│  实验状态饼图           │  Top 10 Prompt 版本柱图       │
│  (DRAFT/RUNNING/       │  (每个 prompt 两根柱:         │
│   COMPLETED/FAILED/    │   pre / release)             │
│   STOPPED)             │                             │
├────────────────────────┼─────────────────────────────┤
│  最近活动 Timeline      │  文档索引状态                 │
│  (三表 UNION, 最近20条) │  (按知识库分组, 进度条+数量)   │
└────────────────────────┴─────────────────────────────┘
```

---

## 3. 接口契约

### 请求

```
GET /console/v1/overview
Authorization: Bearer <token>
```

无入参。

### 返回

```json
{
  "code": 200,
  "message": "success",
  "data": {
    "stats": {
      "prompts":     { "total": 45 },
      "versions":    { "total": 312 },
      "experiments": { "total": 18 },
      "datasets":    { "total": 12 },
      "knowledgeBases": { "total": 8 },
      "models":      { "total": 23 }
    },
    "experimentStatus": {
      "DRAFT": 3, "RUNNING": 2, "COMPLETED": 10,
      "FAILED": 2, "STOPPED": 1
    },
    "topPromptVersions": [
      { "promptKey": "customer-service", "preCount": 8, "releaseCount": 3 },
      { "promptKey": "order-summary",    "preCount": 5, "releaseCount": 2 }
    ],
    "recentActivities": [
      { "type": "prompt_version", "title": "customer-service v5 已发布",
        "time": 1719600000000, "description": "release" },
      { "type": "experiment",    "title": "评估实验: 客服质量对比",
        "time": 1719500000000, "description": "COMPLETED" }
    ],
    "docIndexStatus": [
      { "kbId": "kb-001", "kbName": "产品手册",
        "totalDocs": 50, "indexedDocs": 42, "progress": 0.84 }
    ]
  }
}
```

### 错误码

| 场景 | code |
|------|------|
| 未登录 | 401 |
| 服务异常 | 500 |

---

## 4. 边界场景

| # | 场景 | 预期 |
|---|------|------|
| E01 | 平台全新无数据 | 所有统计为 0/空数组，正常 200，前端展示空状态 |
| E02 | agentscope 库连接失败 | knowledgeBases + models 卡片显示 0 并打 ⚠️ 标记，admin 库卡片正常 |
| E03 | ES 不可用（模型调用量依赖 ES 聚合） | 本期模型调用量暂不实现，留接口位返回空数组 |
| E04 | 某知识库无文档 | `totalDocs=0, indexedDocs=0, progress=0` |
| E05 | agentscope 库的 MyBatis-Plus `BaseMapper.selectCount(null)` 在无数据时返回 `null` 而非 `0` | Service 层 `safeCount()` 做 null-guard：`return v == null ? 0L : v` |
| E06 | `ExperimentMapper.count(null, null)` 的第二个参数类型为 `ExperimentStatus` 枚举，传 `null` 时 MyBatis 动态 SQL `<if test="status != null">` 正确跳过，等效于 `SELECT COUNT(*)` | 实现已验证，null enum 参数行为与 null String 一致 |
| E07 | `DocumentMapper` 的 `kbId` 引用的是 `KnowledgeBaseEntity.kbId`（业务 ID 字符串），而非 `KnowledgeBaseEntity.id`（自增主键），跨表关联需注意字段名 | 实现中 `.eq(DocumentEntity::getKbId, kb.getKbId())` 已修正 |

---

## 5. 不在这次范围

| 候选项 | 决定 |
|--------|------|
| 模型调用量趋势图（需 ES 聚合） | ✂️ 砍掉 — ES 聚合复杂度高，先做简单卡片 |
| 指标环比（%"较上周 +X"） | ✂️ 砍掉 — 需存历史快照，基础设施不够 |
| 实时刷新 / WebSocket 推送 | ✂️ 砍掉 — 手动刷新即可 |
| 可点击跳转（卡片点击进对应模块） | ⏳ 下期 |
| 可配置卡片（用户自定义显示哪些） | ⏳ 下期 |
