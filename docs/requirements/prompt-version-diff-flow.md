# Prompt 版本对比 — 改造流程图

> 对应改造点：`docs/requirements/prompt-version-diff-impact.md`
> 不改表结构

---

## 1. 完整调用链（时序图）

```mermaid
sequenceDiagram
    actor User as 👤 用户
    participant FE as 🖥️ PromptVersionDiffModal
    participant API as 🌐 PromptController
    participant SVC as ⚙️ PromptVersionService
    participant DB as 🗄️ MySQL (prompt_version)

    User->>FE: 选择 versionA=v3, versionB=v5<br/>点击"对比"
    FE->>FE: GET /api/prompt/versions<br/>加载版本下拉列表

    User->>FE: 确认对比
    FE->>API: GET /api/prompt/version/diff<br/>?promptKey=customer-service<br/>&versionA=v3&versionB=v5

    API->>API: @Validated 校验入参<br/>(@NotBlank × 3)

    alt 参数为空
        API-->>FE: 400 "参数错误"
    end

    API->>SVC: diff("customer-service", "v3", "v5")

    SVC->>DB: SELECT * FROM prompt<br/>WHERE prompt_key = ?
    alt promptKey 不存在
        DB-->>SVC: null
        SVC-->>API: NOT_FOUND
        API-->>FE: 404 "Prompt 不存在"
    end

    SVC->>DB: SELECT * FROM prompt_version<br/>WHERE prompt_key=? AND version='v3'
    alt versionA 不存在
        DB-->>SVC: null
        SVC-->>API: NOT_FOUND
        API-->>FE: 404 "版本 v3 不存在"
    end

    SVC->>DB: SELECT * FROM prompt_version<br/>WHERE prompt_key=? AND version='v5'
    alt versionB 不存在
        DB-->>SVC: null
        SVC-->>API: NOT_FOUND
        API-->>FE: 404 "版本 v5 不存在"
    end

    DB-->>SVC: PromptVersionDO(v3) {template, variables, modelConfig, status, createTime}
    DB-->>SVC: PromptVersionDO(v5) {template, variables, modelConfig, status, createTime}

    rect rgb(240, 255, 240)
        Note over SVC: DiffFields 组装 (null → "")

        SVC->>SVC: templateChanged = (!nullA||!nullB) && !equals(templateA, templateB)
        SVC->>SVC: varsChanged   = (!nullA||!nullB) && !equals(varsA, varsB)
        SVC->>SVC: configChanged = (!nullA||!nullB) && !equals(configA, configB)

        SVC->>SVC: build DiffItem(template,  changed, valA, valB)
        SVC->>SVC: build DiffItem(variables, changed, valA, valB)
        SVC->>SVC: build DiffItem(modelConfig,changed,valA,valB)

        SVC->>SVC: build VersionMeta(v3, status, createTime)
        SVC->>SVC: build VersionMeta(v5, status, createTime)

        SVC->>SVC: build PromptVersionDiffResult
    end

    SVC-->>API: PromptVersionDiffResult

    API-->>FE: Result<PromptVersionDiffResult> { code:200 }

    rect rgb(255, 248, 240)
        Note over FE: 前端渲染 diff 视图

        FE->>FE: templateDiff: changed=true<br/>→ 行级高亮渲染 (前端自行 diff)
        FE->>FE: variablesDiff: changed=false<br/>→ 灰色"无变化"
        FE->>FE: modelConfigDiff: changed=true<br/>→ JSON 字段级高亮
        FE->>FE: 展示 versionA/versionB 元信息<br/>(状态、创建时间)
    end

    FE-->>User: 对比结果视图
```

---

## 2. 数据流（入参 → DiffItem 转换）

