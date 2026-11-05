# Laboratório de Bancada & Experimentos Isolados (`src/lab/`)

Este diretório armazena sketches rápidos, ferramentas de calibração e códigos de validação de bancada utilizados durante o desenvolvimento e prototipagem do hardware.

> [!NOTE]
> Os códigos contidos nesta pasta são **isolados e não fazem parte do binário de produção** do ThermoScan.
> Eles são automaticamente ignorados pelo PlatformIO no build principal (`build_src_filter = +<*> -<lab/>`).

---

## Estrutura do Laboratório

### 1. `mlx90640_tests/`
Projetos e scripts de validação inicial da câmera térmica MLX90640:
* **`simpleTest.cpp` / `main.cpp`:** Sketches básicos para leitura direta da matriz de 32x24 pixels via I2C (Wire).
* **`viewMap.py` / `thermalMatrix.py`:** Scripts em Python para leitura da porta serial e renderização visual do mapa de calor em tempo real na tela do computador.

### 2. `nema17_tests/`
Testes cinemáticos do eixo linear:
* **`main.cpp`:** Teste simples de pulso de passos e inversão de sentido no driver DRV8825.
* **`fim_de_curso.cpp`:** Teste de lógica de acionamento do sensor de fim de curso mecânico (chave fim de curso com pull-up e recuo após batente).

### 3. `pin_scanner/`
* **`main.cpp`:** Scanner de barramento I2C e teste rápido de pinagem do ESP32, permitindo descobrir os endereços dos sensores conectados (como 0x33 para MLX90640 e 0x40..0x42 para INA228).
* Pode ser compilado isoladamente com o comando:
  ```bash
  pio run -e pin_scanner -t upload
  ```
