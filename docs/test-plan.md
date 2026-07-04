# Spring AI Alibaba Admin — P0 补测试计划

> 来源：`docs/test-gaps.md` P0 缺口
> 原则：Characterization 优先 → 核心链路集成 → 复杂逻辑单元；简单 CRUD 不列

---

## 批次总览

| 批次 | 类型 | 覆盖链路 | 场景 | 预期工作量 |
|------|------|----------|------|-----------|
| **B1** | Characterization Test | 链路7 Graph 状态机 | 录制 Graph Checkpoint 序列化/反序列化 → 存为 golden file，后续改造 diff 对比 | 1h |
| **B2** | 集成测试 | 链路1 认证 | 登录拿 JWT → 访问受保护接口 → 验证 200 | 1.5h |
| **B3** | 集成测试 | 链路2 App 对话 | 创建 App → POST chat/completions (SSE) → 收到首个 chunk | 2h |
| **B4** | 集成测试 | 链路3 知识库检索 | 创建 KB → POST /retrieve → 返回 chunk 列表（允许空，不 500） | 1.5h |
| **B5** | 集成测试 | 链路5 实验评估 | 创建 Dataset → Evaluator → Experiment → GET /results 返回非空 | 3h |
| **B6** | 集成测试 | 链路6 Prompt 执行 | 创建 Prompt + Version → POST /run (stream) → 收到 SSE complete | 2h |
| **B7** | 集成测试 | 链路4 MCP 注册 | POST /mcp-servers → GET /{code} → 返回完整 McpServerDetail | 1h |

> **总工作量**：~12h（7 批次），可分批交付，每批独立可验证。

---

## 详细批次

### B1 — Graph 状态机 Characterization Test

| 项目 | 内容 |
|------|------|
| **类型** | Characterization Test（行为快照） |
| **覆盖** | 链路7：Graph 状态机 Checkpoint 保存 → 序列化 → 反序列化 → 恢复执行 |
| **为什么排第一** | Graph Engine 是所有工作流运行时底座，改造前必须有 golden baseline；已有 378 单测可参考 |
| **做法** | 选取 3-5 个典型 Graph 场景（线性 / 条件分支 / 子图），执行 → 将 Checkpoint JSON 写入 `src/test/resources/golden/`，后续改造跑 diff |
| **验收标准** | `mvn test -pl spring-ai-alibaba-graph-core -Dtest=GoldenCheckpointTest` 绿 |
| **工作量** | 1h |

### B2 — 认证：登录 + JWT 鉴权

| 项目 | 内容 |
|------|------|
| **类型** | 集成测试（需 MySQL + Redis） |
| **覆盖** | 链路1：`POST /console/v1/auth/login` → JWT → 访问 `/console/v1/system/health` → 200 |
| **为什么必须** | 认证是全站入口，Argon2 密码哈希 / JWT 签发 / Redis session / Interceptor 四段任一段改坏全站 401 |
| **关键断言** | 1) 登录返回 `access_token` 非空 2) token 调受保护接口 200 3) 错误密码返回 401 |
| **前置数据** | `account` 表需有预置测试账号（`saa / 123456`） |
| **工作量** | 1.5h |

### B3 — App 创建 + 对话（SSE）

| 项目 | 内容 |
|------|------|
| **类型** | 集成测试（需 MySQL + Redis + LLM Key） |
| **覆盖** | 链路2：`POST /console/v1/apps` → `POST /api/v1/apps/chat/completions` (stream=true) |
| **为什么必须** | App 是核心业务对象，`AgentRequest` 17+ 字段 + SSE/JSON 双路径，字段变更最容易断裂 |
| **关键断言** | 1) 创建返回 appId 非空 2) SSE 流收到 `[DONE]` 或至少 1 个有效 chunk 3) 非流模式返回完整 JSON |
| **前置数据** | 有效的 LLM API Key（DeepSeek/DashScope）+ App 需先发布（PUBLISHED）才能调 OpenAPI |
| **工作量** | 2h |

### B4 — 知识库检索

