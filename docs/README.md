# ThermoScan — Documentação do Sistema

Este diretório centraliza a documentação técnica, especificações de engenharia, requisitos de produto e guias de simulação do ThermoScan.

## Documentos Principais

- [`AGENT_CONTEXT.md`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/docs/AGENT_CONTEXT.md): Fonte de verdade técnica da arquitetura, convenções, contratos de dados, separação de responsabilidades (ESP32, Backend Go e Flutter App) e regras de negócio multi-painel.
- [`SIMULACAO_HARDWARE_POSTMAN.md`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/docs/SIMULACAO_HARDWARE_POSTMAN.md): Guia passo a passo de testes manuais e simulação completa do ciclo de vida da ESP32 (Handshake, Varredura Multi-Painel, Telemetria em Lotes, Finalização, Lavagem e Verificação).
- [`requeriments/`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/docs/requeriments): Requisitos de Software, Eletrônica e Mecânica (arquivos CSV).
- [`context/app/design.md`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/docs/context/app/design.md): Diretrizes de UX/UI, paleta de cores e especificações visuais do aplicativo mobile.

## Sub-repositórios

- [`firmware/README.md`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/firmware/README.md): Arquitetura do microcontrolador ESP32, pinout centralizado, ciclo multi-painel, alocação de memória RAM e testes nativos/hardware.
- [`software/backend/README.md`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/software/backend/README.md): Arquitetura da API Go (REST/HTTP), modelo relacional PostgreSQL, migrações e endpoints.
- [`software/backend/db/SCHEMA_NOTES.md`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/software/backend/db/SCHEMA_NOTES.md): Notas e regras de integridade das 17 tabelas do PostgreSQL.
- [`software/app/README.md`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/software/app/README.md): Aplicativo mobile Flutter (Android/iOS) com panorama radiométrico multi-painel, acordeão de histórico e monitoramento.

