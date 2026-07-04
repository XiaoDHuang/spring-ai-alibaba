#!/usr/bin/env bash
# =============================================================================
# Spring AI Alibaba Admin — 一键启动所有依赖中间件
# =============================================================================
# 用法: bash scripts/deps-start.sh [MODE]
#   MODE=dev  仅 MySQL（本地开发模式，默认）
#   MODE=prod 全部中间件（MySQL, Redis, ES, Nacos, RocketMQ, LoongCollector, Kibana）
#
# 管理方式自动检测优先级:
#   1. Docker Compose（项目默认方式）
#   2. Homebrew services（macOS）
#   3. systemd（Linux）
#   4. 手动进程（jar / 二进制）
#
# 特性:
#   - 启动后等待各服务健康就绪再返回
#   - 已运行的服务自动跳过
#   - 支持混合场景（部分 Docker、部分 brew / systemd）
# =============================================================================
set -uo pipefail

# -----------------------------------------------------------------------------
# 颜色 & 日志
# -----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}${BOLD}═══ $* ═══${NC}"; }
log_item()  { echo -e "${BLUE}  ▶${NC} $*"; }

# -----------------------------------------------------------------------------
# 全局变量
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIDDLEWARE_DIR="$PROJECT_ROOT/spring-ai-alibaba-admin/docker/middleware"
COMPOSE_DEV="$MIDDLEWARE_DIR/docker-compose-dev.yaml"
COMPOSE_PROD="$MIDDLEWARE_DIR/docker-compose-prod.yaml"
MODE="${1:-dev}"
OS_TYPE=""
START_TIME=$(date '+%s')
RESULTS=()
FOUND_METHOD=""  # 全局记录发现的第一个管理方式

# -----------------------------------------------------------------------------
# 操作系统检测
# -----------------------------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Darwin)  OS_TYPE="macOS" ;;
        Linux)   OS_TYPE="Linux" ;;
        MINGW*|MSYS*|CYGWIN*) OS_TYPE="Windows-GitBash" ;;
        *)       OS_TYPE="Unknown" ;;
    esac
}

# -----------------------------------------------------------------------------
# 工具检查
# -----------------------------------------------------------------------------
has_cmd() { command -v "$1" &>/dev/null; }
has_docker() { has_cmd docker && docker info &>/dev/null 2>&1; }
has_brew() { has_cmd brew; }
has_systemctl() { has_cmd systemctl; }
has_nc() { has_cmd nc || has_cmd ncat || has_cmd netcat; }
has_curl() { has_cmd curl; }

# TCP 端口检查（超时 3s）
port_open() {
    local host="${1:-localhost}" port="$2" timeout="${3:-3}"
    if has_nc; then
        (command nc -z -w "$timeout" "$host" "$port" 2>/dev/null) && return 0 || true
        (command ncat -z -w "$timeout" "$host" "$port" 2>/dev/null) && return 0 || true
        (command netcat -z -w "$timeout" "$host" "$port" 2>/dev/null) && return 0 || true
    fi
    # Fallback: bash /dev/tcp (在 bash 中可用)
    (timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null) && return 0 || true
    return 1
}

# -----------------------------------------------------------------------------
# 管理方式检测
# -----------------------------------------------------------------------------
# 返回值: "docker" "brew" "systemd" "manual" "none"
detect_method() {
    local container="$1" brew_name="$2" systemd_name="$3"

    # 1. Docker 容器存在（不管是否运行） → docker 管理
    if has_cmd docker; then
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
            echo "docker"
            return
        fi
    fi

    # 2. Homebrew services
    if [[ "$OS_TYPE" == "macOS" ]] && has_brew; then
        if brew services list 2>/dev/null | grep -qE "^${brew_name}\s+(started|none)"; then
            echo "brew"
            return
        fi
    fi

    # 3. systemd
    if [[ "$OS_TYPE" == "Linux" ]] && has_systemctl; then
        if systemctl is-active --quiet "$systemd_name" 2>/dev/null; then
            echo "systemd"
            return
        fi
        # 即使未 active，如果 unit 存在也算 systemd 管
        if systemctl list-unit-files "$systemd_name" &>/dev/null 2>&1; then
            echo "systemd"
            return
        fi
    fi

    echo "manual"
}

