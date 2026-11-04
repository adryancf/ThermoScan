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
DATABASE_URL ?= postgres://thermoscan:thermoscan@localhost:5432/thermoscan?sslmode=disable
API_PORT ?= 8080
JWT_SECRET ?= dev-thermoscan-jwt-secret-9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c

.PHONY: help build run dev test clean docker-up docker-down docker-logs db-up reset-admin

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

docker-up: ## Sobe toda a stack (PostgreSQL + API Go) via Docker Compose
	@echo "==> Subindo stack backend via Docker Compose..."
	@docker compose -f ../compose.yaml up -d --build

docker-down: ## Para todos os contêineres Docker do backend
	@echo "==> Parando contêineres do backend..."
	@docker compose -f ../compose.yaml down

docker-logs: ## Acompanha os logs dos contêineres Docker
	@docker compose -f ../compose.yaml logs -f

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

