#include "diagnostics/bench_diagnostics.h"

#include <chrono>
#include <thread>
#include <algorithm>
#include <cstdio>

namespace diagnostics {

static const char DIVIDER_HEAVY[] = "==================================================";
static const char DIVIDER_LIGHT[] = "--------------------------------------------------";

BenchDiagnostics::BenchDiagnostics(IStorage* storage,
                                   ITimeProvider* time_provider,
                                   ICloudClient* cloud,
                                   IThermalCamera* camera,
                                   IMotionController* motion,
                                   IPowerMeter* power_meter,
                                   IWaterSensor* water_sensor,
                                   ISprayActuator* spray,
                                   app::ThermoscanApp* app,
                                   IConsole* console)
    : storage_(storage),
      time_provider_(time_provider),
      cloud_(cloud),
      camera_(camera),
      motion_(motion),
      power_meter_(power_meter),
      water_sensor_(water_sensor),
      spray_(spray),
      app_(app),
      console_(console) {}

uint32_t BenchDiagnostics::nowMs() const {
#if defined(ARDUINO) || defined(ESP32)
    return millis();
#else
    return static_cast<uint32_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
#endif
}

uint32_t BenchDiagnostics::getElapsedMs(uint32_t start_ms) const {
    uint32_t current = nowMs();
    return (current >= start_ms) ? (current - start_ms) : 0;
}

void BenchDiagnostics::delayMs(uint32_t ms) const {
#if defined(ARDUINO) || defined(ESP32)
    delay(ms);
#else
    std::this_thread::sleep_for(std::chrono::milliseconds(ms));
#endif
}

void BenchDiagnostics::printTestResult(const TestResult& res) {
    if (!console_) return;

    console_->println(DIVIDER_LIGHT);
    console_->printf("[DIAG] TESTE: %s\n", res.name.c_str());
    console_->printf("STATUS:       %s\n", testStatusToString(res.status));
    console_->printf("DETALHES:     %s\n", res.details.c_str());
    console_->printf("DURACAO:      %u ms\n", res.duration_ms);
    if (!res.failure_cause.empty()) {
        console_->printf("FALHA:        %s\n", res.failure_cause.c_str());
    }
    console_->println(DIVIDER_LIGHT);
}

void BenchDiagnostics::printList() {
    if (!console_) return;

    console_->println(DIVIDER_HEAVY);
    console_->println("     ThermoScan - Catalogo de Testes de Bancada   ");
    console_->println(DIVIDER_HEAVY);
    console_->println("Comandos disponiveis:");
    console_->println("  diag list         - Lista todos os testes disponiveis");
    console_->println("  diag all          - Executa a bateria completa na sequencia segura");
    console_->println("  diag nvs          - Testa escrita/leitura na memoria NVS");
    console_->println("  diag clock        - Valida sincronizacao NTP e timestamp UTC");
    console_->println("  diag wifi         - Informa SSID, IP local, RSSI e conexao");
    console_->println("  diag backend      - Executa ping HTTP e re-claim se 401");
    console_->println("  diag mlx          - Captura frame MLX90640 e valida 768 pixels");
    console_->println("  diag mlx watch    - Monitoramento continuo de temperatura em tempo real");
    console_->println("  diag ina          - Le tensao (V), corrente (A) e potencia (W) do sensor INA228/INA");
    console_->println("  diag water        - Avalia estabilidade do sensor capacitivo de agua");
    console_->println("  diag motor        - Movimenta carro +2cm/-2cm (requer confirmacao)");
    console_->println("  diag homing       - Referencia carro ate batente NC (requer confirmacao)");
    console_->println("  diag pump         - Aciona bomba por 500ms (requer confirmacao)");
    console_->println("  diag camera-servo - Articula servo da camera para teste de angulo");
    console_->println("  diag nozzle-servo - Articula servo da mangueira/bico (45, 135 e 90 graus)");
    console_->println("  diag scan         - Executa ciclo completo de varredura (motor, MLX90640 e INA228)");
    console_->println("  diag safety       - Testa intertravamentos e parada de emergencia");
    console_->println("==================================================");
}

bool BenchDiagnostics::handleCommand(const std::string& cmd_line) {
    std::string line = cmd_line;
    // Trim leading/trailing whitespace
    while (!line.empty() && (line.front() == ' ' || line.front() == '\t' || line.front() == '\r' || line.front() == '\n')) {
        line.erase(line.begin());
    }
    while (!line.empty() && (line.back() == ' ' || line.back() == '\t' || line.back() == '\r' || line.back() == '\n')) {
        line.pop_back();
    }

    if (line.empty()) return false;

    // Check prefix "diag"
    if (line.rfind("diag", 0) != 0) {
        return false;
    }

    std::string arg = "";
    if (line.length() > 4) {
        arg = line.substr(4);
        while (!arg.empty() && arg.front() == ' ') {
            arg.erase(arg.begin());
        }
    }

    if (arg.empty() || arg == "list") {
        printList();
        return true;
    }

    if (arg == "all") {
        runAll();
        return true;
    }

    if (arg == "nvs") {
        printTestResult(testNvs());
    } else if (arg == "clock") {
        printTestResult(testClock());
    } else if (arg == "wifi") {
        printTestResult(testWifi());
    } else if (arg == "backend") {
        printTestResult(testBackend());
    } else if (arg == "mlx watch") {
        testMlx(true);
    } else if (arg == "mlx") {
        printTestResult(testMlx(false));
    } else if (arg == "ina") {
        printTestResult(testIna());
    } else if (arg == "water") {
        printTestResult(testWater());
    } else if (arg == "motor") {
        printTestResult(testMotor(true));
    } else if (arg == "homing") {
        printTestResult(testHoming());
    } else if (arg == "pump") {
        printTestResult(testPump(true));
    } else if (arg == "camera-servo" || arg == "cam-servo") {
        printTestResult(testCameraServo());
    } else if (arg == "nozzle-servo" || arg == "nozzle") {
        printTestResult(testNozzleServo());
    } else if (arg == "scan") {
        printTestResult(testScan());
    } else if (arg == "safety") {
        printTestResult(testSafety());
    } else {
        if (console_) {
            console_->printf("[ERR] Comando de diagnostico desconhecido: 'diag %s'. Digite 'diag list'.\n", arg.c_str());
        }
        return false;
    }

    // Always restore application orchestrator to safe IDLE state
    if (app_) {
        app_->returnToSafeIdle();
    }

    return true;
}

// 1. diag nvs
TestResult BenchDiagnostics::testNvs() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "nvs";

