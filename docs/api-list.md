# Spring AI Alibaba REST 接口清单

> 来源：扫描所有 Controller 源码自动整理，共 41 个 Controller、295+ 端点。
> 统一返回结构：`Result<T>` = `{ code, message, data: T }`；分页为 `PageResult<T>` / `PagingList<T>` = `{ total, list, current, size }`。
> 流式接口（SSE）返回 `Flux<ServerSentEvent<String>>` 或 `SseEmitter`。

## 关于本清单

### 模块覆盖（多模块扫描）

Spring AI Alibaba Admin 是多模块工程，含 4 个 Maven 子模块，全量扫描并交叉验证 `@RestController/@Controller`、`@*Mapping`、`RouterFunction`、`@MessageMapping` 以及"接口带 `@RequestMapping` + 实现类无注解"的自动暴露模式：

| 子模块 | Controller 数 | 说明 |
|--------|--------------|------|
| spring-ai-alibaba-admin-server-start | 30 | 控制台与平台 API 主要承载模块 |
| spring-ai-alibaba-admin-server-openapi | 1 | 对外 OpenAPI（ChatController） |
| spring-ai-alibaba-admin-server-core | 0 | 纯领域/服务层，无 web 端点 |
| spring-ai-alibaba-admin-server-runtime | 0 | 纯 domain/service，无 web 端点 |

### 接口分类（对外 vs 内部）

每个章节标注类别：

- **【对外·OpenAPI】**：`/api/v1/apps/**`，面向第三方调用。
- **【对外·控制台/平台】**：`/console/v1/**`、`/api/**`、`/oauth2/**`，面向 Admin 前端与平台用户，需登录态鉴权。
- **【内部】**：调试 UI 后端、graph builder SDK 接口、示例/测试代码，不建议第三方直接依赖。

### 返回结构阅读指引

- `Result<String>`：POST 创建类返回**新建资源 ID**（appId、kbId、toolId、accountId 等）；PUT 更新类的 `data` 通常为 `null`，仅表示成功（如 updateApp、changePassword）。
- `Object`：出现在 `chat/completions`、`workflow/completions` 等接口，表示同一端点按入参 `stream` 标志在 **SSE 流式**与 **JSON 同步**两种形态间切换，非类型未定。

---

## 目录

