#!/usr/bin/env bash
# =============================================================================
# Spring AI Alibaba Admin — 中间件运行状态查看
# =============================================================================
# 用法: bash scripts/deps-status.sh [--json] [--watch]
#   --json    以 JSON 格式输出
#   --watch   持续监控（每 5s 刷新）
#   --short   简洁模式（单行摘要）
#
# 输出每个中间件的:
#   - 运行状态 (RUNNING / STOPPED)
#   - 端口监听情况
#   - 管理方式 (docker / brew / systemd / manual)
#   - 版本信息
#   - 健康状态
# =============================================================================
set -uo pipefail

# -----------------------------------------------------------------------------
# 颜色 & 日志
# -----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
WATCH_MODE=false
JSON_MODE=false
SHORT_MODE=false

for arg in "$@"; do
    case "$arg" in
        --watch) WATCH_MODE=true ;;
        --json)  JSON_MODE=true ;;
        --short) SHORT_MODE=true ;;
    esac
done

# -----------------------------------------------------------------------------
# 工具
# -----------------------------------------------------------------------------
has_cmd() { command -v "$1" &>/dev/null; }
has_docker() { has_cmd docker && docker info &>/dev/null 2>&1; }
has_brew() { has_cmd brew; }
has_systemctl() { has_cmd systemctl; }
has_nc() { has_cmd nc || has_cmd ncat || has_cmd netcat; }
has_curl() { has_cmd curl; }

port_open() {
    local host="${1:-localhost}" port="$2" timeout="${3:-2}"
    if has_nc; then
        (command nc -z -w "$timeout" "$host" "$port" 2>/dev/null) && return 0 || true
        (command ncat -z -w "$timeout" "$host" "$port" 2>/dev/null) && return 0 || true
        (command netcat -z -w "$timeout" "$host" "$port" 2>/dev/null) && return 0 || true
    fi
    (timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null) && return 0 || true
    return 1
}

# -----------------------------------------------------------------------------
# 服务元数据
# -----------------------------------------------------------------------------
svc_name()      { case "$1" in
    mysql) echo "MySQL";;          redis) echo "Redis";;
    elasticsearch) echo "Elasticsearch";;   nacos) echo "Nacos";;
    rocketmq) echo "RocketMQ";;    loongcollector) echo "LoongCollector";;
    kibana) echo "Kibana";;        *) echo "$1";;
esac; }

svc_container() { case "$1" in
    mysql) echo "mysql";;          redis) echo "redis";;
    elasticsearch) echo "elasticsearch";;  nacos) echo "nacos";;
    rocketmq) echo "rmq_proxy";;   loongcollector) echo "loongcollector";;
    kibana) echo "kibana";;
esac; }

svc_ports()     { case "$1" in
    mysql)          echo "3306";;
    redis)          echo "6379";;
    elasticsearch)  echo "9200,9300";;
    nacos)          echo "7080,7848,8848";;   # Console, HTTP API, gRPC
    rocketmq)       echo "9876,10909,10911,10912,18080";;
    loongcollector) echo "4318";;
    kibana)         echo "5601";;
esac; }

svc_port()      { case "$1" in
    mysql) echo "3306";;    redis) echo "6379";;
    elasticsearch) echo "9200";;    nacos) echo "7848";;   # HTTP API
    rocketmq) echo "18080";; loongcollector) echo "4318";;
    kibana) echo "5601";;
esac; }

svc_brew()      { case "$1" in
    mysql) echo "mysql";;   redis) echo "redis";;
    elasticsearch) echo "elasticsearch";;  kibana) echo "kibana";;
    *) echo "";;
esac; }

svc_systemd()   { case "$1" in
    mysql) echo "mysql";;   redis) echo "redis-server";;
    elasticsearch) echo "elasticsearch";;  nacos) echo "nacos";;
    kibana) echo "kibana";; *) echo "";;
esac; }

ALL_SERVICES=(mysql redis elasticsearch nacos rocketmq loongcollector kibana)

# -----------------------------------------------------------------------------
# 检测管理方式
# -----------------------------------------------------------------------------
detect_method() {
    local svc="$1"
    local container; container=$(svc_container "$svc")

    # Docker
    if has_docker; then
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
            echo "docker"
            return
        fi
    fi

    # Brew
    if has_brew; then
        local brew_name; brew_name=$(svc_brew "$svc")
        if [[ -n "$brew_name" ]]; then
            if brew services list 2>/dev/null | grep -qE "^${brew_name}\s+(started|none|error)"; then
                echo "brew"
                return
            fi
        fi
    fi

    # Systemd
    if has_systemctl; then
        local unit; unit=$(svc_systemd "$svc")
        if [[ -n "$unit" ]]; then
            if systemctl list-unit-files "$unit" &>/dev/null 2>&1; then
                echo "systemd"
                return
            fi
        fi
    fi

    # 端口被占用但无已知管理方式 → 手动进程
    local port; port=$(svc_port "$svc")
    if port_open "localhost" "$port" 1; then
        echo "manual"
        return
    fi

    echo "none"
}

