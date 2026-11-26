# ThermoScan - Root Software Makefile
# Location: software

SHELL := /bin/bash

.PHONY: help backend-build backend-run backend-dev backend-db backend-clean-db backend-clean-history backend-docker backend-down backend-logs mobile-apk mobile-apk-arm64 mobile-apk-debug mobile-serve mobile-all mobile-all-arm64 clean

help: ## Exibe a lista de comandos disponíveis
	@echo "=================================================="
	@echo "  ThermoScan - Comandos Principais (Root)"
	@echo "=================================================="
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
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

backend-clean-history: ## Limpa leituras/limpezas/logs de um painel (padrão: MODULE="Demo Thermoscan")
	@$(MAKE) -C backend db-clean-history $(if $(MODULE),MODULE="$(MODULE)",)

backend-docker: ## Sobe toda a stack backend (Postgres + API) no Docker
	@$(MAKE) -C backend docker-up

backend-down: ## Para os contêineres Docker do backend
	@$(MAKE) -C backend docker-down

backend-logs: ## Acompanha os logs em tempo real do backend Docker
	@$(MAKE) -C backend docker-logs

# --- MOBILE COMMANDS ---
mobile-apk: ## Gera o APK release para Android apontando para https://api-thermoscan.realan.space/api/v1
	@$(MAKE) -C app/thermoscan apk

mobile-apk-arm64: ## Gera o APK release rápido apenas para Android ARM64
	@$(MAKE) -C app/thermoscan apk-arm64

mobile-apk-debug: ## Gera o APK debug para Android apontando para https://api-thermoscan.realan.space/api/v1
	@$(MAKE) -C app/thermoscan apk-debug

mobile-serve: ## Inicia servidor HTTP Python para baixar o APK no celular
	@$(MAKE) -C app/thermoscan serve-apk

mobile-all: ## Gera o APK release e já sobe o servidor Python para download
	@$(MAKE) -C app/thermoscan run-apk

mobile-all-arm64: ## Gera o APK release ARM64 (rápido) e já sobe o servidor Python para download
	@$(MAKE) -C app/thermoscan run-apk-arm64

# --- CLEAN ---
clean: ## Limpa artefatos temporários do backend e do app
	@$(MAKE) -C backend clean
	@$(MAKE) -C app/thermoscan clean