| 项目 | 内容 |
|------|------|
| **类型** | 集成测试（需 MySQL + ES） |
| **覆盖** | 链路3：`POST /console/v1/knowledge-bases` → `POST /retrieve` |
| **为什么必须** | ES mapping 与 `DocumentChunk` DTO 强耦合；改字段名/类型 → 检索 500 |
| **关键断言** | 1) 创建 KB 返回 kbId 2) retrieve 返回 HTTP 200（允许空结果 `[]`）3) 返回结构符合 `List<DocumentChunk>` schema |
| **前置数据** | ES `loongsuite_traces` 索引存在；q可选：预置测试文档 |
| **工作量** | 1.5h |

### B5 — 实验评估全流程

| 项目 | 内容 |
|------|------|
| **类型** | 集成测试（需 MySQL + LLM Key） |
| **覆盖** | 链路5：Dataset → DataItem → Evaluator → Experiment → Results |
| **为什么必须** | 跨 3 张表 JOIN（experiment + evaluator + dataset），schema 变更最易破坏聚合查询；实验异步执行 |
| **关键断言** | 1) Dataset 创建含 dataItem 2) Evaluator 创建含 version 3) Experiment 创建返回 experimentId 4) `GET /results` 返回非空（轮询至 progress>0） |
| **前置数据** | 有效的 LLM API Key（评估器需调模型评分） |
| **工作量** | 3h |

### B6 — Prompt 版本 + 流式执行

| 项目 | 内容 |
|------|------|
| **类型** | 集成测试（需 MySQL + LLM Key） |
| **覆盖** | 链路6：`POST /api/prompt` → `POST /api/prompt/version` → `POST /api/prompt/run` (stream) |
| **为什么必须** | `PromptRunRequest` 含 variables + template + modelConfig 三层嵌套；SSE 格式变更破坏前端解析；ChatSession 存 Redis 非 MySQL |
| **关键断言** | 1) Prompt 创建成功 2) Version 创建成功 3) run 返回 SSE Flux 直到 complete 4) `GET /api/prompt/session?sessionId=xxx` 返回 ChatSession |
| **前置数据** | 有效的 LLM API Key |
| **工作量** | 2h |

### B7 — MCP Server 注册

| 项目 | 内容 |
|------|------|
| **类型** | 集成测试（需 MySQL，不依赖真实 MCP Server） |
| **覆盖** | 链路4：`POST /console/v1/mcp-servers` → `GET /{serverCode}?need_tools=true` |
| **为什么必须** | `McpServerDetail` 20+ 字段含 JSON 大字段（deployConfig / detailConfig），序列化/反序列化是改造高频出错点 |
| **关键断言** | 1) 注册返回 serverCode 2) GET 详情返回字段完整（serverCode / name / type / deployConfig / tools 非 null）3) DELETE 后可重复注册同名 |
| **前置数据** | 无（注册时不做 MCP Server 连通性校验，纯写库） |
| **工作量** | 1h |

---

## 排序逻辑

```
改造路径上的 Characterization (B1)
  → 核心链路集成 (B2→B7)
    内部按依赖排序：
      B2 认证（入口，最优先）
      B3 App 对话（核心业务）
      B4 知识库检索（ES 耦合）
      B5 实验评估（最复杂多表关联）
      B6 Prompt 执行（SSE 流式）
      B7 MCP 注册（外部依赖，最轻量收尾）
```

## 执行后验收

| 指标 | 当前 | 目标 |
|------|------|------|
| 有集成测试的链路 | 0/8 | **6/8** |
| admin 模块测试用例 | 0 | **≥ 7** |
| SSE 流式测试 | 0 | **≥ 2** (App Chat + Prompt) |
| ES 耦合测试 | 0 | **≥ 1** (KB Retrieve) |
| Golden baseline | 0 | **≥ 1** (Graph Checkpoint) |

> **不列简单 CRUD**（account/workspace/api-key 的增删改查）——这些逻辑薄、出错代价低、出问题一眼可见。
> 配套文档：[核心链路](critical-paths.md) · [测试缺口](test-gaps.md) · [测试状态](test-status.md)
