# Prompt 版本对比 — 改造点清单 & 影响分析

> 关联：`prompt-version-diff.md`（需求）· `prompt-version-diff-flow.md`（流程图）

---

## 改造点清单

| 编号 | 类型 | 文件 | 改什么 |
|------|------|------|--------|
| **P01** | 新增 | `dto/PromptVersionDiffResult.java` | 新建 DTO，含内嵌 `VersionMeta`、`DiffFields`、`DiffItem` |
| **P02** | 修改 | `service/PromptVersionService.java` ~L36 | 接口新增 `diff(String promptKey, String versionA, String versionB)` |
| **P03** | 修改 | `service/impl/PromptVersionServiceImpl.java` ~L145 | 实现 `diff()`：查两版本 → null-safe 比较 → 组装 DiffFields |
| **P04** | 修改 | `controller/PromptController.java` ~L121 | 新增 `@GetMapping("/prompt/version/diff")` |
| **P06** | 无需改动 | `mapper/PromptVersionMapper.java` L27 | 复用 `selectByPromptKeyAndVersion`，不改 SQL |
| **P09** | 修改 | `frontend/.../services/prompt/typing.ts` ~L239 | 新增 `DiffParams`、`DiffResult` 等 TS 类型 |
| **P10** | 修改 | `frontend/.../services/prompt/index.ts` ~L103 | 新增 `getPromptVersionDiff()` |
| **P11** | 新增 | `frontend/.../components/PromptVersionDiffModal.jsx` | 版本对比弹窗（版本选择器 + diff 展示） |
| **P12** | 修改 | `frontend/.../pages/prompts/prompt-detail/prompt-detail.jsx` | "版本对比"按钮 → 打开 diff modal |
| **P15** | 新增 | `test/.../controller/PromptVersionDiffIntegrationTest.java` | 集成测试（404/400/200 各场景） |
| **P17** | 修改 | `docs/api-list.md` ~L125 | 新增 `GET /api/prompt/version/diff` 一行 |

---

## 影响分析

### 1. 现有接口受影响吗？

| 接口 | 影响 | 判断依据 |
|------|------|----------|
| `GET /api/prompt/version` | 🟢 **无影响** | 路径 `/prompt/version` 与 `/prompt/version/diff` 是不同端点；Controller 内无代码交叉 |
| `POST /api/prompt/version` | 🟢 **无影响** | 不走 diff 逻辑；`PromptVersionService.create()` 未修改 |
| `GET /api/prompt/versions` | 🟢 **无影响** | `PromptVersionService.list()` 未修改 |
| `POST /api/prompt/run` | 🟢 **无影响** | `PromptRunService` 不依赖 `PromptVersionService.diff()` |
| 实验评估相关接口（`/api/evaluator/*`, `/api/experiment/*`） | 🟢 **无影响** | `ExperimentServiceImpl` 只调 `getByPromptKeyAndVersion()`，新增 `diff()` 方法不影响现有调用 |
| 其他 `/api/prompt/*`（`/prompt`, `/prompts`, `/prompt/template`, `/prompt/session`） | 🟢 **无影响** | 均不在本次改动范围内 |

**结论：0 个现有接口受影响。** 新端点是纯增量，不与任何现有端点路径冲突。

---

### 2. 现有调用链路受影响吗？

| 调用方 | 调用方法 | 影响 |
|--------|----------|------|
| `PromptController.createPromptVersion()` | `promptVersionService.create()` | 🟢 **无影响** — 实现未改动 |
| `PromptController.getPromptVersion()` | `promptVersionService.getByPromptKeyAndVersion()` | 🟢 **无影响** — 实现未改动 |
| `PromptController.listPromptVersions()` | `promptVersionService.list()` | 🟢 **无影响** — 实现未改动 |
| `ExperimentServiceImpl` L415 | `promptVersionService.getByPromptKeyAndVersion()` | 🟢 **无影响** — 该方法签名和实现不变 |
| 新: `PromptController.diff()` | `promptVersionService.diff()` | 🆕 新增调用链，不触碰已有链路 |

**结论：0 条现有调用链受影响。** `PromptVersionService` 接口是**增量扩展**（加新方法不改变已有方法签名），所有现有调用方透明。

---

### 3. 测试影响

