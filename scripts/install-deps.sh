#!/usr/bin/env bash
# =============================================================================
# Spring AI Alibaba Admin — 本地依赖一键安装脚本
# =============================================================================
# 用法: bash scripts/install-deps.sh [MODE]
#   MODE=dev  仅 MySQL（开发模式）
#   MODE=prod 全部中间件（完整模式，默认）
#   MODE=min  仅 JDK 检查 + LLM API Key 引导
# =============================================================================
set -uo pipefail

# Source user profile for JAVA_HOME / Docker PATH if available
[ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null || true

# Explicitly add common Docker and JDK paths (Windows / macOS / Linux)
for d_bin in "/d/Docker/resources/bin" "/c/Program Files/Docker/Docker/resources/bin" "/usr/local/bin"; do
    [ -d "$d_bin" ] && export PATH="$d_bin:$PATH"
done
for j_bin in "/d/Program Files/Eclipse Adoptium/jdk-17/bin" "/c/Program Files/Eclipse Adoptium/jdk-17.0.19.10-hotspot/bin" "/usr/lib/jvm/java-17-openjdk/bin"; do
    [ -d "$j_bin" ] && export JAVA_HOME="$(dirname "$j_bin")" && export PATH="$j_bin:$PATH"
done

MODE="${1:-prod}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/install-log.md"
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
OS_TYPE=""
PKG_MANAGER=""
RETRY_COUNT=0
MAX_RETRIES=3

# -----------------------------------------------------------------------------
# 颜色输出
# -----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $*"; }
log_skip()  { echo -e "${BLUE}[SKIP]${NC}  $*"; }

# -----------------------------------------------------------------------------
# 初始化日志文件
# -----------------------------------------------------------------------------
init_log() {
    mkdir -p "$SCRIPT_DIR"
    cat > "$LOG_FILE" << 'LOGHEAD'
# Spring AI Alibaba Admin — 本地依赖安装日志

LOGHEAD
    echo "> 安装开始: $START_TIME" >> "$LOG_FILE"
    echo "> 安装模式: $MODE" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    echo "| # | 组件 | 状态 | 方式 | 备注 |" >> "$LOG_FILE"
    echo "|---|------|------|------|------|" >> "$LOG_FILE"
}

log_to_file() {
    local component="$1" status="$2" method="$3" note="$4"
    echo "| $component | $status | $method | $note |" >> "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# 操作系统检测
# -----------------------------------------------------------------------------
detect_os() {
    log_step "检测操作系统..."
    case "$(uname -s)" in
        Darwin)  OS_TYPE="macOS";  PKG_MANAGER="brew" ;;
        Linux)   OS_TYPE="Linux";  PKG_MANAGER="apt"  ;;
        MINGW*|MSYS*|CYGWIN*)
            OS_TYPE="Windows-GitBash"
            PKG_MANAGER="choco"
            log_warn "检测到 Windows + Git Bash 环境，将优先使用 Docker Desktop"
            ;;
        *)
            OS_TYPE="Unknown"
            PKG_MANAGER="unknown"
            log_error "未识别的操作系统: $(uname -s)"
            ;;
    esac
    log_info "操作系统: $OS_TYPE | 包管理器: $PKG_MANAGER"
    echo "" >> "$LOG_FILE"
    echo "**操作系统**: $OS_TYPE | **包管理器**: $PKG_MANAGER" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# 安装前置工具
# -----------------------------------------------------------------------------
ensure_command() {
    local cmd="$1" pkg_name="$2" install_hint="$3"
    if command -v "$cmd" &>/dev/null; then
        log_info "$pkg_name: 已安装 ($(command -v "$cmd"))"
        return 0
    fi
    log_warn "$pkg_name: 未安装，尝试安装..."

    case "$OS_TYPE" in
        macOS)
            if ! command -v brew &>/dev/null; then
                log_warn "Homebrew 未安装，正在安装..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
                    || { log_error "Homebrew 安装失败，请手动安装: https://brew.sh"; return 1; }
            fi
            brew install "$install_hint" 2>/dev/null || {
                log_warn "brew install $install_hint 失败，尝试手动查找..."
                brew search "$install_hint" 2>/dev/null | head -5
                return 1
            }
            ;;
        Linux)
            sudo apt-get update -qq 2>/dev/null || true
            sudo apt-get install -y "$install_hint" 2>/dev/null || {
                log_warn "apt install $install_hint 失败"
                return 1
            }
            ;;
        Windows-GitBash|*)
            log_warn "请手动安装: $install_hint"
            log_info "下载链接/说明: $install_hint"
            return 1
            ;;
    esac
    log_info "$pkg_name: 安装完成"
}

