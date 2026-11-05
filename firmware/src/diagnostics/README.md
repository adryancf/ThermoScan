# Módulo de Diagnósticos de Bancada (Diagnostics)

Este diretório contém a infraestrutura de **diagnósticos interativos** e **painel de testes de bancada** do ThermoScan. Ele permite validar individualmente cada sensor e atuador do robô antes da operação autônoma em campo.

---

## Componentes

### 1. `bench_diagnostics.h` / `bench_diagnostics.cpp`
Engine central de testes com catálogo executável via comando serial ou interface web.

* **Comandos Disponíveis (`diag <comando>`):**
  * `diag list`: Lista todos os testes e descrições disponíveis.
  * `diag all`: Executa todos os testes em sequência com relatório consolidado.
  * `diag mlx`: Captura frame térmico da câmera MLX90640 e valida sanidade dos 768 pixels.
  * `diag motor`: Avança o motor NEMA17 (+2.0 cm) e retorna à origem, confirmando acionamento suave.
  * `diag homing`: Executa ciclo de busca do fim de curso inicial (GPIO 35) e avanço do offset útil (7.0 cm).
  * `diag pump`: Pulsa a bomba d'água por 500 ms (requer confirmação do operador e nível de água OK).
  * `diag camera-servo`: Movimenta o servo de inclinação da câmera em 3 ângulos (0°, 45°, 90°).
  * `diag nozzle-servo`: Movimenta o servo do bico aspersor em 3 posições (-45°, 0°, +45°).
  * `diag ina`: Varre os endereços I2C dos sensores de potência INA228 e lê $V$, $I$ e $P$.
  * `diag water`: Lê o sensor capacitivo de nível do reservatório d'água.
  * `diag scan`: Ciclo unitário de teste de varredura (1 ponto em $X=0$, avanço de $+2.0\text{ cm}$, captura 2 e retorno à base).
  * `diag safety`: Valida resposta ao comando de parada de emergência e desenergização imediata.
  * `diag nvs`: Testa leitura e escrita na memória Flash interna.
  * `diag clock`: Verifica sincronização UTC via NTP.
  * `diag backend`: Executa ping e verifica resposta da API REST na nuvem.

### 2. `web_diagnostics.h`
Interface Web embarcada e proxy de transmissão ao vivo de logs:
* **`WebDiagnosticsServer`:** Servidor HTTP assíncrono acessível na rede local via `http://thermoscan.local` ou pelo IP do ESP32. Oferece botões rápidos para cada teste e console interativo.
* **`DualSerialProxy`:** Intercepta todas as mensagens enviadas para a Serial física (UART) e as duplica em um buffer circular em RAM, permitindo streaming em tempo real na interface web sem fios.