# -----------------------------------------------------------------------------
# Docker Compose 辅助
# -----------------------------------------------------------------------------
compose_cmd() {
    local mode="$1" compose_file="$2" action="$3"; shift 3
    if [ ! -f "$compose_file" ]; then
        log_error "Compose 文件不存在: $compose_file"
        return 1
    fi
    (cd "$MIDDLEWARE_DIR" && docker compose -f "$compose_file" "$action" "$@")
}

# -----------------------------------------------------------------------------
# 服务定义（按启动顺序排列）
# -----------------------------------------------------------------------------
# 每个服务: name container port brew_name systemd_name health_fn extra_notes
# 使用 declare -A 不方便做有序列表，用函数 + case 实现服务目录

svc_name()       { case "$1" in
    mysql)          echo "MySQL";;
    redis)          echo "Redis";;
    elasticsearch)  echo "Elasticsearch";;
    nacos)          echo "Nacos";;
    rocketmq)       echo "RocketMQ";;
    loongcollector) echo "LoongCollector";;
    kibana)         echo "Kibana";;
    *)              echo "$1";;
esac; }

svc_container()  { case "$1" in
    mysql)          echo "mysql";;
    redis)          echo "redis";;
    elasticsearch)  echo "elasticsearch";;
    nacos)          echo "nacos";;
    rocketmq)       echo "rmq_proxy";;     # Proxy 作为对外入口
    loongcollector) echo "loongcollector";;
    kibana)         echo "kibana";;
esac; }

svc_port()       { case "$1" in
    mysql)          echo "3306";;
    redis)          echo "6379";;
    elasticsearch)  echo "9200";;
    nacos)          echo "7848";;   # HTTP API（host 7848→container 8848）
    rocketmq)       echo "18080";;         # Proxy 端口
    loongcollector) echo "4318";;
    kibana)         echo "5601";;
esac; }

svc_brew()       { case "$1" in
    mysql)          echo "mysql";;
    redis)          echo "redis";;
    elasticsearch)  echo "elasticsearch";;
    nacos)          echo "";;              # brew 无 nacos formula
    rocketmq)       echo "";;
    loongcollector) echo "";;
    kibana)         echo "kibana";;
esac; }

svc_systemd()    { case "$1" in
    mysql)          echo "mysql";;
    redis)          echo "redis-server";;
    elasticsearch)  echo "elasticsearch";;
    nacos)          echo "nacos";;
    rocketmq)       echo "";;
    loongcollector) echo "";;
    kibana)         echo "kibana";;
esac; }

svc_deps()       { case "$1" in
    mysql)          echo "";;
    redis)          echo "";;
    elasticsearch)  echo "mysql";;
    kibana)         echo "elasticsearch";;
    nacos)          echo "";;
    rocketmq)       echo "";;
    loongcollector) echo "elasticsearch";;
esac; }

# 服务是否包含在指定 mode 中
svc_in_mode() {
    local svc="$1" mode="$2"
    case "$mode" in
        dev)
            [[ "$svc" == "mysql" ]] && return 0 || return 1 ;;
        prod|*)
            # RocketMQ 拆分为多个容器，这里用 rmq_proxy 代表
            return 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# 健康检查（服务启动后的就绪验证）