# -----------------------------------------------------------------------------
# 1. JDK 17
# -----------------------------------------------------------------------------
install_jdk() {
    log_step "检查 JDK 17..."
    local attempts=0
    while [ $attempts -lt $MAX_RETRIES ]; do
        # 检查已安装的 Java
        if command -v java &>/dev/null; then
            local java_ver
            java_ver=$(java -version 2>&1 | head -1 | grep -oP '"\K[0-9]+' || echo "0")
            if [ "$java_ver" -ge 17 ]; then
                log_info "JDK: $(java -version 2>&1 | head -1)"
                log_to_file "JDK 17" "✅ OK" "$PKG_MANAGER" "$(java -version 2>&1 | head -1)"
                return 0
            fi
            log_warn "当前 Java 版本: $java_ver，需要 17+"
        fi

        log_warn "尝试安装 JDK 17... (attempt $((attempts+1))/$MAX_RETRIES)"
        case "$OS_TYPE" in
            macOS)
                brew install openjdk@17 2>/dev/null && \
                sudo ln -sfn "$(brew --prefix openjdk@17)/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk-17.jdk 2>/dev/null || true
                ;;
            Linux)
                sudo apt-get update -qq && sudo apt-get install -y openjdk-17-jdk-headless 2>/dev/null || \
                sudo apt-get install -y openjdk-17-jdk 2>/dev/null || \
                { log_error "apt 源中没有 openjdk-17，尝试添加源..."; sudo add-apt-repository -y ppa:openjdk-r/ppa 2>/dev/null && sudo apt-get update -qq && sudo apt-get install -y openjdk-17-jdk; }
                ;;
            Windows-GitBash|*)
                log_info "请手动安装 JDK 17:"
                log_info "  下载: https://adoptium.net/download/  (选择 Temurin 17, Windows x64 msi)"
                log_info "  或: winget install EclipseAdoptium.Temurin.17.JDK"
                log_to_file "JDK 17" "⚠️ MANUAL" "manual" "需手动下载: https://adoptium.net/download/"
                # 尝试 winget
                if command -v winget &>/dev/null; then
                    winget install EclipseAdoptium.Temurin.17.JDK --accept-package-agreements 2>/dev/null && \
                    { log_info "winget 安装 JDK 17 成功，请重启终端后重新运行脚本"; return 0; }
                fi
                # 检查 Program Files (C: 和 D:) 下是否有 JDK
                for jdk_dir in "/d/Program Files/Eclipse Adoptium/jdk-17"* "/d/Program Files/Java/jdk-17"* "/d/Program Files/OpenJDK/jdk-17"* "/c/Program Files/Eclipse Adoptium/jdk-17"*; do
                    if [ -d "$jdk_dir" ]; then
                        export JAVA_HOME="$jdk_dir"
                        export PATH="$JAVA_HOME/bin:$PATH"
                        log_info "找到已安装的 JDK: $JAVA_HOME"
                        log_to_file "JDK 17" "✅ OK" "manual-find" "$JAVA_HOME"
                        return 0
                    fi
                done
                # 尝试用 choco
                if command -v choco &>/dev/null; then
                    choco install openjdk17 -y 2>/dev/null && \
                    { log_info "choco 安装 JDK 17 成功，请重启终端后重新运行脚本"; return 0; }
                fi
                ;;
        esac
        attempts=$((attempts + 1))

        # 安装后重新检查
        if command -v java &>/dev/null && [ "$(java -version 2>&1 | head -1 | grep -oP '"\K[0-9]+' || echo "0")" -ge 17 ]; then
            log_info "JDK 17: 安装成功"
            log_to_file "JDK 17" "✅ OK" "$PKG_MANAGER" "$(java -version 2>&1 | head -1)"
            return 0
        fi
    done

    log_error "JDK 17 安装失败，重试 $MAX_RETRIES 次后放弃"
    log_to_file "JDK 17" "❌ FAIL" "$PKG_MANAGER" "重试${MAX_RETRIES}次仍失败"
    return 1
}

