#include <Arduino.h>
#include <Wire.h>
#include <ESP32Servo.h>
#include "pinout.h"

// Servo da camera
static Servo g_camera_servo;

// Ultimos estados para detectar mudancas em tempo real
static int last_limit_state = -1;
static int last_water_state = -1;
static unsigned long last_periodic_print = 0;

void scanI2C() {
    Serial.println(F("\n--- [1] VARREDURA DO BARRAMENTO I2C (SDA=21, SCL=22) ---"));
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(100000); // 100 kHz padrao

    byte error, address;
    int nDevices = 0;
    bool found_mlx = false;
    int ina_count = 0;

    for (address = 1; address < 127; address++) {
        Wire.beginTransmission(address);
        error = Wire.endTransmission();

        if (error == 0) {
            Serial.printf("  [OK] Dispositivo I2C encontrado no endereco 0x%02X: ", address);
            if (address == 0x33) {
                Serial.println(F("--> CAMERA TERMICA MLX90640 CONFIRMADA!"));
                found_mlx = true;
            } else if (address == 0x40) {
                Serial.println(F("--> SENSOR INA219 #1 CONFIRMADO! (Endereco padrao 0x40)"));
                ina_count++;
            } else if (address == 0x41) {
                Serial.println(F("--> SENSOR INA219 #2 CONFIRMADO! (Endereco 0x41 - Jumper A0 soldado)"));
                ina_count++;
            } else if (address == 0x44) {
                Serial.println(F("--> SENSOR INA219 #2 CONFIRMADO! (Endereco 0x44 - Jumper A1 soldado)"));
                ina_count++;
            } else if (address == 0x45) {
                Serial.println(F("--> SENSOR INA219 #2 CONFIRMADO! (Endereco 0x45 - Jumpers A0+A1 soldados)"));
                ina_count++;
            } else {
                Serial.println(F("--> Outro dispositivo I2C"));
            }
            nDevices++;
        } else if (error == 4) {
            Serial.printf("  [ERRO] Erro desconhecido no endereco 0x%02X\n", address);
        }
    }

    if (nDevices == 0) {
        Serial.println(F("  [FALHA] Nenhum dispositivo I2C encontrado no GPIO 21 (SDA) e GPIO 22 (SCL)."));
        Serial.println(F("          Verifique se 3.3V e GND estao ligados e se SDA/SCL nao estao invertidos."));
    } else {
        Serial.printf("  Total de dispositivos I2C detectados: %d\n", nDevices);
        if (!found_mlx) Serial.println(F("  [AVISO] Camera MLX90640 (0x33) NAO respondeu."));
        if (ina_count == 0) {
            Serial.println(F("  [AVISO] Nenhum sensor INA219 respondeu."));
        } else if (ina_count == 1) {
            Serial.println(F("  [ATENCAO] Apenas 1 INA219 foi detectado! Se o segundo estiver conectado,"));
            Serial.println(F("            ele pode estar no mesmo endereco (0x40) em conflito ou sem alimentacao."));
        } else {
            Serial.printf("  [SUCESSO] %d sensores INA219 detectados com sucesso em enderecos distintos!\n", ina_count);
        }
    }
    Serial.println(F("---------------------------------------------------------"));
}

void testMotorPulse() {
    Serial.println(F("\n[TESTE MOTOR] Habilitando driver (EN=5) e enviando 50 passos (STEP=19, DIR=18)..."));
    digitalWrite(STEPPER_EN_PIN, LOW); // Ativo LOW
    digitalWrite(STEPPER_DIR_PIN, HIGH);
    delay(10);

    for (int i = 0; i < 50; i++) {
        digitalWrite(STEPPER_STEP_PIN, HIGH);
        delayMicroseconds(1000);
        digitalWrite(STEPPER_STEP_PIN, LOW);
        delayMicroseconds(1000);
    }

    digitalWrite(STEPPER_EN_PIN, HIGH); // Desabilita motor para nao aquecer
    Serial.println(F("[TESTE MOTOR] Concluido. O eixo do motor deu um pequeno giro?"));
}

void testPumpPulse() {
    Serial.println(F("\n[TESTE BOMBA] Enviando pulso de 200 ms no MOSFET (GPIO 25)..."));
    digitalWrite(PUMP_MOSFET_PIN, HIGH);
    delay(200);
    digitalWrite(PUMP_MOSFET_PIN, LOW);
    Serial.println(F("[TESTE BOMBA] Desligada com seguranca."));
}

void testCameraServo() {
    Serial.printf("\n[TESTE SERVO CAMERA] Articulando servo da camera (GPIO %d)...\n", CAMERA_SERVO_PWM_PIN);
    Serial.println(F("  -> Movendo para 45 graus"));
    g_camera_servo.write(45);
    delay(500);
    Serial.println(F("  -> Movendo para 90 graus"));
    g_camera_servo.write(90);
    delay(500);
    Serial.printf("  -> Retornando para angulo padrao (%.1f graus)\n", CAMERA_DEFAULT_ANGLE);
    g_camera_servo.write(static_cast<int>(CAMERA_DEFAULT_ANGLE));
    Serial.println(F("[TESTE SERVO CAMERA] Concluido. O servo da camera articulou corretamente?"));
}

