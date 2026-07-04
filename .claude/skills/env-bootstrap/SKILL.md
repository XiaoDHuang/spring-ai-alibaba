# env-bootstrap

项目环境一键诊断、搭建、验证的完整流程。从零开始把 Spring AI Alibaba Admin 跑到冒烟测试全部通过。

## 触发场景

- 新人刚 clone 项目，需要从零搭建本地开发环境
- 更换电脑 / 重装系统后重建环境
- 中间件或应用运行异常，需要全链路诊断重置
- 定期验证环境健康（每周 / 发版前）
- 用户说"帮我搭建环境" / "帮我检查环境" / "环境有问题帮我修"

## 前置约束

- **只读优先**：先诊断再修改，每次做改变前告知用户原因
- **允许的操作**：Read、Bash（含 curl / docker / git）、Write（仅写报告和脚本）
- **不允许的操作**：Edit（修改已有代码/配置）、删除文件、裸露 API Key 到日志
- **一次搞定一个**：遇到阻塞问题修好它再继续，不要累积未处理错误
- **所有超时都设大一点**：Maven 首次构建、Docker 拉镜像都可能很慢

## 工作流程

### Phase 1: 环境盘点 (diagnose)

**目标**：不装任何东西，只摸清当前状态。

按顺序检查，每个输出 ✅/❌/⚠️：

1. **操作系统**
   - `uname -s` → macOS / Linux / Windows-GitBash
   - 记录版本，影响后续包管理器和路径写法

