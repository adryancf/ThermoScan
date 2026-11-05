#include <Arduino.h>
#include <Wire.h>
#include <ESP32Servo.h>

// Lista de pinos candidatos para Entradas Digitais (Fins de curso e Sensores)
// GPIOs com suporte a INPUT_PULLUP interno no ESP32:
static const uint8_t INPUT_PULLUP_PINS[] = {
    4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33
};
static const size_t NUM_PULLUP_PINS = sizeof(INPUT_PULLUP_PINS) / sizeof(INPUT_PULLUP_PINS[0]);

// GPIOs de apenas entrada (sem pullup interno, sensores analogicos/digitais):
static const uint8_t INPUT_ONLY_PINS[] = { 34, 35, 36, 39 };
static const size_t NUM_INPUT_ONLY_PINS = sizeof(INPUT_ONLY_PINS) / sizeof(INPUT_ONLY_PINS[0]);

// Lista de pinos candidatos comuns para Servos (PWM de saida):
static const uint8_t CANDIDATE_SERVO_PINS[] = { 26, 27, 14, 13, 12, 4, 16, 17, 32, 33, 25, 18, 19, 5 };
static const size_t NUM_SERVO_PINS = sizeof(CANDIDATE_SERVO_PINS) / sizeof(CANDIDATE_SERVO_PINS[0]);

// Armazena o estado anterior de todos os pinos de entrada
static int last_pullup_states[NUM_PULLUP_PINS];
static int last_input_states[NUM_INPUT_ONLY_PINS];

static Servo g_probe_servo;

void printBanner() {
    Serial.println(F("\n=============================================================="));
    Serial.println(F("       🔍 DETETIVE DE PINOS THERMOSCAN (SENSORES & SERVOS)"));
    Serial.println(F("=============================================================="));
    Serial.println(F("1. FINS DE CURSO:"));
    Serial.println(F("   -> APERTE a chave com a mão. O terminal avisa o GPIO na hora."));
    Serial.println(F(""));
    Serial.println(F("2. SENSOR DE ÁGUA:"));
    Serial.println(F("   -> Mergulhe o sensor na água (ou encoste um dedo úmido nele)"));
    Serial.println(F("      e retire. O terminal acusará a mudança de estado e o GPIO!"));
    Serial.println(F("   -> Ou digite 'a' para tirar um Raio-X de TODOS os pinos agora."));
    Serial.println(F(""));
    Serial.println(F("3. SERVOS (Mangueira & Câmera):"));
    Serial.println(F("   -> Digite 'w' para varrer todos os pinos de servo."));
    Serial.println(F("   -> Digite 'p13' ou 'p32' para testar um pino específico."));
    Serial.println(F(""));
    Serial.println(F("4. OUTROS COMANDOS:"));
    Serial.println(F("   -> 'a' -> Mostra o estado ATUAL (Digital e Analógico) de todos os pinos"));
    Serial.println(F("   -> 'i' -> Faz varredura I2C (Câmera MLX90640 e INA219)"));
    Serial.println(F("   -> 'h' -> Reexibe este menu"));
    Serial.println(F("=============================================================="));
    Serial.println(F("👀 Monitorando em tempo real... altere um sensor agora!\n"));
}

void printAllPinsStatus() {
    Serial.println(F("\n--- [RAIO-X: ESTADO ATUAL DE TODOS OS PINOS] ---"));
    Serial.println(F("Pinos Digitais (com Pull-up):"));
    for (size_t i = 0; i < NUM_PULLUP_PINS; ++i) {
        uint8_t pin = INPUT_PULLUP_PINS[i];
        int val = digitalRead(pin);
        Serial.printf("  GPIO %2d: %s (%d)\n", pin, (val == LOW ? "LOW (0V / GND)" : "HIGH (3.3V)"), val);
    }
    Serial.println(F("\nPinos Apenas Entrada (Input-Only 34, 35, 36, 39):"));
    for (size_t i = 0; i < NUM_INPUT_ONLY_PINS; ++i) {
        uint8_t pin = INPUT_ONLY_PINS[i];
        int val = digitalRead(pin);
        int raw_adc = analogRead(pin);
        Serial.printf("  GPIO %2d: Digital=%d | ADC=%4d (~%.2fV)\n", 
                      pin, val, raw_adc, (raw_adc * 3.3f / 4095.0f));
    }
    Serial.println(F("------------------------------------------------\n"));
}

void scanI2C() {
    Serial.println(F("\n--- [VARREDURA I2C EM GPIO 21 (SDA) E GPIO 22 (SCL)] ---"));
    Wire.begin(21, 22);
    byte error, address;
    int nDevices = 0;

    for (address = 1; address < 127; address++) {
        Wire.beginTransmission(address);
        error = Wire.endTransmission();

        if (error == 0) {
            Serial.printf("  [OK] Dispositivo no endereco 0x%02X: ", address);
            if (address == 0x33) Serial.println(F("--> Camera MLX90640"));
            else if (address == 0x40) Serial.println(F("--> INA219 #1 (Padrao 0x40)"));
            else if (address == 0x41) Serial.println(F("--> INA219 #2 (Jumper A0)"));
            else if (address == 0x44) Serial.println(F("--> INA219 #2 (Jumper A1)"));
            else Serial.println(F("--> Outro dispositivo I2C"));
            nDevices++;
        }
    }
    if (nDevices == 0) Serial.println(F("  [!] Nenhum dispositivo I2C encontrado em 21/22."));
    Serial.println(F("---------------------------------------------------------"));
}