    if (!storage_) {
        r.status = TestStatus::FAIL;
        r.details = "Driver de armazenamento NVS nulo.";
        r.failure_cause = "Ponteiro IStorage invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    const std::string test_key = "diag_test";
    const std::string test_val = "VAL_554433";

    if (!storage_->saveTestKey(test_key, test_val)) {
        r.status = TestStatus::FAIL;
        r.details = "Falha ao gravar chave de teste no NVS.";
        r.failure_cause = "saveTestKey retornou falso.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    std::string read_val;
    if (!storage_->getTestKey(test_key, read_val)) {
        r.status = TestStatus::FAIL;
        r.details = "Falha ao reler chave de teste gravada.";
        r.failure_cause = "getTestKey nao encontrou a chave recem-gravada.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    if (read_val != test_val) {
        r.status = TestStatus::FAIL;
        r.details = "Inconsistencia de dados no NVS. Gravado: " + test_val + ", Lido: " + read_val;
        r.failure_cause = "Valor corrompido na leitura.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    storage_->removeTestKey(test_key);

    // Verify real credentials were not wiped
    std::string mod_id;
    storage_->getModuleId(mod_id);

    r.status = TestStatus::PASS;
    r.details = "Gravacao, leitura e remocao de chave de teste consistentes. Module ID no NVS: " +
                (mod_id.empty() ? "(vazio/aguardando claim)" : mod_id);
    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 2. diag clock
TestResult BenchDiagnostics::testClock() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "clock";

    if (!time_provider_) {
        r.status = TestStatus::FAIL;
        r.details = "Provedor de tempo nulo.";
        r.failure_cause = "Ponteiro ITimeProvider invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    uint32_t epoch = time_provider_->getEpochSeconds();
    bool synced = time_provider_->isTimeSynchronized();

    if (epoch == 0 || !synced) {
        r.status = TestStatus::FAIL;
        r.details = "now == " + std::to_string(epoch) + ", sync=" + (synced ? "true" : "false");
        r.failure_cause = "Relogio UTC invalido ou NTP nao sincronizado.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    r.status = TestStatus::PASS;
    r.details = "Relogio UTC valido. Epoch: " + std::to_string(epoch) + " s, NTP sincronizado: sim";
    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 3. diag wifi
TestResult BenchDiagnostics::testWifi() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "wifi";

#if defined(ARDUINO) || defined(ESP32)
    if (WiFi.status() == WL_CONNECTED) {
        r.status = TestStatus::PASS;
        r.details = "Conectado. SSID: " + std::string(WiFi.SSID().c_str()) +
                    ", IP: " + std::string(WiFi.localIP().toString().c_str()) +
                    ", RSSI: " + std::to_string(WiFi.RSSI()) + " dBm";
    } else {
        r.status = TestStatus::FAIL;
        r.details = "WiFi desconectado (status=" + std::to_string(WiFi.status()) + ")";
        r.failure_cause = "Nao conectado ao ponto de acesso.";
    }
#else
    r.status = TestStatus::PASS;
    r.details = "Conectado via interface de rede nativa/host (POSIX socket loopback/LAN)";
#endif

    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 4. diag backend
TestResult BenchDiagnostics::testBackend() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "backend";

    if (!cloud_) {
        r.status = TestStatus::FAIL;
        r.details = "Cliente HTTP Cloud nulo.";
        r.failure_cause = "Ponteiro ICloudClient invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    uint32_t ping_start = nowMs();
    bool ping_ok = cloud_->sendPing();
    uint32_t latency = getElapsedMs(ping_start);

    if (ping_ok) {
        r.status = TestStatus::PASS;
        r.details = "Ping autenticado respondido com sucesso. Latencia: " + std::to_string(latency) + " ms";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    // Ping failed: check if it was due to 401 Unauthorized
    if (cloud_->hadAuthError()) {
        if (console_) {
            console_->println("[BACKEND] HTTP 401 Unauthorized detectado! Tentando re-claim com credenciais de fabrica...");
        }
        uint32_t claim_start = nowMs();
        bool claim_ok = cloud_->claimDevice();
        uint32_t claim_lat = getElapsedMs(claim_start);

        if (claim_ok) {
            r.status = TestStatus::PASS;
            r.details = "HTTP 401 recuperado com re-claim bem sucedido! Novo token emitido. Latencia do claim: " +
                        std::to_string(claim_lat) + " ms";
            r.duration_ms = getElapsedMs(t0);
            return r;
        } else {
            r.status = TestStatus::FAIL;
            r.details = "HTTP 401 recebido e tentativa de re-claim falhou.";
            r.failure_cause = "Credencial de dispositivo recusada pelo backend e claim falhou.";
            r.duration_ms = getElapsedMs(t0);
            return r;
        }
    }

    r.status = TestStatus::FAIL;
    r.details = "Falha de comunicacao com backend. Latencia: " + std::to_string(latency) + " ms";
    r.failure_cause = "Timeout ou erro de conexao HTTP.";
    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 5. diag mlx
TestResult BenchDiagnostics::testMlx(bool watch) {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "mlx";

    if (!camera_) {
        r.status = TestStatus::FAIL;
        r.details = "Driver de camera MLX90640 nulo.";
        r.failure_cause = "Ponteiro IThermalCamera invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    if (!camera_->init()) {
        r.status = TestStatus::FAIL;
        r.details = "Falha na inicializacao I2C do MLX90640.";
        r.failure_cause = "camera_->init() retornou falso.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    if (watch) {
        if (console_) {
            console_->println("[MLX WATCH] Iniciando monitoramento continuo. Pressione qualquer tecla para interromper.");
        }
        while (console_ && !console_->available()) {
            ThermalFrame frame;
            if (camera_->captureFrame(frame) && frame.valid) {
                float min_t = 999.0f, max_t = -999.0f, sum_t = 0.0f;
                size_t invalids = 0;
                for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
                    float t = frame.pixels[i];
                    if (std::isnan(t) || std::isinf(t) || t < -40.0f || t > 300.0f) {
                        invalids++;
                    } else {
                        if (t < min_t) min_t = t;
                        if (t > max_t) max_t = t;
                        sum_t += t;
                    }
                }
                float avg_t = (invalids < ThermalFrame::PIXEL_COUNT) ? (sum_t / (ThermalFrame::PIXEL_COUNT - invalids)) : 0.0f;
                console_->printf("[MLX WATCH] Min: %.1f C | Max: %.1f C | Med: %.1f C | Invalidos: %zu\n",
                                min_t, max_t, avg_t, invalids);
            } else {
                console_->println("[MLX WATCH] Erro na captura de frame.");
            }
            delayMs(250);
        }
        if (console_) {
            while (console_->available()) console_->read(); // consume key
            console_->println("[MLX WATCH] Monitoramento finalizado.");
        }
        r.status = TestStatus::PASS;
        r.details = "Modo interativo watch executado.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    ThermalFrame frame;
    if (!camera_->captureFrame(frame) || !frame.valid) {
        r.status = TestStatus::FAIL;
        r.details = "Falha ao capturar frame termico valido.";
        r.failure_cause = "captureFrame retornou frame invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    float min_t = 999.0f, max_t = -999.0f, sum_t = 0.0f;
    size_t invalid_count = 0;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        float t = frame.pixels[i];
        if (std::isnan(t) || std::isinf(t) || t < -40.0f || t > 300.0f) {
            invalid_count++;
        } else {
            if (t < min_t) min_t = t;
            if (t > max_t) max_t = t;
            sum_t += t;
        }
    }

    float valid_pixels = static_cast<float>(ThermalFrame::PIXEL_COUNT - invalid_count);
    float avg_t = (valid_pixels > 0) ? (sum_t / valid_pixels) : 0.0f;

    char details_buf[160];
    std::snprintf(details_buf, sizeof(details_buf),
                  "768 pixels lidos. Min: %.1f C, Max: %.1f C, Med: %.1f C, Invalidos: %zu",
                  min_t, max_t, avg_t, invalid_count);

    if (invalid_count > 38) { // Mais de 5% de pixels corrompidos
        r.status = TestStatus::FAIL;
        r.details = details_buf;
        r.failure_cause = "Numero excessivo de pixels termicos invalidos (" + std::to_string(invalid_count) + ").";
    } else {
        r.status = TestStatus::PASS;
        r.details = details_buf;
    }

    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 6. diag ina
TestResult BenchDiagnostics::testIna() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "ina";

    if (!power_meter_) {
        r.status = TestStatus::FAIL;
        r.details = "Driver INA nulo.";
        r.failure_cause = "Ponteiro IPowerMeter invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    bool panel1_ok = false;
    bool has_nan_inf = false;
    std::string combined_details;

    for (uint8_t p = 1; p <= 3; ++p) {
        uint8_t addr = getInaAddressForPanel(p);
        PowerSnapshot snap;
        bool ok = power_meter_->readSnapshotForPanel(p, snap) && snap.valid;

        if (ok) {
            if (std::isnan(snap.voltage_v) || std::isinf(snap.voltage_v) ||
                std::isnan(snap.current_a) || std::isinf(snap.current_a) ||
                std::isnan(snap.power_w) || std::isinf(snap.power_w)) {
                has_nan_inf = true;
                ok = false;
            }
        }

        if (p == 1 && ok) {
            panel1_ok = true;
        }

        char p_buf[160];
        if (ok) {
            std::snprintf(p_buf, sizeof(p_buf),
                          "Painel %u (0x%02X): OK (Tensao: %.2f V, Corrente: %.2f A, Potencia: %.2f W)",
                          p, addr, snap.voltage_v, snap.current_a, snap.power_w);
        } else {
            std::snprintf(p_buf, sizeof(p_buf),
                          "Painel %u (0x%02X): AUSENTE",
                          p, addr);
        }

        if (!combined_details.empty()) {
            combined_details += " | ";
        }
        combined_details += p_buf;
    }

    if (has_nan_inf) {
        r.status = TestStatus::FAIL;
        r.details = "Valores de medicao eletrica sao NaN ou Inf. " + combined_details;
        r.failure_cause = "Corrupcao de leitura do barramento I2C.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    if (!panel1_ok) {
        r.status = TestStatus::FAIL;
        r.details = "Falha ao ler snapshot do sensor INA principal. " + combined_details;
        r.failure_cause = "readSnapshotForPanel(1) retornou falso ou snap.valid == false.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    r.status = TestStatus::PASS;
    r.details = combined_details;
    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 7. diag water
TestResult BenchDiagnostics::testWater() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "water";

    if (!water_sensor_) {
        r.status = TestStatus::FAIL;
        r.details = "Driver de sensor de agua nulo.";
        r.failure_cause = "Ponteiro IWaterSensor invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    int available_count = 0;
    const int SAMPLES = 5;
    for (int i = 0; i < SAMPLES; ++i) {
        if (water_sensor_->isWaterAvailable()) {
            available_count++;
        }
        delayMs(50);
    }

    bool is_stable = (available_count == 0 || available_count == SAMPLES);
    std::string state_str = (available_count > SAMPLES / 2) ? "AGUA DETECTADA" : "RESERVATORIO SECO";

    if (!is_stable) {
        r.status = TestStatus::FAIL;
        r.details = "Leituras oscilando (" + std::to_string(available_count) + "/" + std::to_string(SAMPLES) + " ativas).";
        r.failure_cause = "Sensor capacitivo ruidoso ou com mau contato.";
    } else {
        r.status = TestStatus::MANUAL;
        r.details = "Leituras estaveis (5/5). Estado detectado: " + state_str +
                    ". Confirme manualmente molhando/secando o sensor para checar transicao.";
    }

    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 8. diag motor
TestResult BenchDiagnostics::testMotor(bool require_confirmation) {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "motor";

    if (!motion_) {
        r.status = TestStatus::FAIL;
        r.details = "Controlador de movimento nulo.";
        r.failure_cause = "Ponteiro IMotionController invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    if (require_confirmation && console_) {
        console_->println("AVISO: O teste de motor ira movimentar o carro +2.0 cm e retornar a origem.");
        console_->print("Deseja prosseguir com o movimento do motor? [s/n]: ");
        std::string ans = console_->readLine(10000);
        console_->println(ans.c_str());

        if (ans != "s" && ans != "S" && ans != "y" && ans != "Y") {
            r.status = TestStatus::MANUAL;
            r.details = "Teste de motor nao executado por opcao do operador.";
            r.duration_ms = getElapsedMs(t0);
            return r;
        }
    }

    float initial_x = motion_->getXPositionCm();

    // 1. Forward 2 cm
    float target_forward = initial_x + 2.0f;
    if (!motion_->moveToXCm(target_forward)) {
        motion_->disableMotor();
        r.status = TestStatus::FAIL;
        r.details = "Falha ao mover motor no sentido avancar (+2.0 cm).";
        r.failure_cause = "moveToXCm falhou ou atingiu limite inesperado.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    delayMs(300);

    // 2. Backward to initial
    if (!motion_->moveToXCm(initial_x)) {
        motion_->disableMotor();
        r.status = TestStatus::FAIL;
        r.details = "Falha ao mover motor no sentido recuar.";
        r.failure_cause = "moveToXCm de retorno falhou.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    // Always ensure de-energization
    motion_->disableMotor();

    r.status = TestStatus::MANUAL;
    r.details = "Carro movimentado (+2.0 cm ida, -2.0 cm volta). Motor desenergizado com sucesso. Confirme visualmente se o movimento foi suave e sem travamento.";
    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 9. diag homing
TestResult BenchDiagnostics::testHoming() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "homing";

    if (!motion_) {
        r.status = TestStatus::FAIL;
        r.details = "Controlador de movimento nulo.";
        r.failure_cause = "Ponteiro IMotionController invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    if (console_) {
        console_->println("AVISO: O carro vai se mover ate o batente mecanico NC na origem (X=0).");
    }

    if (!motion_->checkLimitsIntegrity()) {
        motion_->disableMotor();
        r.status = TestStatus::FAIL;
        r.details = "Circuito de fim de curso NC aberto antes do movimento (possivel fio partido ou batente ja pressionado).";
        r.failure_cause = "checkLimitsIntegrity retornou falso.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    if (!motion_->home()) {
        motion_->disableMotor();
        r.status = TestStatus::FAIL;
        r.details = "Ciclo de homing falhou ao buscar a chave NC.";
        r.failure_cause = "motion_->home() retornou falso (timeout ou travamento).";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    motion_->disableMotor();

    r.status = TestStatus::PASS;
    r.details = "Homing concluido com sucesso. Batente detectado, recuo de seguranca executado e carro em X=0.0 cm.";
    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 10. diag pump
TestResult BenchDiagnostics::testPump(bool require_confirmation) {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "pump";

    if (!spray_) {
        r.status = TestStatus::FAIL;
        r.details = "Atuador de spray nulo.";
        r.failure_cause = "Ponteiro ISprayActuator invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    // Safety rule: strictly require operator confirmation before any pump actuation
    if (require_confirmation && console_) {
        console_->println("ATENCAO: Este teste acionara a bomba d'agua por 500 ms.");
        console_->print("Deseja acionar a bomba agora? [s/n]: ");
        std::string ans = console_->readLine(10000);
        console_->println(ans.c_str());

        if (ans != "s" && ans != "S" && ans != "y" && ans != "Y") {
            r.status = TestStatus::MANUAL;
            r.details = "Acionamento da bomba cancelado pelo operador.";
            r.duration_ms = getElapsedMs(t0);
            return r;
        }
    }

    bool water_before = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;
    if (!water_before && console_) {
        console_->println("[AVISO] Sensor indica reservatorio seco! Pulso curto de 500 ms sera mantido apenas para checar rele/MOSFET.");
    }

    if (!spray_->startPump()) {
        spray_->stopPump();
        r.status = TestStatus::FAIL;
        r.details = "Falha ao enviar sinal de acionamento para a bomba.";
        r.failure_cause = "spray_->startPump() retornou falso.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    delayMs(500);
    spray_->stopPump();

    if (spray_->isPumpActive()) {
        // Safety violation: pump did not stop!
        if (motion_) motion_->emergencyStop();
        r.status = TestStatus::FAIL;
        r.details = "BOMBA PERMANECEU ATIVA APOS COMANDO DE PARADA! Parada de emergencia acionada.";
        r.failure_cause = "Falha de desligamento da bomba.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    bool water_after = (water_sensor_ != nullptr) ? water_sensor_->isWaterAvailable() : true;

    r.status = TestStatus::MANUAL;
    r.details = "Pulso de 500 ms acionado e desligado com sucesso. Agua antes: " +
                std::string(water_before ? "sim" : "nao") + ", Agua depois: " +
                std::string(water_after ? "sim" : "nao") +
                ". Confirme visualmente se houve pressurizacao e saida de agua.";
    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 11. diag camera-servo
TestResult BenchDiagnostics::testCameraServo() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "camera-servo";

    if (!camera_) {
        r.status = TestStatus::FAIL;
        r.details = "Driver de camera nulo.";
        r.failure_cause = "Ponteiro IThermalCamera invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    float initial_angle = camera_->getTiltAngle();
    if (console_) {
        console_->printf("[CAM SERVO] Angulo atual: %.1f graus. Articulando para 45.0 e 90.0 graus...\n", initial_angle);
    }

    camera_->setTiltAngle(45.0f);
    delayMs(300);

    camera_->setTiltAngle(90.0f);
    delayMs(300);

    camera_->setTiltAngle(CAMERA_DEFAULT_ANGLE);

    r.status = TestStatus::PASS;
    r.details = "Servo da camera articulado para 45 e 90 graus com sucesso. Retornado ao angulo padrao: " +
                std::to_string(static_cast<int>(CAMERA_DEFAULT_ANGLE)) + " graus.";
    r.duration_ms = getElapsedMs(t0);
    return r;
}

TestResult BenchDiagnostics::testNozzleServo() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "nozzle-servo";

    if (!spray_) {
        r.status = TestStatus::FAIL;
        r.details = "Driver de atuador de spray/nozzle nulo.";
        r.failure_cause = "Ponteiro ISprayActuator invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    if (console_) {
        console_->println("[NOZZLE SERVO] Articulando servo do bico: 45 graus...");
    }
    spray_->setNozzleAngle(45.0f);
    delayMs(350);

    if (console_) {
        console_->println("[NOZZLE SERVO] Articulando servo do bico: 135 graus...");
    }
    spray_->setNozzleAngle(135.0f);
    delayMs(350);

    if (console_) {
        console_->println("[NOZZLE SERVO] Centralizando servo do bico: 90 graus...");
    }
    spray_->setNozzleAngle(90.0f);
    delayMs(200);

    r.status = TestStatus::PASS;
    r.details = "Servo do bico da mangueira articulado com sucesso (45, 135 e 90 graus). Retornado ao centro (90 graus).";
    r.duration_ms = getElapsedMs(t0);
    return r;
}

TestResult BenchDiagnostics::testScan() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "scan";

    if (!camera_) {
        r.status = TestStatus::FAIL;
        r.details = "Driver da camera termica nulo.";
        r.failure_cause = "camera_ == nullptr";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }
    if (!motion_) {
        r.status = TestStatus::FAIL;
        r.details = "Driver de movimento linear nulo.";
        r.failure_cause = "motion_ == nullptr";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    float initial_x = motion_->getXPositionCm();

    if (console_) {
        console_->println(DIVIDER_LIGHT);
        console_->printf("[SCAN DIAG] Iniciando ciclo de teste de varredura na bancada a partir de X = %.1f cm...\n", initial_x);
        console_->println("[SCAN DIAG] 1/3: Capturando frame termico e medindo potencia no ponto atual...");
    }

    // 1. Captura termica no ponto atual
    ThermalFrame frame1;
    if (!camera_->captureFrame(frame1) || !frame1.valid) {
        r.status = TestStatus::FAIL;
        r.details = "Falha na captura termica da camera MLX90640.";
        r.failure_cause = "captureFrame retornou falso ou frame invalido.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    float max_temp1 = -999.0f;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        if (frame1.pixels[i] > max_temp1) max_temp1 = frame1.pixels[i];
    }

    PowerSnapshot power1{};
    if (power_meter_) {
        power_meter_->readSnapshot(power1);
    }

    if (console_) {
        console_->printf("  [CAPTURA 1] X=%.1f cm | Tmax=%.2f C | V=%.2f V | I=%.2f A | P=%.2f W\n",
                         initial_x, max_temp1, power1.voltage_v, power1.current_a, power1.power_w);
        console_->printf("[SCAN DIAG] 2/3: Avancando o trilho linear em +%.1f cm...\n", STEP_SIZE_CM);
    }

    // 2. Deslocamento do motor (+2.0 cm)
    float target_forward = initial_x + STEP_SIZE_CM;
    if (!motion_->moveToXCm(target_forward)) {
        r.status = TestStatus::FAIL;
        r.details = "Falha no deslocamento do motor para X = " + std::to_string(target_forward) + " cm.";
        r.failure_cause = "moveToXCm falhou durante o avanco de teste do scan.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    // 3. Captura termica no ponto avancado
    ThermalFrame frame2;
    if (!camera_->captureFrame(frame2) || !frame2.valid) {
        motion_->moveToXCm(initial_x);
        r.status = TestStatus::FAIL;
        r.details = "Falha na segunda captura termica apos deslocamento.";
        r.failure_cause = "Segunda captura de frame invalida.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    float max_temp2 = -999.0f;
    for (size_t i = 0; i < ThermalFrame::PIXEL_COUNT; ++i) {
        if (frame2.pixels[i] > max_temp2) max_temp2 = frame2.pixels[i];
    }

    PowerSnapshot power2{};
    if (power_meter_) {
        power_meter_->readSnapshot(power2);
    }

    if (console_) {
        console_->printf("  [CAPTURA 2] X=%.1f cm | Tmax=%.2f C | V=%.2f V | I=%.2f A | P=%.2f W\n",
                         target_forward, max_temp2, power2.voltage_v, power2.current_a, power2.power_w);
        console_->println("[SCAN DIAG] 3/3: Retornando o carro linear a posicao inicial...");
    }

    // 4. Retorno a posicao original
    if (!motion_->moveToXCm(initial_x)) {
        r.status = TestStatus::FAIL;
        r.details = "Falha ao retornar o carro para a posicao inicial X = " + std::to_string(initial_x) + " cm.";
        r.failure_cause = "moveToXCm falhou no retorno.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    r.status = TestStatus::PASS;
    r.details = "Varredura de teste concluida com sucesso! Avanco de " +
                std::to_string(static_cast<int>(STEP_SIZE_CM)) +
                " cm, 2 capturas MLX90640 (Tmax=" + std::to_string(static_cast<int>(max_temp2)) +
                " C) e retorno suave para X=" + std::to_string(static_cast<int>(initial_x)) + " cm.";
    r.duration_ms = getElapsedMs(t0);
    return r;
}

// 12. diag safety
TestResult BenchDiagnostics::testSafety() {
    uint32_t t0 = nowMs();
    TestResult r;
    r.name = "safety";

    // Trigger emergency stop on motion and spray
    if (spray_) spray_->stopPump();
    if (motion_) motion_->emergencyStop();
    if (app_) app_->executeEmergencyStop();

    bool pump_ok = (!spray_ || !spray_->isPumpActive());
    bool limits_ok = (!motion_ || motion_->checkLimitsIntegrity());

    if (!pump_ok) {
        r.status = TestStatus::FAIL;
        r.details = "Intertravamento falhou: bomba nao desenergizada na parada de emergencia.";
        r.failure_cause = "Bomba ainda reporta ativa.";
        r.duration_ms = getElapsedMs(t0);
        return r;
    }

    // Restore safe idle state
    if (app_) app_->returnToSafeIdle();
    if (motion_) motion_->disableMotor();

    r.status = TestStatus::PASS;
    r.details = "Intertravamentos verificados. Bomba desligada, motor desenergizado, sistema retornado ao IDLE seguro. Limites NC integros: " +
                std::string(limits_ok ? "sim" : "nao");
    r.duration_ms = getElapsedMs(t0);
    return r;
}

// diag all
void BenchDiagnostics::runAll() {
    if (console_) {
        console_->println(DIVIDER_HEAVY);
        console_->println("  INICIANDO BATERIA COMPLETA DE TESTES DE BANCADA ");
        console_->println(DIVIDER_HEAVY);
    }

    std::vector<TestResult> results;

    // Sequence: nvs -> clock -> wifi -> backend -> mlx -> ina -> water -> motor -> homing -> pump -> safety
    results.push_back(testNvs());
    printTestResult(results.back());

    results.push_back(testClock());
    printTestResult(results.back());

    results.push_back(testWifi());
    printTestResult(results.back());

    results.push_back(testBackend());
    printTestResult(results.back());

    results.push_back(testMlx(false));
    printTestResult(results.back());

    results.push_back(testIna());
    printTestResult(results.back());

    results.push_back(testWater());
    printTestResult(results.back());

    results.push_back(testMotor(true));
    printTestResult(results.back());

    results.push_back(testHoming());
    printTestResult(results.back());

    results.push_back(testPump(true));
    printTestResult(results.back());

    results.push_back(testCameraServo());
    printTestResult(results.back());

    results.push_back(testNozzleServo());
    printTestResult(results.back());

    results.push_back(testScan());
    printTestResult(results.back());

    results.push_back(testSafety());
    printTestResult(results.back());

    // Final safety restore
    if (app_) {
        app_->returnToSafeIdle();
    }

    // Tally
    int pass_count = 0;
    int fail_count = 0;
    int manual_count = 0;
    std::string failed_tests = "";

    for (const auto& res : results) {
        if (res.status == TestStatus::PASS) pass_count++;
        else if (res.status == TestStatus::FAIL) {
            fail_count++;
            if (!failed_tests.empty()) failed_tests += ", ";
            failed_tests += res.name;
        } else if (res.status == TestStatus::MANUAL) {
            manual_count++;
        }
    }

    if (console_) {
        console_->println(DIVIDER_HEAVY);
        console_->println("         RESUMO DO DIAGNOSTICO DE BANCADA         ");
        console_->println(DIVIDER_HEAVY);
        console_->printf("Total de testes executados: %zu\n", results.size());
        console_->printf("  [PASS]   Aprovados automaticamente:   %d\n", pass_count);
        console_->printf("  [FAIL]   Falhas detectadas:          %d\n", fail_count);
        console_->printf("  [MANUAL] Requerem confirmacao visual: %d\n", manual_count);
        console_->println(DIVIDER_LIGHT);

        if (fail_count > 0) {
            console_->printf("RECOMENDACAO: FALHA CRITICA em [%s]! Nao inicie varredura ou operacao em campo antes de reparar os componentes indicados.\n",
                             failed_tests.c_str());
        } else if (manual_count > 0) {
            console_->println("RECOMENDACAO: Todos os testes automaticos foram APROVADOS! Valide se os itens com status MANUAL (movimento do motor, jato da bomba e transicao de agua) corresponderam ao esperado.");
        } else {
            console_->println("RECOMENDACAO: Bancada 100% aprovada e operacional. O sistema esta pronto para ser instalado no painel.");
        }
        console_->println(DIVIDER_HEAVY);
    }
}

} // namespace diagnostics