# -----------------------------------------------------------------------------
check_health() {
    local svc="$1" port
    port=$(svc_port "$svc")
    local container; container=$(svc_container "$svc")

    case "$svc" in
        mysql)
            # Docker 方式
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
                docker exec "$container" mysqladmin ping -h localhost --silent 2>/dev/null && return 0
            fi
            # 通用端口 + 协议检查
            port_open "localhost" "$port" 3 && return 0
            return 1
            ;;
        redis)
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
                docker exec "$container" redis-cli ping 2>/dev/null | grep -q PONG && return 0
            fi
            port_open "localhost" "$port" 3 && return 0
            return 1
            ;;
        elasticsearch)
            local health; health=$(curl -s "http://localhost:$port/_cluster/health" 2>/dev/null \
                | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "")
            [[ "$health" == "green" || "$health" == "yellow" ]] && return 0
            # 兜底：能响应 HTTP 即认为可用
            curl -s -o /dev/null "http://localhost:$port" 2>/dev/null && return 0
            return 1
            ;;
        nacos)
            local code; code=$(curl -s -o /dev/null -w "%{http_code}" \
                "http://localhost:$port/nacos/v1/console/health" 2>/dev/null || echo "000")
            [[ "$code" == "200" ]] && return 0
            return 1
            ;;
        rocketmq)
            # Proxy 响应 HTTP 即就绪（即使是 404 / 405 也表示进程在监听）
            curl -s -o /dev/null --connect-timeout 3 "http://localhost:18080" 2>/dev/null && return 0
            # 检查 NameServer
            port_open "localhost" "9876" 3 && return 0
            return 1
            ;;
        loongcollector)
            curl -s -o /dev/null --connect-timeout 3 "http://localhost:$port" 2>/dev/null && return 0
            return 1
            ;;
        kibana)
            curl -s -o /dev/null --connect-timeout 5 "http://localhost:$port" 2>/dev/null && return 0
            return 1
            ;;
        *) return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Docker Compose 方式启动
