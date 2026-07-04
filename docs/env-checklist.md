# Spring AI Alibaba Admin — 运行环境依赖清单

> 来源：`docs/external-deps.svg`、`application*.yml`、`docker-compose*.yaml`、`pom.xml`、`README` 交叉整理。
> 最后更新：2026-06-28

---

## 一、中间件（自部署 · Docker Compose）

所有中间件均提供 Docker Compose 编排，支持 **Dev 模式**（仅 MySQL）和 **Prod 模式**（全部）。

| # | 名字 | 版本 | 默认端口 | 用途 | 连接信息（本地） |
|---|------|------|----------|------|-----------------|
| 1 | **MySQL** | 8.0.35 | `3306` | 业务主库，存储所有平台、Agent、Schema、评估、实验等数据 | `jdbc:mysql://localhost:3306/admin` · 用户 `admin` / `admin` |
| 2 | **Redis** | 7.2.5 | `6379` | Session 缓存（ChatSession）、分布式锁（Redisson） | `redis://localhost:6379` · 默认 db=0 |
| 3 | **Elasticsearch** | 9.1.2 | `9200` / `9300` | RAG 向量检索、链路追踪 Span 全文索引（`loongsuite_traces`） | `http://localhost:9200` · 禁用安全认证 |
| 4 | **Nacos** | `latest` | `8848`（HTTP）<br>`9848`（gRPC） | 配置中心：Agent 运行时配置下发、Prompt 动态同步 | `localhost:8848` · 单机模式 · `NACOS_AUTH_TOKEN=dG9rZW5hbHNka2ZqbGFza2RqZmxhc2tkamZsYXNrZGpmb3dpZWpmbztzZGxm` |
| 5 | **RocketMQ** | 5.3.2 | `18080`（Proxy）<br>`9876`（NameServer）<br>`10909`/`10911`/`10912`（Broker） | 异步文档索引消息队列（RAG 文档入库） | `localhost:18080` · Proxy 模式连接 · Topic: `topic_saa_studio_document_index` |
| 6 | **LoongCollector** | 3.1.4 | `4318` | OpenTelemetry OTLP 接收器，接收应用 Span 并写入 ES | `http://localhost:4318/v1/traces` |
| 7 | **Kibana** | 9.1.2 | `5601` | （可选）ES 可视化查询工具，仅开发调试用 | `http://localhost:5601` |

### 启动方式

```bash
# 从项目根目录
make env-start MODE=dev     # 仅 MySQL，适用于基础开发
make env-start MODE=prod    # 全部中间件，适用于完整功能测试

# 停止
make env-stop MODE=prod

# 清理（含数据）
make env-clean MODE=prod
```

---

## 二、数据库初始化要求

| 数据库 | Schema 来源 | 包含表数 | 初始化方式 |
|--------|------------|---------|-----------|
| `admin` | `spring-ai-alibaba-admin/docker/middleware/init/mysql/admin-schema.sql` | ~20 张 | Docker 启动时自动执行（挂载到 `/docker-entrypoint-initdb.d/`） |
| `admin`（同上） | `spring-ai-alibaba-admin/docker/middleware/init/mysql/agentscope-schema.sql` | ~10 张 | 同上，两个 SQL 文件在同一数据库中创建表 |

> **注意**：两个 SQL schema 都建在名为 `admin` 的同一数据库中（参见 `mysql.env` → `MYSQL_DATABASE=admin`），
> 并非分开为 admin / agentscope 两个库。

### 初始化要点

1. **MySQL 容器首次启动时自动执行** `init/mysql/` 下全部 `.sql` 文件
2. 字符集统一为 `utf8mb4`，排序规则 `utf8mb4_0900_ai_ci`
3. 所有主键自增起始值为 `AUTO_INCREMENT=10000`
4. 逻辑删除字段统一为 `deleted TINYINT(1) NOT NULL DEFAULT 0`
5. JPA 使用 `ddl-auto: none`（完全由 SQL 脚本管理 schema）

---

## 三、中间件初始化要求

### Elasticsearch

| 初始化项 | 说明 |
|----------|------|
| **Pipeline** | `parsing_loongsuite_traces` — 将 OTLP Span JSON 解析为结构化字段 |
| **索引** | `loongsuite_traces` — 链路追踪 Span 存储索引，mapping 已定义 |
| **初始化脚本** | `docker/middleware/init/elasticsearch/init-indices.sh` |
| **自动执行** | 启动 `elasticsearch-init` 容器，ES 健康检查通过后自动创建 Pipeline → 索引 → 验证 |

### RocketMQ

| 初始化项 | 说明 |
|----------|------|
| **Topic** | `topic_saa_studio_document_index`（NORMAL 类型） |
| **Consumer Group** | `group_saa_studio_document_index` |
| **自动执行** | `rmq-init-topic` 容器在 NameServer + Broker 就绪后自动创建 Topic 和 Group |

### Nacos