void printMenu() {
    Serial.println(F("\n========================================================"));
    Serial.println(F("           ThermoScan - VALIDADOR DE PINOUT E SENSORES  "));
    Serial.println(F("========================================================"));
    Serial.println(F("Pinos monitorados:"));
    Serial.printf("  I2C SDA:            GPIO %d\n", I2C_SDA_PIN);
    Serial.printf("  I2C SCL:            GPIO %d\n", I2C_SCL_PIN);
    Serial.printf("  Fim de Curso (NC):  GPIO %d (INPUT_PULLUP)\n", STEPPER_LIMIT_NC_PIN);
    Serial.printf("  Nivel de Agua:      GPIO %d (INPUT)\n", WATER_SENSOR_PIN);
    Serial.printf("  Motor STEP/DIR/EN:  GPIO %d / %d / %d\n", STEPPER_STEP_PIN, STEPPER_DIR_PIN, STEPPER_EN_PIN);
    Serial.printf("  Bomba MOSFET:       GPIO %d\n", PUMP_MOSFET_PIN);
    Serial.printf("  Servo Mangueira:    GPIO %d\n", SERVO_PWM_PIN);
    Serial.printf("  Servo Camera:       GPIO %d (Padrao: %.1f deg)\n", CAMERA_SERVO_PWM_PIN, CAMERA_DEFAULT_ANGLE);
    Serial.println(F("--------------------------------------------------------"));
    Serial.println(F("COMANDOS TECLADO (digite a letra e aperte Enter):"));
    Serial.println(F("  's' -> Fazer nova varredura do barramento I2C"));
    Serial.println(F("  'm' -> Testar pequeno giro no motor de passo"));
    Serial.println(F("  'b' -> Testar pulso rapido de 200 ms na bomba"));
    Serial.println(F("  'c' -> Testar articulacao do servo da camera"));
    Serial.println(F("  'h' -> Exibir este menu novamente"));
    Serial.println(F("========================================================"));
}

void setup() {
    Serial.begin(115200);
    delay(600);

    // Configuracao segura inicial das saidas
    pinMode(PUMP_MOSFET_PIN, OUTPUT);
    digitalWrite(PUMP_MOSFET_PIN, LOW); // Garante bomba desligada

    pinMode(STATUS_LED_PIN, OUTPUT);
    digitalWrite(STATUS_LED_PIN, HIGH);

    pinMode(STEPPER_STEP_PIN, OUTPUT);
    pinMode(STEPPER_DIR_PIN, OUTPUT);
    pinMode(STEPPER_EN_PIN, OUTPUT);
    digitalWrite(STEPPER_EN_PIN, HIGH); // Desabilitado em repouso

    // Configuracao do servo da camera
    g_camera_servo.setPeriodHertz(50);
    g_camera_servo.attach(CAMERA_SERVO_PWM_PIN, 500, 2500);
    g_camera_servo.write(static_cast<int>(CAMERA_DEFAULT_ANGLE));

    // Configuracao das entradas
    pinMode(STEPPER_LIMIT_NC_PIN, INPUT_PULLUP);
    pinMode(WATER_SENSOR_PIN, INPUT);

    printMenu();

    // Executa varredura inicial do I2C
    scanI2C();

    Serial.println(F("\n[MONITOR AO VIVO] Teste os sensores com a mao:"));
    Serial.println(F("  - Aperte a chave de fim de curso para ver a mudanca instantanea."));
    Serial.println(F("  - Molhe ou encoste no sensor de agua para ver a deteccao.\n"));
}

void loop() {
    // 1. Ler entradas digitais
    int cur_limit = digitalRead(STEPPER_LIMIT_NC_PIN);
    int cur_water = digitalRead(WATER_SENSOR_PIN);

    // Detectar mudanca no Fim de Curso
    if (cur_limit != last_limit_state) {
        last_limit_state = cur_limit;
        if (cur_limit == LOW) {
            // Com pullup, contato fechado leva a GND (LOW). No microswitch NC, repouso = LOW, pressionado = HIGH (ou vice-versa dependendo da ligacao C/NC/NO).
            Serial.printf(">>> [FIM DE CURSO - GPIO %d] Estado mudou para: LOW (0) [CONTATO FECHADO / GND]\n", STEPPER_LIMIT_NC_PIN);
        } else {
            Serial.printf(">>> [FIM DE CURSO - GPIO %d] Estado mudou para: HIGH (1) [CONTATO ABERTO / PULLUP]\n", STEPPER_LIMIT_NC_PIN);
        }
    }

    // Detectar mudanca no Sensor de Agua
    if (cur_water != last_water_state) {
        last_water_state = cur_water;
        if (cur_water == HIGH) {
            Serial.printf(">>> [NIVEL DE AGUA - GPIO %d] Estado mudou para: HIGH (1) [AGUA DETECTADA]\n", WATER_SENSOR_PIN);
        } else {
            Serial.printf(">>> [NIVEL DE AGUA - GPIO %d] Estado mudou para: LOW (0) [SECO / SEM AGUA]\n", WATER_SENSOR_PIN);
        }
    }

    // Print periodico de status a cada 2 segundos
    if (millis() - last_periodic_print > 2000) {
        last_periodic_print = millis();
        Serial.printf("[STATUS VIVO] Fim de Curso (GPIO %d): %s | Nivel Agua (GPIO %d): %s\n",
                      STEPPER_LIMIT_NC_PIN,
                      (cur_limit == LOW) ? "FECHADO (0)" : "ABERTO (1)",
                      WATER_SENSOR_PIN,
                      (cur_water == HIGH) ? "COM AGUA (1)" : "SECO (0)");
    }

    // 2. Processar comandos do usuario
    if (Serial.available()) {
        char c = Serial.read();
        if (c == 's' || c == 'S') {
            scanI2C();
        } else if (c == 'm' || c == 'M') {
            testMotorPulse();
        } else if (c == 'b' || c == 'B') {
            testPumpPulse();
        } else if (c == 'c' || c == 'C') {
            testCameraServo();
        } else if (c == 'h' || c == 'H') {
            printMenu();
        }
    }

    delay(20);
}

