# Spring AI Alibaba Admin · 新人上手环境搭建指南

> 适用版本：`v1.0.0-SNAPSHOT` · 最后更新：2026-07-01
> 配套脚本：`scripts/install-deps.sh` · `scripts/deps-start.sh` · `scripts/deps-stop.sh` · `scripts/deps-status.sh` · `scripts/smoke-test.sh`

---

## 目录

- [1. 前置条件](#1-前置条件)
- [2. 快速开始（最小依赖）](#2-快速开始最小依赖)
- [3. 中间件安装步骤](#3-中间件安装步骤)
- [4. 应用启动步骤](#4-应用启动步骤)
- [5. 常见踩坑](#5-常见踩坑)
- [6. 验证清单](#6-验证清单)
- [7. 常用命令速查](#7-常用命令速查)
- [8. 访问地址汇总](#8-访问地址汇总)

---

## 1. 前置条件

### 1.1 硬件要求

| 资源 | 最小 | 推荐（完整模式） |
|------|------|-----------------|
| CPU | 4 核 | 8 核 |
| 内存 | 8 GB | 16 GB+ |
| 磁盘 | 10 GB | 50 GB+ |
| 网络 | 可访问 GitHub / Maven Central | 国内配置镜像加速 |

### 1.2 软件要求

| 软件 | 版本 | 获取方式 | 说明 |
|------|------|---------|------|
| **JDK** | 17+ | [Adoptium Temurin 17](https://adoptium.net/download/) | 推荐 Temurin / Zulu |
| **Maven** | 3.6+ | 项目自带 `mvnw`（Maven Wrapper），无需额外安装 | 首次启动会自动下载 |
| **Docker** | 20.10+ | [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Linux 可用 `get.docker.com` |
| **Docker Compose** | v2+ | 随 Docker Desktop 附带 | 传统版 `docker-compose` 也可 |
| **Git** | 2.30+ | [git-scm.com](https://git-scm.com/) | — |
| **Node.js**（仅前端） | 18+ | [nodejs.org](https://nodejs.org/) | 仅本地运行前端需要 |
| **npm**（仅前端） | 9+ | 随 Node.js 附带 | — |

### 1.3 LLM API Key（至少配置一个）

| 提供商 | 环境变量 | 获取地址 |
|--------|---------|---------|
| 阿里云 DashScope | `AI_DASHSCOPE_API_KEY` | [百炼控制台](https://bailian.console.aliyun.com/) |
| OpenAI | `OPENAI_API_KEY` | [OpenAI Dashboard](https://platform.openai.com/) |
| DeepSeek | `DEEPSEEK_API_KEY` | [DeepSeek Platform](https://platform.deepseek.com/) |

### 1.4 环境变量

```bash
# 写入 ~/.bashrc 或 ~/.zshrc

# ===== JDK =====
export JAVA_HOME="/path/to/jdk-17"
export PATH="$JAVA_HOME/bin:$PATH"

# ===== Docker（Windows 用户额外加）=====
export PATH="/d/Docker/resources/bin:$PATH"

# ===== LLM API Key（至少配置一个）=====
export DEEPSEEK_API_KEY=sk-xxxx
# export AI_DASHSCOPE_API_KEY=sk-xxxx
# export OPENAI_API_KEY=sk-xxxx
```

---

## 2. 快速开始（最小依赖）

如果只想**快速体验 ChatBot**（不需要 Admin 平台），只需：

```bash
# 1. 克隆项目
git clone https://github.com/alibaba/spring-ai-alibaba.git
cd spring-ai-alibaba

# 2. 确保 JDK 17 和 API Key 已配置
java -version
echo $DEEPSEEK_API_KEY

# 3. 运行 ChatBot 示例
cd examples/chatbot
../../mvnw spring-boot:run
```

ChatBot 示例**不需要** MySQL / Redis / ES / Nacos / RocketMQ。

---

## 3. 中间件安装步骤

完整 Admin 平台需要以下中间件：

| # | 中间件 | 端口 | 用途 |
|---|--------|------|------|
| 1 | MySQL 8.0.35 | 3306 | 业务主库 |
| 2 | Redis 7.2.5 | 6379 | Session 缓存 / 分布式锁 |
| 3 | Elasticsearch 9.1.2 | 9200 | RAG 向量检索 + Span 全文索引 |
| 4 | Nacos | 7848→8848 | 配置中心 |
| 5 | RocketMQ 5.3.2 | 9876 / 18080 | 异步文档索引消息队列 |
| 6 | LoongCollector 3.1.4 | 4318 | OTLP 链路追踪接收器 |
| 7 | Kibana 9.1.2 | 5601 | ES 可视化（可选） |

### 3.1 一键安装（推荐）

```bash
# Dev 模式：仅 MySQL
bash scripts/install-deps.sh dev

# Prod 模式：全部 7 个中间件
bash scripts/install-deps.sh prod
```

脚本会自动检查 JDK → Docker → 拉取镜像 → 启动容器 → 健康检查 → 输出环境变量模板。

### 3.2 手动安装（Docker Compose）

```bash
# 1. 进入中间件目录
cd spring-ai-alibaba-admin/docker/middleware

# 2. 创建 .env 文件（首次）
cp env.template .env
# 编辑 .env，Windows 用户注意 UID=0 GID=0

# 3. 启动
docker compose -f docker-compose-prod.yaml up -d
# 或使用传统版 docker-compose：
docker-compose -f docker-compose-prod.yaml up -d

# 4. 验证
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### 3.3 Docker Hub 镜像加速（国内用户）

```json
// 编辑 ~/.docker/daemon.json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerhub.timeweb.cloud"
  ]
}
```
重启 Docker Desktop 生效。

### 3.4 中间件生命周期管理

```bash
# 启动全部
bash scripts/deps-start.sh prod

# 查看状态
bash scripts/deps-status.sh
bash scripts/deps-status.sh --watch    # 持续监控
bash scripts/deps-status.sh --json     # JSON 输出

# 停止
bash scripts/deps-stop.sh prod
bash scripts/deps-stop.sh prod --clean # 停止+清数据
```

---

## 4. 应用启动步骤

### 4.1 构建 Admin 项目

```bash
# 从项目根目录构建 admin 及所有子模块（必须加 -Drevision）
cd spring-ai-alibaba-admin
../mvnw install -DskipTests -Drevision=1.0.0-SNAPSHOT
```

首次构建需下载全部 Maven 依赖（约 500MB），需 5~15 分钟（取决于网络）。

### 4.2 启动后端

```bash
# 方式 1：直接运行 JAR（推荐，最快）
java -jar -Dspring.profiles.active=local \
  spring-ai-alibaba-admin-server-start/target/spring-ai-alibaba-admin-server-start.jar

# 方式 2：Maven spring-boot:run
cd spring-ai-alibaba-admin
../mvnw -pl spring-ai-alibaba-admin-server-start spring-boot:run \
  -Dspring.profiles.active=local -Drevision=1.0.0-SNAPSHOT
```

`local` profile 自动连接 `localhost` 上的全部中间件（端口见 §3）。

后端启动约需 45 秒，日志出现 `Started SaaStudioAdmin` 表示就绪。

### 4.3 启动前端

```bash
cd spring-ai-alibaba-admin/frontend

# 首次：安装依赖 + 构建子包
npm install --ignore-scripts
npm run build:flow

# 启动开发服务器
cd packages/main && npm run dev
```

前端 dev server 默认监听 `http://localhost:8000`，API 自动代理到 `localhost:8080`。

### 4.4 验证应用启动

```bash
# 检查后端健康
curl http://localhost:8080/actuator/health

# 检查前端
curl http://localhost:8000

# 运行冒烟测试（5 个核心接口）
bash scripts/smoke-test.sh http://localhost:8080
```

---

## 5. 常见踩坑

### 坑 1：Docker Desktop 一直 loading 转圈

**现象**：Docker Desktop 启动后始终显示 "Starting"，`docker info` 挂起无响应。

**原因**：上次非正常退出后，WSL2 的 VHD 数据磁盘残留挂载，Engine 无法启动。

**修复**：
```bash
# 彻底杀掉 Docker 进程 → 关闭 WSL → 重新启动
taskkill /F /IM "Docker Desktop.exe"           # Windows
wsl --shutdown                                   # 释放 VHD 锁
# 重新打开 Docker Desktop
```

---

### 坑 2：Maven 构建 `${revision}` 未解析

**现象**：`mvn install` 成功，但 `spring-boot:run` 报 `Could not find artifact ...:pom:${revision}`。

**原因**：flatten-maven-plugin 安装到本地仓库的 POM 中 `${revision}` 未替换为实际版本号。

**修复**：
```bash
# 始终加 -Drevision 参数
../mvnw install -DskipTests -Drevision=1.0.0-SNAPSHOT

# 或用 java -jar 绕过 Maven 依赖解析
java -jar spring-ai-alibaba-admin-server-start/target/*.jar
```

---

### 坑 3：端口 3306 被占用

**现象**：`docker-compose up` 报 `port 3306 bind: permission denied`。

**原因**：Windows 原生 MySQL 服务 `MySQL80` 已占用 3306。

**修复**：
```powershell
# Windows
Stop-Service MySQL80
Get-Process mysqld | Stop-Process -Force
```
```bash
# macOS
brew services stop mysql
```
```bash
# Linux
sudo systemctl stop mysql
```

---

### 坑 4：RocketMQ NameServer 重启循环

**现象**：`rmq_namesrv` 状态 `Restarting`，日志 `runserver.sh: Permission denied`。

**原因**：`.env` 中 `UID=1000`（非 root）导致容器无权执行启动脚本。

**修复**：编辑 `docker/middleware/.env`：
```
UID=0
GID=0
```
然后 `docker-compose up -d --force-recreate rmq_namesrv rmq_broker rmq_proxy`。

---

### 坑 5：Elasticsearch init 容器失败（CRLF）

**现象**：`elasticsearch-init` 容器 `Exited (2)`，日志 `\r: not found`。

**原因**：`init/elasticsearch/init-indices.sh` 文件含 Windows CRLF 换行，Linux 容器无法解析。

**修复**：
```bash
# 转换换行符
dos2unix spring-ai-alibaba-admin/docker/middleware/init/elasticsearch/init-indices.sh

# 或手动创建 ES pipeline 和 index
curl -X PUT "http://localhost:9200/_ingest/pipeline/parsing_loongsuite_traces" \
  -H "Content-Type: application/json" -d '{...}'
curl -X PUT "http://localhost:9200/loongsuite_traces" \
  -H "Content-Type: application/json" -d '{...}'
```

---

### 坑 6：`docker compose` 找不到命令

**现象**：`docker: 'compose' is not a docker command`。

**原因**：旧版 Docker CLI 不带 compose 插件，需用独立 `docker-compose`。

**修复**：将所有 `docker compose` 替换为 `docker-compose`，或升级 Docker Desktop。

---

### 坑 7：Docker Hub 拉取镜像超时

**现象**：`docker pull` 报 `EOF` / `timeout`。

**原因**：国内网络直接访问 Docker Hub 不稳定。

**修复**：配置镜像加速器（见 §3.3），推荐 DaoCloud 镜像。

---

### 坑 8：Nacos 端口连接不上

**现象**：Nacos Java 客户端连 `localhost:8848` 失败，或 HTTP API 返回 404。

**原因**：Compose 中 Nacos 端口映射为 `7848:8848`（HTTP API）、`8848:9848`（gRPC）。
- HTTP API → `localhost:7848`
- gRPC 客户端 → `localhost:8848`

**修复**：健康检查用 `curl http://localhost:7848/nacos/v1/console/health`。

---

### 坑 9：前端 `npm install` 失败

**现象**：`npm install` 报 husky / prepare script 错误。

**修复**：
```bash
npm install --ignore-scripts    # 跳过 husky 等 hooks
npm run build:flow              # 构建 spark-flow 子包
cd packages/main && npm run dev # 启动 dev server
```

---

## 6. 验证清单

安装完成后，逐项验证。

### 6.1 中间件

| 检查项 | 命令 | 预期输出 |
|--------|------|---------|
| 所有容器运行 | `docker ps --format "{{.Names}} {{.Status}}"` | 9 个容器 `Up` |
| MySQL 可连接 | `docker exec mysql mysqladmin ping -h localhost` | `mysqld is alive` |
| MySQL 表数量 | `docker exec mysql mysql -uadmin -padmin -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='admin';"` | `27` |
| Redis PING | `docker exec redis redis-cli ping` | `PONG` |
| ES 集群健康 | `curl -s http://localhost:9200/_cluster/health \| grep status` | `green` 或 `yellow` |
| ES 索引存在 | `curl -s http://localhost:9200/_cat/indices` | 包含 `loongsuite_traces` |
| Nacos 健康 | `curl -s http://localhost:7848/nacos/v1/console/health` | HTTP 200 |
| RocketMQ Proxy | `curl -s --connect-timeout 3 http://localhost:18080` | 有响应 |
| LoongCollector | `curl -s --connect-timeout 3 http://localhost:4318` | 有响应 |

### 6.2 应用

| 检查项 | 命令 | 预期输出 |
|--------|------|---------|
| 后端健康检查 | `curl http://localhost:8080/actuator/health` | `{"status":"UP"}` |
| 前端可访问 | `curl -s -o /dev/null -w "%{http_code}" http://localhost:8000` | `200` |
| 登录接口 | `curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/console/v1/auth/login -H "Content-Type: application/json" -d '{"username":"saa","password":"123456"}'` | `200` |
| 冒烟测试 | `bash scripts/smoke-test.sh` | 5/5 PASS |

### 6.3 环境变量

```bash
# 确认以下已设置
echo $JAVA_HOME        # /path/to/jdk-17
echo $DEEPSEEK_API_KEY # sk-xxxx（至少一个 LLM Key）
java -version          # 17.x.x
docker info            # Server Version: xx.x.x
```

---

## 7. 常用命令速查

### 中间件

```bash
bash scripts/deps-start.sh prod      # 启动全部中间件
bash scripts/deps-stop.sh prod       # 停止全部中间件
bash scripts/deps-status.sh          # 查看状态表
bash scripts/deps-status.sh --watch  # 持续监控（每 5s 刷新）
bash scripts/deps-stop.sh prod --clean  # 停止 + 清数据
```

### 应用

```bash
# 构建
cd spring-ai-alibaba-admin && ../mvnw install -DskipTests -Drevision=1.0.0-SNAPSHOT

# 后端
java -jar -Dspring.profiles.active=local \
  spring-ai-alibaba-admin-server-start/target/spring-ai-alibaba-admin-server-start.jar

# 前端（首次）
cd frontend && npm install --ignore-scripts && npm run build:flow
cd packages/main && npm run dev

# 冒烟测试
bash scripts/smoke-test.sh
```

### 故障排查

```bash
# Docker 重启三板斧
taskkill /F /IM "Docker Desktop.exe"    # Windows 强杀
sudo pkill -f Docker                     # macOS 强杀
wsl --shutdown                           # 释放 WSL VHD 锁
# → 重新启动 Docker Desktop

# 查看后端日志
tail -f /tmp/backend.log

# 查看某个容器的日志
docker logs -f mysql

# 检查端口占用
# Windows: netstat -ano | findstr :3306
# macOS/Linux: lsof -i :3306
```

---

## 8. 访问地址汇总

| 服务 | 地址 | 说明 |
|------|------|------|
| **Admin 前端** | http://localhost:8000 | UmiJS dev server |
| **Admin 后端 API** | http://localhost:8080 | Spring Boot |
| **Studio 调试 UI** | http://localhost:8080/chatui/index.html | 嵌入式单页应用 |
| MySQL | `localhost:3306` | 用户 `admin` / `admin` |
| Redis | `localhost:6379` | — |
| Elasticsearch | http://localhost:9200 | 禁用安全认证 |
| Kibana | http://localhost:5601 | ES 可视化 |
| Nacos 控制台 | http://localhost:7080/nacos | — |
| Nacos HTTP API | http://localhost:7848 | gRPC: `localhost:8848` |
| RocketMQ Proxy | `localhost:18080` | NameServer: `localhost:9876` |
| LoongCollector | http://localhost:4318 | OTLP receiver |

### 默认登录凭据

| 字段 | 值 |
|------|-----|
| 用户名 | `saa` |
| 密码 | `123456` |

---

> 📚 更多文档：[API 接口清单](api-list.md) · [数据模型](data-model.md) · [环境依赖](env-checklist.md) · [冒烟测试结果](smoke-test-result.md)
>
> 🤖 Generated with [Claude Code](https://claude.com/claude-code)
