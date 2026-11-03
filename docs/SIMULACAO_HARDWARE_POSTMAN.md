# Guia de Simulação de Hardware & Firmware ESP32 (Postman)

Este guia orienta como simular todo o comportamento do firmware embarcado da **ESP32**, dos sensores físicos (**câmera termográfica MLX90640**, **sensor capacitivo de nível de água**, **microswitches de fim de curso NC**) e do **atuador mecânico de lavagem** utilizando o **Postman** contra a API Go do **ThermoScan**.

Com essa abordagem, o aplicativo Flutter e o backend operam em modo **100% real**, sem dados fictícios embutidos (*mocks*) ou botões de teste artificiais na interface.

---

## 1. Arquivos da Coleção

A coleção oficial está localizada em:
- Arquivo: [`software/backend/postman/ThermoScan_Hardware_ESP32_Simulation.postman_collection.json`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/software/backend/postman/ThermoScan_Hardware_ESP32_Simulation.postman_collection.json)

---

## 2. Como Importar no Postman

1. Abra o **Postman**.
2. Clique no botão **Import** (canto superior esquerdo).
3. Selecione o arquivo `ThermoScan_Hardware_ESP32_Simulation.postman_collection.json`.
4. A collection `ThermoScan - Simulação de Hardware & Firmware ESP32` aparecerá na sua barra lateral.

---

## 3. Variáveis de Coleção

A coleção já vem configurada com variáveis automáticas. Você pode ajustá-las na aba **Variables** da coleção se necessário:

| Variável | Valor Padrão | Descrição |
| :--- | :--- | :--- |
| `baseUrl` | `http://localhost:8080` | Endereço do backend Go (use `http://10.0.2.2:8080` no emulador Android) |
| `email` | `marco@soltech.io` | E-mail do técnico cadastrado no banco |
| `password` | `Senha@123` | Senha de acesso |
| `token` | *(Preenchido automaticamente)* | Token JWT retornado pelo login |
| `moduleId` | *(Preenchido automaticamente)* | ID do módulo PV em teste |

---

## 4. Roteiro de Demonstração ao Vivo

Recomendamos abrir o **Aplicativo Flutter** (no emulador ou dispositivo físico) e o **Postman** lado a lado.

```
┌──────────────────────────────────────┐        ┌─────────────────────────────────────┐
│           POSTMAN (ESP32)            │        │           APP FLUTTER               │
│                                      │        │                                     │
│  [POST] /api/v1/modules/:id/ping ────┼───────>│  Checklist Handshake fica VERDE     │
│  [POST] /api/v1/modules/:id/telemetry│        │  Card Radiométrico exibe Heatmap    │
│  [POST] /api/v1/modules/:id/cleanings│        │  Log de Lavagens registra Atuação   │
└──────────────────────────────────────┘        └─────────────────────────────────────┘
```

---

### Passo 1: Autenticação & Identificação do Módulo
1. Na pasta `00 - Autenticação & Configuração Inicial`, execute:
   - `01. Login do Técnico (Obter Token JWT)`: Faz login e armazena o token de acesso.
   - `02. Listar Módulos (Identificar ID do Módulo)`: Obtém o primeiro módulo cadastrado e define o `moduleId`.

---

### Passo 2: Simular o Boot & Handshake da ESP32
1. No App, acerte o cadastro de um módulo no Wizard de Instalação ou entre na tela de **Hardware Handshake** (`/modules/:id/handshake`).
2. Observe que a tela estará no estado de espera:
   - Wi-Fi & HTTPS Handshake: *Aguardando conexão...*
   - Sensor de Água: *Aguardando leitura...*
3. No Postman, abra a pasta `01 - Handshake & Conectividade Inicial (ESP32 Boot)` e dispare:
   - `01. Ping Inicial ESP32 (Conexão Wi-Fi OK + Água Presente)`
4. **Resultado no App:**
   - Em menos de 4 segundos (tempo do ciclo de polling), os itens de Wi-Fi e Sensor de Água mudam para **Conectado / ONLINE** e **Água OK** com chips verdes.

---

