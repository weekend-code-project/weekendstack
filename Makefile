# =============================================================================
# WeekendStack Makefile - Common Commands
# =============================================================================
# Quick reference for managing your WeekendStack deployment
#
# Usage: make <target>
# Example: make start

.PHONY: help setup start stop restart status logs ps clean update backup restore \
        pull validate env health test profile-dev profile-ai profile-all \
        cloudflare-setup cert-setup docker-login prune shell config

# Default target - show help
.DEFAULT_GOAL := help

# Variables
COMPOSE_CMD := docker compose
COMPOSE_FILES := -f docker-compose.yml
BACKUP_DIR := backups
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# =============================================================================
# Primary Commands
# =============================================================================

help: ## Show this help message
	@echo "WeekendStack - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick Start:"
	@echo "  make setup     - Run interactive setup wizard"
	@echo "  make start     - Start all enabled services"
	@echo "  make status    - Check service status"
	@echo "  make logs      - View logs (Ctrl+C to exit)"

setup: ## Run the interactive setup script
	@./setup.sh

setup-quick: ## Run setup with defaults (quick mode)
	@./setup.sh --quick

# =============================================================================
# Docker Compose Operations
# =============================================================================

start: ## Start all services
	$(COMPOSE_CMD) $(COMPOSE_FILES) up -d

stop: ## Stop all services
	$(COMPOSE_CMD) $(COMPOSE_FILES) down

restart: ## Restart all services
	$(COMPOSE_CMD) $(COMPOSE_FILES) restart

status: ## Show service status
	$(COMPOSE_CMD) $(COMPOSE_FILES) ps

logs: ## Show logs (follow mode)
	$(COMPOSE_CMD) $(COMPOSE_FILES) logs -f

logs-tail: ## Show last 100 lines of logs
	$(COMPOSE_CMD) $(COMPOSE_FILES) logs --tail=100

ps: ## List running containers
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# =============================================================================
# Profile Management
# =============================================================================

profile-dev: ## Start only dev profile (Coder)
	$(COMPOSE_CMD) $(COMPOSE_FILES) --profile dev up -d

profile-ai: ## Start AI services
	$(COMPOSE_CMD) $(COMPOSE_FILES) --profile ai up -d

profile-productivity: ## Start productivity services
	$(COMPOSE_CMD) $(COMPOSE_FILES) --profile productivity up -d

profile-media: ## Start media services
	$(COMPOSE_CMD) $(COMPOSE_FILES) --profile media up -d

profile-all: ## Start all services including optional ones
	$(COMPOSE_CMD) $(COMPOSE_FILES) --profile all --profile personal --profile gpu up -d

# =============================================================================
# Maintenance & Updates
# =============================================================================

pull: ## Pull latest images for all services
	$(COMPOSE_CMD) $(COMPOSE_FILES) pull

update: ## Update services (pull + restart)
	@echo "Pulling latest images..."
	@$(COMPOSE_CMD) $(COMPOSE_FILES) pull
	@echo "Restarting services..."
	@$(COMPOSE_CMD) $(COMPOSE_FILES) up -d
	@echo "Update complete!"

validate: ## Validate docker-compose configuration
	$(COMPOSE_CMD) $(COMPOSE_FILES) config --quiet && echo "✓ Configuration is valid"

config: ## Show merged docker-compose configuration
	$(COMPOSE_CMD) $(COMPOSE_FILES) config

# =============================================================================
# Health & Monitoring
# =============================================================================

health: ## Check health of all services
	@docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "Up|health"

test: ## Run basic connectivity tests
	@echo "Testing Docker..."
	@docker version > /dev/null && echo "✓ Docker is running"
	@echo "Testing Docker Compose..."
	@$(COMPOSE_CMD) version > /dev/null && echo "✓ Docker Compose is available"
	@echo "Testing services..."
	@$(COMPOSE_CMD) $(COMPOSE_FILES) ps --quiet > /dev/null && echo "✓ Services are accessible"

# =============================================================================
# Backup & Restore
# =============================================================================

backup: ## Backup configuration and data
	@echo "Creating backup..."
	@mkdir -p $(BACKUP_DIR)/backup-$(TIMESTAMP)
	@cp .env $(BACKUP_DIR)/backup-$(TIMESTAMP)/ 2>/dev/null || echo "No .env file found"
	@cp -r config $(BACKUP_DIR)/backup-$(TIMESTAMP)/ 2>/dev/null || echo "No config directory found"
	@echo "Backup created in $(BACKUP_DIR)/backup-$(TIMESTAMP)"

backup-volumes: ## Backup Docker volumes
	@echo "Backing up Docker volumes..."
	@mkdir -p $(BACKUP_DIR)/volumes-$(TIMESTAMP)
	@./backup-volumes.sh || echo "Note: Volume backup script not found"

