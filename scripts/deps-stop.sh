#!/usr/bin/env bash
# =============================================================================
# Spring AI Alibaba Admin — 一键停止所有依赖中间件
# =============================================================================
# 用法: bash scripts/deps-stop.sh [MODE] [--clean]
#   MODE=dev   仅停止 MySQL（默认）
#   MODE=prod  停止全部中间件
#   --clean    同时删除容器和数据（Docker Compose down -v）
#   --force    强制停止（跳过确认）
#
# 特性:
#   - 按依赖逆序停止（先停 Kibana → ES → MySQL）
#   - 支持 Docker / brew / systemd / 手动进程
#   - 验证端口已释放
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
MODE="dev"
CLEAN_MODE=false
FORCE_MODE=false
OS_TYPE=""
RESULTS=()

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        dev|prod) MODE="$arg" ;;
        --clean)  CLEAN_MODE=true ;;
        --force)  FORCE_MODE=true ;;
    esac
done

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

port_open() {
    local host="${1:-localhost}" port="$2" timeout="${3:-3}"
    if has_nc; then
        (command nc -z -w "$timeout" "$host" "$port" 2>/dev/null) && return 0 || true
        (command ncat -z -w "$timeout" "$host" "$port" 2>/dev/null) && return 0 || true
        (command netcat -z -w "$timeout" "$host" "$port" 2>/dev/null) && return 0 || true
    fi
    (timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null) && return 0 || true
    return 1
}

# -----------------------------------------------------------------------------
# 服务定义
# -----------------------------------------------------------------------------
svc_name()       { case "$1" in
    mysql) echo "MySQL";;        redis) echo "Redis";;
    elasticsearch) echo "Elasticsearch";;  nacos) echo "Nacos";;
    rocketmq) echo "RocketMQ";;  loongcollector) echo "LoongCollector";;
    kibana) echo "Kibana";;      *) echo "$1";;
esac; }

svc_container()  { case "$1" in
    mysql) echo "mysql";;                redis) echo "redis";;
    elasticsearch) echo "elasticsearch";;    nacos) echo "nacos";;
    rocketmq) echo "rmq_proxy";;         loongcollector) echo "loongcollector";;
    kibana) echo "kibana";;
esac; }

svc_port()       { case "$1" in
    mysql) echo "3306";;    redis) echo "6379";;
    elasticsearch) echo "9200";;  nacos) echo "7848";;   # HTTP API
    rocketmq) echo "18080";; loongcollector) echo "4318";;
    kibana) echo "5601";;
esac; }

svc_brew()       { case "$1" in
    mysql) echo "mysql";;        redis) echo "redis";;
    elasticsearch) echo "elasticsearch";;  nacos) echo "";;
    rocketmq) echo "";;         loongcollector) echo "";;
    kibana) echo "kibana";;
esac; }

svc_systemd()    { case "$1" in
    mysql) echo "mysql";;        redis) echo "redis-server";;
    elasticsearch) echo "elasticsearch";;  nacos) echo "nacos";;
    rocketmq) echo "";;         loongcollector) echo "";;
    kibana) echo "kibana";;
esac; }

# RocketMQ 额外容器
svc_extra_docker_containers() { case "$1" in
    rocketmq) echo "rmq_broker rmq_namesrv rmq-init-topic";;
    *)        echo "";;
esac; }

# -----------------------------------------------------------------------------
# 停止 Docker 管理的服务
# -----------------------------------------------------------------------------
stop_docker_service() {
    local svc="$1"
    local container; container=$(svc_container "$svc")
    local name; name=$(svc_name "$svc")

    # 检查容器是否存在
    if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
        return 1  # 不存在 = 不需要处理
    fi

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
        log_item "停止 Docker 容器: $container"
        docker stop -t 10 "$container" 2>/dev/null || {
            log_warn "优雅停止超时，强制停止 $container..."
            docker kill "$container" 2>/dev/null || true
        }

        if $CLEAN_MODE; then
            log_item "删除容器: $container"
            docker rm -f "$container" 2>/dev/null || true
        fi
        return 0
    fi

    # 容器存在但已停止
    if $CLEAN_MODE; then
        log_item "删除已停止的容器: $container"
        docker rm -f "$container" 2>/dev/null || true
    fi
    return 0
}