| 初始化项 | 说明 |
|----------|------|
| **模式** | `MODE=standalone`（单机模式，生产环境需集群） |
| **认证** | `NACOS_AUTH_IDENTITY_KEY=admin` · `NACOS_AUTH_IDENTITY_VALUE=admin` |
| **命名空间** | 无需手动创建 — Admin 启动时自动注册配置 |

### Redis

| 初始化项 | 说明 |
|----------|------|
| **持久化** | `--appendonly yes`（AOF 模式） |
| **无需特殊配置** | 不涉及 keyspace notification 等高级特性，即开即用 |

---

## 四、外部 API / 云服务

| # | 名字 | 说明 | 获取方式 | 环境变量 |
|---|------|------|----------|----------|
| 1 | **DashScope** | 阿里云百炼大模型服务（Qwen 系列、Embedding、TTS、图像生成） | [百炼控制台](https://bailian.console.aliyun.com/) → API Key | `AI_DASHSCOPE_API_KEY` |
| 2 | **OpenAI** | GPT 系列 Chat / Embedding / Image | [OpenAI Dashboard](https://platform.openai.com/) → API Key | `OPENAI_API_KEY` |
| 3 | **DeepSeek** | DeepSeek Reasoning 模型，OpenAI 兼容 API | [DeepSeek Platform](https://platform.deepseek.com/) → API Key | `DEEPSEEK_API_KEY` |
| 4 | **Ollama** | （可选）本地 LLM 运行时，离线/内网场景 | 本地安装 `ollama pull <model>` | — |
| 5 | **阿里云 OSS** | 文件/文档上传对象存储（前端直传 OSS） | 阿里云控制台 → AccessKey ID / Secret | `ALIBABA_CLOUD_ACCESS_KEY_ID` `ALIBABA_CLOUD_ACCESS_KEY_SECRET` |
| 6 | **阿里云 ARMS** | 可观测遥测服务（可选，通过 `spring.ai.alibaba.arms.enabled` 开关） | 阿里云控制台 → ARMS | 自动配置 |

---

## 五、运行时环境

| # | 名字 | 版本要求 | 说明 |
|---|------|----------|------|
| 1 | **JDK** | 17 | `pom.xml` 中 `java.version=17`，`maven.compiler.source/target=17` |
| 2 | **Maven** | 3.6+ | 项目自带 `mvnw`（Maven Wrapper），无需本地安装 Maven |
| 3 | **Docker** | 20.10+ | 用于启动中间件环境（Docker Compose） |
| 4 | **Docker Compose** | v2+ | Compose 文件使用 `version: '3.8'` 语法 |

---

## 六、应用服务端口

| 组件 | 端口 | 说明 |
|------|------|------|
| Admin Backend | `8080` | Spring Boot Admin 后端，提供 REST API |
| Admin Frontend | `80` | Admin 管理控制台前端 UI |
| Studio 调试 UI | 内嵌后端 | `/chatui/index.html`，嵌入式单页应用 |

---

## 七、Quick Start 最小依赖集

如果只想**快速跑起来体验 ChatBot**，只需：

| 依赖 | 说明 |
|------|------|
| ✅ JDK 17+ | 编译运行 |
| ✅ DashScope API Key | LLM 调用（或选择 OpenAI / DeepSeek） |
| ❌ MySQL / Redis / ES / Nacos / RocketMQ | ChatBot 示例**不需要**这些中间件 |

如果要在**本地完整运行 Admin 平台**，需要：

| 依赖 | 模式 |
|------|------|
| ✅ MySQL | Dev 模式（仅数据库） |
| ✅ MySQL + Redis + ES + Nacos + RocketMQ + LoongCollector | Prod 模式（完整功能） |

---

## 八、环境变量速查

```bash
# ===== LLM API Keys（至少配置一个）=====
export AI_DASHSCOPE_API_KEY=sk-xxxx
export OPENAI_API_KEY=sk-xxxx
export DEEPSEEK_API_KEY=sk-xxxx

# ===== 中间件地址（Prod 模式全部需要）=====
export SPRING_DATASOURCE_URL=jdbc:mysql://localhost:3306/admin?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=Asia/Shanghai
export SPRING_DATASOURCE_USERNAME=admin
export SPRING_DATASOURCE_PASSWORD=admin
export SPRING_REDIS_HOST=localhost
export SPRING_REDIS_PORT=6379
export SPRING_ELASTICSEARCH_URIS=http://localhost:9200
export NACOS_SERVER_ADDR=localhost:8848
export ROCKETMQ_ENDPOINTS=localhost:18080
export MANAGEMENT_OTLP_TRACING_EXPORT_ENDPOINT=http://localhost:4318/v1/traces

# ===== 阿里云 OSS（文件上传功能需要）=====
export ALIBABA_CLOUD_ACCESS_KEY_ID=xxx
export ALIBABA_CLOUD_ACCESS_KEY_SECRET=xxx
```
