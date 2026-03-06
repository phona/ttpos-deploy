#!/bin/bash
# Health check script for Nginx
# Returns 0 if healthy, 1 if unhealthy

set -e

# Configuration
HEALTH_PORT=${NGINX_HTTP_PORT:-80}
HEALTH_PATH=${HEALTH_PATH:-/health}
HEALTH_HOST=${HEALTH_HOST:-localhost}
TIMEOUT=${HEALTH_TIMEOUT:-5}

# Check if nginx is responding
check_http() {
    local url="http://${HEALTH_HOST}:${HEALTH_PORT}${HEALTH_PATH}"

    if command -v curl &> /dev/null; then
        response=$(curl -sf --max-time "${TIMEOUT}" "${url}" 2>/dev/null) && return 0
    elif command -v wget &> /dev/null; then
        wget -q --timeout="${TIMEOUT}" --spider "${url}" 2>/dev/null && return 0
    else
        # Fallback: check if port is listening
        nc -z "${HEALTH_HOST}" "${HEALTH_PORT}" 2>/dev/null && return 0
    fi

    return 1
}

# Check nginx process
check_nginx() {
    # Check if nginx is running
    if nginx -t 2>/dev/null; then
        return 0
    fi

    return 1
}

# Main health check
if check_http && check_nginx; then
    echo "healthy"
    exit 0
else
    echo "unhealthy"
    exit 1
fi