# -----------------------------------------------------------------------------
start_via_docker() {
    local svc="$1" mode="$2"
    local compose_file="$3"
    local container; container=$(svc_container "$svc")
    local name; name=$(svc_name "$svc")

    # 检查容器是否已存在且运行中
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
        log_info "$name 已在 Docker 中运行，跳过"
        return 0
    fi

    # 容器存在但未运行 → 启动它
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
        log_item "启动已存在的 $name 容器..."
        docker start "$container" 2>/dev/null || {
            log_warn "$name 容器启动失败，尝试重新创建..."
            docker rm -f "$container" 2>/dev/null || true
            compose_cmd "$mode" "$compose_file" up -d --no-deps "$svc" 2>&1 || return 1
        }
    else
        log_item "通过 Docker Compose 创建并启动 $name..."
        compose_cmd "$mode" "$compose_file" up -d --no-deps "$svc" 2>&1 || {
            log_error "$name Docker Compose 启动失败"
            return 1
        }
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Homebrew 方式启动
# -----------------------------------------------------------------------------
start_via_brew() {
    local svc="$1"
    local brew_name; brew_name=$(svc_brew "$svc")
    local name; name=$(svc_name "$svc")

    if [[ -z "$brew_name" ]]; then
        log_warn "$name 不支持 brew 安装，跳过"
        return 1
    fi

    local status; status=$(brew services list 2>/dev/null | grep "^${brew_name}\s" | awk '{print $2}' || echo "")
    if [[ "$status" == "started" ]]; then
        log_info "$name 已通过 brew services 运行，跳过"
        return 0
    fi

    log_item "通过 brew services 启动 $name..."
    brew services start "$brew_name" 2>/dev/null || {
        log_error "$name brew services 启动失败"
        return 1
    }
    return 0
}

# -----------------------------------------------------------------------------
# systemd 方式启动
# -----------------------------------------------------------------------------
start_via_systemd() {
    local svc="$1"
    local unit; unit=$(svc_systemd "$svc")
    local name; name=$(svc_name "$svc")

    if [[ -z "$unit" ]]; then
        log_warn "$name 不支持 systemd 管理，跳过"
        return 1
    fi

    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        log_info "$name 已通过 systemd 运行，跳过"
        return 0
    fi

    log_item "通过 systemd 启动 $name..."
    sudo systemctl start "$unit" 2>/dev/null || {
        log_error "$name systemd 启动失败"
        return 1
    }
    return 0
}

# -----------------------------------------------------------------------------
# 带重试的健康等待
# -----------------------------------------------------------------------------
wait_for_ready() {
    local svc="$1"
    local name; name=$(svc_name "$svc")
    local max_wait="${2:-120}" interval="${3:-5}" elapsed=0

    log_item "等待 $name 就绪..."

    while [ $elapsed -lt $max_wait ]; do
        if check_health "$svc"; then
            local port; port=$(svc_port "$svc")
            log_info "$name 就绪 ✅  (${elapsed}s, port $port)"
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_item "  仍在等待 $name... (${elapsed}s/${max_wait}s)"
        fi
    done

    log_error "$name 启动超时 (${max_wait}s) ❌"
    return 1
}

# -----------------------------------------------------------------------------
# 启动单个服务
# -----------------------------------------------------------------------------
start_service() {
    local svc="$1" mode="$2" compose_file="$3"
    local name; name=$(svc_name "$svc")
    local port; port=$(svc_port "$svc")

    log_step "启动 $name"

    # 先检查是否已经在运行
    if check_health "$svc"; then
        local method; method=$(detect_method "$(svc_container "$svc")" "$(svc_brew "$svc")" "$(svc_systemd "$svc")")
        log_info "$name 已在运行 (port $port, 方式: $method)，跳过"
        RESULTS+=("$svc:SKIP:already_running:$method")
        return 0
    fi

    # 按优先级尝试启动
    local started=false start_method="none"

    # 1. 尝试 Docker Compose
    if has_docker; then
        if [ -f "$compose_file" ]; then
            local container; container=$(svc_container "$svc")
            # 检查 compose 文件中是否定义了这个服务
            if grep -q "^  ${svc}:" "$compose_file" 2>/dev/null || [ "$svc" = "rocketmq" ]; then
                if start_via_docker "$svc" "$mode" "$compose_file"; then
                    started=true; start_method="docker"
                fi
            fi
        fi
    fi

    # 2. 尝试 brew（macOS）
    if ! $started && [[ "$OS_TYPE" == "macOS" ]]; then
        local brew_name; brew_name=$(svc_brew "$svc")
        if [[ -n "$brew_name" ]]; then
            if start_via_brew "$svc"; then
                started=true; start_method="brew"
            fi
        fi
    fi

    # 3. 尝试 systemd（Linux）
    if ! $started && [[ "$OS_TYPE" == "Linux" ]]; then
        local unit; unit=$(svc_systemd "$svc")
        if [[ -n "$unit" ]]; then
            if start_via_systemd "$svc"; then
                started=true; start_method="systemd"
            fi
        fi
    fi

    # 4. 手动方式 — 提示用户
    if ! $started; then
        log_warn "$name 无法通过自动方式启动"
        log_warn "  请手动启动 $name（端口 $port），然后重新运行本脚本"
        RESULTS+=("$svc:FAIL:no_method:manual")
        return 1
    fi

    # 等待健康就绪
    local max_wait
    case "$svc" in
        mysql)          max_wait=90;;
        elasticsearch)  max_wait=120;;
        rocketmq)       max_wait=90;;
        nacos)          max_wait=60;;
        kibana)         max_wait=60;;
        *)              max_wait=45;;
    esac

    if wait_for_ready "$svc" "$max_wait"; then
        RESULTS+=("$svc:OK:started:$start_method")
        return 0
    else
        RESULTS+=("$svc:FAIL:timeout:$start_method")
        return 1
    fi
}

