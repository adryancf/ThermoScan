# ThermoScan - Root Software Makefile
# Location: software

SHELL := /bin/bash

.PHONY: help backend-build backend-run backend-dev backend-db backend-docker mobile-apk mobile-apk-debug mobile-serve mobile-all clean

help: ## Exibe a lista de comandos disponíveis
	@echo "=================================================="
	@echo "  ThermoScan - Comandos Principais (Root)"
	@echo "=================================================="
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Dica: Você também pode entrar diretamente em 'backend/' ou 'app/thermoscan/' e rodar 'make help'."
	@echo ""

# --- BACKEND COMMANDS ---
backend-build: ## Compila o binário do backend Go
	@$(MAKE) -C backend build

backend-run: ## Compila e executa o backend Go localmente
	@$(MAKE) -C backend run

backend-dev: ## Executa o backend com 'go run'
	@$(MAKE) -C backend dev

backend-db: ## Sobe apenas o banco de dados PostgreSQL
	@$(MAKE) -C backend db-up

backend-clean-db: ## Limpa todas as empresas e registros operacionais, mantendo apenas o System Admin
	@$(MAKE) -C backend db-clean

backend-docker: ## Sobe toda a stack backend (Postgres + API) no Docker
	@$(MAKE) -C backend docker-up

backend-down: ## Para os contêineres Docker do backend
	@$(MAKE) -C backend docker-down

backend-logs: ## Acompanha os logs em tempo real do backend Docker
	@$(MAKE) -C backend docker-logs

# --- MOBILE COMMANDS ---
mobile-apk: ## Gera o APK release para Android com auto-detecção de IP
	@$(MAKE) -C app/thermoscan apk

mobile-apk-debug: ## Gera o APK debug para Android
	@$(MAKE) -C app/thermoscan apk-debug

mobile-serve: ## Inicia servidor HTTP Python para baixar o APK no celular
	@$(MAKE) -C app/thermoscan serve-apk

mobile-all: ## Gera o APK release e já sobe o servidor Python para download
	@$(MAKE) -C app/thermoscan run-apk

# --- CLEAN ---
clean: ## Limpa artefatos temporários do backend e do app
	@$(MAKE) -C backend clean
	@$(MAKE) -C app/thermoscan clean
