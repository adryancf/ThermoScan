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
| `email` | `marco@soltech.io` | E-mail do técnico (opcional, para testes de auditoria de usuário) |
| `password` | `Senha@123` | Senha de acesso do técnico (opcional) |
| `token` | *(Opcional)* | Token JWT retornado pelo login de técnico |

---

## 4. O que é o Ponto 4 do Handshake? (Hardware Interlocks & Radiometer)

Na tela de **Hardware Handshake** do aplicativo Flutter, existem 4 itens de verificação:

1. **Configuration Sync**: O módulo foi completamente configurado (dimensões, ângulo solar mínimo, coordenadas e intervalo de inspeção) e salvo no backend.
2. **Wi-Fi & HTTPS REST Connection**: A ESP32 conectou-se ao Wi-Fi local e conseguiu efetuar handshake com a API Go (`is_online = true`).
3. **Binary Water Level Sensor**: O sensor capacitivo de nível acusa água presente no reservatório (`water_available = true`), liberando os ciclos da minibomba.
4. **Hardware Interlocks & Radiometer**: Valida a rotina física de **Homing Mecânico** do carrinho (microswitch Normalmente Fechado - NC - em $X=0$) e o **Autoteste do Barramento I2C** do sensor radiométrico infravermelho (MLX90640 no endereço `0x33`). Quando a ESP32 liga, ela recua o motor de passo até tocar a chave fim de curso e checa a resposta I2C da câmera; se tudo estiver íntegro, envia `limits_check_passed = true` e `thermal_sensor_active = true`.

---

## 5. Roteiro de Demonstração Passo a Passo

Recomendamos abrir o **Aplicativo Flutter** e o **Postman** lado a lado na tela.

```
┌──────────────────────────────────────┐        ┌─────────────────────────────────────┐
│           POSTMAN (ESP32)            │        │           APP FLUTTER               │
│                                      │        │                                     │
│  [POST] /api/v1/devices/claim ───────┼───────>│  Checklist Handshake 2, 3 e 4 VERDES│
│  [POST] /api/v1/modules/:id/telemetry│        │  Card Radiométrico exibe Heatmap    │
│  [POST] /api/v1/modules/:id/cleanings│        │  Log de Lavagens registra Atuação   │
└──────────────────────────────────────┘        └─────────────────────────────────────┘
```

---

### Passo 1: Pareamento Físico Inicial (ESP32 Claim)
1. No Postman, abra a pasta `00 - Pareamento do Dispositivo (ESP32 Claim)` e execute:
   - `01. [ESP32 Boot] Claim do Dispositivo por MAC Address`
2. **O que acontece:**
   - A requisição pública envia o `mac_address` cadastrado no módulo (`aa:bb:cc:dd:ee:01`) e os flags de diagnóstico (`water_available: true`, `limits_check_passed: true`, `thermal_sensor_active: true`).
   - O backend Go registra o primeiro ping de presença, gera o `device_token` (`dev_sec_...`) e retorna o `module_id`.
   - O script de teste do Postman armazena instantaneamente `deviceToken` e `moduleId` nas variáveis de coleção.
   - **Nenhum login com usuário técnico é necessário!**

---

### Passo 2: Visualizar Handshake 100% Concluído no App
1. No App Flutter, acesse a tela do módulo ou a rota `/modules/:id/handshake`.
2. Observe que todos os pontos do Checklist agora ficam **VERDES**:
   - [x] **1. Configuration Sync** (Configuração confirmada pelo backend)
   - [x] **2. Wi-Fi & HTTPS REST Connection** (ESP32 Online)
   - [x] **3. Binary Water Level Sensor** (Água disponível no reservatório)
   - [x] **4. Hardware Interlocks & Radiometer** (Fim de curso homed + MLX90640 ativo)
3. Caso queira retestar o envio de ping a qualquer momento:
   - Na pasta `01 - Handshake & Conectividade Inicial (ESP32 Boot)`, execute `01. Ping Inicial ESP32 (Diagnóstico Completo)`.

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