| 测试文件 | 影响 | 说明 |
|----------|------|------|
| **无现有 Prompt 测试** | 🟢 **无需改** | 项目中不存在 `*Prompt*Test*.java`，无需担心破坏已有测试 |
| `AuthIntegrationTest` | 🟢 **无需改** | 认证测试不涉及 Prompt 路径 |
| `graph-core` / `studio` 单元测试 | 🟢 **无需改** | 与 admin 模块无依赖关系 |
| 新增: `PromptVersionDiffIntegrationTest` | 🆕 | P15，独立文件，不影响已有测试 |

**结论：0 个现有测试需修改。** 本项目 Prompt 模块此前无自动化测试。

---

### 4. 文档影响

| 文档 | 影响 | 风险 | 说明 |
|------|------|------|------|
| `docs/api-list.md` | 🟡 需更新 | **低** | §2 Prompt 版本管理段末尾新增一行 `GET /api/prompt/version/diff` |
| `docs/data-model.md` | 🟢 无需改 | — | `prompt_version` 表结构无 DDL 变更；`previousVersion` 字段已记录 |
| `CLAUDE.md` | 🟢 无需改 | — | 无新增模块、无新依赖类型、无禁区触及 |
| `docs/critical-paths.md` | 🟢 无需改 | — | 链路6（Prompt 版本管理 → 流式执行）已覆盖，diff 是版本管理的子功能 |
| `docs/test-plan.md` | 🟢 无需改 | — | B6（Prompt 执行）测试计划不变；diff 测试按 P15 独立追加 |

**结论：仅 api-list.md 需追加一行。** 其他文档无需变动。

---

### 5. 前端兼容性

| 维度 | 风险 | 说明 |
|------|------|------|
| npm 依赖 | 🟢 **低** | **不引入新依赖。** diff 展示用纯 React 组件渲染两个文本并排，行级高亮用 CSS class 标注差异行，JsonDiff 用 `JSON.stringify` + 原生 `===` 比较。无需 `diff` / `jsdiff` / `react-diff-viewer` 等三方库 |
| TypeScript 类型 | 🟢 **低** | 新增类型在 `PromptAPI` namespace 下追加，不修改已有 interface，编译期零破坏 |
| 路由 | 🟢 **低** | `PromptVersionDiffModal` 是弹窗组件，不注册新路由 |
| 已有组件 | 🟢 **低** | `PromptDetailModal.jsx` 和 `prompt-detail.jsx` 只加了按钮入口，不改已有渲染逻辑 |
| `spark-flow` / `spark-i18n` | 🟢 **无影响** | diff 组件在主应用包内，不涉及子包 |

**结论：纯增量，零破坏。** 无新依赖、无路由注册、不改已有组件逻辑。

---

### 6. 性能影响

| 场景 | 风险 | 分析 |
|------|------|------|
| `template` 字段 LONGTEXT（200KB+）| 🟡 **中** | `DiffItem` 同时返回 `valueA` 和 `valueB`，若两版本 template 各 200KB，响应体约 400KB+。**本期不做大小限制**（产品决策），前端虚拟滚动可缓解渲染压力。建议：后续通过 `Transfer-Encoding: chunked` 或前端分页加载优化 |
| 串行两次 DB 查询 | 🟢 **低** | `selectByPromptKeyAndVersion` 是主键+版本号的联合查询，有索引（`prompt_version` 表 `UNIQUE(prompt_key, version)`），单次 <5ms，两次 <10ms |
| 字符串 equals 比较 | 🟢 **低** | `String.equals()` 在 Java 中是 O(n) 但在短-中长度 template 下可忽略；超长 template 首次比较略慢但仍在毫秒级 |
| JSON 序列化 | 🟢 **低** | Jackson 序列化 `Result<PromptVersionDiffResult>` 是标准 Spring Boot 行为，无自定义序列化逻辑 |
| HTTP 传输 | 🟡 **中** | 无 gzip（需确认 Nginx/Spring Boot compression 是否已开启）。`application-local.yml` 无 compression 配置，但 `application.yml` 中 `server.compression.enabled=true` 已对 `text/html` 等启用，**需确认对 `application/json` 也生效** |
| 并发安全性 | 🟢 **低** | 纯只读接口，无锁、无事务写、无状态 |