# -----------------------------------------------------------------------------
# 准备环境
# -----------------------------------------------------------------------------
prepare_env() {
    if [ ! -f "$MIDDLEWARE_DIR/.env" ] && [ -f "$MIDDLEWARE_DIR/env.template" ]; then
        cp "$MIDDLEWARE_DIR/env.template" "$MIDDLEWARE_DIR/.env"
        log_info "从 env.template 创建 .env 文件"
    fi

    # 确保数据目录存在
    mkdir -p "$MIDDLEWARE_DIR/mysql/data" \
             "$MIDDLEWARE_DIR/redis/data" \
             "$MIDDLEWARE_DIR/nacos/data" \
             "$MIDDLEWARE_DIR/nacos/logs" \
             "$MIDDLEWARE_DIR/rocketmq/store" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# 打印摘要
# -----------------------------------------------------------------------------
print_summary() {
    local end_time; end_time=$(date '+%s')
    local duration=$(( end_time - START_TIME ))

    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  启动摘要  (${MODE} mode · ${duration}s)                              ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"

    local ok=0 fail=0 skip=0
    for r in "${RESULTS[@]}"; do
        local svc="${r%%:*}" rest="${r#*:}"
        local status="${rest%%:*}" info="${rest#*:}"
        local name; name=$(svc_name "$svc")
        if [[ "$status" == "OK" ]]; then
            echo -e "  ${GREEN}✅${NC} $name"
            ((ok++))
        elif [[ "$status" == "SKIP" ]]; then
            echo -e "  ${CYAN}⏭️${NC} $name (已运行)"
            ((skip++))
        else
            echo -e "  ${RED}❌${NC} $name"
            ((fail++))
        fi
    done

    echo ""
    echo -e "  ${GREEN}启动: $ok${NC}  ${CYAN}跳过: $skip${NC}  ${RED}失败: $fail${NC}"
    echo ""

    if [ $fail -gt 0 ]; then
        echo -e "${YELLOW}部分服务启动失败，请检查上方日志。${NC}"
        echo -e "${YELLOW}可运行 ${CYAN}bash scripts/deps-status.sh${NC} ${YELLOW}查看详情。${NC}"
    else
        echo -e "${GREEN}所有依赖中间件就绪 ✅${NC}"
        echo ""
        echo -e "  快速验证: ${CYAN}bash scripts/deps-status.sh${NC}"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    detect_os

    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  Spring AI Alibaba Admin · 中间件一键启动               ║${NC}"
    echo -e "${CYAN}${BOLD}║  Mode: ${MODE} · OS: ${OS_TYPE}                                      ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 验证 MODE
    if [[ "$MODE" != "dev" && "$MODE" != "prod" ]]; then
        log_error "无效 MODE: '$MODE'，请使用 'dev' 或 'prod'"
        echo "用法: bash scripts/deps-start.sh [dev|prod]"
        exit 1
    fi

    # 选择 compose 文件
    local compose_file
    if [[ "$MODE" == "dev" ]]; then
        compose_file="$COMPOSE_DEV"
    else
        compose_file="$COMPOSE_PROD"
    fi

    # 检查 Docker
    if [ -f "$compose_file" ]; then
        if ! has_docker; then
            log_warn "Docker 不可用"
            if [[ "$OS_TYPE" == "macOS" ]]; then
                log_info "将尝试通过 brew services 启动服务"
            elif [[ "$OS_TYPE" == "Linux" ]]; then
                log_info "将尝试通过 systemd 启动服务"
            else
                log_error "请先启动 Docker Desktop 或安装 Docker Engine"
                exit 1
            fi
        fi
    fi

    # 准备环境
    prepare_env

    # 按依赖顺序定义服务列表
    local services=()
    if [[ "$MODE" == "dev" ]]; then
        services=(mysql)
    else
        services=(mysql redis elasticsearch kibana nacos rocketmq loongcollector)
    fi

    # 逐一启动
    local exit_code=0
    for svc in "${services[@]}"; do
        if ! start_service "$svc" "$MODE" "$compose_file"; then
            exit_code=1
            # 继续启动后续服务（它们可能不依赖失败的）
        fi
    done

    # 打印摘要
    print_summary

    exit $exit_code
}

main "$@"