### Passo 4: Varredura com Passos de 2cm & Sobreposição de 60%
A câmera térmica MLX90640 tem abertura física de 5 cm. O carrinho avança em passos de **2 cm** ($\Delta X = 2\text{ cm}$), gerando uma **sobreposição óptica de 60%** (3 cm compartilhados entre frames adjacentes).

O backend Go executa a costura ponderada (*linear blending*) e divide o painel em **faixas operacionais de 5 cm** (Faixa 1: [0-5cm], Faixa 2: [5-10cm], Faixa 3: [10-15cm], etc.).

1. No Postman, abra a pasta `03 - Telemetria & Varredura Térmica (Passos 2cm - Sobreposição 60%)`:
   - Dispare os passos individuais consecutivamente:
     - `01. Passo 1: X = 0.0 cm (Faixa 1 [0-5cm])`
     - `02. Passo 2: X = 2.0 cm (Sobreposição 60%)`
     - `03. Passo 3: X = 4.0 cm (Transição de faixa)`
   - Ou execute a varredura completa em lote:
     - `05. Ingestão em Lote (Varredura Completa - Passos de 2cm)`
2. **Resultado no App:**
   - No **Card Radiométrico (SCR-10)**, o Canvas desenha:
     - As **divisões verticais pontilhadas das faixas de 5 cm** ao longo de todo o comprimento.
     - As etiquetas superiores de cada faixa (`F1 0-5cm`, `F2 5-10cm`, `F3 10-15cm`).
     - A barra horizontal de resumo das faixas com temperatura máxima e média de cada setor.

---

### Passo 5: Detecção Local de Hotspot (Faixa 2 [5-10cm])
A ESP32 calcula o gradiente térmico **localmente** durante o passo de 2 cm. Ao identificar $\Delta T > 15^\circ\text{C}$ na posição $X = 6.0\text{ cm}$, a anomalia é associada à **Faixa 2 (5-10 cm)**.

1. No Postman, execute:
   - `04. Passo 4: X = 6.0 cm (Hotspot Crítico na Faixa 2 [5-10cm])`
2. **Resultado no App:**
   - A **Faixa 2 (5-10 cm)** do mapa térmico fica contornada em vermelho com a badge `🔥 Hotspot Detectado`.
   - No breakdown de faixas abaixo do canvas, a Faixa 2 é destacada com status de perigo e temperatura de pico de 58.4°C.
   - O atuador é orientado para a coordenada exata da anomalia.

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

## 6. Endpoints REST da API Go Envolvidos

| Método | Endpoint | Autenticação | Papel no Sistema |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/devices/claim` | Pública (MAC Address) | Pareamento inicial do hardware e emissão do `device_token` |
| `POST` | `/api/v1/modules/:id/device-ping` | Bearer `dev_sec_...` | Ping periódico, sensor capacitivo de água e diagnóstico dos interlocks |
| `GET` | `/api/v1/modules/:id/device-status` | Bearer `dev_sec_...` / JWT | Polling consumido pelo app e pelo hardware para validar checklist |
| `POST` | `/api/v1/modules/:id/telemetry` | Bearer `dev_sec_...` | Ingestão de telemetria, medições elétricas e matriz 32x24 MLX90640 |
| `POST` | `/api/v1/modules/:id/cleanings` | Bearer `dev_sec_...` | Ingestão de relatórios de ciclos do atuador mecânico e lavagem |
| `GET` | `/api/v1/modules/:id/measurements` | Bearer `dev_sec_...` / JWT | Consulta do histórico de inspeções |
| `GET` | `/api/v1/modules/:id/cleanings` | Bearer `dev_sec_...` / JWT | Consulta do log de operações de limpeza |
| `GET` | `/api/v1/modules/:id/thermal-map` | Bearer `dev_sec_...` / JWT | Consulta do mapa térmico composto com algoritmo de interpolação |