**结论：性能风险低。** 主要关注点在超大 LONGTEXT 时的网络传输，建议在 `application.yml` 的 `server.compression.mime-types` 中追加 `application/json`。

---

## 风险汇总

| # | 维度 | 风险等级 | 概述 |
|---|------|----------|------|
| 1 | 现有接口 | 🟢 低 | 0 个接口受影响，纯增量端点 |
| 2 | 现有调用链 | 🟢 低 | 0 条链路受影响，接口增量扩展 |
| 3 | 测试 | 🟢 低 | 0 个现有测试需改，本模块此前无测试 |
| 4 | 文档 | 🟢 低 | 仅 api-list.md 加一行 |
| 5 | 前端兼容 | 🟢 低 | 零新依赖，纯增量组件 |
| 6 | 性能 | 🟡 中 | LONGTEXT 大字段时网络传输需关注，建议启用 JSON compression |

---

## 7. 改造步骤与顺序

### 7.1 依赖图

```
S1 (DTO)
 │
 ├──▶ S2 (Service 接口) ──▶ S3 (Service 实现) ──▶ S4 (Controller)
 │                                                      │
 │                                                      ▼
 │                                                   S7 (集成测试)
 │
 └──▶ S5 (前端类型) ──▶ S6 (前端 API) ──▶ S8 (Modal) ──▶ S9 (按钮接入)
```

后端与前端的 TS 类型定义可并行开始；Controller 就绪后集成测试和前端调用可并行。

### 7.2 步骤详表

| 步骤 | 对应改造点 | 做什么 | 前置依赖 | 预估 |
|------|-----------|--------|----------|------|
| **S1** | P01 | 新建 `PromptVersionDiffResult.java`，含 4 个内嵌 POJO：`VersionMeta`(version, status, createTime)、`DiffItem`(changed, valueA, valueB)、`DiffFields`(template, variables, modelConfig 各一个 DiffItem)、顶层 `PromptVersionDiffResult`(promptKey, versionA, versionB, diffs)。所有字段加 `@Data` `@Builder` `@NoArgsConstructor` `@AllArgsConstructor`，与项目已有 DTO 风格一致 | 无 | 20 min |
| **S2** | P02 | 在 `PromptVersionService` 接口中新增方法签名：`PromptVersionDiffResult diff(@NotBlank String promptKey, @NotBlank String versionA, @NotBlank String versionB) throws StudioException` | S1 | 5 min |
| **S3** | P03 | 在 `PromptVersionServiceImpl` 中实现 `diff()`：① 调 `promptMapper.selectByPromptKey` 校验 Prompt 存在 → NOT_FOUND；② 两次调 `promptVersionMapper.selectByPromptKeyAndVersion` 查出 versionA/versionB → NOT_FOUND；③ **决策点 D01**：逐字段比较 `changed` 标志；④ null→`""` 处理后设 `DiffItem.valueA/valueB`；⑤ 组装 `VersionMeta` 和 `DiffFields`；⑥ 返回 | S2 | 45 min |
| **S4** | P04 | 在 `PromptController` 中新增 `@GetMapping("/prompt/version/diff")`，入参 `@RequestParam @NotBlank String promptKey, @RequestParam @NotBlank String versionA, @RequestParam @NotBlank String versionB`，调 `promptVersionService.diff(...)` 包 `Result.success()` 返回。参照现有 `getPromptVersion()` 方法风格 | S3 | 15 min |
| **S5** | P09 | 在 `typing.ts` 的 `PromptAPI` namespace 末尾追加：`DiffParams`、`DiffResult`(含 `VersionMeta`、`DiffFields`、`DiffItem`) 接口定义。字段名与后端 JSON key 对齐（`promptKey`, `versionA`, `versionB`, `diffs`, `changed`, `valueA`, `valueB`） | 无，可与 S1 并行 | 15 min |
| **S6** | P10 | 在 `services/prompt/index.ts` 中新增 `getPromptVersionDiff(params: PromptAPI.DiffParams)`，调用 `GET /api/prompt/version/diff`，返回类型 `PromptAPI.DiffResult`。参照已有的 `getPromptVersion()` 函数写法 | S5 | 10 min |
| **S7** | P15 | 新建 `PromptVersionDiffIntegrationTest.java`（黑盒，参照 `AuthIntegrationTest` 风格）：① `promptKey` 不存在 → 404；② `versionA` 不存在 → 404；③ 正常 diff → 200 + `changed` 正确；④ `versionA==versionB` → 400；⑤ null 字段返回 `""`。前置：需后端运行中 + DB 有预置 prompt 数据 | S4 | 45 min |
| **S8** | P11 | 新建 `PromptVersionDiffModal.jsx`：双下拉选择器（A/B 各取 `GET /api/prompt/versions` 列表，默认 A=最新 release，B=最新 pre），确认后调 `getPromptVersionDiff`，结果分三段展示（template 原始文本并排 + variables JSON 并排 + modelConfig JSON 并排）。行级高亮由前端 `split('\n')` + 逐行 class 标注实现 | S5, S6（类型+API 就绪，后端 S4 可并行等） | 2h |
| **S9** | P12 | 在 `prompt-detail.jsx` 的版本列表工具栏加"版本对比"按钮，`onClick` 打开 `PromptVersionDiffModal`（传 `promptKey` 和当前版本列表） | S8 | 15 min |
| **S10** | P17 | 在 `docs/api-list.md` §2 Prompt 版本管理段末尾追加一行：`GET \| /api/prompt/version/diff \| 对比两个 Prompt 版本的内容与元信息` | 无 | 5 min |

