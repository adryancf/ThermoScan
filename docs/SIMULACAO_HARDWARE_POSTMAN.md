# Guia de Simulação de Hardware & Firmware ESP32 (Postman)

Este guia orienta como simular todo o comportamento do firmware embarcado da **ESP32**, dos sensores físicos (**câmera termográfica MLX90640**, **sensor de corrente/tensão INA219**, **sensor capacitivo de nível de água**, **microswitches de fim de curso NC**) e do **atuador mecânico de lavagem** utilizando o **Postman** contra a API Go do **ThermoScan**.

Com essa abordagem, o aplicativo Flutter e o backend operam em modo **100% real**, sem dados fictícios embutidos (*mocks*) ou botões de teste artificiais na interface.

---

## 1. Arquivos da Coleção

A coleção oficial está localizada em:
- Arquivo: [`software/backend/postman/ThermoScan_Hardware_ESP32_Simulation.postman_collection.json`](file:///home/acf/Downloads/Faculdade/8/oficinas_3/ThermoScan/software/backend/postman/ThermoScan_Hardware_ESP32_Simulation.postman_collection.json)

---

## 2. Como Importar no Postman

1. Abra o **Postman**.
2. Clique no botão **Import** (canto superior esquerdo).
3. Selecione o arquivo `software/backend/postman/ThermoScan_Hardware_ESP32_Simulation.postman_collection.json`.
4. A collection `ThermoScan - Simulação de Hardware & Firmware ESP32` aparecerá na sua barra lateral.

---

## 3. Variáveis de Coleção & Autenticação de Dispositivo

O hardware ESP32 não utiliza JWT de usuário técnico. Ele utiliza um segredo de hardware de alta entropia (**`device_token`**, prefixo `dev_sec_...`) obtido no primeiro boot via endpoint público de pareamento (`POST /api/v1/devices/claim`).

| Variável | Valor Padrão | Descrição |
| :--- | :--- | :--- |
| `baseUrl` | `http://10.183.2.254:8080` | Endereço IP local da máquina onde o backend Go roda (ou `http://localhost:8080` se rodar localmente) |
| `macAddress` | `aa:bb:cc:dd:ee:01` | Endereço MAC físico gravado na memória eFuse da ESP32 |
| `deviceToken` | *(Preenchido automaticamente)* | Token de hardware secreto (`dev_sec_...`) capturado no Claim |
| `moduleId` | *(Preenchido automaticamente)* | UUID do módulo retornado no Claim e utilizado em todas as rotas |
| `inspectionSourceEventId` | *(Preenchido automaticamente)* | UUID da sessão de inspeção gerado pela simulação da ESP32 |
| `email` | `marco@soltech.io` | E-mail do técnico (opcional, para testes de auditoria de usuário) |
| `password` | `Senha@123` | Senha de acesso do técnico (opcional) |
| `token` | *(Opcional)* | Token JWT retornado pelo login de técnico |

---

## 4. O que é o Handshake de Hardware? (Checklist de 4 Itens)

Na tela de **Hardware Handshake** do aplicativo Flutter, existem 4 itens de verificação obrigatórios:

1. **Configuration Sync**: O módulo foi completamente configurado (dimensões, ângulo solar mínimo, coordenadas e intervalo de inspeção) e salvo no backend. O firmware confirma a aplicação na NVS via `POST /api/v1/devices/:id/configuration/ack`.
2. **Wi-Fi & HTTPS REST Connection**: A ESP32 conectou-se à rede e efetuou handshake com a API Go (`is_online = true`).
3. **Binary Water Level Sensor**: O sensor capacitivo de nível acusa água presente no reservatório (`water_available = true`), liberando os ciclos da minibomba.
4. **Hardware Interlocks & Radiometer**: Valida a rotina física de **Homing Mecânico** do carrinho (microswitch Normalmente Fechado - NC - em $X=0$) e o **Autoteste do Barramento I2C** do sensor radiométrico infravermelho (MLX90640 no endereço `0x33`). Quando a ESP32 liga, recua o motor de passo até tocar a chave fim de curso e checa a resposta I2C da câmera; se tudo estiver íntegro, envia `limits_check_passed = true` e `thermal_sensor_active = true`.

---

## 5. Roteiro de Demonstração Passo a Passo

Recomendamos abrir o **Aplicativo Flutter** e o **Postman** lado a lado na tela.

```text
┌───────────────────────────────────────┐        ┌─────────────────────────────────────┐
│            POSTMAN (ESP32)            │        │             APP FLUTTER             │
│                                       │        │                                     │
│  [POST] /api/v1/devices/claim ────────┼───────>│  Checklist Handshake 2, 3 e 4 VERDES │
│  [POST] .../devices/:id/telemetry ────┼───────>│  Frames no Canvas na Posição X      │
│  [POST] .../inspections/:id/finalize ─┼───────>│  Hotspots Confirmados em Destaque   │
│  [POST] .../devices/:id/cleanings ────┼───────>│  Histórico de Lavagem Registrado    │
└───────────────────────────────────────┘        └─────────────────────────────────────┘
```

---

### Passo 1: Pareamento Físico Inicial (ESP32 Claim)
1. No Postman, abra a pasta `00 - Pareamento do Dispositivo (ESP32 Claim)` e execute:
   - `01. [ESP32 Boot] Claim do Dispositivo por MAC Address`
2. **O que acontece:**
   - A requisição pública envia o `mac_address` cadastrado no módulo (`aa:bb:cc:dd:ee:01`) e os flags de diagnóstico (`water_available: true`, `limits_check_passed: true`, `thermal_sensor_active: true`).
   - O backend Go registra o primeiro ping de presença, gera o `device_token` (`dev_sec_...`) e retorna o `module_id`.
   - O script do Postman armazena `deviceToken` e `moduleId` nas variáveis de coleção.

---

### Passo 2: Handshake Concluído & Sincronização de Configuração
1. Na pasta `01 - Handshake & Conectividade Inicial (ESP32 Boot)`:
   - Execute `01. Ping Inicial ESP32 (Diagnóstico Completo)`.
   - Execute `03. [Two-Phase Handshake] Obter Configuração Atual do Dispositivo`.
   - Execute `04. [Two-Phase Handshake] Confirmar Aplicação da Configuração (POST Acknowledge Configuration)`.
2. **Resultado no App:**
   - No app Flutter (tela do módulo ou `/modules/:id/handshake`), os 4 itens do Checklist tornam-se **VERDES**.

---

### Passo 3: Simulação de Intertravamento do Nível de Água
1. Na pasta `02 - Sensores de Nível & Interlocks Físicos`, execute:
   - `01. Tanque Vazio (water_available = false)`
2. **Resultado no App:**
   - O checklist de Handshake passa a acusar **"Nível de Água Insuficiente"**.
   - Qualquer tentativa de ciclo de lavagem é bloqueada pelo interlock de segurança para evitar queima da minibomba a seco.
3. Para restabelecer, execute:
   - `02. Tanque Reabastecido (water_available = true)`

---

### Passo 4: Varredura com Passos de 2 cm & Telemetria Bruta (Lotes de até 5 medições)

A câmera térmica MLX90640 tem abertura física útil de 5 cm. O carrinho avança em passos mecânicos fixos de **2 cm** ($\Delta X = 2\text{ cm}$), gerando uma **sobreposição óptica de 60%** (3 cm compartilhados entre aquisições adjacentes).

> [!IMPORTANT]
> **Separação Arquitetural de Responsabilidades:**
> - O backend Go **NÃO** calcula baseline, **NÃO** calcula sobreposição, **NÃO** compara frames consecutivos, **NÃO** realiza fusão (*linear blending*) e **NÃO** divide o painel em faixas operacionais artificiais.
> - A telemetria bruta consiste em medições individuais (ou lotes de **no máximo 5 medições**).
> - As medições brutas **NÃO** contêm `hotspot_detected`. O conceito de candidato por medição individual deixa de existir no envio de telemetria bruta.
> - Leituras elétricas (`voltage_v`, `current_a`, `power_w`) são coletadas junto ao frame e são *nullable* (`null` quando o sensor INA219 falhar ou estiver desconectado).
> - Cada frame MLX90640 possui 768 posições (32×24) com `null` estrito para pixels inválidos.
> - Após o backend confirmar o recebimento (`200 OK`), a ESP32 libera imediatamente o frame da RAM, evitando estouro de memória no microcontrolador.

1. No Postman, abra a pasta `03 - Telemetria & Varredura Térmica (Lotes <= 5 e Finalização)`:
   - Execute os passos de varredura ou o envio em lote de até 5 itens:
     - `01. Iniciar Varredura - Passo 1: X = 0.0 cm (Início do Painel)`
     - `02. Passo 2: X = 2.0 cm (Avanço 2cm - Sobreposição 60%)`
     - `03. Passo 3: X = 4.0 cm (Candidato a Hotspot 1)`
     - `04. Passo 4: X = 6.0 cm (Confirmação de Hotspot 2)`
     - `05. Ingestão em Lote / Fragmento (Chunk <= 5 medições)`

---

### Passo 5: Finalização da Inspeção com Baseline & Hotspots Confirmados

Ao concluir o percurso físico da varredura, a ESP32 executa localmente:
1. **Cálculo do Baseline:** Mediana das temperaturas válidas de todos os frames capturados na varredura completa.
2. **Identificação de Candidatos:** Pixels com $T \ge \text{baseline} + 10^\circ\text{C}$.
3. **Confirmação Espacial de Hotspots:** O candidato deve persistir em pelo menos duas aquisições consecutivas (avanço de 2 cm, sobreposição de 60% e tolerância espacial de 0,5 cm).
4. **Chamada de Finalização:** Envia `POST /api/v1/devices/:id/inspections/:inspectionSourceEventId/finalize` contendo `finished_at`, `baseline_temperature_c` e a lista de `confirmed_hotspots`.

1. No Postman, execute:
   - `06. Finalizar Varredura (POST Finalize com Baseline & Hotspot Confirmado)`
2. **Resultado no App (SCR-10 e SCR-11):**
   - **Card Radiométrico (SCR-10):** Cada frame térmico é renderizado exatamente na sua posição $X$ sobre a régua graduada do painel. **Apenas os hotspots confirmados** recebem anel de alerta vermelho pulsante e indicador de temperatura crítica. O baseline consolidado é exibido no card de métricas. Se as leituras elétricas forem nulas, a interface exibe `N/A` de forma limpa.
   - **Histórico de Medições (SCR-11):** Exibe a lista paginada de medições (`?page=1&limit=10`, ordenadas por `x_position_cm ASC`), com navegação entre páginas e vinculação direta aos hotspots confirmados.

---

### Passo 6: Atuação do Bocal & Ciclo de Lavagem

Quando um hotspot é confirmado, o firmware posiciona o carrinho sobre a coordenada $X$ da anomalia e executa a limpeza localizada (se os intertravamentos de água e temperatura base $\le 60^\circ\text{C}$ permitirem).

1. No Postman, abra a pasta `04 - Atuação Mecânica & Ciclos de Lavagem` e execute:
   - `01. Relatório de Lavagem com Sucesso (Tentativa 1)`
   *(Registra acionamento da minibomba, duração de 45 segundos, ~80 mL consumidos e status `completed` com `post_cleaning_result: "pending"`).*
2. **Resultado no App:**
   - Na aba **Cleanings (SCR-12)**, a operação é exibida com badge de tentativa #1 e status aguardando verificação.

---

### Passo 7: Inspeção de Verificação Pós-Lavagem

O firmware respeita o repouso térmico obrigatório de **30 minutos** e verifica a janela de radiação solar antes de iniciar a varredura de verificação.

1. No Postman, execute:
   - `03. Varredura de Verificação Pós-Lavagem (Verification Inspection)` (`type = "verification"` vinculado ao `cleaning_operation_id`).
   - `04. Finalizar Inspeção de Verificação (Resolução da Anomalia)`.
2. **O que acontece no Backend:**
   - A finalização da verificação compara a temperatura residual na coordenada do hotspot. Sem persistência térmica, a operação de limpeza é atualizada para `post_cleaning_result = "resolved"` e a anomalia é marcada como `resolved` de forma atômica.

---

## 6. Endpoints REST Oficiais Envolvidos na Simulação

| Método | Endpoint | Autenticação | Papel no Sistema |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/devices/claim` | Pública (MAC Address) | Pareamento inicial do hardware e emissão do `device_token` |
| `POST` | `/api/v1/devices/:id/device-ping` | Bearer `dev_sec_...` | Ping periódico, sensor de nível de água binário e autoteste de hardware |
| `GET` | `/api/v1/devices/:id/device-status` | Bearer `dev_sec_...` / JWT | Consulta agregada do status para checklist do aplicativo |
| `GET` | `/api/v1/devices/:id/configuration` | Bearer `dev_sec_...` / JWT | Consulta da versão ativa da configuração no servidor |
| `POST` | `/api/v1/devices/:id/configuration/ack` | Bearer `dev_sec_...` | Confirmação da gravação na memória NVS física da ESP32 |
| `POST` | `/api/v1/devices/:id/telemetry` | Bearer `dev_sec_...` | Ingestão de medições brutas em streaming ou lote (máx. 5 itens, sem `hotspot_detected`) |
| `POST` | `/api/v1/devices/:id/inspections/:inspectionSourceEventId/finalize` | Bearer `dev_sec_...` | **Finalização da inspeção** enviando `baseline_temperature_c` e `confirmed_hotspots` |
| `POST` | `/api/v1/devices/:id/cleanings` | Bearer `dev_sec_...` | Registro de acionamento do atuador de pulverização e lavagem |
| `GET` | `/api/v1/modules/:id/latest-inspection` | Bearer `dev_sec_...` / JWT | Consulta da última inspeção finalizada com baseline e anomalias confirmadas |
| `GET` | `/api/v1/modules/:id/inspections/:inspectionId/measurements` | Bearer `dev_sec_...` / JWT | Consulta paginada das medições brutas da inspeção (`?page=1&limit=10`, `x_position_cm ASC`) |
| `GET` | `/api/v1/modules/:id/cleanings` | Bearer `dev_sec_...` / JWT | Consulta do histórico e ciclo de tentativas de limpeza |