stop_rocketmq_docker() {
    # RocketMQ 有多个关联容器
    for c in rmq_proxy rmq_broker rmq_namesrv rmq-init-topic; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
            log_item "停止 Docker 容器: $c"
            docker stop -t 10 "$c" 2>/dev/null || docker kill "$c" 2>/dev/null || true
            if $CLEAN_MODE; then
                docker rm -f "$c" 2>/dev/null || true
            fi
        elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
            if $CLEAN_MODE; then
                docker rm -f "$c" 2>/dev/null || true
            fi
        fi
    done
}

# -----------------------------------------------------------------------------
# 停止 brew 管理的服务
# -----------------------------------------------------------------------------
stop_brew_service() {
    local svc="$1"
    local brew_name; brew_name=$(svc_brew "$svc")
    local name; name=$(svc_name "$svc")

    if [[ -z "$brew_name" ]]; then return 1; fi

    local status; status=$(brew services list 2>/dev/null | grep "^${brew_name}\s" | awk '{print $2}' || echo "")
    if [[ "$status" == "started" ]]; then
        log_item "停止 brew service: $brew_name"
        brew services stop "$brew_name" 2>/dev/null || {
            log_error "brew services stop $brew_name 失败"
            return 1
        }
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# 停止 systemd 管理的服务
# -----------------------------------------------------------------------------
stop_systemd_service() {
    local svc="$1"
    local unit; unit=$(svc_systemd "$svc")
    local name; name=$(svc_name "$svc")

    if [[ -z "$unit" ]]; then return 1; fi

    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        log_item "停止 systemd 服务: $unit"
        sudo systemctl stop "$unit" 2>/dev/null || {
            log_error "systemctl stop $unit 失败"
            return 1
        }
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# 杀死手动进程
# -----------------------------------------------------------------------------
kill_manual_process() {
    local svc="$1"
    local name; name=$(svc_name "$svc")
    local port; port=$(svc_port "$svc")

    if ! port_open "localhost" "$port" 2; then
        return 1  # 端口已释放
    fi

    # 查找监听该端口的进程
    local pids=""
    if [[ "$OS_TYPE" == "macOS" || "$OS_TYPE" == "Linux" ]]; then
        pids=$(lsof -ti "TCP:$port" -sTCP:LISTEN 2>/dev/null || true)
    fi

    if [[ -n "$pids" ]]; then
        log_item "停止 $name 进程 (PIDs: $pids)"
        for pid in $pids; do
            kill -15 "$pid" 2>/dev/null || true
        done
        # 等待 5 秒
        sleep 5
        # 如果还没死，强制杀
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                log_warn "强制终止 $name (PID: $pid)"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        return 0
    fi

    log_warn "找不到 $name 的进程（端口 $port 被占用但无关联 PID）"
    return 1
}

# -----------------------------------------------------------------------------
# 验证端口已释放
# -----------------------------------------------------------------------------
wait_port_released() {
    local svc="$1"
    local port; port=$(svc_port "$svc")
    local name; name=$(svc_name "$svc")
    local max_wait=15 elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        if ! port_open "localhost" "$port" 2; then
            return 0  # 端口已释放
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    log_warn "$name 端口 $port 仍被占用（${max_wait}s 超时）"
    return 1
}

# -----------------------------------------------------------------------------
# Docker Compose 整组停止（prod 模式可选）
# -----------------------------------------------------------------------------
docker_compose_down() {
    local mode="$1"
    local compose_file="$2"

    if [ ! -f "$compose_file" ]; then
        return 1
    fi

    log_step "Docker Compose 整组停止"
    if $CLEAN_MODE; then
        log_item "停止并删除所有容器 + 数据卷..."
        (cd "$MIDDLEWARE_DIR" && docker compose -f "$compose_file" down -v --remove-orphans 2>&1) || {
            log_warn "部分容器/卷清理失败，尝试强制清理..."
            (cd "$MIDDLEWARE_DIR" && docker compose -f "$compose_file" down -v --remove-orphans --timeout 5 2>&1) || true
        }
    else
        log_item "停止所有容器（保留数据）..."
        (cd "$MIDDLEWARE_DIR" && docker compose -f "$compose_file" down --remove-orphans 2>&1) || {
            log_warn "Compose down 失败，尝试逐个停止..."
            (cd "$MIDDLEWARE_DIR" && docker compose -f "$compose_file" stop 2>&1) || true
        }
    fi
}

# -----------------------------------------------------------------------------
# 停止单个服务（综合入口）
# -----------------------------------------------------------------------------
stop_service() {
    local svc="$1"
    local name; name=$(svc_name "$svc")
    local port; port=$(svc_port "$svc")

    log_step "停止 $name"

    local stopped=false

    # 1. 尝试 Docker
    if has_docker; then
        if [[ "$svc" == "rocketmq" ]]; then
            stop_rocketmq_docker && stopped=true
        elif stop_docker_service "$svc"; then
            stopped=true
        fi
    fi

    # 2. 尝试 brew（macOS）
    if ! $stopped && [[ "$OS_TYPE" == "macOS" ]]; then
        stop_brew_service "$svc" && stopped=true
    fi

    # 3. 尝试 systemd（Linux）
    if ! $stopped && [[ "$OS_TYPE" == "Linux" ]]; then
        stop_systemd_service "$svc" && stopped=true
    fi

    # 4. 兜底：杀进程
    if ! $stopped; then
        kill_manual_process "$svc" && stopped=true
    fi

    # 5. 验证端口释放
    if port_open "localhost" "$port" 2; then
        if wait_port_released "$svc"; then
            log_info "$name 已停止 ✅"
            RESULTS+=("$svc:OK:stopped")
        else
            log_warn "$name 端口 $port 未释放 ⚠️"
            RESULTS+=("$svc:WARN:port_still_open")
        fi
    else
        log_info "$name 已停止 ✅"
        RESULTS+=("$svc:OK:already_stopped")
    fi
}

# -----------------------------------------------------------------------------
# 确认提示（clean 模式）
# -----------------------------------------------------------------------------
confirm_clean() {
    if $FORCE_MODE; then return 0; fi

    echo ""
    echo -e "${RED}${BOLD}⚠️  WARNING: --clean 模式将删除所有中间件数据！${NC}"
    echo -e "${RED}   包括: MySQL 数据库、Redis 数据、ES 索引、RocketMQ 消息等${NC}"
    echo ""
    read -r -p "确认清理数据? (yes/no): " confirm
    case "$confirm" in
        yes|YES|y|Y) return 0 ;;
        *) echo "已取消"; exit 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# 打印摘要
# -----------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  停止摘要  (${MODE} mode)                                          ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"

    for r in "${RESULTS[@]}"; do
        local svc="${r%%:*}" rest="${r#*:}" status="${rest%%:*}"
        local name; name=$(svc_name "$svc")
        if [[ "$status" == "OK" ]]; then
            echo -e "  ${GREEN}✅${NC} $name 已停止"
        elif [[ "$status" == "WARN" ]]; then
            echo -e "  ${YELLOW}⚠️${NC} $name (端口未释放)"
        else
            echo -e "  ${CYAN}—${NC} $name"
        fi
    done
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    detect_os

    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  Spring AI Alibaba Admin · 中间件一键停止               ║${NC}"
    echo -e "${CYAN}${BOLD}║  Mode: ${MODE} · OS: ${OS_TYPE}                                      ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 确认清理
    if $CLEAN_MODE; then
        confirm_clean
    fi

    # 逆序停止（先停依赖方，再停被依赖方）
    local services=()
    if [[ "$MODE" == "dev" ]]; then
        services=(mysql)
    else
        # 逆依赖顺序：Kibana > LoongCollector > RocketMQ > Nacos > ES > Redis > MySQL
        services=(kibana loongcollector rocketmq nacos elasticsearch redis mysql)
    fi

    # 如果有 Docker 且使用 Compose，先尝试整组停止（更快）
    local compose_file
    if [[ "$MODE" == "dev" ]]; then
        compose_file="$COMPOSE_DEV"
    else
        compose_file="$COMPOSE_PROD"
    fi

    if has_docker && [ -f "$compose_file" ]; then
        # 检查是否有 compose 管理的容器在运行
        local running_count
        running_count=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -cE 'mysql|redis|elasticsearch|nacos|rmq_|loongcollector|kibana' || echo 0)
        if [ "$running_count" -gt 0 ]; then
            docker_compose_down "$MODE" "$compose_file"
            # compose down 后仍逐个验证
        fi
    fi

    # 逐个验证并兜底停止
    for svc in "${services[@]}"; do
        local port; port=$(svc_port "$svc")
        if port_open "localhost" "$port" 2; then
            stop_service "$svc"
        else
            local name; name=$(svc_name "$svc")
            log_info "$name 已停止（端口 $port 无监听），跳过"
            RESULTS+=("$svc:OK:already_stopped")
        fi
    done

    # 额外检查：dev 模式下也确认 MySQL 停止
    if [[ "$MODE" == "dev" ]]; then
        if port_open "localhost" "3306" 2; then
            stop_service "mysql"
        fi
    fi

    print_summary

    echo -e "${GREEN}所有中间件已停止 ✅${NC}"
    echo ""
}

main "$@"
