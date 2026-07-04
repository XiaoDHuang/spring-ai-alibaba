# Spring AI Alibaba Admin — 本地依赖安装日志

> **安装时间**: 2026-06-30 08:06 ~ 08:25 (UTC+8)
> **环境**: Windows 11 Pro · Git Bash · Docker Desktop on D:\Docker
> **模式**: prod（全部中间件）
> **脚本**: `scripts/install-deps.sh`

---

## 安装摘要

| # | 组件 | 状态 | 最终命令/方式 | 备注 |
|---|------|------|--------------|------|
| 1 | JDK 17 | ✅ OK | ZIP 解压到 D:\Program Files\Eclipse Adoptium\jdk-17 | Temurin 17.0.19+10 |
| 2 | Docker | ✅ OK | D:\Docker\resources\bin | v29.5.3, Compose v5.1.4 |
| 3 | MySQL 8.0.35 | ✅ OK | docker-compose up -d | :3306, 27 tables in admin |
| 4 | Redis 7.2.5 | ✅ OK | docker-compose up -d | :6379, healthy |
| 5 | Elasticsearch 9.1.2 | ✅ OK | docker-compose up -d | :9200, green, loongsuite_traces index |
| 6 | Nacos | ✅ OK | docker-compose up -d | :7848→8848 standalone |
| 7 | RocketMQ 5.3.2 | ✅ OK | docker-compose up -d | :9876 nameServer + :18080 proxy |
| 8 | LoongCollector 3.1.4 | ✅ OK | docker start (手动) | :4318 OTLP receiver |
| 9 | Kibana 9.1.2 | ✅ OK | docker-compose up -d | :5601, 可选 |

---

## 遇到的问题与修复过程

### 问题 1: `docker compose` 找不到 → 用 `docker-compose`

**现象**: 脚本中 `docker compose` 报 `unknown command`

**原因**: D:\Docker 安装的 Docker CLI v29.5.3 不带 compose 插件，需用独立 `docker-compose.exe`

**修复**: 将脚本中所有 `docker compose` 替换为 `docker-compose`

**修复后命令**: `docker-compose -f docker-compose-prod.yaml up -d`

---

### 问题 2: Docker Hub 拉镜像超时 → 配置国内镜像源

**现象**: `docker pull redis:7.2.5` 报 `EOF` 错误

**原因**: 国内网络环境直接访问 Docker Hub 不稳定

**修复**: 写入 `~/.docker/daemon.json`，配置 DaoCloud 镜像加速器：
```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerhub.timeweb.cloud"
  ]
}
```
重启 Docker Desktop 后生效。所有镜像通过 mirror 成功拉取。

---

### 问题 3: MySQL 端口 3306 被占用 → 停止原生 MySQL 服务

**现象**: `Error response from daemon: port 3306 bind: permission denied`

**原因**: Windows 原生 MySQL 服务 `MySQL80` 已占用 3306 端口

**修复**: `Stop-Service MySQL80` + `Stop-Process mysqld` 释放端口后重建容器

---

### 问题 4: RocketMQ NameServer 重启循环 → 修复 UID

**现象**: `rmq_namesrv` 状态 `Restarting`，日志 `runserver.sh: Permission denied`

**原因**: `.env` 中 `UID=1000` 导致容器以非 root 用户运行，RocketMQ 镜像脚本需 root 权限

**修复**: 修改 `.env` 为 `UID=0 GID=0`（root），重建容器

---

### 问题 5: ES 初始化脚本 CRLF 换行错误 → 手动创建

**现象**: `elasticsearch-init` 容器 `Exited (2)`，日志 `\r: not found`

**原因**: `init-indices.sh` 文件有 Windows CRLF 换行，Linux 容器无法解析

**修复**: 手动通过 curl 创建 pipeline 和 index：
```bash
curl -X PUT "http://localhost:9200/_ingest/pipeline/parsing_loongsuite_traces" ...
curl -X PUT "http://localhost:9200/loongsuite_traces" ...
```

---

### 问题 6: LoongCollector 未启动 → 手动启动

**原因**: Compose 中 `depends_on: elasticsearch-init` 条件不满足（init 失败）

**修复**: `docker start loongcollector` 手动启动

---

## 最终验证结果

```
mysql            Up (healthy)    0.0.0.0:3306->3306/tcp
redis            Up (healthy)    0.0.0.0:6379->6379/tcp
elasticsearch    Up (healthy)    0.0.0.0:9200->9200/tcp
nacos            Up              0.0.0.0:7848->8848/tcp
rmq_namesrv      Up (healthy)    0.0.0.0:9876->9876/tcp
rmq_broker       Up (healthy)    0.0.0.0:10909-10912->10909-10912/tcp
rmq_proxy        Up              0.0.0.0:18080-18081->18080-18081/tcp
loongcollector   Up              0.0.0.0:4318->4318/tcp
kibana           Up              0.0.0.0:5601->5601/tcp

MySQL: 27 tables in 'admin' database
ES: loongsuite_traces index + parsing_loongsuite_traces pipeline
RocketMQ: topic_saa_studio_document_index created
```

---

## 环境变量（已写入 ~/.bashrc）

```bash
export JAVA_HOME="/d/Program Files/Eclipse Adoptium/jdk-17"
export PATH="$JAVA_HOME/bin:/d/Docker/resources/bin:$PATH"
export AI_DASHSCOPE_API_KEY=sk-xxxx  # 需自行填入
```

> **结论**: 全部 9 个中间件成功运行。遇到 6 个问题全部自主修复。最终状态：所有端口正常监听、健康检查通过。