- [1. 认证 / 账号](#1-认证--账号) 【对外·控制台/平台】
- [2. Prompt 管理](#2-prompt-管理) 【对外·控制台/平台】
- [3. 数据集管理](#3-数据集管理) 【对外·控制台/平台】
- [4. 评估器管理](#4-评估器管理) 【对外·控制台/平台】
- [5. 实验管理](#5-实验管理) 【对外·控制台/平台】
- [6. 模型配置（Studio）](#6-模型配置studio) 【对外·控制台/平台】
- [7. 可观测性](#7-可观测性) 【对外·控制台/平台】
- [8. 应用管理](#8-应用管理) 【对外·控制台/平台】
- [9. 工作流调试](#9-工作流调试) 【对外·控制台/平台】
- [10. 知识库 / 文档 / 分块](#10-知识库--文档--分块) 【对外·控制台/平台】
- [11. 模型 / Provider 管理](#11-模型--provider-管理) 【对外·控制台/平台】
- [12. 工具 / 插件](#12-工具--插件) 【对外·控制台/平台】
- [13. MCP Server](#13-mcp-server) 【对外·控制台/平台】
- [14. Agent Schema](#14-agent-schema) 【对外·控制台/平台】
- [15. 文件上传](#15-文件上传) 【对外·控制台/平台】
- [16. API Key](#16-api-key) 【对外·控制台/平台】
- [17. 工作空间](#17-工作空间) 【对外·控制台/平台】
- [18. 组件服务](#18-组件服务) 【对外·控制台/平台】
- [19. Chat 对话（OpenAPI）](#19-chat-对话openapi) 【对外·OpenAPI】
- [20. OAuth2](#20-oauth2) 【对外·控制台/平台】
- [21. 系统](#21-系统) 【对外·控制台/平台】
- [21b. 平台总览](#21b-平台总览) 【对外·控制台/平台】
- [22. 代码生成器（Graph Studio）](#22-代码生成器graph-studio) 【内部】
- [23. Studio 调试 UI 后端](#23-studio-调试-ui-后端) 【内部】
- [24. 示例应用](#24-示例应用) 【内部·示例】

---

## 1. 认证 / 账号

**Base path：** `/console/v1/auth`、`/console/v1/accounts` · 【对外·控制台/平台】

### 1.1 认证

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/auth/login` | 用户名密码登录，返回 JWT Token |
| POST | `/console/v1/auth/refresh-token` | 刷新 Token |
| POST | `/console/v1/auth/logout` | 退出登录，使 Token 失效 |

**POST `/console/v1/auth/login`**
- 入参：`LoginRequest { username, password }`
- 返回：`Result<TokenResponse>` — `{ accessToken(access_token), refreshToken(refresh_token), expiresIn(expires_in) }`

**POST `/console/v1/auth/refresh-token`**
- 入参：`RefreshTokenRequest { refreshToken(refresh_token) }`
- 返回：`Result<TokenResponse>`

**POST `/console/v1/auth/logout`**
- 入参：Header 携带 Token（`HttpServletRequest`）
- 返回：`Result<Void>`

### 1.2 账号管理

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/accounts` | 创建账号（返回新建 accountId） |
| GET | `/console/v1/accounts` | 分页查询账号列表 |
| GET | `/console/v1/accounts/{accountId}` | 获取账号详情 |
| PUT | `/console/v1/accounts/{accountId}` | 更新账号信息 |
| DELETE | `/console/v1/accounts/{accountId}` | 删除账号 |
| PUT | `/console/v1/accounts/change-password` | 修改密码 |
| GET | `/console/v1/accounts/profile` | 获取当前登录用户信息 |

**POST `/console/v1/accounts`**
- 入参：`Account { username, password, email, mobile, status, type, nickname, icon, ... }`
- 返回：`Result<String>` — 新建 accountId

**GET `/console/v1/accounts`**
- 入参：`BaseQuery { page, size, keyword }` (query string)
- 返回：`Result<PagingList<Account>>`

**PUT `/console/v1/accounts/change-password`**
- 入参：`ChangePasswordRequest { password, newPassword(new_password) }`
- 返回：`Result<String>` — `data` 为 `null`，仅表示成功

---

## 2. Prompt 管理

**Base path：** `/api` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/prompt` | 创建 Prompt |
| GET | `/api/prompt` | 按 promptKey 获取 Prompt |
| GET | `/api/prompts` | 分页列表 |
| PUT | `/api/prompt` | 更新 Prompt |
| DELETE | `/api/prompt` | 删除 Prompt |
| POST | `/api/prompt/version` | 创建 Prompt 版本 |
| GET | `/api/prompt/version` | 获取指定版本详情 |
| GET | `/api/prompt/versions` | 版本分页列表 |
| GET | `/api/prompt/version/diff` | 对比两个版本的内容与元信息（✅ 已上线） |
| GET | `/api/prompt/template` | 获取 Prompt 模板详情 |
| GET | `/api/prompt/templates` | 模板分页列表 |
| POST | `/api/prompt/run` | 执行 Prompt（流式） |
| GET | `/api/prompt/session` | 获取对话 Session |
| DELETE | `/api/prompt/session` | 删除对话 Session |

**POST `/api/prompt`**
- 入参：`PromptCreateRequest { promptKey, promptDescription, tags }`
- 返回：`Result<Prompt>`

**GET `/api/prompt`**
- 入参：`?promptKey=xxx` (必填)
- 返回：`Result<Prompt>`

**GET `/api/prompts`**
- 入参：`PromptListRequest { page, size, keyword }` (query string)
- 返回：`Result<PageResult<Prompt>>`

**POST `/api/prompt/version`**
- 入参：`PromptVersionCreateRequest { promptKey, content, remark, ... }`
- 返回：`Result<PromptVersion>`

**GET `/api/prompt/version`**
- 入参：`?promptKey=xxx&version=xxx` (均必填)
- 返回：`Result<PromptVersionDetail>`

**GET `/api/prompt/version/diff`** ✅
- 入参：`?promptKey=xxx&versionA=v3&versionB=v5`（均必填，`@NotBlank`）
- 返回：`Result<PromptVersionDiffResult>` — `{ promptKey, versionA: { version, status, createTime(epoch ms) }, versionB: { version, status, createTime(epoch ms) }, diffs: { template: { changed, valueA, valueB }, variables: { changed, valueA, valueB }, modelConfig: { changed, valueA, valueB } } }`。null 字段值返回 `""`，`changed` 基于 `Objects.equals(nullToEmpty(a), nullToEmpty(b))` 判定

**POST `/api/prompt/run`**
- 入参：`PromptRunRequest { sessionId, promptKey, version, template, variables, modelConfig, message, newSession, mockTools }`
- 返回：`Flux<PromptRunResponse>` — SSE 流式响应

**GET `/api/prompt/session`**
- 入参：`?sessionId=xxx` (必填)
- 返回：`Result<ChatSession>` — `{ sessionId, promptKey, version, template, variables, modelConfig, messages, mockTools, createTime, lastUpdateTime }`

---

## 3. 数据集管理

**Base path：** `/api/dataset` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/dataset/dataset` | 创建数据集 |
| GET | `/api/dataset/datasets` | 数据集分页列表 |
| GET | `/api/dataset/dataset` | 获取数据集详情 |
| PUT | `/api/dataset/dataset` | 更新数据集 |
| DELETE | `/api/dataset/dataset` | 删除数据集 |
| POST | `/api/dataset/datasetVersion` | 创建数据集版本 |
| GET | `/api/dataset/datasetVersions` | 版本分页列表 |
| PUT | `/api/dataset/datasetVersion` | 更新版本信息 |
| POST | `/api/dataset/dataItem` | 创建数据项 |
| GET | `/api/dataset/dataItems` | 数据项分页列表 |
| GET | `/api/dataset/dataItem` | 获取单条数据项 |
| PUT | `/api/dataset/dataItem` | 更新数据项 |
| DELETE | `/api/dataset/dataItem` | 删除数据项 |
| GET | `/api/dataset/experiments` | 关联实验列表 |
| POST | `/api/dataset/dataItemFromTrace` | 从链路追踪创建数据项 |

**POST `/api/dataset/dataset`**
- 入参：`DatasetCreateRequest { name, description, columnsConfig: List<DatasetColumn> }`
- 返回：`Result<Dataset>`

**GET `/api/dataset/datasets`**
- 入参：`DatasetListRequest { page, size, keyword }` (query string)
- 返回：`Result<PageResult<Dataset>>`

**GET `/api/dataset/dataset`**
- 入参：`?datasetId=123` (必填)
- 返回：`Result<Dataset>`

**POST `/api/dataset/dataItem`**
- 入参：`DatasetItemCreateRequest { datasetId, dataContent: List<String>, columnsConfig }`
- 返回：`Result<List<DatasetItem>>`

**POST `/api/dataset/dataItemFromTrace`**
- 入参：`DataItemCreateFromTraceRequest { datasetId, datasetVersionId, dataContent, columnsConfig }`
- 返回：`Result<List<DatasetItem>>`

---

## 4. 评估器管理

**Base path：** `/api/evaluator` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/evaluator/evaluator` | 创建评估器 |
| GET | `/api/evaluator/evaluators` | 评估器分页列表 |
| GET | `/api/evaluator/evaluator` | 获取评估器详情 |
| PUT | `/api/evaluator/evaluator` | 更新评估器 |
| DELETE | `/api/evaluator/evaluator` | 删除评估器 |
| POST | `/api/evaluator/evaluatorVersion` | 创建评估器版本 |
| GET | `/api/evaluator/evaluatorVersions` | 版本分页列表 |
| POST | `/api/evaluator/debug` | 调试评估器 |
| GET | `/api/evaluator/templates` | 评估器模板列表 |
| GET | `/api/evaluator/template` | 获取模板详情 |
| GET | `/api/evaluator/experiments` | 关联实验列表 |

**POST `/api/evaluator/evaluator`**
- 入参：`EvaluatorCreateRequest { name, description }`
- 返回：`Result<Evaluator>`

**POST `/api/evaluator/debug`**
- 入参：`EvaluatorTestRequest { modelConfig, prompt, variables }`
- 返回：`Result<EvaluatorDebugResult>` — `{ score, reason }`

**GET `/api/evaluator/templates`**
- 入参：`EvaluatorTemplateListRequest { page, size }` (query string)
- 返回：`Result<PageResult<EvaluatorTemplate>>`

---

## 5. 实验管理

**Base path：** `/api` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/experiment` | 创建实验 |
| GET | `/api/experiments` | 实验分页列表 |
| GET | `/api/experiment` | 获取实验详情 |
| GET | `/api/experiment/results` | 获取实验整体评估结果 |
| GET | `/api/experiment/result` | 获取单个评估结果明细（分页） |
| PUT | `/api/experiment/stop` | 停止实验 |
| PUT | `/api/experiment/restart` | 重启实验 |
| DELETE | `/api/experiment` | 删除实验 |

**POST `/api/experiment`**
- 入参：`ExperimentCreateRequest { name, description, datasetId, datasetVersionId, datasetVersion, evaluationObjectConfig, evaluatorConfig }`
- 返回：`Result<Experiment>`

**GET `/api/experiment/results`**
- 入参：`?experimentId=123` (必填)
- 返回：`Result<List<ExperimentEvaluatorResult>>` — 每项 `{ experimentId, averageScore, evaluatorVersionId, progress, completeItemsCount, totalItemsCount }`

**GET `/api/experiment/result`**
- 入参：`ExperimentEvaluatorResultDetailListRequest { experimentId, evaluatorId, page, size }`
- 返回：`Result<PageResult<ExperimentEvaluatorResultDetail>>` — 每项 `{ experimentId, input, actualOutput, referenceOutput, score, reason, evaluationTime, evaluatorVersionId, ... }`

---

## 6. 模型配置（Studio）

**Base path：** `/api` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/model/supported` | 查询支持的模型提供商列表 |
| GET | `/api/models` | 模型配置分页列表 |
| GET | `/api/model` | 按 ID 获取单条模型配置 |
| GET | `/api/models/enabled` | 获取所有已启用的模型配置 |

**GET `/api/model/supported`**
- 入参：无
- 返回：`Result<List<String>>` — 提供商名称列表，如 `["openai","dashscope","deepseek"]`

**GET `/api/models`**
- 入参：`ModelConfigQueryRequest { page(默认1), size(默认10), name, provider, status }` (query string)
- 返回：`Result<PageResult<ModelConfigResponse>>`

**GET `/api/model`**
- 入参：`?id=123` (必填)
- 返回：`Result<ModelConfigResponse>` — `{ id, name, provider, modelName, baseUrl, defaultParameters, supportedParameters, status, createTime, updateTime }`

**GET `/api/models/enabled`**
- 入参：无
- 返回：`Result<List<ModelConfigResponse>>`

---

## 7. 可观测性

**Base path：** `/api/observability` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/observability/traces` | 链路列表（分页） |
| GET | `/api/observability/traces/{traceId}` | 获取 Trace 详情及 Span 树 |
| GET | `/api/observability/services` | 服务列表及统计 |
| GET | `/api/observability/overview` | 全局概览统计 |

**GET `/api/observability/traces`**
- 入参：`TracesQueryRequest { serviceName, traceId, spanName, startTime, endTime, attributes, pageNumber(默认1), pageSize(默认50) }` (query string)
- 返回：`Result<PageResult<TraceSpanDTO>>`

**GET `/api/observability/traces/{traceId}`**
- 入参：`traceId` (path)
- 返回：`Result<TraceDetailDTO>` — `{ records: List<TraceSpanDTO> }`（含完整 Span 树）

**GET `/api/observability/services`**
- 入参：`ServicesQueryRequest { startTime, endTime }` (query string)
- 返回：`Result<ServicesResponseDTO>` — `{ services: List<ServiceInfoDTO> }`

**GET `/api/observability/overview`**
- 入参：`OverviewQueryRequest { startTime, endTime }` (query string)
- 返回：`Result<OverviewStatsDTO>` — `{ operationCount(operation.count), modelCount(model.count), usageTokens(usage.tokens) }`，每项为 `StatDetail { total, detail: List<StatItem> }`

---

## 8. 应用管理

**Base path：** `/console/v1/apps` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/apps` | 创建应用（返回新建 appId） |
| GET | `/console/v1/apps` | 应用分页列表 |
| GET | `/console/v1/apps/{appId}` | 获取应用详情 |
| PUT | `/console/v1/apps/{appId}` | 更新应用 |
| DELETE | `/console/v1/apps/{appId}` | 删除应用 |
| POST | `/console/v1/apps/{appId}/publish` | 发布应用 |
| POST | `/console/v1/apps/{appId}/copy` | 复制应用（返回新 appId） |
| GET | `/console/v1/apps/{appId}/versions` | 应用版本列表 |
| GET | `/console/v1/apps/{appId}/versions/{version}` | 获取指定版本详情 |
| POST | `/console/v1/apps/chat/completions` | 应用对话（内部调试用，见 §19 同形态） |

**POST `/console/v1/apps`**
- 入参：`Application { name, description, type(AppType), status, config, icon, source, ... }`
- 返回：`Result<String>` — 新建 appId

**POST `/console/v1/apps/{appId}/publish`**
- 入参：`appId` (path)
- 返回：`Result<Void>`

**POST `/console/v1/apps/chat/completions`**
- 入参：`AgentRequest { appId, conversationId, messages, stream, promptVariables, extraParams, draft }`，`HttpServletResponse`
- 返回：SSE 流（`stream=true`）或 JSON

---

## 9. 工作流调试

**Base path：** `/console/v1/apps` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/apps/workflow/debug/init` | 初始化工作流调试，返回入参定义 |
| POST | `/console/v1/apps/workflow/debug/run-task` | 执行调试任务 |
| POST | `/console/v1/apps/workflow/debug/get-task-process` | 查询任务执行进度 |
| POST | `/console/v1/apps/workflow/debug/resume-task` | 恢复暂停的任务 |
| POST | `/console/v1/apps/workflow/debug/part-graph/run-task` | 执行子图任务 |
| POST | `/console/v1/apps/workflow/debug/part-graph/stop-task` | 停止子图任务 |
| POST | `/console/v1/apps/workflow/{appId}/run_stream` | 正式运行工作流（SSE 流） |

**POST `/console/v1/apps/workflow/debug/init`**
- 入参：`InitRequest { appId, version }`
- 返回：`Result<List<TaskRunParam>>` — 入参字段定义列表

**POST `/console/v1/apps/workflow/debug/run-task`**
- 入参：`TaskRunRequest { appId, inputs: List<TaskRunParam>, conversationId, version }`
- 返回：`Result<TaskRunResponse>` — `{ taskId, conversationId, requestId }`

**POST `/console/v1/apps/workflow/{appId}/run_stream`**
- 入参：`appId` (path)，`ApiTaskRunRequest { inputs, conversationId }`
- 返回：`SseEmitter` — 实时事件流

---

## 10. 知识库 / 文档 / 分块

**Base path：** `/console/v1/knowledge-bases`、`/console/v1/documents` · 【对外·控制台/平台】

### 知识库

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/knowledge-bases` | 创建知识库（返回 kbId） |
| GET | `/console/v1/knowledge-bases` | 知识库分页列表 |
| GET | `/console/v1/knowledge-bases/{kbId}` | 获取知识库详情 |
| PUT | `/console/v1/knowledge-bases/{kbId}` | 更新知识库 |
| DELETE | `/console/v1/knowledge-bases/{kbId}` | 删除知识库 |
| POST | `/console/v1/knowledge-bases/query-by-codes` | 按 code 批量查询 |
| POST | `/console/v1/knowledge-bases/retrieve` | 向量检索（RAG 召回） |

**POST `/console/v1/knowledge-bases/retrieve`**
- 入参：`DocumentRetrieverQuery { query, searchOptions(search_options): FileSearchOptions }`
- 返回：`Result<List<DocumentChunk>>` — 每项 `{ docId, docName, title, text, score, pageNumber, chunkId, enabled, workspaceId }`

### 文档

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/knowledge-bases/{kbId}/documents` | 批量创建文档（返回文档 ID 列表） |
| GET | `/console/v1/knowledge-bases/{kbId}/documents` | 文档分页列表 |
| GET | `/console/v1/knowledge-bases/{kbId}/documents/{docId}` | 获取文档详情 |
| PUT | `/console/v1/knowledge-bases/{kbId}/documents/{docId}` | 更新文档 |
| DELETE | `/console/v1/knowledge-bases/{kbId}/documents/{docId}` | 删除文档 |
| DELETE | `/console/v1/knowledge-bases/{kbId}/documents/batch-delete` | 批量删除文档 |
| PUT | `/console/v1/knowledge-bases/{kbId}/documents/{docId}/re-index` | 重新索引文档 |

**POST `/console/v1/knowledge-bases/{kbId}/documents`**
- 入参：`CreateDocumentRequest { kbId, files: List<UploadPolicy>, type(DocumentType), processConfig }`
- 返回：`Result<List<String>>` — 文档 ID 列表

### 文档分块

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/documents/{docId}/chunks` | 创建分块（返回 chunkId） |
| GET | `/console/v1/documents/{docId}/chunks` | 分块分页列表 |
| PUT | `/console/v1/documents/{docId}/chunks/{chunkId}` | 更新分块 |
| DELETE | `/console/v1/documents/{docId}/chunks/{chunkId}` | 删除分块 |
| DELETE | `/console/v1/documents/{docId}/chunks/batch-delete` | 批量删除分块 |
| POST | `/console/v1/documents/{docId}/chunks/preview` | 预览分块效果（不入库） |
| PUT | `/console/v1/documents/{docId}/chunks/update-status` | 批量更新分块状态 |

---

## 11. 模型 / Provider 管理

**Base path：** `/console/v1/models`、`/console/v1/providers` · 【对外·控制台/平台】

### 模型选择器

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/console/v1/models/{modelType}/selector` | 按类型获取可用模型分组列表 |
| GET | `/console/v1/models/enabled` | 获取已启用模型列表 |

**GET `/console/v1/models/{modelType}/selector`**
- 入参：`modelType` (path) — 如 `chat`、`embedding`
- 返回：`Result<List<ModelProviderGroup>>` — 每项 `{ provider: ProviderConfigInfo, models: List<ModelConfigInfo> }`

### Provider 配置

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/providers` | 添加 Provider |
| GET | `/console/v1/providers` | Provider 列表 |
| GET | `/console/v1/providers/{provider}` | 获取 Provider 详情 |
| PUT | `/console/v1/providers/{provider}` | 更新 Provider |
| DELETE | `/console/v1/providers/{provider}` | 删除 Provider |
| GET | `/console/v1/providers/protocols` | 查询支持的协议列表 |
| POST | `/console/v1/providers/{provider}/models` | 为 Provider 添加模型 |
| GET | `/console/v1/providers/{provider}/models` | 查询 Provider 下的模型 |
| GET | `/console/v1/providers/{provider}/models/{modelId}` | 获取模型详情 |
| PUT | `/console/v1/providers/{provider}/models/{modelId}` | 更新模型配置 |
| DELETE | `/console/v1/providers/{provider}/models/{modelId}` | 删除模型 |
| GET | `/console/v1/providers/{provider}/models/{modelId}/parameter_rules` | 获取模型参数规则 |

**GET `/console/v1/providers/{provider}`**
- 入参：`provider` (path)
- 返回：`Result<ProviderConfigInfo>` — `{ provider, name, description, icon, credential, enable, source, protocol, supportedModelTypes, modelCount, ... }`

**GET `/console/v1/providers/{provider}/models/{modelId}/parameter_rules`**
- 入参：`provider`(path), `modelId`(path)
- 返回：`Result<List<ParameterRule>>` — 每项 `{ code, name, type, defaultValue, min, max, precision, options, required, help, ... }`

---

## 12. 工具 / 插件

**Base path：** `/console/v1/tools`、`/console/v1`（plugins） · 【对外·控制台/平台】

### 工具（内置）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/tools` | 创建工具 |
| GET | `/console/v1/tools` | 全量工具列表 |
| GET | `/console/v1/tools/page` | 工具分页列表 |
| GET | `/console/v1/tools/{id}` | 获取工具详情 |
| PUT | `/console/v1/tools/{id}` | 更新工具 |
| DELETE | `/console/v1/tools/{id}` | 删除工具 |
| GET | `/console/v1/tools/search` | 按名称搜索工具 |
| GET | `/console/v1/tools/plugin/{pluginId}` | 按插件 ID 查询工具 |
| PATCH | `/console/v1/tools/{id}/enabled` | 启用 / 禁用工具 |

**PATCH `/console/v1/tools/{id}/enabled`**
- 入参：`id` (path)，`?enabled=true/false` (必填)
- 返回：`Result<Void>`

**GET `/console/v1/tools/page`**
- 入参：`?current=1&size=10` (默认值)
- 返回：`Result<PagingList<ToolEntity>>`

### 插件

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/plugins` | 创建插件（返回 pluginId） |
| GET | `/console/v1/plugins` | 插件分页列表 |
| GET | `/console/v1/plugins/{pluginId}` | 获取插件详情 |
| PUT | `/console/v1/plugins/{pluginId}` | 更新插件 |
| DELETE | `/console/v1/plugins/{pluginId}` | 删除插件 |
| POST | `/console/v1/plugins/{pluginId}/tools` | 为插件添加工具（返回 toolId） |
| GET | `/console/v1/plugins/{pluginId}/tools` | 插件工具列表 |
| GET | `/console/v1/plugins/{pluginId}/tools/{toolId}` | 获取插件工具详情 |
| PUT | `/console/v1/plugins/{pluginId}/tools/{toolId}` | 更新插件工具 |
| DELETE | `/console/v1/plugins/{pluginId}/tools/{toolId}` | 删除插件工具 |
| POST | `/console/v1/plugins/{pluginId}/tools/{toolId}/test` | 测试插件工具 |
| POST | `/console/v1/plugins/{pluginId}/tools/{toolId}/publish` | 发布插件工具 |
| POST | `/console/v1/tools/{toolId}/enable` | 启用工具 |
| POST | `/console/v1/tools/{toolId}/disable` | 禁用工具 |
| POST | `/console/v1/tools/query-by-ids` | 按 ID 批量查询工具 |

---

## 13. MCP Server

**Base path：** `/console/v1/mcp-servers` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/mcp-servers` | 注册 MCP Server（返回 serverCode） |
| PUT | `/console/v1/mcp-servers` | 更新 MCP Server |
| GET | `/console/v1/mcp-servers` | MCP Server 分页列表 |
| GET | `/console/v1/mcp-servers/{serverCode}` | 获取 MCP Server 详情（含工具列表） |
| DELETE | `/console/v1/mcp-servers/{serverCode}` | 删除 MCP Server |
| POST | `/console/v1/mcp-servers/query-by-codes` | 按 code 批量查询 |
| POST | `/console/v1/mcp-servers/debug-tools` | 调试 MCP 工具调用 |

**POST `/console/v1/mcp-servers`**
- 入参：`McpServerDetail { serverCode, name, deployConfig, detailConfig, status, type, bizType, description, installType(默认SSE), tools, deployEnv, source, needTools, ... }`
- 返回：`Result<String>` — serverCode

**GET `/console/v1/mcp-servers/{serverCode}`**
- 入参：`serverCode`(path), `?need_tools=true/false`(必填)
- 返回：`Result<McpServerDetail>`

**POST `/console/v1/mcp-servers/debug-tools`**
- 入参：`McpServerCallToolRequest { requestId, serverCode, toolName, workspaceId, accountId, toolParams }`
- 返回：`Result<McpServerCallToolResponse>` — `{ isError, content: List<Content> }`

---

## 14. Agent Schema

**Base path：** `/console/v1/agent-schemas` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/agent-schemas` | 创建 Agent Schema |
| GET | `/console/v1/agent-schemas` | 全量列表 |
| GET | `/console/v1/agent-schemas/page` | 分页列表 |
| GET | `/console/v1/agent-schemas/{id}` | 获取详情 |
| PUT | `/console/v1/agent-schemas/{id}` | 更新 |
| DELETE | `/console/v1/agent-schemas/{id}` | 删除 |
| GET | `/console/v1/agent-schemas/search` | 按名称搜索 |
| PATCH | `/console/v1/agent-schemas/{id}/enabled` | 启用 / 禁用 |

**GET `/console/v1/agent-schemas/page`**
- 入参：`?current=1&size=10`
- 返回：`Result<PagingList<AgentSchemaEntity>>`

**PATCH `/console/v1/agent-schemas/{id}/enabled`**
- 入参：`id`(path), `?enabled=true/false`(必填)
- 返回：`Result<Void>`

---

## 15. 文件上传

**Base path：** `/console/v1/files` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/files/upload` | 上传文件（服务端转存） |
| GET | `/console/v1/files/download` | 下载 / 预览文件 |
| POST | `/console/v1/files/upload-policies` | 获取前端直传 OSS 策略 |
| GET | `/console/v1/files/get-preview-url` | 获取文件预览链接 |

**POST `/console/v1/files/upload`**
- 入参：`multipart/form-data`，`files[]`（多文件，必填），`category`（必填）
- 返回：`Result<List<UploadPolicy>>` — 每项 `{ name, path, extension, contentType, size, uploadType }`

**POST `/console/v1/files/upload-policies`**
- 入参：`WebUploadRequest { category, files: List<{ name }> }`
- 返回：`Result<List<WebUploadPolicy>>` — 前端直传 OSS 所需签名：`{ accessId, policy, host, expire, signature, securityToken, uploadType, name, path, ... }`

**GET `/console/v1/files/download`**
- 入参：`?path=xxx`(必填), `?preview=true/false`(默认 false)
- 返回：文件字节流（`void`，直接写入 response）

**GET `/console/v1/files/get-preview-url`**
- 入参：`?path=xxx`(必填)
- 返回：`Result<String>` — 预览 URL

---

## 16. API Key

**Base path：** `/console/v1/api-keys` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/api-keys` | 创建 API Key（返回 key 值，仅此次可见） |
| GET | `/console/v1/api-keys` | 分页列表 |
| GET | `/console/v1/api-keys/{id}` | 获取详情 |
| PUT | `/console/v1/api-keys/{id}` | 更新 |
| DELETE | `/console/v1/api-keys/{id}` | 删除 |

**POST `/console/v1/api-keys`**
- 入参：`ApiKey { apiKey, description, accountId, status, ... }`
- 返回：`Result<String>` — 生成的 key 值（仅此次可见）

---

## 17. 工作空间

**Base path：** `/console/v1/workspaces` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/console/v1/workspaces` | 创建工作空间（返回 workspaceId） |
| GET | `/console/v1/workspaces` | 分页列表 |
| GET | `/console/v1/workspaces/{workspaceId}` | 获取详情 |
| PUT | `/console/v1/workspaces/{workspaceId}` | 更新 |
| DELETE | `/console/v1/workspaces/{workspaceId}` | 删除 |

---

## 18. 组件服务

**Base path：** `/console/v1/component-servers` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/console/v1/component-servers` | 组件分页列表 |
| GET | `/console/v1/component-servers/app-publishable` | 可发布应用分页列表 |
| POST | `/console/v1/component-servers` | 发布应用为组件（返回 code） |
| PUT | `/console/v1/component-servers/{code}` | 更新组件 |
| DELETE | `/console/v1/component-servers/{code}` | 删除组件 |
| GET | `/console/v1/component-servers/{code}/detail-by-code` | 按 code 获取组件详情 |
| GET | `/console/v1/component-servers/{appId}/detail-by-appid` | 按 appId 获取组件详情 |
| GET | `/console/v1/component-servers/{code}/query-refer` | 查询引用关系 |
| GET | `/console/v1/component-servers/{appId}/query-config` | 查询组件配置 |
| POST | `/console/v1/component-servers/query-by-codes` | 按 code 批量查询 |
| GET | `/console/v1/component-servers/{code}/query-schema` | 获取组件 Schema |
| POST | `/console/v1/component-servers/schema-by-codes` | 按 code 批量获取 Schema |

**GET `/console/v1/component-servers`**
- 入参：`AppComponentQuery { code, codes, appName, type, appId, config, description, status, page, size }` (query string)
- 返回：`Result<PagingList<AppComponent>>` — 每项 `{ code, name, appName, type, appId, config, description, status, needUpdate, ... }`

---

## 19. Chat 对话（OpenAPI）

**Base path：** `/api/v1/apps` · 【对外·OpenAPI】

> 供外部 Agent 应用调用的标准对话接口。

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v1/apps/chat/completions` | Agent 对话（流式 / 非流式） |
| POST | `/api/v1/apps/workflow/completions` | 工作流同步执行 |
| POST | `/api/v1/apps/workflow/async-completions` | 工作流异步执行 |
| POST | `/api/v1/apps/workflow/stop-completions` | 停止异步任务 |
| POST | `/api/v1/apps/workflow/async-results` | 查询异步执行结果 |

**POST `/api/v1/apps/chat/completions`**
- 入参：`AgentRequest { appId, conversationId, messages, stream(默认false), promptVariables, extraParams, draft }`，`HttpServletResponse`
- 返回：SSE 流（`stream=true`）或 JSON

**POST `/api/v1/apps/workflow/completions`**
- 入参：`WorkflowRequest { appId, conversationId, requestId, messages, stream(默认false), draft, inputParams }`
- 返回：SSE 流 / JSON

**POST `/api/v1/apps/workflow/async-completions`**
- 入参：`WorkflowRequest { ... }`
- 返回：`Result<TaskRunResponse>` — `{ taskId, conversationId, requestId }`

**POST `/api/v1/apps/workflow/async-results`**
- 入参：`AsyncResultRequest { taskId }`
- 返回：`Result<AsyncResultResponse>` — `{ taskId, requestId, conversationId, taskStatus, errorCode, errorInfo, taskExecTime, outputs: List<{ content, nodeId, nodeName, nodeType, nodeStatus }> }`

**POST `/api/v1/apps/workflow/stop-completions`**
- 入参：`TaskStopRequest`
- 返回：`Result<Boolean>`

---

## 20. OAuth2

**Base path：** `/oauth2` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/oauth2/login/github` | 获取 GitHub OAuth 授权跳转 URL |
| GET | `/oauth2/callback/github` | GitHub OAuth 回调，完成登录 |

**GET `/oauth2/login/github`**
- 入参：无
- 返回：`Result<String>` — 授权 URL

**GET `/oauth2/callback/github`**
- 入参：`?code=xxx`（GitHub 回调 code，必填），`HttpServletResponse`
- 返回：`void` — 重定向（写入 Cookie / 跳转前端）

---

## 21. 系统

**Base path：** `/console/v1/system` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/console/v1/system/global-config` | 获取系统全局配置 |
| GET | `/console/v1/system/health` | 健康检查 |

**GET `/console/v1/system/global-config`**
- 入参：无
- 返回：`Result<GlobalConfig>` — `{ loginMethod(login_method), uploadMethod(upload_method) }`

**GET `/console/v1/system/health`**
- 入参：无
- 返回：`"ok"`（纯字符串）

---

## 21b. 平台总览

**Base path：** `/console/v1` · 【对外·控制台/平台】

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/console/v1/overview` | 平台总览数据聚合（✅ 已上线） |

**GET `/console/v1/overview`**
- 入参：无
- 返回：`Result<OverviewResponse>` — `{ stats: { prompts, versions, experiments, datasets, knowledgeBases, models: {total} }, experimentStatus: Map<String,Integer>, topPromptVersions: [{promptKey, preCount, releaseCount}], recentActivities: [{type, title, time, description}], docIndexStatus: [{kbId, kbName, totalDocs, indexedDocs, progress}] }`
- 数据来源：admin 库（prompt/prompt_version/experiment/dataset）+ agentscope 库（knowledge_base/document/model_config），内存聚合

---

## 22. 代码生成器（Graph Studio）

**Base path：** `/graph-studio/api` · 【内部】

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/graph-studio/api/app/delegate` | Graph 应用管理（实现 AppAPI 接口） |
| GET | `/graph-studio/api/dsl/{dialect}` | DSL 导入导出（实现 DSLAPI 接口） |
| GET | `/graph-studio/api/run/{type}` | 运行 Graph（实现 RunnerAPI 接口） |

> 此模块基于 Spring Initializr 框架扩展，`ApplicationController`/`DSLController`/`RunnerController` 分别实现 `AppAPI`/`DSLAPI`/`RunnerAPI` 接口，具体路由由框架约定。`/graph-studio/api/dsl/{dialect}` 的 `dialect` 为 `DSLDialectType` 枚举。

---

## 23. Studio 调试 UI 后端

**Base path：** 无统一前缀 · 【内部】

> 嵌入式调试 UI 的后端接口，供 Studio 前端调用，不建议第三方依赖。

### Thread / App / Graph 元信息

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/list-apps` | 列出可用应用（根 Agent 名称） |
| GET | `/list-graphs` | 列出所有可用图 |
| GET | `/graphs/{graphName}/representation` | 返回指定图的 Mermaid 表示 |
| GET | `/chatui`、`/chatui/` | 重定向到 `/chatui/index.html` |

### 线程管理（App 维度）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/apps/{appName}/users/{userId}/threads/{threadId}` | 获取指定线程 |
| GET | `/apps/{appName}/users/{userId}/threads` | 列出非评估线程 |
| POST | `/apps/{appName}/users/{userId}/threads/{threadId}` | 用指定 ID 创建线程 |
| POST | `/apps/{appName}/users/{userId}/threads` | 创建线程（ID 服务端生成） |
| DELETE | `/apps/{appName}/users/{userId}/threads/{threadId}` | 删除线程 |

### 线程管理（Graph 维度）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/graphs/{graphName}/users/{userId}/threads/{threadId}` | 获取指定图线程 |
| GET | `/graphs/{graphName}/users/{userId}/threads` | 列出非评估图线程 |
| POST | `/graphs/{graphName}/users/{userId}/threads/{threadId}` | 用指定 ID 创建图线程 |
| POST | `/graphs/{graphName}/users/{userId}/threads` | 创建图线程 |
| DELETE | `/graphs/{graphName}/users/{userId}/threads/{threadId}` | 删除图线程 |

### 执行

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/run_sse` | 执行 Agent 运行（SSE 流） |
| POST | `/resume_sse` | 恢复暂停的 Agent 执行（SSE 流） |
| POST | `/graph_run_sse` | 执行图运行（SSE 流） |

**POST `/run_sse`**
- 入参：`AgentRunRequest` (Body)
- 返回：`Flux<ServerSentEvent<String>>`

---

## 24. 示例应用

**Base path：** 各异 · 【内部·示例】

> examples 模块下的演示接口，仅供学习参考。

### Multimodal（`/api`）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/image/from-url` | 用 ChatModel 描述公网 URL 图片 |
| POST | `/api/image/from-resource`（multipart） | 描述上传文件图片 |
| POST | `/api/image/from-resource`（JSON） | 描述 classpath 资源图片 |
| POST | `/api/vision/agent` | 基于 ReactAgent 的多模态视觉 Agent |
| POST | `/api/creative/agent` | 带图像生成工具的创意 Agent |
| POST | `/api/audio/tts` | DashScope 语音合成 |
| GET | `/` | 返回首页 |

### RemoteMcpToolsExample（`/mcpToolsExample`）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/mcpToolsExample/mcpWithReactSpring` | Spring Boot + ReactAgent + 远程 MCP |
| POST | `/mcpToolsExample/mcpWithReact` | 非 Spring Boot + ReactAgent + 远程 MCP |
| POST | `/mcpToolsExample/mcpWithSpringChat` | Spring Boot + ChatClient + 远程 MCP |

### A2AExample（`/api/a2a`）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/a2a/demo` | 运行 A2A（Agent to Agent）统一演示 |