restore: ## Restore from backup (use BACKUP=path/to/backup)
	@if [ -z "$(BACKUP)" ]; then \
		echo "Error: Please specify backup directory: make restore BACKUP=backups/backup-XXXXXXXX"; \
		exit 1; \
	fi
	@echo "Restoring from $(BACKUP)..."
	@cp $(BACKUP)/.env . 2>/dev/null || echo "No .env in backup"
	@cp -r $(BACKUP)/config ./ 2>/dev/null || echo "No config in backup"
	@echo "Restore complete! Review settings and restart services."

# =============================================================================
# Cleanup Operations
# =============================================================================

clean: ## Stop and remove all containers (keeps volumes)
	$(COMPOSE_CMD) $(COMPOSE_FILES) down

clean-volumes: ## Stop and remove containers AND volumes (destructive!)
	@echo "WARNING: This will delete all data volumes!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(COMPOSE_CMD) $(COMPOSE_FILES) down -v; \
	fi

prune: ## Remove unused Docker resources
	@echo "Removing unused containers, networks, and images..."
	docker system prune -f
	@echo "Cleanup complete!"

prune-all: ## Remove ALL unused Docker resources including volumes
	@echo "WARNING: This will remove unused volumes!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker system prune -af --volumes; \
	fi

uninstall: ## Run the uninstall script
	@./uninstall.sh

# =============================================================================
# Setup Helpers
# =============================================================================

cloudflare-setup: ## Run Cloudflare Tunnel setup wizard
	@./setup.sh --cloudflare-only

cert-setup: ## Generate and install local certificates
	@./setup.sh --certs-only

docker-login: ## Authenticate with Docker registries
	@./setup.sh --docker-only

env: ## Generate .env file from template
	@if [ -f .env ]; then \
		echo "Error: .env already exists. Move it first or use 'make env-force'"; \
		exit 1; \
	fi
	@cp .env.example .env
	@echo ".env created! Edit it with your configuration."

env-force: ## Regenerate .env (overwrites existing - creates backup)
	@if [ -f .env ]; then \
		cp .env $(BACKUP_DIR)/.env.backup.$(TIMESTAMP); \
		echo "Backed up existing .env to $(BACKUP_DIR)/.env.backup.$(TIMESTAMP)"; \
	fi
	@cp .env.example .env
	@echo "New .env created from template"

# =============================================================================
# Development & Debugging
# =============================================================================

shell: ## Open shell in a container (use SERVICE=name)
	@if [ -z "$(SERVICE)" ]; then \
		echo "Error: Please specify service: make shell SERVICE=servicename"; \
		exit 1; \
	fi
	$(COMPOSE_CMD) $(COMPOSE_FILES) exec $(SERVICE) /bin/sh || \
	$(COMPOSE_CMD) $(COMPOSE_FILES) exec $(SERVICE) /bin/bash

shell-root: ## Open root shell in a container (use SERVICE=name)
	@if [ -z "$(SERVICE)" ]; then \
		echo "Error: Please specify service: make shell-root SERVICE=servicename"; \
		exit 1; \
	fi
	$(COMPOSE_CMD) $(COMPOSE_FILES) exec -u root $(SERVICE) /bin/sh || \
	$(COMPOSE_CMD) $(COMPOSE_FILES) exec -u root $(SERVICE) /bin/bash

logs-service: ## Show logs for specific service (use SERVICE=name)
	@if [ -z "$(SERVICE)" ]; then \
		echo "Error: Please specify service: make logs-service SERVICE=servicename"; \
		exit 1; \
	fi
	$(COMPOSE_CMD) $(COMPOSE_FILES) logs -f $(SERVICE)

inspect: ## Inspect a service (use SERVICE=name)
	@if [ -z "$(SERVICE)" ]; then \
		echo "Error: Please specify service: make inspect SERVICE=servicename"; \
		exit 1; \
	fi
	$(COMPOSE_CMD) $(COMPOSE_FILES) config --services | grep $(SERVICE) || echo "Service not found"
	@docker inspect $$($(COMPOSE_CMD) ps -q $(SERVICE))

# =============================================================================
# Information
# =============================================================================

version: ## Show Docker and Compose versions
	@echo "Docker version:"
	@docker --version
	@echo ""
	@echo "Docker Compose version:"
	@$(COMPOSE_CMD) version

info: ## Show system information
	@echo "=== WeekendStack System Information ==="
	@echo ""
	@echo "Docker Info:"
	@docker info --format '  Containers: {{.Containers}} ({{.ContainersRunning}} running)'
	@docker info --format '  Images: {{.Images}}'
	@echo ""
	@echo "Storage:"
	@df -h | grep -E "Filesystem|/var/lib/docker|/$" || df -h
	@echo ""
	@echo "Services Configured:"
	@$(COMPOSE_CMD) $(COMPOSE_FILES) config --services | wc -l | xargs echo "  Total services:"
	@echo ""
	@echo "Running Services:"
	@$(COMPOSE_CMD) ps --quiet | wc -l | xargs echo "  Active containers:"

services: ## List all available services
	@echo "Available services:"
	@$(COMPOSE_CMD) $(COMPOSE_FILES) config --services | sort

ports: ## Show exposed ports
	@echo "Exposed ports:"
	@docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -v "^NAMES"
