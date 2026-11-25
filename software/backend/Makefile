# ThermoScan Backend Makefile
# Location: software/backend

SHELL := /bin/bash

# Configuration
ENV_FILE ?= ../.env
APP_NAME ?= thermoscan-backend
MAIN_SRC ?= ./cmd/api
BIN_DIR  ?= ./bin
BINARY   ?= $(BIN_DIR)/$(APP_NAME)

# Load environment variables from .env if present
ifneq (,$(wildcard $(ENV_FILE)))
    include $(ENV_FILE)
    export
endif

# Fallbacks if not set in .env
POSTGRES_USER ?= thermoscan
POSTGRES_DB ?= thermoscan
DATABASE_URL ?= postgres://$(POSTGRES_USER):thermoscan@localhost:5432/$(POSTGRES_DB)?sslmode=disable
API_PORT ?= 8080
JWT_SECRET ?= dev-thermoscan-jwt-secret-9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c

.PHONY: help build run dev test clean docker-up docker-down docker-logs local-up local-down local-logs db-up db-clean db-clean-history db-seed db-reset reset-admin

help: ## Exibe a lista de comandos disponíveis
	@echo "=================================================="
	@echo "  ThermoScan Backend - Comandos Disponíveis"
	@echo "=================================================="
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""

build: ## Compila o binário do backend Go em ./bin/
	@echo "==> Compilando o backend Go..."
	@mkdir -p $(BIN_DIR)
	@go build -v -o $(BINARY) $(MAIN_SRC)
	@echo "==> Binário gerado com sucesso em: $(BINARY)"

run: build ## Compila e executa o binário do backend localmente
	@echo "==> Iniciando o servidor na porta $(API_PORT)..."
	@DATABASE_URL="$(DATABASE_URL)" API_PORT="$(API_PORT)" JWT_SECRET="$(JWT_SECRET)" $(BINARY)

dev: ## Executa o backend diretamente com 'go run' (sem gerar binário em disco)
	@echo "==> Executando com 'go run'..."
	@DATABASE_URL="$(DATABASE_URL)" API_PORT="$(API_PORT)" JWT_SECRET="$(JWT_SECRET)" go run $(MAIN_SRC)

db-up: ## Sobe apenas o banco de dados PostgreSQL via Docker Compose
	@echo "==> Subindo banco PostgreSQL..."
	@docker compose -f ../compose.yaml up -d db

db-clean: ## Limpa todos os dados operacionais e empresas do banco, preservando apenas o System Admin
	@echo "==> Limpando banco de dados (preservando System Admin)..."
	@if docker ps --format '{{.Names}}' | grep -q '^thermoscan-db$$'; then \
		docker exec -i thermoscan-db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) < ./db/clean.sql; \
	elif command -v psql >/dev/null 2>&1; then \
		psql "$(DATABASE_URL)" < ./db/clean.sql; \
	else \
		echo "Erro: Contêiner thermoscan-db não está rodando e psql local não foi encontrado."; \
		exit 1; \
	fi
	@echo "==> Banco limpo com sucesso! Apenas a conta de System Admin foi mantida."

