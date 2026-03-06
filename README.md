# TTPOS Deploy Repository

Centralized deployment repository for managing TTPOS services across multiple environments using Docker Compose, Ansible, and GitOps-like workflows.

## Overview

This repository contains all deployment configurations for TTPOS services:

- **Docker Compose** configurations for each service
- **Environment-specific** settings (staging, production)
- **Ansible playbooks** for deployment orchestration
- **GitHub Actions** workflows for CI/CD automation

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                      │
│   ttpos-server-go              ttops-deploy (this repo)              │
│   ┌──────────────────┐         ┌──────────────────────────────────┐  │
│   │ Code + Tests     │         │ Configs + Deployment             │  │
│   │ CI: Build, Test  │────────►│ CD: Deploy, Configure            │  │
│   │ Push Images      │ trigger │ Environment Management           │  │
│   └──────────────────┘         └──────────────────────────────────┘  │
│                                        │                             │
│                    ┌───────────────────┼───────────────────┐         │
│                    ▼                   ▼                   ▼         │
│              ┌──────────┐        ┌──────────┐        ┌──────────┐   │
│              │  Staging │        │   Prod   │        │   Prod   │   │
│              │  Server  │        │   US     │        │   EU     │   │
│              └──────────┘        └──────────┘        └──────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Services

| Service | Description | Image |
|---------|-------------|-------|
| `main` | Go + Gin core service | `ttpos-server-go` |
| `php` | PHP-FPM service | `php-fpm` |
| `bmp-erp` | ERP microservice | `ttpos-bmp-erp` |
| `bmp-takeout` | Takeout microservice | `ttpos-bmp-takeout` |
| `bmp-message` | Message microservice | `ttpos-bmp-message` |
| `bmp-websocket` | WebSocket microservice | `ttpos-bmp-websocket` |
| `nginx` | API Gateway | `nginx:alpine` |

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Ansible (for remote deployments)
- SOPS (for secrets management)

### Local Development

Run a complete isolated stack locally for manual testing. All 7 application services + MySQL + Redis + Nacos + RocketMQ.

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/ttops-deploy.git
   cd ttops-deploy
   ```

2. **One-time setup**
   ```bash
   make dev-init
   ```

3. **Start full stack**
   ```bash
   make dev
   ```

4. **Verify services**
   ```bash
   make dev-status
   ```

5. **Access services**
   | Service | URL | Credentials |
   |---------|-----|-------------|
   | Nginx | http://localhost | - |
   | Main API | http://localhost:8080 | - |
   | Nacos | http://localhost:8848/nacos | nacos/nacos |
   | MySQL | `mysql -h 127.0.0.1 -u ttpos -pttpos123` | ttpos/ttpos123 |
   | Redis | `redis-cli -h 127.0.0.1` | - |

#### Local Dev Commands

| Command | Description |
|---------|-------------|
| `make dev` | Start full local stack |
| `make dev-down` | Stop all services |
| `make dev-logs` | View all logs |
| `make dev-logs-service SVC=main` | View specific service logs |
| `make dev-status` | Show service status |
| `make dev-partial SERVICES=main,bmp-erp` | Start partial stack + infra |
| `make dev-reset` | Reset all data (destructive) |

#### Partial Stack

Start only specific services with infrastructure:

```bash
make dev-partial SERVICES=main,bmp-erp
```

### Deployment

#### Deploy to Staging

```bash
# Deploy a single service
make deploy SERVICE=main ENV=staging

# Deploy all services
make deploy SERVICE=all ENV=staging
```

#### Deploy to Production

```bash
# Deploy with explicit tag (required for production)
make deploy SERVICE=main ENV=production TAG=v1.2.3
```

#### Rollback

```bash
make rollback SERVICE=main ENV=production TAG=v1.2.2
```

#### Health Check

```bash
make health-check ENV=staging
```

## Project Structure

```
ttops-deploy/
├── README.md
├── DESIGN.md                    # Detailed design documentation
├── Makefile                     # Quick commands
├── docker-compose.dev.yml       # Full local development stack
├── .env.example                 # Example environment file
├── .env.dev                     # Local development environment
├── .env.dev.example             # Local dev template
│
├── init/                        # Initialization scripts
│   └── mysql/
│       └── 01-init.sql          # MySQL init script
│
├── .github/
│   └── workflows/
│       ├── deploy.yml           # Main deployment workflow
│       ├── rollback.yml         # Rollback workflow
│       └── health-check.yml     # Scheduled health checks
│
├── services/                    # Service definitions
│   ├── main/
│   │   ├── compose.yml          # Base compose file
│   │   ├── compose.staging.yml  # Staging overrides
│   │   ├── compose.prod.yml     # Production overrides
│   │   └── healthcheck.sh
│   ├── php/
│   │   ├── compose.yml
│   │   ├── compose.staging.yml
│   │   ├── compose.prod.yml
│   │   ├── healthcheck.sh
│   │   └── config/              # PHP configuration files
│   ├── bmp-erp/
│   ├── bmp-takeout/
│   ├── bmp-message/
│   ├── bmp-websocket/
│   └── nginx/
│       ├── compose.yml
│       ├── compose.staging.yml
│       ├── compose.prod.yml
│       ├── config/              # Nginx configuration files
│       └── healthcheck.sh
│
├── environments/                # Environment configs
│   ├── staging/
│   │   ├── env                  # Environment variables
│   │   └── inventory.yml        # Server inventory
│   └── production/
│       ├── env
│       └── inventory.yml
│
├── ansible/                     # Ansible playbooks
│   ├── ansible.cfg
│   ├── inventories/
│   │   ├── staging/
│   │   ├── production-us/
│   │   └── production-eu/
│   ├── playbooks/
│   │   ├── deploy.yml
│   │   ├── deploy-service.yml
│   │   ├── health-check.yml
│   │   └── rollback.yml
│   └── roles/
│       ├── docker-compose/
│       └── health-check/
│
├── scripts/                     # Utility scripts
│   ├── dev-init.sh              # Local dev setup script
│   ├── deploy.sh
│   ├── rollback.sh
│   ├── health-check.sh
│   ├── decrypt-secrets.sh
│   ├── notify.sh
│   └── cd-runner.py
│
└── libs/                        # Shared configurations
    ├── logging.yml
    └── network.yml
