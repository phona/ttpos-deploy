#!/bin/bash
# Health check script for PHP-FPM Service
# Returns 0 if healthy, 1 if unhealthy

set -e

# Configuration
PHP_FPM_HOST=${PHP_FPM_HOST:-localhost}
PHP_FPM_PORT=${PHP_FPM_PORT:-9000}
PHP_FPM_STATUS_PATH=${PHP_FPM_STATUS_PATH:-/status}
TIMEOUT=${HEALTH_TIMEOUT:-5}

# Check PHP-FPM status
check_php_fpm() {
    # Method 1: Check if port is listening
    if command -v nc &> /dev/null; then
        nc -z "${PHP_FPM_HOST}" "${PHP_FPM_PORT}" 2>/dev/null && return 0
    fi

    # Method 2: Check using cgi-fcgi if available
    if command -v cgi-fcgi &> /dev/null; then
        response=$(SCRIPT_NAME="${PHP_FPM_STATUS_PATH}" \
                   SCRIPT_FILENAME="${PHP_FPM_STATUS_PATH}" \
                   REQUEST_METHOD=GET \
                   cgi-fcgi -bind -connect "${PHP_FPM_HOST}:${PHP_FPM_PORT}" 2>/dev/null) && return 0
    fi

    # Method 3: Check PHP-FPM process
    if pgrep php-fpm &> /dev/null; then
        return 0
    fi

    return 1
}

# Main health check
if check_php_fpm; then
    echo "healthy"
    exit 0
else
    echo "unhealthy"
    exit 1
fi
