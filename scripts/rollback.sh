#!/bin/bash
# Rollback Script for TTPOS
# scripts/rollback.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
SERVICE=""
ENV="staging"
PREVIOUS_TAG=""

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICES_DIR="$PROJECT_DIR/services"
ENVIRONMENTS_DIR="$PROJECT_DIR/environments"

# Help message
usage() {
    cat << EOF
Usage: $(basename "$0") SERVICE ENVIRONMENT PREVIOUS_TAG

Rollback a TTPOS service to a previous version.

Arguments:
    SERVICE        Service to rollback (main, php, bmp-erp, bmp-takeout,
                   bmp-message, bmp-websocket, nginx)
    ENVIRONMENT    Target environment (staging, production)
    PREVIOUS_TAG   The image tag to rollback to

Examples:
    $(basename "$0") main production v1.2.2
    $(basename "$0") nginx staging v1.2.0
EOF
    exit 0
}

# Parse arguments
parse_args() {
    if [[ $# -lt 3 ]]; then
        echo -e "${RED}Error: Missing required arguments${NC}"
        usage
    fi

    SERVICE="$1"
    ENV="$2"
    PREVIOUS_TAG="$3"
}

# Validate inputs
validate_inputs() {
    # Validate environment
    if [[ ! "$ENV" =~ ^(staging|production)$ ]]; then
        echo -e "${RED}Error: Invalid environment '$ENV'. Must be 'staging' or 'production'.${NC}"
        exit 1
    fi

    # Validate service
    VALID_SERVICES="main php bmp-erp bmp-takeout bmp-message bmp-websocket nginx"
    if [[ ! " $VALID_SERVICES " =~ " $SERVICE " ]]; then
        echo -e "${RED}Error: Invalid service '$SERVICE'.${NC}"
        echo "Valid services: $VALID_SERVICES"
        exit 1
    fi

    # Validate tag
    if [[ -z "$PREVIOUS_TAG" ]]; then
        echo -e "${RED}Error: Previous tag is required for rollback.${NC}"
        exit 1
    fi

    # Check compose file exists
    COMPOSE_FILE="$SERVICES_DIR/$SERVICE/compose.yml"
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        echo -e "${RED}Error: Compose file not found: $COMPOSE_FILE${NC}"
        exit 1
    fi
}

# Get current version
get_current_version() {
    local container="ttpos-$SERVICE-$ENV"
    docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null || echo "unknown"
}

# Rollback service
rollback_service() {
    local compose_dir="$SERVICES_DIR/$SERVICE"
    local compose_file="$compose_dir/compose.yml"
    local env_compose_file="$compose_dir/compose.$ENV.yml"
    local env_file="$ENVIRONMENTS_DIR/$ENV/env"

    echo -e "${YELLOW}======================================${NC}"
    echo -e "${YELLOW}TTPOS Rollback${NC}"
    echo -e "${YELLOW}======================================${NC}"
    echo -e "Service:       $SERVICE"
    echo -e "Environment:   $ENV"
    echo -e "Current:       $(get_current_version)"
    echo -e "Rollback to:   $PREVIOUS_TAG"
    echo -e "${YELLOW}======================================${NC}"

    # Confirm rollback
    read -p "Proceed with rollback? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Rollback cancelled.${NC}"
        exit 0
    fi

    # Load environment
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
    fi

    # Set deployment variables
    export IMAGE_TAG="$PREVIOUS_TAG"
    export ENV="$ENV"
    export ENV_FILE="$env_file"

    # Build compose command
    local compose_cmd="docker compose -f $compose_file"
    if [[ -f "$env_compose_file" ]]; then
        compose_cmd="$compose_cmd -f $env_compose_file"
    fi

    echo -e "${BLUE}Pulling image with tag $PREVIOUS_TAG...${NC}"
    $compose_cmd pull 2>/dev/null || {
        echo -e "${RED}Error: Failed to pull image with tag $PREVIOUS_TAG${NC}"
        exit 1
    }

    echo -e "${BLUE}Deploying previous version...${NC}"
    $compose_cmd up -d --remove-orphans

    # Wait for health
    echo -e "${BLUE}Waiting for service to be healthy...${NC}"
    local container="ttpos-$SERVICE-$ENV"
    local max_wait=120
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        local status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")

        if [[ "$status" == "healthy" ]]; then
            echo -e "${GREEN}Service is healthy${NC}"
            break
        elif [[ "$status" == "unhealthy" ]]; then
            echo -e "${RED}Service is unhealthy after rollback${NC}"
            echo -e "${YELLOW}Manual intervention may be required.${NC}"
            exit 1
        fi

        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    echo

    if [[ $elapsed -ge $max_wait ]]; then
        echo -e "${YELLOW}Warning: Health check timed out${NC}"
    fi
}

# Main function
main() {
    parse_args "$@"
    validate_inputs
    rollback_service

    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}Rollback Complete!${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo -e "Service:     $SERVICE"
    echo -e "Version:     $PREVIOUS_TAG"
    echo -e "Status:      $(docker inspect --format='{{.State.Health.Status}}' "ttpos-$SERVICE-$ENV" 2>/dev/null || echo 'unknown')"
}

main "$@"