```mermaid
flowchart LR
    subgraph INPUT["入参 (Query String)"]
        PK["promptKey<br/>= 'customer-service'"]
        VA["versionA<br/>= 'v3'"]
        VB["versionB<br/>= 'v5'"]
    end

    subgraph DB_QUERY["DB 查询 (复用已有 Mapper)"]
        Q1["PromptMapper<br/>.selectByPromptKey(PK)"]
        Q2["PromptVersionMapper<br/>.selectByPromptKeyAndVersion(PK, VA)"]
        Q3["PromptVersionMapper<br/>.selectByPromptKeyAndVersion(PK, VB)"]
    end

    subgraph RAW["原始数据 (PromptVersionDO × 2)"]
        DO_A["v3: {template, variables, modelConfig, status, createTime}"]
        DO_B["v5: {template, variables, modelConfig, status, createTime}"]
    end

    subgraph NULL_SAFE["null-safe 处理"]
        NS1["template 为 null → ''"]
        NS2["variables 为 null → ''"]
        NS3["modelConfig 为 null → ''"]
    end

    subgraph COMPARE["逐字段比较"]
        C1["templateDiff.changed<br/>= !equals(tA, tB)"]
        C2["variablesDiff.changed<br/>= !equals(vA, vB)"]
        C3["modelConfigDiff.changed<br/>= !equals(mA, mB)"]
    end

    subgraph META["版本元信息"]
        META_A["VersionMeta(v3, status, createTime)"]
        META_B["VersionMeta(v5, status, createTime)"]
    end

    subgraph OUTPUT["返回 (Result)"]
        R["Result&lt;PromptVersionDiffResult&gt;"]
        R_PK["promptKey"]
        R_VA["versionA: VersionMeta"]
        R_VB["versionB: VersionMeta"]
        R_DIFFS["diffs: DiffFields<br/>├ template: DiffItem<br/>├ variables: DiffItem<br/>└ modelConfig: DiffItem"]
    end

    PK --> Q1
    VA --> Q2
    VB --> Q3
    Q1 -->|"存在性校验"| DO_A
    Q2 --> DO_A
    Q3 --> DO_B

    DO_A --> NS1 & NS2 & NS3
    DO_B --> NS1 & NS2 & NS3

    NS1 --> C1
    NS2 --> C2
    NS3 --> C3

    DO_A --> META_A
    DO_B --> META_B

    C1 & C2 & C3 & META_A & META_B & PK --> OUTPUT
    R --> R_PK & R_VA & R_VB & R_DIFFS
```

---

## 3. 表结构：不改表

> 本需求**不涉及任何 DDL 变更**。
>
> `prompt_version` 表的 `previous_version` 字段（`VARCHAR(32)`，非空，默认 `''`）已在建表时预留，本次不做修改，也不通过后端逻辑消费该字段。`GET /api/prompt/version/diff` 的 `versionA`/`versionB` 由调用方显式传入，不从 `previous_version` 推断。

```mermaid
erDiagram
    prompt_version {
        BIGINT id PK "自增主键"
        VARCHAR prompt_key "FK → prompt"
        VARCHAR version "版本号"
        VARCHAR version_desc "版本描述"
        LONGTEXT template "模板内容 ← diff 对象"
        LONGTEXT variables "变量 JSON ← diff 对象"
        LONGTEXT model_config "模型参数 JSON ← diff 对象"
        VARCHAR status "pre / release"
        VARCHAR previous_version "前置版本 (已有，本次不消费)"
        DATETIME create_time "创建时间 ← VersionMeta"
    }
```

---

## 4. 与现有代码的接缝

| 接缝点 | 现有代码 | 本次改动 |
|--------|----------|----------|
| Controller 路由 | `PromptController` 已有 `GET /api/prompt/version` | 新增 `GET /api/prompt/version/diff`，同 Controller 加方法 |
| Service 接口 | `PromptVersionService` 已有 `getByPromptKeyAndVersion` | 新增 `diff()` 方法签名 |
| DAO 查询 | `PromptVersionMapper.selectByPromptKeyAndVersion` | **不改**：两次调用查出 versionA + versionB |
| DTO | `PromptVersionDetail` 已有 `template` / `variables` / `modelConfig` | 新建 `PromptVersionDiffResult`，不修改现有 DTO |
| 鉴权 | `Authorization: Bearer <token>` 统一拦截 | **不改**：`/api/**` 路径已受保护 |
