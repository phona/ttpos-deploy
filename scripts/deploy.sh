#!/bin/bash
# Main Deployment Script for TTPOS
# scripts/deploy.sh

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
TAG=""
DRY_RUN=false
VERBOSE=false

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICES_DIR="$PROJECT_DIR/services"
ENVIRONMENTS_DIR="$PROJECT_DIR/environments"

# Help message
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy TTPOS services to specified environment.

Options:
    -s, --service SERVICE    Service to deploy (default: all)
                             Options: all, main, php, bmp-erp, bmp-takeout,
                                      bmp-message, bmp-websocket, nginx
    -e, --env ENVIRONMENT    Target environment (default: staging)
                             Options: staging, production
    -t, --tag TAG            Image tag to deploy (required for production)
    --dry-run                Show what would be deployed without making changes
    -v, --verbose            Enable verbose output
    -h, --help               Show this help message

Examples:
    $(basename "$0") -s main -e staging
    $(basename "$0") -s all -e production -t v1.2.3
    $(basename "$0") -s nginx -e staging --dry-run
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
            -t|--tag)
                TAG="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
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

# Validate inputs
validate_inputs() {
    # Validate environment
    if [[ ! "$ENV" =~ ^(staging|production)$ ]]; then
        echo -e "${RED}Error: Invalid environment '$ENV'. Must be 'staging' or 'production'.${NC}"
        exit 1
    fi

    # Validate service
    VALID_SERVICES="all main php bmp-erp bmp-takeout bmp-message bmp-websocket nginx"
    if [[ ! " $VALID_SERVICES " =~ " $SERVICE " ]]; then
        echo -e "${RED}Error: Invalid service '$SERVICE'.${NC}"
        echo "Valid services: $VALID_SERVICES"
        exit 1
    fi

    # Production requires explicit tag
    if [[ "$ENV" == "production" ]] && [[ -z "$TAG" || "$TAG" == "latest" ]]; then
        echo -e "${RED}Error: Production deployments require an explicit image tag (not 'latest').${NC}"
        exit 1
    fi

    # Set default tag for staging
    if [[ -z "$TAG" ]]; then
        TAG="latest"
    fi

    # Check environment file exists
    ENV_FILE="$ENVIRONMENTS_DIR/$ENV/env"
    if [[ ! -f "$ENV_FILE" ]]; then
        echo -e "${YELLOW}Warning: Environment file not found: $ENV_FILE${NC}"
    fi
}

# Load environment variables
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        echo -e "${BLUE}Loading environment from $ENV_FILE${NC}"
        set -a
        source "$ENV_FILE"
        set +a
    fi
}

# Get services to deploy
get_services() {
    if [[ "$SERVICE" == "all" ]]; then
        echo "main php bmp-erp bmp-takeout bmp-message bmp-websocket nginx"
    else
        echo "$SERVICE"
    fi
}

# Deploy a single service
deploy_service() {
    local svc="$1"
    local compose_dir="$SERVICES_DIR/$svc"
    local compose_file="$compose_dir/compose.yml"
    local env_compose_file="$compose_dir/compose.$ENV.yml"

    if [[ ! -f "$compose_file" ]]; then
        echo -e "${YELLOW}Warning: Compose file not found for $svc, skipping${NC}"
        return 0
    fi

    echo -e "${BLUE}Deploying $svc...${NC}"

    # Build compose command
    local compose_cmd="docker compose -f $compose_file"

    if [[ -f "$env_compose_file" ]]; then
        compose_cmd="$compose_cmd -f $env_compose_file"
    fi

    # Add environment variables (compatible with production naming)
    export IMAGE_VERSION="$TAG"
    export IMAGE_TAG="$TAG"  # Backward compatibility
    export ENV="$ENV"
    export APP_ID="${APP_ID:-$ENV}"
    export ENV_FILE="$ENV_FILE"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN] Would execute:${NC}"
        echo "  $compose_cmd up -d --remove-orphans"
        return 0
    fi

    # Pull images
    if [[ "$VERBOSE" == true ]]; then
        echo "Pulling images for $svc..."
    fi
    $compose_cmd pull 2>/dev/null || true

    # Deploy
    $compose_cmd up -d --remove-orphans

    echo -e "${GREEN}Deployed $svc successfully${NC}"
}

# Wait for services to be healthy
wait_for_health() {
    local services="$1"
    local max_wait=120
    local interval=5
    local elapsed=0

    echo -e "${BLUE}Waiting for services to be healthy...${NC}"

    for svc in $services; do
        elapsed=0
        while [[ $elapsed -lt $max_wait ]]; do
            # Support both old and new container naming
            local container_old="ttpos-$svc-$ENV"
            local container_new="saas-$svc-${APP_ID:-$ENV}"
            local container=""

            if docker ps --format '{{.Names}}' | grep -q "^saas-$svc"; then
                container=$container_new
            else
                container=$container_old
            fi

            local status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")

            if [[ "$status" == "healthy" ]]; then
                echo -e "${GREEN}$svc is healthy${NC}"
                break
            elif [[ "$status" == "unhealthy" ]]; then
                echo -e "${RED}$svc is unhealthy${NC}"
                return 1
            fi

            sleep $interval
            elapsed=$((elapsed + interval))
        done

        if [[ $elapsed -ge $max_wait ]]; then
            echo -e "${YELLOW}Warning: $svc health check timed out${NC}"
        fi
    done
}

# Main deployment function
main() {
    parse_args "$@"
    validate_inputs

    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}TTPOS Deployment${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "Service:     $SERVICE"
    echo -e "Environment: $ENV"
    echo -e "Image Tag:   $TAG"
    echo -e "Dry Run:     $DRY_RUN"
    echo -e "${BLUE}======================================${NC}"

    load_env

    # Create Docker network if needed (support both old and new naming)
    if [[ "$DRY_RUN" == false ]]; then
        docker network create "ttpos-$ENV" 2>/dev/null || true
        docker network create "saas-network-${APP_ID:-$ENV}" 2>/dev/null || true
        docker network create "bmp-network-${APP_ID:-$ENV}" 2>/dev/null || true
    fi

    # Get services to deploy
    services=$(get_services)

    # Deploy services
    for svc in $services; do
        deploy_service "$svc"
    done

    # Wait for health checks
    if [[ "$DRY_RUN" == false ]]; then
        wait_for_health "$services"
    fi

    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${GREEN}======================================${NC}"

    if [[ "$DRY_RUN" == false ]]; then
        echo -e "${BLUE}Service Status:${NC}"
        for svc in $services; do
            # Support both old and new container naming patterns
            docker ps --filter "name=ttpos-$svc-$ENV" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
            docker ps --filter "name=saas-$svc-${APP_ID:-$ENV}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
        done
    fi
}

main "$@"
