# ThermoScan Mobile Makefile
# Location: software/app/thermoscan

SHELL := /bin/bash

# Tools
FLUTTER ?= /home/acf/develop/flutter/bin/flutter
PYTHON  ?= /usr/bin/python3

API_URL ?= https://api-thermoscan.realan.space/api/v1

# Network auto-detection: detects Wi-Fi/LAN IP of this machine (for serving APK locally)
HOST_IP ?= $(shell hostname -I | awk '{print $$1}')

# Output directories & server settings
APK_DIR      ?= build/app/outputs/flutter-apk
DIST_DIR     ?= dist
HTTP_PORT    ?= 8000
RELEASE_APK  ?= $(APK_DIR)/app-release.apk
DEBUG_APK    ?= $(APK_DIR)/app-debug.apk

# Automatic Versioning based on Git Commit Count
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
BUILD_NAME   ?= 1.0.$(BUILD_NUMBER)

.PHONY: help apk apk-debug serve-apk serve run-apk clean analyze test

help: ## Exibe a lista de comandos disponíveis
	@echo "=================================================="
	@echo "  ThermoScan Mobile - Comandos Disponíveis"
	@echo "=================================================="
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "API_URL configurada: $(API_URL)"
	@echo "Versão automática calculada: v$(BUILD_NAME)+$(BUILD_NUMBER)"
	@echo "IP detectado para download local do APK: $(HOST_IP)"
	@echo ""

apk: ## Gera o APK de release injetando API_URL e auto-versionamento via Git
	@echo "==> Compilando APK Release (v$(BUILD_NAME)+$(BUILD_NUMBER))..."
	@echo "==> Usando API_BASE_URL: $(API_URL)"
	@$(FLUTTER) build apk --release --dart-define=API_BASE_URL=$(API_URL) --build-name=$(BUILD_NAME) --build-number=$(BUILD_NUMBER)
	@mkdir -p $(DIST_DIR)
	@cp -f $(RELEASE_APK) $(DIST_DIR)/thermoscan.apk
	@if [ -d ../../../dist ]; then cp -f $(RELEASE_APK) ../../../dist/thermoscan.apk; fi
	@echo ""
	@echo "==> APK gerado em: $(RELEASE_APK)"
	@echo "==> Cópia pronta em: $(DIST_DIR)/thermoscan.apk"

apk-debug: ## Gera o APK de debug injetando API_URL e auto-versionamento via Git
	@echo "==> Compilando APK Debug (v$(BUILD_NAME)+$(BUILD_NUMBER))..."
	@echo "==> Usando API_BASE_URL: $(API_URL)"
	@$(FLUTTER) build apk --debug --dart-define=API_BASE_URL=$(API_URL) --build-name=$(BUILD_NAME) --build-number=$(BUILD_NUMBER)
	@mkdir -p $(DIST_DIR)
	@cp -f $(DEBUG_APK) $(DIST_DIR)/thermoscan-debug.apk
	@echo ""
	@echo "==> APK Debug gerado em: $(DEBUG_APK)"
	@echo "==> Cópia pronta em: $(DIST_DIR)/thermoscan-debug.apk"

serve-apk: ## Inicia servidor HTTP Python para baixar o APK no celular via Wi-Fi
	@echo "=================================================="
	@echo "  Servidor de Download do APK"
	@echo "=================================================="
	@mkdir -p $(DIST_DIR)
	@if [ ! -f $(DIST_DIR)/thermoscan.apk ]; then \
		if [ -f $(RELEASE_APK) ]; then \
			cp -f $(RELEASE_APK) $(DIST_DIR)/thermoscan.apk; \
		elif [ -f $(DEBUG_APK) ]; then \
			cp -f $(DEBUG_APK) $(DIST_DIR)/thermoscan.apk; \
		else \
			echo "Nenhum APK encontrado. Execute 'make apk' primeiro!"; \
			exit 1; \
		fi; \
	fi
	@echo "Abra no navegador do celular (conectado na mesma rede Wi-Fi):"
	@echo ""
	@echo "  -> http://$(HOST_IP):$(HTTP_PORT)/thermoscan.apk"
	@echo "  -> Ou lista de arquivos: http://$(HOST_IP):$(HTTP_PORT)/"
	@echo ""
	@echo "Pressione Ctrl+C para encerrar o servidor."
	@echo "=================================================="
	@cd $(DIST_DIR) && $(PYTHON) -m http.server $(HTTP_PORT)

serve: serve-apk ## Alias para serve-apk

run-apk: apk serve-apk ## Gera o APK release e já sobe o servidor Python em seguida

analyze: ## Executa o linter do Flutter
	@$(FLUTTER) analyze

test: ## Executa a suíte de testes do Flutter
	@$(FLUTTER) test

clean: ## Limpa o build do Flutter e diretório dist
	@$(FLUTTER) clean
	@rm -rf $(DIST_DIR)
	@echo "==> Limpeza concluída."
