# TTPOS Deploy Makefile
# Quick commands for deployment operations

# Default values
SERVICE ?= all
ENV ?= staging
TAG ?= latest
SVC ?= main

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m

# Directories
SERVICES_DIR := services
ENVIRONMENTS_DIR := environments
SCRIPTS_DIR := scripts

.PHONY: help deploy rollback health-check logs validate clean lint \
        dev dev-down dev-logs dev-logs-service dev-partial dev-reset dev-status dev-ps dev-init \
        dev-restart dev-rebuild decrypt-secrets ansible-deploy ansible-health status pull

# Default target
help:
	@echo "$(BLUE)TTPOS Deploy - Available Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Local Development:$(NC)"
	@echo "  make dev-init                                     - One-time setup for local dev"
	@echo "  make dev                                          - Start full local stack"
	@echo "  make dev-down                                     - Stop local stack"
	@echo "  make dev-logs                                     - View all logs"
	@echo "  make dev-logs-service SVC=<name>                  - View specific service logs"
	@echo "  make dev-status                                   - Show service status"
	@echo "  make dev-partial SERVICES=main,bmp-erp            - Start partial stack"
	@echo "  make dev-reset                                    - Reset all data (destructive)"
	@echo ""
	@echo "$(GREEN)Deployment:$(NC)"
	@echo "  make deploy SERVICE=<name> ENV=<env> [TAG=<tag>]  - Deploy a service"
	@echo "  make rollback SERVICE=<name> ENV=<env> TAG=<tag>  - Rollback to previous version"
	@echo "  make health-check ENV=<env>                       - Run health checks"
	@echo "  make logs SERVICE=<name> ENV=<env>                - View service logs"
	@echo ""
	@echo "$(GREEN)Utilities:$(NC)"
	@echo "  make validate                                     - Validate all compose files"
	@echo "  make lint                                         - Lint configuration files"
	@echo "  make clean                                        - Clean up temporary files"
	@echo ""
	@echo "$(GREEN)Examples:$(NC)"
	@echo "  make dev                                          # Start full local stack"
	@echo "  make deploy SERVICE=main ENV=staging"
	@echo "  make deploy SERVICE=main ENV=production TAG=v1.2.3"
	@echo "  make rollback SERVICE=main ENV=production TAG=v1.2.2"
	@echo ""

# ===========================================
# Deployment Commands
# ===========================================

# Deploy a service
deploy:
	@echo "$(BLUE)Deploying $(SERVICE) to $(ENV)...$(NC)"
	@if [ "$(ENV)" = "production" ] && [ "$(TAG)" = "latest" ]; then \
		echo "$(RED)Error: Production deployments require an explicit tag (not 'latest')$(NC)"; \
		exit 1; \
	fi
	@$(SCRIPTS_DIR)/deploy.sh -s $(SERVICE) -e $(ENV) -t $(TAG)

# Rollback a service
rollback:
	@echo "$(YELLOW)Rolling back $(SERVICE) in $(ENV) to $(TAG)...$(NC)"
	@if [ -z "$(TAG)" ] || [ "$(TAG)" = "latest" ]; then \
		echo "$(RED)Error: Rollback requires an explicit tag$(NC)"; \
		exit 1; \
	fi
	@$(SCRIPTS_DIR)/rollback.sh $(SERVICE) $(ENV) $(TAG)

# Health check
health-check:
	@echo "$(BLUE)Running health checks for $(ENV)...$(NC)"
	@$(SCRIPTS_DIR)/health-check.sh -s all -e $(ENV)

# View logs
logs:
	@echo "$(BLUE)Viewing logs for $(SERVICE) in $(ENV)...$(NC)"
	@if [ "$(SERVICE)" = "all" ]; then \
		docker compose -f $(SERVICES_DIR)/main/compose.yml -f $(SERVICES_DIR)/main/compose.$(ENV).yml logs -f; \
	else \
		docker compose -f $(SERVICES_DIR)/$(SERVICE)/compose.yml -f $(SERVICES_DIR)/$(SERVICE)/compose.$(ENV).yml logs -f; \
	fi