# -----------------------------------------------------------------------------
# Docker 容器状态
# -----------------------------------------------------------------------------
docker_container_status() {
    local container="$1"
    if ! has_docker; then echo "n/a"; return; fi
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
        local status; status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        local health; health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "n/a")
        if [[ "$health" != "n/a" && "$health" != "" ]]; then
            echo "running (health: $health)"
        else
            echo "running"
        fi
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
        local status; status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        echo "$status"
    else
        echo "not_found"
    fi
}

# -----------------------------------------------------------------------------
# 获取 Docker 镜像版本
# -----------------------------------------------------------------------------
docker_image_version() {
    local container="$1"
    if ! has_docker; then echo ""; return; fi
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
        docker inspect -f '{{.Config.Image}}' "$container" 2>/dev/null | sed 's/.*://' || echo ""
    fi
}

# -----------------------------------------------------------------------------
# Homebrew 服务状态
# -----------------------------------------------------------------------------
brew_service_status() {
    local brew_name="$1"
    if ! has_brew; then echo "n/a"; return; fi
    local line; line=$(brew services list 2>/dev/null | grep "^${brew_name}\s" || echo "")
    if [[ -z "$line" ]]; then echo "not_found"; return; fi
    local status; status=$(echo "$line" | awk '{print $2}')
    local user; user=$(echo "$line" | awk '{print $3}')
    echo "$status (user: $user)"
}

# -----------------------------------------------------------------------------
# Systemd 服务状态
# -----------------------------------------------------------------------------
systemd_service_status() {
    local unit="$1"
    if ! has_systemctl; then echo "n/a"; return; fi
    if ! systemctl list-unit-files "$unit" &>/dev/null 2>&1; then
        echo "not_found"
        return
    fi
    local active; active=$(systemctl is-active "$unit" 2>/dev/null || echo "unknown")
    local enabled; enabled=$(systemctl is-enabled "$unit" 2>/dev/null || echo "unknown")
    echo "$active (enabled: $enabled)"
}

# -----------------------------------------------------------------------------
# 端口状态检查（逐个端口）
# -----------------------------------------------------------------------------
check_all_ports() {
    local svc="$1"
    local ports; ports=$(svc_ports "$svc")
    local results=()
    IFS=',' read -ra port_arr <<< "$ports"
    for p in "${port_arr[@]}"; do
        p="${p// /}"  # trim spaces
        if port_open "localhost" "$p" 1; then
            results+=("$p:✅")
        else
            results+=("$p:❌")
        fi
    done
    local joined; joined=$(printf ", %s" "${results[@]}")
    echo "${joined:2}"  # 去掉开头的 ", "
}

# -----------------------------------------------------------------------------
# 健康检查详情
# -----------------------------------------------------------------------------
health_detail() {
    local svc="$1"
    local port; port=$(svc_port "$svc")

    if ! port_open "localhost" "$port" 1; then
        echo "—"
        return
    fi

    case "$svc" in
        mysql)
            # 检查 MySQL 是否可连接
            if has_docker && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$(svc_container "$svc")"; then
                if docker exec "$(svc_container "$svc")" mysqladmin ping -h localhost --silent 2>/dev/null; then
                    echo "mysqld alive"
                else
                    echo "ping failed"
                fi
            elif has_cmd mysql; then
                if mysqladmin ping -h localhost --silent 2>/dev/null; then
                    echo "mysqld alive"
                else
                    echo "ping failed"
                fi
            else
                echo "port open"
            fi
            ;;
        redis)
            if has_docker && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$(svc_container "$svc")"; then
                local pong; pong=$(docker exec "$(svc_container "$svc")" redis-cli ping 2>/dev/null || echo "")
                [[ "$pong" == "PONG" ]] && echo "PONG" || echo "no response"
            elif has_cmd redis-cli; then
                local pong; pong=$(redis-cli ping 2>/dev/null || echo "")
                [[ "$pong" == "PONG" ]] && echo "PONG" || echo "no response"
            else
                echo "port open"
            fi
            ;;
        elasticsearch)
            local health; health=$(curl -s "http://localhost:$port/_cluster/health" 2>/dev/null \
                | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "")
            [[ -n "$health" ]] && echo "cluster: $health" || echo "port open"
            ;;
        nacos)
            local code; code=$(curl -s -o /dev/null -w "%{http_code}" \
                "http://localhost:$port/nacos/v1/console/health" 2>/dev/null || echo "000")
            [[ "$code" == "200" ]] && echo "healthy" || echo "HTTP $code"
            ;;
        rocketmq)
            if curl -s -o /dev/null --connect-timeout 2 "http://localhost:18080" 2>/dev/null; then
                echo "proxy reachable"
            elif port_open "localhost" "9876" 1; then
                echo "namesrv only"
            else
                echo "—"
            fi
            ;;
        loongcollector)
            curl -s -o /dev/null --connect-timeout 2 "http://localhost:$port" 2>/dev/null \
                && echo "reachable" || echo "no response"
            ;;
        kibana)
            curl -s -o /dev/null --connect-timeout 3 "http://localhost:$port" 2>/dev/null \
                && echo "reachable" || echo "no response"
            ;;
        *) echo "—" ;;
    esac
}