MODULE ?= Demo Thermoscan
db-clean-history: ## Limpa leituras, limpezas, anomalias e logs de um painel (padrão: MODULE="Demo Thermoscan")
	@echo "==> Limpando histórico operacional do painel: $(MODULE)..."
	@SQL="BEGIN; \
		DELETE FROM notifications WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)'); \
		DELETE FROM inspection_panel_results WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)'); \
		DELETE FROM measurements WHERE inspection_id IN (SELECT id FROM inspections WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)') AND cleaning_operation_id IS NOT NULL); \
		DELETE FROM inspections WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)') AND cleaning_operation_id IS NOT NULL; \
		DELETE FROM cleaning_operations WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)'); \
		DELETE FROM anomaly_events WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)'); \
		DELETE FROM measurements WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)'); \
		DELETE FROM inspections WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)'); \
		DELETE FROM module_state_logs WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)'); \
		DELETE FROM reservoir_readings WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)'); \
		DELETE FROM interval_change_logs WHERE module_id IN (SELECT id FROM modules WHERE name = '$(MODULE)'); \
		UPDATE modules SET firmware_state = 'IDLE', firmware_state_detail = NULL, verification_ready_at = NULL, \
			manual_cleaning_pending = false, manual_cleaning_target_x_cm = NULL, \
			manual_reading_pending = false, manual_reading_target_x_cm = NULL, reset_pending = false \
		WHERE name = '$(MODULE)'; \
		COMMIT;"; \
	if docker ps --format '{{.Names}}' | grep -q '^thermoscan-db$$'; then \
		docker exec -i thermoscan-db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -v ON_ERROR_STOP=1 -c "$$SQL"; \
	elif command -v psql >/dev/null 2>&1; then \
		psql "$(DATABASE_URL)" -v ON_ERROR_STOP=1 -c "$$SQL"; \
	else \
		echo "Erro: Contêiner thermoscan-db não está rodando e psql local não foi encontrado."; \
		exit 1; \
	fi
	@echo "==> Histórico do painel '$(MODULE)' limpo com sucesso!"

db-seed: ## Popula o banco com empresa e usuários de teste (manager/tech/client@test.local, senha teste123)
	@echo "==> Populando banco com usuários de teste..."
	@if docker ps --format '{{.Names}}' | grep -q '^thermoscan-db$$'; then \
		docker exec -i thermoscan-db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) < ./db/seed_local.sql; \
	elif command -v psql >/dev/null 2>&1; then \
		psql "$(DATABASE_URL)" < ./db/seed_local.sql; \
	else \
		echo "Erro: Contêiner thermoscan-db não está rodando e psql local não foi encontrado."; \
		exit 1; \
	fi
	@echo "==> Usuários de teste criados: manager@test.local, tech@test.local, client@test.local (senha: teste123)"

db-reset: db-clean db-seed ## Limpa o banco (mantendo System Admin) e recria os usuários de teste

docker-up: ## Sobe toda a stack (PostgreSQL + API Go) via Docker Compose
	@echo "==> Subindo stack backend via Docker Compose..."
	@docker compose -f ../compose.yaml up -d --build

docker-down: ## Para todos os contêineres Docker do backend
	@echo "==> Parando contêineres do backend..."
	@docker compose -f ../compose.yaml down

docker-logs: ## Acompanha os logs dos contêineres Docker
	@docker compose -f ../compose.yaml logs -f

local-up: ## Sobe banco + API expostos na rede local (porta 8080) via docker-compose.local.yml
	@echo "==> Subindo stack local (PostgreSQL + API Go na porta 8080)..."
	@docker compose -f ../../docker-compose.yml -f ../../docker-compose.local.yml up -d --build --remove-orphans

local-down: ## Para os contêineres da stack local
	@echo "==> Parando stack local..."
	@docker compose -f ../../docker-compose.yml -f ../../docker-compose.local.yml down

local-logs: ## Acompanha os logs da stack local
	@docker compose -f ../../docker-compose.yml -f ../../docker-compose.local.yml logs -f

test: ## Executa todos os testes do backend Go
	@echo "==> Executando testes..."
	@go test -v -count=1 ./...

clean: ## Remove binários compilados
	@echo "==> Limpando binários..."
	@rm -rf $(BIN_DIR)
	@echo "==> Limpeza concluída."

reset-admin: ## Redefine a senha do system_admin gerando uma nova senha temporária
	@echo "==> Redefinindo senha do system_admin..."
	@DATABASE_URL="$(DATABASE_URL)" API_PORT="$(API_PORT)" JWT_SECRET="$(JWT_SECRET)" go run $(MAIN_SRC) -reset-admin