# ===========================================
# Local Development (Full Stack)
# ===========================================

dev-init: ## One-time setup for local development
	@echo "$(BLUE)Initializing local development environment...$(NC)"
	@./scripts/dev-init.sh

dev: ## Start full local development stack (all services + infra)
	@echo "$(BLUE)Starting local development stack...$(NC)"
	@if [ ! -f ".env.dev" ]; then \
		echo "$(YELLOW)Creating .env.dev from template...$(NC)"; \
		cp .env.dev.example .env.dev; \
	fi
	docker compose -f docker-compose.dev.yml up -d
	@echo ""
	@echo "$(GREEN)Development stack started!$(NC)"
	@echo ""
	@echo "$(BLUE)Endpoints:$(NC)"
	@echo "  Nginx:    http://localhost"
	@echo "  Main API: http://localhost:8080"
	@echo "  Nacos:    http://localhost:8848/nacos (nacos/nacos)"
	@echo ""
	@echo "$(BLUE)Commands:$(NC)"
	@echo "  make dev-logs     # View all logs"
	@echo "  make dev-status   # Check status"
	@echo "  make dev-down     # Stop all"
	@echo ""

dev-down: ## Stop local development stack
	@echo "$(YELLOW)Stopping local development stack...$(NC)"
	docker compose -f docker-compose.dev.yml down
	@echo "$(GREEN)Development stack stopped$(NC)"

dev-logs: ## View logs from all services
	docker compose -f docker-compose.dev.yml logs -f

dev-logs-service: ## View logs from specific service (make dev-logs-service SVC=main)
	docker compose -f docker-compose.dev.yml logs -f $(SVC)

dev-partial: ## Start only specified services + infra (make dev-partial SERVICES="main,bmp-erp")
	@echo "$(BLUE)Starting partial stack: $(SERVICES)...$(NC)"
	@if [ ! -f ".env.dev" ]; then \
		cp .env.dev.example .env.dev; \
	fi
	docker compose -f docker-compose.dev.yml up -d mysql redis nacos rocketmq-namesrv rocketmq-broker $(subst $(comma), ,$(SERVICES))

dev-reset: ## Reset all data and restart fresh (WARNING: destroys all data)
	@echo "$(RED)Resetting all data...$(NC)"
	@read -p "Are you sure? This will delete all databases and data. [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		docker compose -f docker-compose.dev.yml down -v; \
		docker compose -f docker-compose.dev.yml up -d; \
		echo "$(GREEN)Reset complete$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled$(NC)"; \
	fi

dev-status: ## Show status of all services
	@echo "$(BLUE)Local Development Stack Status:$(NC)"
	@docker compose -f docker-compose.dev.yml ps

dev-ps: ## Alias for dev-status
	$(MAKE) dev-status

dev-restart: ## Restart all services
	@echo "$(BLUE)Restarting local development stack...$(NC)"
	docker compose -f docker-compose.dev.yml restart
	@echo "$(GREEN)Restart complete$(NC)"

dev-rebuild: ## Rebuild and restart all services
	@echo "$(BLUE)Rebuilding local development stack...$(NC)"
	docker compose -f docker-compose.dev.yml up -d --build --force-recreate
	@echo "$(GREEN)Rebuild complete$(NC)"

# ===========================================
# Utilities
# ===========================================

