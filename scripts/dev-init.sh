#!/bin/bash
# One-time setup for local development environment
# Usage: ./scripts/dev-init.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Initializing local development environment...${NC}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Create .env.dev if not exists
if [ ! -f ".env.dev" ]; then
    if [ -f ".env.dev.example" ]; then
        cp ".env.dev.example" ".env.dev"
        echo -e "${GREEN}✅ Created .env.dev from template${NC}"
    else
        echo -e "${YELLOW}Warning: .env.dev.example not found${NC}"
    fi
else
    echo -e "${BLUE}ℹ️  .env.dev already exists${NC}"
fi

# Create init directories
mkdir -p init/mysql

# Create MySQL init script if not exists
if [ ! -f "init/mysql/01-init.sql" ]; then
    cat > init/mysql/01-init.sql << 'EOF'
-- TTPOS Local Development MySQL Initialization
-- This script runs on first container startup

-- Create application database
CREATE DATABASE IF NOT EXISTS ttpos CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create Nacos database (for service discovery)
CREATE DATABASE IF NOT EXISTS nacos CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Grant permissions for application user
GRANT ALL PRIVILEGES ON ttpos.* TO 'ttpos'@'%';

-- Grant permissions for Nacos
GRANT ALL PRIVILEGES ON nacos.* TO 'root'@'%';

FLUSH PRIVILEGES;

-- Log completion
SELECT 'MySQL initialization complete' AS status;
EOF
    echo -e "${GREEN}✅ Created init/mysql/01-init.sql${NC}"
else
    echo -e "${BLUE}ℹ️  init/mysql/01-init.sql already exists${NC}"
fi

# Create Docker network
echo ""
echo -e "${BLUE}🌐 Creating Docker network...${NC}"
docker network create ttpos-dev 2>/dev/null || echo -e "${YELLOW}ℹ️  Network ttpos-dev already exists${NC}"

# Pull required infrastructure images
echo ""
echo -e "${BLUE}📦 Pulling infrastructure Docker images...${NC}"
docker pull mysql:8.0
docker pull redis:6.0-alpine
docker pull nacos/nacos-server:v2.2.0
docker pull apache/rocketmq:5.1.0
docker pull nginx:alpine

echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo -e "${BLUE}Quick Start:${NC}"
echo "  make dev          # Start full stack"
echo "  make dev-down     # Stop all services"
echo "  make dev-logs     # View all logs"
echo "  make dev-status   # Check service status"
echo ""
echo -e "${BLUE}Partial Stack:${NC}"
echo "  make dev-partial SERVICES=main,bmp-erp    # Start selected services + infra"
echo ""
echo -e "${BLUE}Endpoints:${NC}"
echo "  Nginx:    http://localhost"
echo "  Main API: http://localhost:8080"
echo "  Nacos:    http://localhost:8848/nacos (nacos/nacos)"
echo "  MySQL:    mysql -h 127.0.0.1 -u ttpos -pttpos123 ttpos"
echo "  Redis:    redis-cli -h 127.0.0.1 ping"
echo ""