# -----------------------------------------------------------------------------
# 2. Docker
# -----------------------------------------------------------------------------
install_docker() {
    log_step "检查 Docker..."
    # Ensure Docker bin is in PATH
    for d_bin in "/d/Docker/resources/bin" "/c/Program Files/Docker/Docker/resources/bin"; do
        if [ -f "$d_bin/docker.exe" ] || [ -f "$d_bin/docker" ]; then
            export PATH="$d_bin:$PATH"
        fi
    done
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        log_info "Docker: $(docker --version)"
        log_to_file "Docker" "✅ OK" "existing" "$(docker --version)"
    else
        log_warn "Docker 未安装或未运行"
        case "$OS_TYPE" in
            macOS)
                log_info "请安装 Docker Desktop: https://www.docker.com/products/docker-desktop/"
                brew install --cask docker 2>/dev/null || true
                ;;
            Linux)
                curl -fsSL https://get.docker.com | sudo sh
                sudo systemctl enable docker
                sudo systemctl start docker
                sudo usermod -aG docker "$USER" 2>/dev/null || true
                ;;
            Windows-GitBash|*)
                log_info "请安装 Docker Desktop: https://www.docker.com/products/docker-desktop/"
                if command -v winget &>/dev/null; then
                    winget install Docker.DockerDesktop 2>/dev/null || true
                fi
                ;;
        esac
        log_to_file "Docker" "⚠️ MANUAL" "manual" "需安装 Docker Desktop: https://www.docker.com/products/docker-desktop/"
    fi

    # 验证 Compose
    if docker-compose version &>/dev/null 2>&1; then
        log_info "Docker Compose: $(docker-compose version)"
        log_to_file "Docker Compose" "✅ OK" "built-in" "$(docker-compose version)"
    elif command -v docker-compose &>/dev/null; then
        log_info "Docker Compose (legacy): $(docker-compose --version)"
        log_to_file "Docker Compose" "✅ OK" "legacy" "$(docker-compose --version)"
    else
        log_warn "Docker Compose 不可用，请升级 Docker Desktop 到最新版"
        log_to_file "Docker Compose" "❌ FAIL" "missing" "请升级 Docker Desktop"
    fi
}

# -----------------------------------------------------------------------------
# 3. 中间件 — Docker Compose 启动
# -----------------------------------------------------------------------------
start_middleware() {
    local mode="$1"
    local compose_file
    local services_list

    log_step "启动中间件 (mode=$mode)..."

    case "$mode" in
        dev)
            compose_file="$PROJECT_ROOT/spring-ai-alibaba-admin/docker/middleware/docker-compose-dev.yaml"
            services_list="MySQL"
            ;;
        prod|*)
            compose_file="$PROJECT_ROOT/spring-ai-alibaba-admin/docker/middleware/docker-compose-prod.yaml"
            services_list="MySQL, Redis, Elasticsearch, Nacos, RocketMQ, LoongCollector, Kibana"
            ;;
    esac

    if [ ! -f "$compose_file" ]; then
        log_error "Compose 文件不存在: $compose_file"
        log_to_file "Middleware" "❌ FAIL" "compose" "文件缺失: $compose_file"
        return 1
    fi

    # 创建必要目录
    local mw_home="$PROJECT_ROOT/spring-ai-alibaba-admin/docker/middleware"
    mkdir -p "$mw_home/mysql/data" "$mw_home/redis/data" "$mw_home/elasticsearch/data" \
             "$mw_home/nacos/data" "$mw_home/nacos/logs" "$mw_home/rocketmq/store"

    # 确保 env 文件存在
    if [ ! -f "$mw_home/.env" ]; then
        cp "$mw_home/env.template" "$mw_home/.env"
        log_info "从 env.template 创建 .env 文件"
    fi

    # 停止已有容器（避免端口冲突）
    log_info "停止已有中间件容器..."
    docker-compose -f "$compose_file" down --remove-orphans 2>/dev/null || true

    # 启动
    log_info "启动中间件容器 ($services_list)..."
    if ! docker-compose -f "$compose_file" up -d 2>&1; then
        log_error "中间件 Docker Compose 启动失败"
        log_to_file "Middleware" "❌ FAIL" "docker-compose" "启动失败"
        return 1
    fi

    log_info "中间件容器已提交启动，等待健康检查..."
    log_to_file "Middleware" "✅ STARTED" "docker-compose" "$services_list"
}