```

## Available Make Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make dev-init` | One-time setup for local development |
| `make dev` | Start full local development stack |
| `make dev-down` | Stop local development stack |
| `make dev-logs` | View all logs from local stack |
| `make dev-logs-service SVC=<name>` | View specific service logs |
| `make dev-status` | Show local stack status |
| `make dev-partial SERVICES=<svc1,svc2>` | Start partial stack with infra |
| `make dev-reset` | Reset all data (destructive) |
| `make deploy SERVICE=<name> ENV=<env> [TAG=<tag>]` | Deploy a service |
| `make rollback SERVICE=<name> ENV=<env> TAG=<tag>` | Rollback a service |
| `make health-check ENV=<env>` | Run health checks |
| `make logs SERVICE=<name> ENV=<env>` | View service logs |
| `make validate` | Validate all compose files |

## Environment Promotion

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                            │
│                                                                      │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐    │
│  │ Local Dev    │────►│ Local Tests  │────►│ Publish to       │    │
│  │ (Full Stack) │     │ (Manual)     │     │ Staging          │    │
│  └──────────────┘     └──────────────┘     └──────────────────┘    │
│                                                   │                  │
│                                                   ▼                  │
│                                          ┌──────────────────┐       │
│                                          │ Test Team        │       │
│                                          │ (Staging Tests)  │       │
│                                          └────────┬─────────┘       │
│                                                   │                  │
│                                                   ▼                  │
│                                          ┌──────────────────┐       │
│                                          │ Bug Reports      │       │
│                                          │ (if any)         │       │
│                                          └────────┬─────────┘       │
│                                                   │                  │
│                                                   ▼                  │
│                                          ┌──────────────────┐       │
│                                          │ Developer Fixes  │───────┘
│                                          │ (Local)          │
│                                          └──────────────────┘
└─────────────────────────────────────────────────────────────────────┘
```

| Environment | Auto-deploy | Tag Strategy | Approval Required |
|-------------|-------------|--------------|-------------------|
| **local** | Manual (`make dev`) | `latest` | None |
| **staging** | Yes (on merge) | `branch-name` / `sha` | None |
| **production** | No (manual) | `v1.2.3` (semver) | 2 approvals |

## Secrets Management

Secrets are encrypted using SOPS and stored in `environments/<env>/secrets/`.

### Setup SOPS

1. Install SOPS: https://github.com/getsops/sops/releases
2. Configure age key or cloud KMS in `.sops.yaml`
3. Encrypt secrets:
   ```bash
   sops --encrypt --inplace environments/production/secrets/secrets.yaml
   ```

### Decrypt Secrets

```bash
# Decrypt for a specific environment
./scripts/decrypt-secrets.sh production
```

## GitHub Actions Workflows

### Deploy Workflow

Triggers:
- `repository_dispatch` from application repos (auto staging deploy)
- `workflow_dispatch` for manual deployments

### Rollback Workflow

Manual trigger only via `workflow_dispatch`.

### Health Check

Scheduled every 15 minutes via cron, or manual trigger.

## Configuration

### Environment Variables

Key environment variables (see `.env.example`):

| Variable | Description | Required |
|----------|-------------|----------|
| `ENV` | Environment name (staging/production) | Yes |
| `IMAGE_REGISTRY` | Container registry URL | Yes |
| `IMAGE_TAG` | Image tag to deploy | Yes (prod requires explicit tag) |
| `DB_HOST` | Database host | Yes |
| `REDIS_HOST` | Redis host | Yes |

### Docker Compose Override Pattern

Each service uses base + override files:

- `compose.yml` - Base configuration
- `compose.staging.yml` - Staging-specific settings
- `compose.prod.yml` - Production-specific settings

Deploy with:
```bash
docker compose -f compose.yml -f compose.staging.yml up -d
```

## Adding a New Service

1. Create directory: `services/<service-name>/`
2. Add compose files:
   - `compose.yml` (base)
   - `compose.staging.yml` (staging overrides)
   - `compose.prod.yml` (production overrides)
   - `healthcheck.sh` (health check script)
3. Update environment files with service-specific variables
4. Add service to inventory files
5. Update workflow options in `.github/workflows/deploy.yml`

## Troubleshooting

### Check Service Status

```bash
docker compose -f services/main/compose.yml -f services/main/compose.staging.yml ps
```

### View Logs

```bash
make logs SERVICE=main ENV=staging
```

### Validate Compose Files

```bash
make validate
```

## Contributing

1. Create a feature branch
2. Make changes
3. Submit PR for review
4. Production changes require 2 approvals from senior devs

## Related Repositories

- [ttpos-server-go](https://github.com/your-org/ttpos-server-go) - Main application code
- [ttpos-bmp](https://github.com/your-org/ttpos-bmp) - BMP microservices

## License

Private repository - All rights reserved
