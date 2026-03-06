#!/bin/bash
# Health Check Script for TTPOS
# scripts/health-check.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
SERVICE="all"
ENV="staging"
VERBOSE=false

# Help message
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Check health of TTPOS services.

Options:
    -s, --service SERVICE    Service to check (default: all)
    -e, --env ENVIRONMENT    Target environment (default: staging)
    -v, --verbose            Enable verbose output
    -h, --help               Show this help message

Examples:
    $(basename "$0") -s all -e staging
    $(basename "$0") -s main -e production -v
EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--service)
                SERVICE="$2"
                shift 2
                ;;
            -e|--env)
                ENV="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                ;;
        esac
    done
}

# Service health configurations
declare -A SERVICE_PORTS=(
    ["main"]="8080"
    ["php"]="9000"
    ["bmp-erp"]="14020"
    ["bmp-takeout"]="14030"
    ["bmp-message"]="14040"
    ["bmp-websocket"]="14050"
    ["nginx"]="80"
)

declare -A SERVICE_PATHS=(
    ["main"]="/health"
    ["php"]="/status"
    ["bmp-erp"]="/health"
    ["bmp-takeout"]="/health"
    ["bmp-message"]="/health"
    ["bmp-websocket"]="/health"
    ["nginx"]="/health"
)

# Check container health
check_container_health() {
    local svc="$1"
    local container="ttpos-$svc-$ENV"

    local status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")

    case $status in
        healthy)
            echo -e "${GREEN}✓${NC} $svc: $status"
            return 0
            ;;
        unhealthy)
            echo -e "${RED}✗${NC} $svc: $status"
            return 1
            ;;
        starting)
            echo -e "${YELLOW}○${NC} $svc: $status"
            return 2
            ;;
        not_found)
            echo -e "${YELLOW}?${NC} $svc: container not found"
            return 3
            ;;
        *)
            echo -e "${YELLOW}?${NC} $svc: $status"
            return 4
            ;;
    esac
}

# Check HTTP health endpoint
check_http_health() {
    local svc="$1"
    local port="${SERVICE_PORTS[$svc]}"
    local path="${SERVICE_PATHS[$svc]}"
    local url="http://localhost:$port$path"

    if [[ "$VERBOSE" == true ]]; then
        echo "Checking $url..."
    fi

    local response=$(curl -sf --max-time 5 "$url" 2>/dev/null)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} $svc: HTTP OK"
        return 0
    else
        echo -e "${RED}✗${NC} $svc: HTTP FAILED"
        return 1
    fi
}

# Get services to check
get_services() {
    if [[ "$SERVICE" == "all" ]]; then
        echo "main php bmp-erp bmp-takeout bmp-message bmp-websocket nginx"
    else
        echo "$SERVICE"
    fi
}

# Main function
main() {
    parse_args "$@"

    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}TTPOS Health Check${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "Environment: $ENV"
    echo -e "Service:     $SERVICE"
    echo -e "${BLUE}======================================${NC}"

    local services=$(get_services)
    local healthy=0
    local unhealthy=0
    local unknown=0

    for svc in $services; do
        # Try container health first
        if ! check_container_health "$svc"; then
            # Fallback to HTTP health check
            if check_http_health "$svc"; then
                ((healthy++))
            else
                ((unhealthy++))
            fi
        else
            ((healthy++))
        fi
    done

    echo -e "${BLUE}======================================${NC}"
    echo -e "Summary: ${GREEN}$healthy healthy${NC}, ${RED}$unhealthy unhealthy${NC}, ${YELLOW}$unknown unknown${NC}"
    echo -e "${BLUE}======================================${NC}"

    if [[ $unhealthy -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