# -----------------------------------------------------------------------------
# 获取版本
# -----------------------------------------------------------------------------
get_version() {
    local svc="$1" method="$2"
    local port; port=$(svc_port "$svc")

    case "$method" in
        docker)
            docker_image_version "$(svc_container "$svc")"
            ;;
        brew)
            if has_brew; then
                local brew_name; brew_name=$(svc_brew "$svc")
                brew info "$brew_name" 2>/dev/null | head -1 | grep -oP '\d+\.\d+(\.\d+)?' | head -1 || echo ""
            fi
            ;;
        systemd)
            case "$svc" in
                mysql)
                    if has_cmd mysqld; then mysqld --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1; fi ;;
                redis)
                    if has_cmd redis-server; then redis-server --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1; fi ;;
                elasticsearch)
                    if port_open "localhost" "$port" 1; then
                        curl -s "http://localhost:$port" 2>/dev/null | grep -oP '"number"\s*:\s*"[^"]*"' | head -1 | grep -oP '\d+\.\d+\.\d+' || echo ""
                    fi ;;
                *) echo "" ;;
            esac
            ;;
        manual)
            # 手动进程 — 尝试从端口获取版本
            case "$svc" in
                elasticsearch)
                    if port_open "localhost" "$port" 1; then
                        curl -s "http://localhost:$port" 2>/dev/null | grep -oP '"number"\s*:\s*"[^"]*"' | head -1 | grep -oP '\d+\.\d+\.\d+' || echo ""
                    fi ;;
                nacos)
                    if port_open "localhost" "$port" 1; then
                        curl -s "http://localhost:$port/nacos/v1/console/health" 2>/dev/null \
                            | grep -oP '"version":"[^"]*"' | cut -d'"' -f4 || echo ""
                    fi ;;
                *) echo "" ;;
            esac
            ;;
        *) echo "" ;;
    esac
}

# -----------------------------------------------------------------------------
# 获取进程列表
# -----------------------------------------------------------------------------
get_processes() {
    local svc="$1" method="$2"
    if [[ "$method" == "docker" || "$method" == "none" ]]; then
        echo "—"
        return
    fi

    local port; port=$(svc_port "$svc")
    if ! port_open "localhost" "$port" 1; then
        echo "—"
        return
    fi

    local os_type
    case "$(uname -s)" in
        Darwin) os_type="macOS";;
        Linux)  os_type="Linux";;
        *)      os_type="Other";;
    esac

    if [[ "$os_type" == "macOS" || "$os_type" == "Linux" ]]; then
        local pids
        pids=$(lsof -ti "TCP:$port" -sTCP:LISTEN 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
        if [[ -n "$pids" ]]; then
            echo "PID: $pids"
        else
            echo "—"
        fi
    else
        echo "—"
    fi
}

# -----------------------------------------------------------------------------
# 表格输出（人类可读）
# -----------------------------------------------------------------------------
print_table_header() {
    printf "\n"
    printf "${BOLD}%-16s  %-12s  %-26s  %-12s  %-18s  %s${NC}\n" \
        "SERVICE" "STATUS" "PORTS" "METHOD" "HEALTH" "VERSION"
    printf '%.0s─' {1..115}
    printf "\n"
}

print_table_row() {
    local name="$1" status="$2" ports="$3" method="$4" health="$5" version="$6"

    local status_color=""
    case "$status" in
        RUNNING)  status_color="${GREEN}";;
        STOPPED)  status_color="${RED}";;
        WARNING)  status_color="${YELLOW}";;
        *)        status_color="${DIM}";;
    esac

    printf "%-16s  ${status_color}%-12s${NC}  %-26s  %-12s  %-18s  %s\n" \
        "$name" "$status" "$ports" "$method" "$health" "$version"
}

