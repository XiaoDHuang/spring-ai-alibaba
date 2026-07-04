# Spring AI Alibaba Admin — 核心改造易损链路

> 筛选原则：跨模块/跨中间件、含状态流转或异步行为、改一处可能牵连多处。
> 共 8 条，来源：`docs/api-list.md` + `docs/data-model.md` + `CLAUDE.md`。

---

## 链路总览

| # | 链路名 | 起点 | 关键节点 | 终点 |
|---|--------|------|----------|------|
| 1 | **用户认证 → 全接口鉴权** | `POST /console/v1/auth/login` | AuthController → MySQL(`account`) + Redis(session) → JWT签发 → Spring Interceptor 验签 | 拿到 `access_token` 后可访问任意 `/console/v1/**` 接口 |
| 2 | **Agent 应用创建 → 对话** | `POST /console/v1/apps` | AppController(MySQL insert `app`) → `POST /api/v1/apps/chat/completions` → ChatController → LLM调用(DashScope/OpenAI/DeepSeek) → SSE流式返回 | SSE 流正常推送至 `[DONE]`，MySQL `app` 表记录更新 |
| 3 | **知识库 RAG 全链路** | `POST /console/v1/knowledge-bases` | KB创建(MySQL) → `POST documents`(文件上传/OSS) → RocketMQ异步索引(`topic_saa_studio_document_index`) → ES写入向量 → `POST /retrieve` 召回 `DocumentChunk[]` | `/retrieve` 返回 `score>0` 的 chunk 列表，ES 索引存在 |
| 4 | **MCP Server 注册 → 工具调试** | `POST /console/v1/mcp-servers` | McpServerController(MySQL `mcp_server`) → 建立 SSE/HTTP 连接到外部 MCP Server → `POST /debug-tools` → MCP SDK 调用 → 返回 tool result | `/debug-tools` 返回 `McpServerCallToolResponse`，`isError=false` |
| 5 | **实验评估全流程** | `POST /api/dataset/dataset` | DatasetController(MySQL `dataset`+`data_item`) → EvaluatorController(`evaluator`+`evaluator_version`) → `POST /api/experiment` → 异步评估引擎 → 结果回写 `experiment_result` | `GET /api/experiment/results` 返回 `ExperimentEvaluatorResult[]`，`progress=100%` |
| 6 | **Prompt 版本管理 → 流式执行** | `POST /api/prompt` | PromptController(MySQL `prompt`+`prompt_version`) → `POST /api/prompt/run` → Model调用(SSE) → `Flux<PromptRunResponse>` | SSE 流正常结束，`ChatSession` 存入 Redis |
| 7 | **工作流 Graph 调试** | `POST /console/v1/apps/workflow/debug/init` | WorkflowController → Graph Engine(内存图状态) → `POST /debug/run-task` → 子图调度(Nacos配置下发) → `POST /debug/get-task-process` 轮询进度 | `get-task-process` 返回 `TaskRunResponse{taskId, status=COMPLETED}` |
| 8 | **应用发布 → 组件复用** | `POST /console/v1/apps/{appId}/publish` | AppController(更新 `app.status`) → `POST /console/v1/component-servers`(MySQL `app_component`) → `GET /{code}/query-schema`/`query-refer` | `query-refer` 返回引用列表，`query-schema` 返回完整 DSL |

---

## 每条链路的"为什么容易坏"

### 1. 用户认证 → 全接口鉴权

- **跨存储**：MySQL(`account`) + Redis(session/token) + JWT签名，三者任一故障则全站不可用
- **暗坑**：`account` 表有两个 schema 入口（`agentscope-schema.sql` 建表但 `admin-schema.sql` 也有 account），改造时容易改错 schema
- **改造注意**：修改 `AuthController` 或密码哈希(Argon2)逻辑会直接影响所有接口

### 2. Agent 应用创建 → 对话

- **多模块**：AppController(admin-server-start) → ChatController(admin-server-openapi) → LLM Provider(DashScope SDK / OpenAI SDK)
- **状态机**：`app.status` 字段有 `DRAFT → PUBLISHED` 状态流转，发布后才能通过 OpenAPI 调用
- **SSE 分叉**：同一个 `/chat/completions` 根据 `stream` 参数走 SSE 或 JSON 两条路径，入参 `AgentRequest` 字段多(17+字段)

### 3. 知识库 RAG 全链路

- **四中间件串联**：MySQL → 文件存储(OSS/local) → RocketMQ → ES，任一断则链不通
- **异步窗口**：文档上传后经 RocketMQ 异步建索引，存在延迟，测试时需等待 `topic_saa_studio_document_index` 消费完成
- **ES 映射敏感**：`DocumentChunk` 的向量字段映射由 ES 自动推断，改 Java 实体字段可能导致检索返回空

### 4. MCP Server 注册 → 工具调试

- **外部依赖**：依赖外部 MCP Server 可用（SSE/HTTP 连接），注册时不做连通性校验
- **协议版本**：MCP SDK v0.9.0，服务端协议版本不匹配会静默失败
- **改造注意**：`McpServerDetail` 实体字段 20+，`deployConfig`/`detailConfig` 是 JSON 大字段

### 5. 实验评估全流程

- **异步长任务**：实验启动后异步执行评估，依赖评估器版本+数据集版本+模型配置三者匹配
- **版本锁定**：`dataset_version` 和 `evaluator_version` 是多版本管理，改 entity 的 version 字段需同步改关联查询
- **结果聚合**：`ExperimentEvaluatorResult` 需要 JOIN 三张表(`experiment`+`evaluator`+`dataset`)，改 schema 影响聚合 SQL

### 6. Prompt 版本管理 → 流式执行

- **模板变量注入**：`PromptRunRequest` 含 `variables`(Map)+`template`+`modelConfig`，变量缺失或模板语法错误导致运行时异常
- **Session 管理**：`ChatSession` 存 Redis 非 MySQL，清理 Redis 数据会导致对话历史丢失
- **SSE 格式**：返回 `Flux<PromptRunResponse>`，改 DTO 字段可能破坏前端 SSE 解析

### 7. 工作流 Graph 调试

- **状态机复杂**：Graph 节点状态 `PENDING → RUNNING → COMPLETED/FAILED/PAUSED`，支持暂停→恢复→停止
- **Nacos 耦合**：运行时配置可通过 Nacos 动态下发，Nacos 不可用可能导致 Graph 初始化失败
- **子图嵌套**：`/part-graph/run-task` 支持子图执行，改 Graph 核心逻辑会影响所有嵌套场景

### 8. 应用发布 → 组件复用

- **跨模块引用**：App(admin) → Component(admin) → DSL Export(Graph Studio)，改 App 实体需同步检查 Component 的外键引用
- **引用计数**：`/query-refer` 返回哪些 App 引用了该组件，删除组件前需检查引用关系
- **Schema 导出**：`/query-schema` 依赖 DSL 序列化，改 Agent Schema 结构会影响导出结果

---

> **使用方式**：改造以上任一链路的代码后，按"起点 → 关键节点 → 终点"逐段验证，确保全链路无断点。
> 配套文档：[API 接口清单](api-list.md) · [数据模型](data-model.md) · [环境依赖](env-checklist.md)