# Validate all compose files
validate:
	@echo "$(BLUE)Validating compose files...$(NC)"
	@for svc in main php bmp-erp bmp-takeout bmp-message bmp-websocket nginx; do \
		if [ -f "$(SERVICES_DIR)/$$svc/compose.yml" ]; then \
			echo "Validating $$svc..."; \
			docker compose -f $(SERVICES_DIR)/$$svc/compose.yml config --quiet 2>/dev/null || echo "$(RED)Invalid: $$svc/compose.yml$(NC)"; \
			if [ -f "$(SERVICES_DIR)/$$svc/compose.staging.yml" ]; then \
				docker compose -f $(SERVICES_DIR)/$$svc/compose.yml -f $(SERVICES_DIR)/$$svc/compose.staging.yml config --quiet 2>/dev/null || echo "$(RED)Invalid: $$svc staging override$(NC)"; \
			fi; \
			if [ -f "$(SERVICES_DIR)/$$svc/compose.prod.yml" ]; then \
				docker compose -f $(SERVICES_DIR)/$$svc/compose.yml -f $(SERVICES_DIR)/$$svc/compose.prod.yml config --quiet 2>/dev/null || echo "$(RED)Invalid: $$svc production override$(NC)"; \
			fi; \
		fi \
	done
	@echo "$(GREEN)Validation complete$(NC)"

# Lint configuration files
lint:
	@echo "$(BLUE)Linting configuration files...$(NC)"
	@if command -v yamllint >/dev/null 2>&1; then \
		yamllint services/ environments/ ansible/ libs/; \
	else \
		echo "$(YELLOW)yamllint not installed, skipping YAML lint$(NC)"; \
	fi
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint ansible/playbooks/*.yml; \
	else \
		echo "$(YELLOW)ansible-lint not installed, skipping Ansible lint$(NC)"; \
	fi
	@echo "$(GREEN)Lint complete$(NC)"

# Clean temporary files
clean:
	@echo "$(BLUE)Cleaning up...$(NC)"
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".DS_Store" -delete
	@rm -rf .ansible/tmp 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete$(NC)"

# ===========================================
# Ansible Commands
# ===========================================

# Decrypt secrets for an environment
decrypt-secrets:
	@echo "$(BLUE)Decrypting secrets for $(ENV)...$(NC)"
	@$(SCRIPTS_DIR)/decrypt-secrets.sh $(ENV)

# Run Ansible playbook directly
ansible-deploy:
	@echo "$(BLUE)Running Ansible deployment for $(SERVICE) to $(ENV)...$(NC)"
	@cd ansible && ansible-playbook -i inventories/$(ENV)/hosts.yml playbooks/deploy.yml \
		-e "service_name=$(SERVICE)" \
		-e "env=$(ENV)" \
		-e "tag=$(TAG)"

# Run Ansible health check
ansible-health:
	@echo "$(BLUE)Running Ansible health check for $(ENV)...$(NC)"
	@cd ansible && ansible-playbook -i inventories/$(ENV)/hosts.yml playbooks/health-check.yml

# Show service status
status:
	@echo "$(BLUE)Service status for $(ENV):$(NC)"
	@for svc in main php bmp-erp bmp-takeout bmp-message bmp-websocket nginx; do \
		if [ -f "$(SERVICES_DIR)/$$svc/compose.yml" ]; then \
			echo "\n$$svc:"; \
			docker compose -f $(SERVICES_DIR)/$$svc/compose.yml -f $(SERVICES_DIR)/$$svc/compose.$(ENV).yml ps 2>/dev/null || echo "  Not running"; \
		fi \
	done

# Pull latest images
pull:
	@echo "$(BLUE)Pulling latest images for $(ENV)...$(NC)"
	@source $(ENVIRONMENTS_DIR)/$(ENV)/env && \
	for svc in main php bmp-erp bmp-takeout bmp-message bmp-websocket nginx; do \
		if [ -f "$(SERVICES_DIR)/$$svc/compose.yml" ]; then \
			echo "Pulling $$svc..."; \
			docker compose -f $(SERVICES_DIR)/$$svc/compose.yml pull 2>/dev/null || true; \
		fi \
	done
	@echo "$(GREEN)Pull complete$(NC)"