> **总预估**：~5h（后端 1.5h + 前端 2.5h + 测试 0.75h + 文档 0.1h）。前后端可并行启动（S1/S5 无互相依赖）。

---

## 8. 关键决策点

### D01 — JSON 字段（variables / modelConfig）的 `changed` 判定

| 方案 | 做法 | 优点 | 缺点 |
|------|------|------|------|
| **A（推荐）** | `String.equals()` — 直接比较原始字符串。`changed = !Objects.equals(valueA, valueB)` | 零解析开销、不引入 JSON 库依赖、行为可预测 | 若同一个 JSON 的 key 顺序不同（`{"a":1,"b":2}` vs `{"b":2,"a":1}`），会被误判为 `changed=true`，前端可能展示"有差异"但实际内容等价 |
| B | JSON 结构化比较 — 对 variables/modelConfig 先 `ObjectMapper.readTree()` 解析为 `JsonNode`，再 `JsonNode.equals()` 做结构比较 | 语义正确：key 顺序不影响判断；对前端展示更友好 | 引入 JSON 解析开销（每个字段一次 `readTree`）；若字段非合法 JSON 会抛异常需要额外 try-catch |

**推荐 A**，理由：
1. 与需求文档设计一致（"后端返回原始字段值，不生成行级 diff 标注"）；
2. `prompt_version` 表的 variables/modelConfig 由应用层写入（`PromptVersionCreateRequest`），key 顺序稳定，结合实际数据不易出现仅顺序不同的情况；
3. 零额外依赖和异常处理。后续如有大量顺序不一致的反馈，再升到 B 方案成本很低（在 `equals` 前加一层 `try { readTree } catch { fallback to String.equals }`）。

### D02 — 集成测试的后端依赖

| 方案 | 做法 | 优点 | 缺点 |
|------|------|------|------|
| **A（推荐）** | 黑盒测试（参照 `AuthIntegrationTest`）：对运行中 `localhost:8080` 发 HTTP 请求，校验响应 | 和已有测试风格一致（`AuthIntegrationTest` 已跑通）；不依赖 `@SpringBootTest` 上下文启动 | 需后端先启动 + DB 有预置数据 |
| B | `@SpringBootTest` + `TestRestTemplate`：测试内启动 Spring 上下文 | 自包含，不依赖外部进程 | 启动慢（~45s），且之前因 MySQL 连接问题失败过 |

**推荐 A**，与 B2 批次测试保持一致。

### D03 — 前端行级 diff 渲染

单方案（无分歧）：`split('\n')` 后逐行 `===` 比较，用 CSS class `diff-added` / `diff-removed` / `diff-unchanged` 区分。不需要引入 `jsdiff` 或 `react-diff-viewer` 等三方库。原因：后端只返原始值，前端对 template 字段做行级标注是纯字符串操作，~30 行代码即可完成。