# -----------------------------------------------------------------------------
# 等待服务健康
# -----------------------------------------------------------------------------
wait_for_mysql() {
    log_info "等待 MySQL :3306 就绪..."
    local max_wait=90 interval=5 elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker exec mysql mysqladmin ping -h localhost --silent 2>/dev/null; then
            log_info "MySQL 就绪 (${elapsed}s)"
            # 验证数据库存在
            local db_check
            db_check=$(docker exec mysql mysql -uadmin -padmin -e "SHOW DATABASES LIKE 'admin';" 2>/dev/null | grep admin || echo "")
            if [ -n "$db_check" ]; then
                log_info "数据库 'admin' 已创建"
                # 验证表数量
                local table_count
                table_count=$(docker exec mysql mysql -uadmin -padmin -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='admin';" 2>/dev/null | tail -1 || echo "0")
                log_info "数据库 'admin' 包含 ${table_count} 张表"
                log_to_file "MySQL" "✅ OK" "docker:3306" "${table_count} tables in admin"
                return 0
            fi
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        if [ $((elapsed % 15)) -eq 0 ]; then
            log_info "  仍在等待 MySQL... (${elapsed}s/${max_wait}s)"
        fi
    done
    log_error "MySQL 启动超时 (${max_wait}s)"
    log_to_file "MySQL" "❌ TIMEOUT" "docker:3306" "超时 ${max_wait}s"
    return 1
}

wait_for_redis() {
    log_info "等待 Redis :6379 就绪..."
    local max_wait=30 interval=3 elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker exec redis redis-cli ping 2>/dev/null | grep -q PONG; then
            log_info "Redis 就绪 (${elapsed}s)"
            log_to_file "Redis" "✅ OK" "docker:6379" "PONG"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    log_error "Redis 启动超时"
    log_to_file "Redis" "⚠️ TIMEOUT" "docker:6379" "超时"
    return 1
}

wait_for_elasticsearch() {
    log_info "等待 Elasticsearch :9200 就绪..."
    local max_wait=120 interval=5 elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local health
        health=$(curl -s "http://localhost:9200/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "")
        if [ "$health" = "green" ] || [ "$health" = "yellow" ]; then
            log_info "Elasticsearch 就绪 (${elapsed}s, status=$health)"
            # 验证索引
            local index_check
            index_check=$(curl -s "http://localhost:9200/_cat/indices/loongsuite_traces?h=index" 2>/dev/null || echo "")
            if [ -n "$index_check" ]; then
                log_info "索引 loongsuite_traces 已创建"
                log_to_file "Elasticsearch" "✅ OK" "docker:9200" "index=loongsuite_traces, health=$health"
            else
                log_warn "索引 loongsuite_traces 尚未创建，init 容器可能还在运行..."
                log_to_file "Elasticsearch" "⚠️ OK" "docker:9200" "health=$health, index pending"
                # 再等一会儿
                sleep 15
                index_check=$(curl -s "http://localhost:9200/_cat/indices/loongsuite_traces?h=index" 2>/dev/null || echo "")
                if [ -n "$index_check" ]; then
                    log_info "索引已创建"
                    log_to_file "Elasticsearch" "✅ OK" "docker:9200" "index=loongsuite_traces created"
                fi
            fi
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "  仍在等待 ES... (${elapsed}s/${max_wait}s)"
        fi
    done
    log_error "Elasticsearch 启动超时"
    log_to_file "Elasticsearch" "⚠️ TIMEOUT" "docker:9200" "超时"
    return 1
}

wait_for_nacos() {
    log_info "等待 Nacos :8848 就绪..."
    local max_wait=60 interval=5 elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8848/nacos/v1/console/health" 2>/dev/null | grep -q "200"; then
            log_info "Nacos 就绪 (${elapsed}s)"
            log_to_file "Nacos" "✅ OK" "docker:8848" "standalone"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    log_warn "Nacos 启动超时 (端口映射可能不同: 7848→8848)"
    log_to_file "Nacos" "⚠️ TIMEOUT" "docker:7848" "检查端口映射"
    return 0  # 不致命
}

wait_for_rocketmq() {
    log_info "等待 RocketMQ Proxy :18080 就绪..."
    local max_wait=90 interval=5 elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        # 简单 TCP 检查
        if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://localhost:18080" 2>/dev/null; then
            log_info "RocketMQ Proxy 就绪 (${elapsed}s)"
            log_to_file "RocketMQ" "✅ OK" "docker:18080" "proxy+namesrv=9876"
            return 0
        fi
        # 也检查 name server
        if nc -z localhost 9876 2>/dev/null; then
            log_info "RocketMQ NameServer 就绪，等待 Proxy... (${elapsed}s)"
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "  仍在等待 RocketMQ... (${elapsed}s/${max_wait}s)"
        fi
    done
    log_warn "RocketMQ Proxy 健康检查失败，Topic 可能由 init-topic 容器自动创建"
    log_to_file "RocketMQ" "⚠️ TIMEOUT" "docker:18080" "init-topic 可能仍在运行"
    return 0  # 不致命，init-topic 容器独立运行
}

wait_for_loongcollector() {
    log_info "等待 LoongCollector :4318 就绪..."
    local max_wait=30 interval=3 elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://localhost:4318" 2>/dev/null; then
            log_info "LoongCollector 就绪 (${elapsed}s)"
            log_to_file "LoongCollector" "✅ OK" "docker:4318" "OTLP receiver"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    log_warn "LoongCollector 健康检查未响应，可能不影响核心功能"
    log_to_file "LoongCollector" "⚠️ UNCHECKED" "docker:4318" "无响应"
    return 0  # 不致命
}

# -----------------------------------------------------------------------------
# 打印环境变量模板
# -----------------------------------------------------------------------------
print_env_template() {
    echo ""
    log_info "=========================================="
    log_info " 环境变量模板（写入 ~/.bashrc 或 ~/.zshrc）"
    log_info "=========================================="
    cat << 'EOF'
# ===== LLM API Keys（至少配置一个）=====
export AI_DASHSCOPE_API_KEY=sk-xxxx
# export OPENAI_API_KEY=sk-xxxx
# export DEEPSEEK_API_KEY=sk-xxxx

# ===== 中间件连接（Docker Compose 本地默认值）=====
export SPRING_DATASOURCE_URL='jdbc:mysql://localhost:3306/admin?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=Asia/Shanghai'
export SPRING_DATASOURCE_USERNAME=admin
export SPRING_DATASOURCE_PASSWORD=admin
export SPRING_REDIS_HOST=localhost
export SPRING_REDIS_PORT=6379
export SPRING_ELASTICSEARCH_URIS=http://localhost:9200
export NACOS_SERVER_ADDR=localhost:8848
export ROCKETMQ_ENDPOINTS=localhost:18080
export MANAGEMENT_OTLP_TRACING_EXPORT_ENDPOINT=http://localhost:4318/v1/traces
EOF
    echo ""
    log_to_file "Env Template" "✅ PRINTED" "stdout" "已输出环境变量模板"
}

# -----------------------------------------------------------------------------
# 验证安装
# -----------------------------------------------------------------------------
verify_all() {
    log_step "=========================================="
    log_step " 安装验证"
    log_step "=========================================="

    local all_ok=true

    # JDK
    echo ""
    log_info "--- JDK ---"
    if command -v java &>/dev/null; then
        java -version 2>&1 | head -3
    else
        log_warn "java 命令不可用"
        all_ok=false
    fi

    # Docker
    echo ""
    log_info "--- Docker ---"
    if docker info &>/dev/null 2>&1; then
        docker --version
        echo "Containers running:"
        docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || true
    else
        log_warn "Docker 不可用"
        all_ok=false
    fi

    # Port checks
    echo ""
    log_info "--- 端口监听 ---"
    for port in 3306 6379 9200 8848 18080 4318; do
        case "$OS_TYPE" in
            Windows-GitBash)
                # Windows 用 netstat
                if powershell.exe -Command "Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue" 2>/dev/null | grep -q $port; then
                    log_info "  port $port: LISTENING"
                else
                    log_warn "  port $port: NOT LISTENING"
                fi
                ;;
            *)
                if ss -tlnp 2>/dev/null | grep -q ":$port " || netstat -an 2>/dev/null | grep -q "LISTEN.*:$port "; then
                    log_info "  port $port: LISTENING"
                else
                    log_warn "  port $port: NOT LISTENING"
                fi
                ;;
        esac
    done

    # MySQL 表验证
    echo ""
    log_info "--- MySQL 表清单 ---"
    if docker exec mysql mysql -uadmin -padmin -e "SHOW TABLES;" admin 2>/dev/null; then
        log_info "MySQL 表验证通过"
    else
        log_warn "MySQL 表验证失败，可能是容器名不同或密码不同"
    fi

    echo ""
    if $all_ok; then
        log_info "全部核心依赖验证通过 ✅"
        log_to_file "VERIFY" "✅ ALL OK" "" "全部检查通过"
    else
        log_warn "部分检查未通过，请检查上方输出"
        log_to_file "VERIFY" "⚠️ PARTIAL" "" "部分检查未通过"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Spring AI Alibaba Admin — 本地依赖安装脚本                  ║"
    echo "║  Mode: $MODE                                               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    init_log
    detect_os

    # ---- Step 1: JDK 17 ----
    log_step "══════ Step 1: JDK 17 ══════"
    if ! install_jdk; then
        log_error "JDK 17 是硬性依赖，无法继续。请手动安装: https://adoptium.net/download/"
        log_to_file "FATAL" "❌ STOP" "" "JDK 17 安装失败，终止"
        exit 1
    fi

    # ---- Step 2: Docker ----
    log_step "══════ Step 2: Docker ══════"
    install_docker

    # 验证 Docker 可用
    if ! docker info &>/dev/null 2>&1; then
        log_error "Docker 不可用。请先启动 Docker Desktop 或安装 Docker Engine"
        log_error "  macOS: https://www.docker.com/products/docker-desktop/"
        log_error "  Linux: curl -fsSL https://get.docker.com | sudo sh"
        log_error "  Windows: https://www.docker.com/products/docker-desktop/"
        log_to_file "FATAL" "❌ STOP" "" "Docker 不可用，终止"
        exit 1
    fi

    # ---- Step 3: 中间件 ----
    if [ "$MODE" = "min" ]; then
        log_info "min 模式：跳过中间件安装"
        log_to_file "Middleware" "⏭️ SKIP" "min-mode" "min 模式不需要中间件"
    else
        log_step "══════ Step 3: 中间件 ($MODE) ══════"
        start_middleware "$MODE"

        log_step "══════ Step 4: 健康检查 ══════"
        wait_for_mysql
        if [ "$MODE" = "prod" ]; then
            wait_for_redis
            wait_for_elasticsearch
            wait_for_nacos
            wait_for_rocketmq
            wait_for_loongcollector
        fi
    fi

    # ---- Step 5: 环境变量 ----
    log_step "══════ Step 5: 环境变量模板 ══════"
    print_env_template

    # ---- Step 6: 验证 ----
    verify_all

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  安装完成！日志: scripts/install-log.md                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # 写入结束时间
    echo "" >> "$LOG_FILE"
    echo "> 安装结束: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
}

main