### Passo 3: Simular Alerta de Reservatório de Água Seco
1. Na pasta `02 - Sensores de Nível & Interlocks Físicos`, execute:
   - `01. Tanque Vazio (water_available = false)`
2. **Resultado no App:**
   - O checklist de Handshake e a visão geral passam a acusar **"Nível de Água Insuficiente"**.
   - Qualquer tentativa de ciclo de lavagem é bloqueada pelo interlock de segurança para evitar queima da minibomba a seco.
3. Para restabelecer, execute:
   - `02. Tanque Reabastecido (water_available = true)`

---

### Passo 4: Envio de Varredura Normal (Sem Anomalia)
1. No App, navegue para a tela de detalhes do módulo (**Overview**).
2. Se nenhuma telemetria tiver sido enviada, o card exibe honestamente:
   > *"Awaiting Radiometric Telemetry — No thermal frames or electrical readings recorded yet by the ESP32."*
3. No Postman, abra a pasta `03 - Telemetria & Varredura Térmica (MLX90640)` e dispare:
   - `01. Varredura Normal (Sem Hotspot - Painel Saudável)`
4. **Resultado no App:**
   - Ao puxar a tela para atualizar (*Pull to Refresh*) ou reentrar, o **Card Radiométrico (SCR-10)** exibe o gradiente térmico homogêneo, temperatura de pico de 37.8°C, tensão de 18.6V, corrente de 4.4A e o status **Delta: 3.3°C (Normal)** em verde.
   - A tela de **Telemetry History (SCR-11)** ganha o registro detalhado dessa medição.

---

### Passo 5: Detecção de Hotspot Crítico (Ponto Quente)
1. No Postman, execute:
   - `02. Detecção de Hotspot Crítico (Delta > 15°C - Anomalia Térmica)`
   *(Envia T_max = 58.4°C vs Baseline = 35.0°C na posição X = 24.2 cm)*.
2. **Resultado no App:**
   - O Card Radiométrico exibe badge vermelha de alerta: **Delta: +23.4°C (Hotspot)**.
   - O retículo de mira do atuador centraliza na coordenada do hotspot.
   - A aba de **Alerts** do app passa a listar a anomalia aberta exigindo atenção.

---

### Passo 6: Atuação do Bocal & Ciclo de Lavagem
1. No Postman, abra a pasta `04 - Atuação Mecânica & Ciclos de Lavagem` e execute:
   - `01. Relatório de Lavagem com Sucesso (Tentativa 1)`
   *(Registra deslocamento do bocal para X = 24.2 cm, 45 segundos de bomba d'água acionada, ~80ml de água e verificação térmica que atestou saneamento do ponto quente).*
2. **Resultado no App:**
   - Navegue para a aba **Cleanings (SCR-12)**.
   - O registro aparece instantaneamente com badge verde **VERIFIED POST-CLEAN**, detalhando a tentativa #1, duração, consumo hídrico e horário da atuação.

3. Você também pode testar a recusa de lavagem com interlock acionado:
   - `02. Recusa de Lavagem por Falta d'Água (Interlock Ativado)`
   - Registra no histórico o status **REFUSED** com a justificativa de segurança do sensor capacitivo.

---

## 5. Endpoints REST da API Go Envolvidos

| Método | Endpoint | Papel no Sistema |
| :--- | :--- | :--- |
| `POST` | `/api/v1/modules/:id/device-ping` | Ping de presença e leitura do sensor capacitivo de água |
| `GET` | `/api/v1/modules/:id/device-status` | Polling consumido pelo app para validar o checklist de hardware |
| `POST` | `/api/v1/modules/:id/telemetry` | Ingestão de telemetria, medições elétricas e matriz 32x24 MLX90640 |
| `POST` | `/api/v1/modules/:id/cleanings` | Ingestão de relatórios de ciclos do atuador mecânico e lavagem |
| `GET` | `/api/v1/modules/:id/measurements` | Consulta do histórico de inspeções |
| `GET` | `/api/v1/modules/:id/cleanings` | Consulta do log de operações de limpeza |
| `GET` | `/api/v1/modules/:id/thermal-map` | Consulta do mapa térmico composto |
