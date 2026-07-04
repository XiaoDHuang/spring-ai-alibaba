# Spring AI Alibaba Admin — 测试缺口分析

> 对照标准：核心链路（`docs/critical-paths.md`） vs 现有测试（`docs/test-status.md`）
> 原则：仅列主链路缺口，宁少勿多；P0 = 改造前必须有，P1 = 有了更好

---

## 缺口总览（15 项）

| # | 优先级 | 对应链路 | 场景描述 | 为什么必须 | 建议测试类型 |
|---|--------|----------|----------|------------|-------------|
| 1 | **P0** | 链路1 认证 | 正常登录 → 拿 JWT → 访问任一 `/console/v1/**` 受保护接口返回 200 | 认证是全站入口，Argon2 密码哈希 / JWT 签发 / Redis session 任一环节改坏则全站不可用 | **集成测试**（需 MySQL + Redis） |
| 2 | **P0** | 链路2 App 对话 | 创建 App → `GET /apps/{id}` 返回完整 App 对象 → `POST /chat/completions` 启动 SSE 收到首 token | App 是核心业务对象，17+ 字段的 `AgentRequest` + SSE/JSON 双路径最容易因字段变更而断裂 | **集成测试**（需 LLM Key） |
| 3 | **P0** | 链路3 知识库检索 | 创建 KB → `POST /retrieve` 传入 query 返回 `List<DocumentChunk>`（允许空，但不能 500） | ES mapping 与 `DocumentChunk` 实体强耦合，改字段名/类型可能导致检索 500 | **集成测试**（需 ES） |
| 4 | **P0** | 链路7 Graph 状态机 | 创建 Checkpoint → 暂停 → 从 Checkpoint 恢复执行 → 状态正确流转 | Graph Engine 是所有工作流底座，Checkpoint 序列化反序列化错误会导致整个流程不可恢复 | **单元 + Characterization Test**（已有 378 个单测，需补 snapshot/回归） |
| 5 | **P0** | 链路5 实验评估 | 创建 Dataset + DataItem → 创建 Evaluator → 创建 Experiment → `GET /results` 返回非空 | 实验链跨 3 张表 JOIN（experiment + evaluator + dataset），schema 变更最易破坏查询 | **集成测试**（需 MySQL） |
| 6 | **P0** | 链路6 Prompt 执行 | 创建 Prompt → 创建 Version → `POST /run`（stream=true）→ 收到 Flux SSE 事件直到 complete | `PromptRunRequest` 含模板变量注入，变量缺失/模板语法错误会抛非预期异常 | **集成测试**（需 LLM Key） |
| 7 | **P0** | 链路4 MCP 注册 | `POST /mcp-servers` 注册 → `GET /{serverCode}?need_tools=true` 返回含工具列表的详情 | `McpServerDetail` 20+ 字段，JSON 大字段 `deployConfig`/`detailConfig` 序列化易出错 | **集成测试**（需 MySQL，可选 mock MCP） |
| 8 | **P0** | 链路1 账号管理 | `POST /accounts` 创建 → `GET /accounts` 分页列表 → `GET /accounts/{id}` 详情一致 | `account` 表有两个 schema 入口（admin + agentscope），字段对齐是改造高频出错点 | **集成测试**（需 MySQL） |
| 9 | **P1** | 链路1 Token 刷新 | `POST /auth/refresh-token` → 新 token 可正常访问受保护接口 | 长时间运行的应用依赖 refresh 机制，token 过期逻辑改坏会导致会话中断 | **集成测试**（需 MySQL + Redis） |
| 10 | **P1** | 链路8 发布组件 | `POST /apps/{id}/publish` → `POST /component-servers` 发布为组件 → `GET /query-schema` 返回 DSL | 跨模块引用链（App → Component → DSL Export），改 App 状态机影响发布流程 | **集成测试**（需 MySQL） |
| 11 | **P1** | 链路3 文档入库 | `POST /knowledge-bases/{kbId}/documents` 上传 → 等待 RocketMQ → ES `_search` 确认文档可检索 | 异步索引链路（MySQL → RocketMQ → ES）有三个断点，任何一段出问题都是静默失败 | **集成测试**（需 ES + RocketMQ） |
| 12 | **P1** | 链路7 工作流调试 | `POST /workflow/debug/init` → `POST /run-task` → `POST /get-task-process` 轮询直到 COMPLETED | Nacos 配置下发 + Graph Engine + 子图嵌套，Nacos 不可用会导致 Graph 初始化失败 | **集成测试**（需 Nacos） |
| 13 | **P1** | 链路4 MCP 调试 | `POST /mcp-servers/debug-tools` → 返回 `McpServerCallToolResponse{isError=false}` | MCP SDK 协议版本敏感，服务端协议不匹配会静默返回空或超时 | **集成测试**（需可用的 MCP Server） |
| 14 | **P1** | 链路5 数据集版本 | `POST /dataset/datasetVersion` → `GET /datasetVersions` → 列表包含新版本且字段完整 | 版本管理是多对多关联，改 entity 字段可能导致版本查询返回脏数据 | **单元测试**（MyBatis-Plus mapper） |
| 15 | **P1** | 链路2 App 状态流转 | App 从 DRAFT → PUBLISHED → 尝试 DELETE 已发布的 App → 返回业务错误 | `app.status` 状态机缺少校验会导致脏数据（已发布的 App 被误删） | **单元测试**（Service 层状态机） |

---

## 缺口分布

| 链路 | 现有测试 | P0 缺口 | P1 缺口 | 风险等级 |
|------|---------|---------|---------|---------|
| 链路1 认证 | 无 | #1 #8 | #9 | 🔴 高 |
| 链路2 App 对话 | 无 | #2 | #15 | 🔴 高 |
| 链路3 知识库 RAG | 无 | #3 | #11 | 🔴 高 |
| 链路4 MCP | 无 | #7 | #13 | 🟠 中 |
| 链路5 实验评估 | 无 | #5 | #14 | 🟠 中 |
| 链路6 Prompt | 无 | #6 | — | 🟠 中 |
| 链路7 Graph 工作流 | 378 单测（仅引擎内部） | #4 | #12 | 🟡 低 |
| 链路8 发布组件 | 无 | — | #10 | 🟡 低 |

---

## 现状 vs 目标

| | 现有 | 目标 |
|------|------|------|
| **有集成测试的链路** | 0 / 8 | 6 / 8 (P0 全覆盖) |
| **admin 模块测试数** | 0 | ≥ 8 (P0 每条至少 1 个) |
| **跨中间件测试** | 0 | ≥ 3 (MySQL+ES / MySQL+RocketMQ / MySQL+Redis) |
| **SSE 流式测试** | 0 | ≥ 2 (chat + prompt) |
| **状态机测试** | 1 (Graph 引擎) | ≥ 3 (Graph + App + Experiment) |

> **不追求覆盖率指标**。目标不是"测试数量多"，而是"改造 8 条核心链路中的任意一条时，至少有 1 个测试能告诉你改坏了"。
>
> 配套文档：[核心链路](critical-paths.md) · [测试状态](test-status.md) · [API 清单](api-list.md)