void sweepAllServoPins() {
    Serial.println(F("\n=============================================================="));
    Serial.println(F("🤖 INICIANDO VARREDURA DE SERVOS NOS PINOS CANDIDATOS"));
    Serial.println(F("   Observe a mangueira e a camera se movimentarem!"));
    Serial.println(F("=============================================================="));

    for (size_t i = 0; i < NUM_SERVO_PINS; ++i) {
        uint8_t pin = CANDIDATE_SERVO_PINS[i];
        Serial.printf("\n>>> TESTANDO AGORA: GPIO %d ...\n", pin);
        Serial.println(F("    Movendo servo para 45 graus..."));

        g_probe_servo.setPeriodHertz(50);
        g_probe_servo.attach(pin, 500, 2500);
        g_probe_servo.write(45);
        delay(600);

        Serial.println(F("    Movendo servo para 90 graus..."));
        g_probe_servo.write(90);
        delay(600);

        g_probe_servo.detach();
        Serial.printf("    Fim do teste no GPIO %d. (Algum servo se mexeu?)\n", pin);
        delay(400);
    }

    Serial.println(F("\n=============================================================="));
    Serial.println(F("Varredura de servos finalizada! Anote os pinos correspondentes."));
    Serial.println(F("==============================================================\n"));
}

void testSingleServoPin(uint8_t pin) {
    Serial.printf("\n[SERVO TEST] Testando especificamente o GPIO %d...\n", pin);
    g_probe_servo.setPeriodHertz(50);
    g_probe_servo.attach(pin, 500, 2500);
    g_probe_servo.write(30);
    delay(500);
    g_probe_servo.write(120);
    delay(500);
    g_probe_servo.write(90);
    delay(300);
    g_probe_servo.detach();
    Serial.printf("[SERVO TEST] Concluido no GPIO %d.\n", pin);
}

void setup() {
    Serial.begin(115200);
    delay(500);

    // Inicializa todos os pinos de pullup como entradas
    for (size_t i = 0; i < NUM_PULLUP_PINS; ++i) {
        pinMode(INPUT_PULLUP_PINS[i], INPUT_PULLUP);
        last_pullup_states[i] = digitalRead(INPUT_PULLUP_PINS[i]);
    }

    // Inicializa pinos apenas de entrada
    for (size_t i = 0; i < NUM_INPUT_ONLY_PINS; ++i) {
        pinMode(INPUT_ONLY_PINS[i], INPUT);
        last_input_states[i] = digitalRead(INPUT_ONLY_PINS[i]);
    }

    printBanner();
}

void loop() {
    // 1. Detectar mudanca de estado em qualquer pino PULLUP (Fins de curso)
    for (size_t i = 0; i < NUM_PULLUP_PINS; ++i) {
        uint8_t pin = INPUT_PULLUP_PINS[i];
        int current = digitalRead(pin);

        if (current != last_pullup_states[i]) {
            last_pullup_states[i] = current;

            Serial.println(F("\n**************************************************************"));
            Serial.printf("🎯 DETECCAO NO GPIO %d !\n", pin);
            if (current == LOW) {
                Serial.printf("   Estado mudou para: LOW (0V / CONTATO FECHADO PARA O GND)\n");
            } else {
                Serial.printf("   Estado mudou para: HIGH (3.3V / CONTATO ABERTO / PULLUP)\n");
            }
            Serial.printf("   --> Se voce acabou de apertar o fim de curso, este e o GPIO %d!\n", pin);
            Serial.println(F("**************************************************************\n"));
        }
    }

    // 2. Detectar mudanca nos pinos Input-only (34-39)
    for (size_t i = 0; i < NUM_INPUT_ONLY_PINS; ++i) {
        uint8_t pin = INPUT_ONLY_PINS[i];
        int current = digitalRead(pin);

        if (current != last_input_states[i]) {
            last_input_states[i] = current;
            Serial.println(F("\n**************************************************************"));
            Serial.printf("🎯 DETECCAO NO GPIO %d (Input Only)!\n", pin);
            Serial.printf("   Estado: %d\n", current);
            Serial.println(F("**************************************************************\n"));
        }
    }

    // 3. Processar comandos do teclado
    if (Serial.available()) {
        String cmd = Serial.readStringUntil('\n');
        cmd.trim();

        if (cmd == "w" || cmd == "W") {
            sweepAllServoPins();
        } else if (cmd == "a" || cmd == "A") {
            printAllPinsStatus();
        } else if (cmd == "i" || cmd == "I") {
            scanI2C();
        } else if (cmd == "h" || cmd == "H") {
            printBanner();
        } else if (cmd.startsWith("p") || cmd.startsWith("P")) {
            int pin = cmd.substring(1).toInt();
            if (pin > 0 && pin <= 33) {
                testSingleServoPin(static_cast<uint8_t>(pin));
            } else {
                Serial.printf("Pino invalido: %s. Use ex: p26 ou p27\n", cmd.c_str());
            }
        }
    }

    delay(25);
}