# -----------------------------------------------------------------------------
# JSON 输出
# -----------------------------------------------------------------------------
print_json() {
    echo "["
    local first=true
    for svc in "${ALL_SERVICES[@]}"; do
        local name; name=$(svc_name "$svc")
        local port; port=$(svc_port "$svc")
        local method; method=$(detect_method "$svc")
        local running=false
        port_open "localhost" "$port" 1 && running=true

        local container_status="n/a"
        if has_docker; then
            container_status=$(docker_container_status "$(svc_container "$svc")")
        fi

        local health
        $running && health=$(health_detail "$svc") || health="—"

        local version; version=$(get_version "$svc" "$method")
        local ports_status; ports_status=$(check_all_ports "$svc")

        $first || echo ","
        first=false

        local status_str
        $running && status_str="RUNNING" || status_str="STOPPED"

        cat <<JSONBLOCK
  {
    "service": "$name",
    "key": "$svc",
    "status": "$status_str",
    "port": "$port",
    "ports": "$ports_status",
    "method": "$method",
    "container": "$container_status",
    "health": "$health",
    "version": "$version"
  }
JSONBLOCK
    done
    echo ""
    echo "]"
}

# -----------------------------------------------------------------------------
# 单服务检查（供 watch 模式复用）
# -----------------------------------------------------------------------------
check_all_services() {
    local running=0 stopped=0 warn=0
    local rows=()

    for svc in "${ALL_SERVICES[@]}"; do
        local name; name=$(svc_name "$svc")
        local port; port=$(svc_port "$svc")
        local method; method=$(detect_method "$svc")

        local is_running=false
        port_open "localhost" "$port" 1 && is_running=true

        local health; health=$(health_detail "$svc")
        local version; version=$(get_version "$svc" "$method")
        local ports_status; ports_status=$(check_all_ports "$svc")

        # 判定状态
        local status
        if $is_running; then
            if [[ "$health" == "—" || "$health" == "no response" || "$health" == *"failed"* ]]; then
                status="WARNING"
                ((warn++))
            else
                status="RUNNING"
                ((running++))
            fi
        else
            status="STOPPED"
            ((stopped++))
        fi

        # Docker 容器状态叠加
        if [[ "$method" == "docker" ]]; then
            local cstatus; cstatus=$(docker_container_status "$(svc_container "$svc")")
            if [[ "$cstatus" == "exited" || "$cstatus" == "dead" ]]; then
                status="STOPPED"
                ((stopped++))
                $is_running && ((running--))
            fi
        fi

        if $JSON_MODE; then
            rows+=("$(printf '{"service":"%s","status":"%s","ports":"%s","method":"%s","health":"%s","version":"%s"}' \
                "$name" "$status" "$ports_status" "$method" "$health" "$version")")
        else
            print_table_row "$name" "$status" "$ports_status" "$method" "$health" "$version"
        fi
    done

    if ! $JSON_MODE; then
        printf '%.0s─' {1..115}
        printf "\n"
        printf "${BOLD}Summary:${NC}  ${GREEN}Running: $running${NC}  ${RED}Stopped: $stopped${NC}  ${YELLOW}Warning: $warn${NC}\n"
    fi
}

# -----------------------------------------------------------------------------
# 简洁模式
# -----------------------------------------------------------------------------
print_short() {
    local parts=()
    for svc in "${ALL_SERVICES[@]}"; do
        local port; port=$(svc_port "$svc")
        if port_open "localhost" "$port" 1; then
            parts+=("${GREEN}$(svc_name "$svc")✅${NC}")
        else
            parts+=("${DIM}$(svc_name "$svc")❌${NC}")
        fi
    done

    local joined; joined=$(printf "  " "${parts[@]}")
    echo -e "$joined"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    if $SHORT_MODE; then
        print_short
        exit 0
    fi

    if $JSON_MODE; then
        print_json
        exit 0
    fi

    if $WATCH_MODE; then
        echo -e "${CYAN}持续监控模式 · 每 5s 刷新 · Ctrl+C 退出${NC}"
        while true; do
            clear 2>/dev/null || printf "\n\n"
            echo -e "${CYAN}${BOLD}Spring AI Alibaba Admin · 中间件运行状态${NC}"
            echo -e "${DIM}刷新间隔 5s · $(date '+%Y-%m-%d %H:%M:%S')${NC}"
            print_table_header
            check_all_services
            sleep 5
        done
    fi

    # 单次输出
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  Spring AI Alibaba Admin · 中间件运行状态               ║${NC}"
    echo -e "${CYAN}${BOLD}║  $(date '+%Y-%m-%d %H:%M:%S')                                               ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"

    # 环境信息
    local os_name; os_name="$(uname -s)"
    echo -e "\n${DIM}OS: $os_name · Docker: $(has_docker && echo 'available' || echo 'unavailable') · Brew: $(has_brew && echo 'yes' || echo 'no') · Systemd: $(has_systemctl && echo 'yes' || echo 'no')${NC}"

    print_table_header
    check_all_services

    echo ""
}

main "$@"