2. **JDK 17**
   - `java -version` 检查已安装版本
   - 检查 `JAVA_HOME` 是否已设
   - 未安装时输出下载链接：[Adoptium Temurin 17](https://adoptium.net/download/)

3. **Docker**
   - `docker info` 检查 Engine 是否运行
   - 如果 Docker Desktop 进程在跑但 `docker info` 挂起 → **参考坑 1**
   - `docker-compose` 或 `docker compose` 哪个可用

4. **Node.js & npm**（仅前端需要）
   - `node --version` ≥ 18
   - `npm --version`

5. **LLM API Key**
   - 检查 `AI_DASHSCOPE_API_KEY` / `OPENAI_API_KEY` / `DEEPSEEK_API_KEY` 是否已设
   - **只能检查是否为空**，绝对不能 echo 出来

6. **中间件端口扫描**
   - 逐个 `port_open localhost <port>` 检查：3306 / 6379 / 9200 / 7848 / 9876 / 18080 / 4318
   - 已监听 → ✅ 记录管理方式（docker / brew / systemd）
   - 未监听但有容器 → ⚠️ 停止状态，需启动
   - 端口被占用但非预期服务 → ⚠️ 端口冲突

7. **Maven 本地仓库**
   - 检查 `~/.m2/repository/com/alibaba/cloud/ai/spring-ai-alibaba-admin-server-core/` 是否存在
   - 存在 → 可跳过构建直接启动；不存在 → 需要先 `mvn install`

**产出**：一份简短的环境诊断报告（直接输出到对话，不用写入文件），列出所有检查项状态和需要修复的问题。

---

### Phase 2: 修复与安装 (fix & install)

**目标**：把 Phase 1 发现的 ❌/⚠️ 全部修成 ✅。

**2.1 Docker 故障修复**

| 问题 | 诊断信号 | 修复步骤 |
|------|---------|---------|
| Engine 不响应 | `docker info` 挂起 | 杀进程 → `wsl --shutdown` → 重启 Docker Desktop |
| `docker compose` 不可用 | unknown command | 后续全部改用 `docker-compose` |
| 镜像拉取超时 | pull 报 EOF/timeout | 写 `~/.docker/daemon.json` 配置 DaoCloud mirror → 重启 Docker |

Docker 修复后必须跑通 `docker info` 再继续。

**2.2 端口冲突处理**

如果端口被非 Docker 的服务占用：
- macOS: `brew services stop <name>`
- Linux: `sudo systemctl stop <name>`
- Windows: `Stop-Service <name>` / `Stop-Process`

**2.3 安装中间件**

如果所有中间件端口都已监听 → 跳过。

否则，使用 Docker Compose 启动：

```bash
cd spring-ai-alibaba-admin/docker/middleware

# 检查/修复 .env（Windows 需 UID=0 GID=0）
[ ! -f .env ] && cp env.template .env
# 如果是 Windows, sed -i 's/UID=1000/UID=0/; s/GID=1000/GID=0/' .env

# 启动
docker-compose -f docker-compose-prod.yaml up -d
```

启动后逐一等待健康检查：
- MySQL: `docker exec mysql mysqladmin ping -h localhost --silent`
- Redis: `docker exec redis redis-cli ping | grep PONG`
- ES: `curl -s http://localhost:9200/_cluster/health` (status=green/yellow)
- Nacos: `curl -s http://localhost:7848/nacos/v1/console/health`
- RocketMQ: `curl -s --connect-timeout 3 http://localhost:18080`
- LoongCollector: `docker start loongcollector`（可能需手动启动，depends_on 失败时）
- Kibana: `curl -s --connect-timeout 5 http://localhost:5601`

**常见问题速修**（详见 `docs/setup-guide.md` §5）：

1. RocketMQ 重启循环 → `.env` 设 `UID=0 GID=0`，重建容器
2. elasticsearch-init Exited(2) → CRLF 问题，手动 curl 创建 pipeline/index
3. LoongCollector 未启动 → `docker start loongcollector`

---

### Phase 3: 启停脚本 (scripts)

**目标**：确保 `scripts/deps-start.sh` / `scripts/deps-stop.sh` / `scripts/deps-status.sh` 三个脚本存在且可执行。

如果不存在或语法报错，参考以下设计重新生成：
- **deps-start.sh**：OS 检测 → Docker Compose / brew / systemd 自动适配 → 逐个启动 → 健康等待 → 打印摘要
- **deps-stop.sh**：逆依赖序停止 → 验证端口释放
- **deps-status.sh**：表格输出每个中间件的状态/端口/管理方式/版本/健康详情，支持 `--watch` / `--json` / `--short`

完成后运行 `bash scripts/deps-status.sh` 确认所有中间件 RUNNING。

---

### Phase 4: 编译与启动 (build & run)

**目标**：后端 8080 + 前端 8000 全部就绪。

**4.1 构建 Admin 项目**

检查 `~/.m2/repository/com/alibaba/cloud/ai/spring-ai-alibaba-admin-server-core/` 是否存在 JAR。
如果不存在：

```bash
cd spring-ai-alibaba-admin
../mvnw install -DskipTests -Drevision=1.0.0-SNAPSHOT
```

**关键**：必须加 `-Drevision=1.0.0-SNAPSHOT`，否则本地 POM 中 `${revision}` 不解析。

如果网络不稳导致 SSL 握手失败（`Remote host terminated the handshake`），重试：
```bash
../mvnw install -DskipTests -Drevision=1.0.0-SNAPSHOT \
  -Dhttps.protocols=TLSv1.2,TLSv1.3 \
  -rf :spring-ai-alibaba-admin-server-core
```

构建成功后检查 JAR：
```bash
ls -lh spring-ai-alibaba-admin-server-start/target/spring-ai-alibaba-admin-server-start.jar
```

**4.2 启动后端**

```bash
nohup java -jar -Dspring.profiles.active=local \
  spring-ai-alibaba-admin-server-start/target/spring-ai-alibaba-admin-server-start.jar \
  > /tmp/backend.log 2>&1 &
```

监控 `Started SaaStudioAdmin` 出现（约 45 秒），然后验证：
```bash
curl -s http://localhost:8080/actuator/health
```

**4.3 启动前端（可选）**

```bash
cd spring-ai-alibaba-admin/frontend
[ ! -d node_modules ] && npm install --ignore-scripts
[ ! -d packages/spark-flow/dist ] && npm run build:flow
cd packages/main && nohup npm run dev > /tmp/frontend.log 2>&1 &
```

等待 `App listening at: http://localhost:8000` 出现。

---

### Phase 5: 接口冒烟 (smoke test)

**目标**：5 个核心模块接口全部返回 200。

检查 `scripts/smoke-test.sh` 是否存在且可执行。不存在则生成一个——覆盖：

| # | 模块 | 接口 | 预期 |
|---|------|------|------|
| 1 | 登录 | `POST /console/v1/auth/login` | 200 + JWT |
| 2 | Prompt | `GET /api/prompts?page=1&size=5` | 200 |
| 3 | Dataset | `GET /api/dataset/datasets?page=1&size=5` | 200 |
| 4 | Evaluator | `GET /api/evaluator/templates?page=1&size=5` | 200 |
| 5 | Trace | `GET /api/observability/traces?pageNumber=1&pageSize=5&startTime=2024-01-01&endTime=2026-12-31` | 200 |

默认凭据：`saa` / `123456`（来自 `init/mysql/agentscope-schema.sql`）。

Trace 接口需要 `startTime` / `endTime` 参数，缺少返回 400。

用 `curl -s -o /dev/null -w "%{http_code}"` 逐个调，每个返回 200 算通过。

**产出**：冒烟结果写到 `docs/smoke-test-result.md`，含测试摘要表、统计、每个接口的 crul 命令和实际返回。

---

## 产出清单

完成全流程后，以下文件应全部就绪：

| 文件 | 说明 | Phase |
|------|------|-------|
| `docs/smoke-test-result.md` | 冒烟测试报告 | P5 |
| `scripts/deps-start.sh` | 一键启动中间件 | P3 |
| `scripts/deps-stop.sh` | 一键停止中间件 | P3 |
| `scripts/deps-status.sh` | 中间件状态查看 | P3 |
| `scripts/smoke-test.sh` | 核心接口冒烟脚本 | P5 |
| `~/.docker/daemon.json` | Docker 镜像加速（国内用户） | P2 |
| `docker/middleware/.env` | UID/GID 配置 | P2 |

## 关键参考

- [环境依赖清单](docs/env-checklist.md) — 所有中间件端口、连接信息、环境变量
- [新人上手指南](docs/setup-guide.md) — 完整搭建步骤 + 常见踩坑
- [API 接口清单](docs/api-list.md) — 295+ 个端点，5 大模块分类
- [安装日志](scripts/install-log.md) — 真实踩坑记录
- [项目 README / CLAUDE.md](CLAUDE.md) — 项目结构、构建命令

## 注意事项

1. **Maven `${revision}` 是头号坑**：构建 admin 必须带 `-Drevision=1.0.0-SNAPSHOT`，否则依赖解析失败
2. **Windows 用户 UID=0**：`.env` 中设 `UID=0 GID=0`，否则 RocketMQ 起不来
3. **Nacos 端口映射非标准**：HTTP API 在 `7848`，gRPC 在 `8848`，不要搞混
4. **Docker Desktop 卡 loading**：`wsl --shutdown` 是第一修复手段
5. **不要泄漏 API Key**：检查是否已设用 `[ -n "$VAR" ]`，绝对不能 echo 出来
6. **日志统一放 `/tmp/`**：后端启动日志、前端日志、Maven 构建日志
7. **中文环境普遍**：提示信息可以用中文，方便团队理解
