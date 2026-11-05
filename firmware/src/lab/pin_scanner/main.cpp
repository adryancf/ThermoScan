#include <Arduino.h>
#include <Wire.h>
#include <ESP32Servo.h>

// Candidate pins for Digital Inputs (Endstops and Sensors)
// GPIOs with internal INPUT_PULLUP support on ESP32:
static const uint8_t INPUT_PULLUP_PINS[] = {
    4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33
};
static const size_t NUM_PULLUP_PINS = sizeof(INPUT_PULLUP_PINS) / sizeof(INPUT_PULLUP_PINS[0]);

// Input-only GPIOs (no internal pullup, analog/digital sensors):
static const uint8_t INPUT_ONLY_PINS[] = { 34, 35, 36, 39 };
static const size_t NUM_INPUT_ONLY_PINS = sizeof(INPUT_ONLY_PINS) / sizeof(INPUT_ONLY_PINS[0]);

// Candidate pins for Servos (PWM output):
static const uint8_t CANDIDATE_SERVO_PINS[] = { 26, 27, 14, 13, 12, 4, 16, 17, 32, 33, 25, 18, 19, 5 };
static const size_t NUM_SERVO_PINS = sizeof(CANDIDATE_SERVO_PINS) / sizeof(CANDIDATE_SERVO_PINS[0]);

// Stores previous state of all input pins
static int last_pullup_states[NUM_PULLUP_PINS];
static int last_input_states[NUM_INPUT_ONLY_PINS];

static Servo g_probe_servo;

void printBanner() {
    Serial.println(F("\n=============================================================="));
    Serial.println(F("       🔍 THERMOSCAN PIN DETECTIVE (SENSORS & SERVOS)"));
    Serial.println(F("=============================================================="));
    Serial.println(F("1. ENDSTOPS:"));
    Serial.println(F("   -> PRESS the switch by hand. The terminal reports the GPIO instantly."));
    Serial.println(F(""));
    Serial.println(F("2. WATER SENSOR:"));
    Serial.println(F("   -> Dip sensor into water (or touch with a wet finger)"));
    Serial.println(F("      and release. The terminal logs state change and GPIO!"));
    Serial.println(F("   -> Or type 'a' to inspect ALL pins immediately."));
    Serial.println(F(""));
    Serial.println(F("3. SERVOS (Nozzle & Camera):"));
    Serial.println(F("   -> Type 'w' to sweep all candidate servo pins."));
    Serial.println(F("   -> Type 'p13' or 'p32' to test a specific pin."));
    Serial.println(F(""));
    Serial.println(F("4. OTHER COMMANDS:"));
    Serial.println(F("   -> 'a' -> Show CURRENT state (Digital and Analog) of all pins"));
    Serial.println(F("   -> 'i' -> Run I2C bus scan (MLX90640 Camera and INA219)"));
    Serial.println(F("   -> 'h' -> Show this menu"));
    Serial.println(F("=============================================================="));
    Serial.println(F("👀 Monitoring in real time... toggle a sensor now!\n"));
}

void printAllPinsStatus() {
    Serial.println(F("\n--- [X-RAY: CURRENT STATE OF ALL PINS] ---"));
    Serial.println(F("Digital Pins (with Pull-up):"));
    for (size_t i = 0; i < NUM_PULLUP_PINS; ++i) {
        uint8_t pin = INPUT_PULLUP_PINS[i];
        int val = digitalRead(pin);
        Serial.printf("  GPIO %2d: %s (%d)\n", pin, (val == LOW ? "LOW (0V / GND)" : "HIGH (3.3V)"), val);
    }
    Serial.println(F("\nInput-Only Pins (34, 35, 36, 39):"));
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
    Serial.println(F("\n--- [I2C SCAN ON GPIO 21 (SDA) AND GPIO 22 (SCL)] ---"));
    Wire.begin(21, 22);
    byte error, address;
    int nDevices = 0;

    for (address = 1; address < 127; address++) {
        Wire.beginTransmission(address);
        error = Wire.endTransmission();

        if (error == 0) {
            Serial.printf("  [OK] Device at address 0x%02X: ", address);
            if (address == 0x33) Serial.println(F("--> MLX90640 Thermal Camera"));
            else if (address == 0x40) Serial.println(F("--> INA219 #1 (Default 0x40)"));
            else if (address == 0x41) Serial.println(F("--> INA219 #2 (Jumper A0)"));
            else if (address == 0x44) Serial.println(F("--> INA219 #2 (Jumper A1)"));
            else Serial.println(F("--> Other I2C device"));
            nDevices++;
        }
    }
    if (nDevices == 0) Serial.println(F("  [!] No I2C device found on 21/22."));
    Serial.println(F("---------------------------------------------------------"));
}

void sweepAllServoPins() {
    Serial.println(F("\n=============================================================="));
    Serial.println(F("🤖 STARTING SERVO SWEEP ACROSS CANDIDATE PINS"));
    Serial.println(F("   Watch the nozzle and camera move!"));
    Serial.println(F("=============================================================="));

    for (size_t i = 0; i < NUM_SERVO_PINS; ++i) {
        uint8_t pin = CANDIDATE_SERVO_PINS[i];
        Serial.printf("\n>>> TESTING NOW: GPIO %d ...\n", pin);
        Serial.println(F("    Moving servo to 45 degrees..."));

        g_probe_servo.setPeriodHertz(50);
        g_probe_servo.attach(pin, 500, 2500);
        g_probe_servo.write(45);
        delay(600);

        Serial.println(F("    Moving servo to 90 degrees..."));
        g_probe_servo.write(90);
        delay(600);

        g_probe_servo.detach();
        Serial.printf("    End of test on GPIO %d. (Did any servo move?)\n", pin);
        delay(400);
    }

    Serial.println(F("\n=============================================================="));
    Serial.println(F("Servo sweep completed! Record corresponding pins."));
    Serial.println(F("==============================================================\n"));
}

void testSingleServoPin(uint8_t pin) {
    Serial.printf("\n[SERVO TEST] Testing GPIO %d specifically...\n", pin);
    g_probe_servo.setPeriodHertz(50);
    g_probe_servo.attach(pin, 500, 2500);
    g_probe_servo.write(30);
    delay(500);
    g_probe_servo.write(120);
    delay(500);
    g_probe_servo.write(90);
    delay(300);
    g_probe_servo.detach();
    Serial.printf("[SERVO TEST] Completed on GPIO %d.\n", pin);
}

void setup() {
    Serial.begin(115200);
    delay(500);

    // Initialize all pullup pins as inputs
    for (size_t i = 0; i < NUM_PULLUP_PINS; ++i) {
        pinMode(INPUT_PULLUP_PINS[i], INPUT_PULLUP);
        last_pullup_states[i] = digitalRead(INPUT_PULLUP_PINS[i]);
    }

    // Initialize input-only pins
    for (size_t i = 0; i < NUM_INPUT_ONLY_PINS; ++i) {
        pinMode(INPUT_ONLY_PINS[i], INPUT);
        last_input_states[i] = digitalRead(INPUT_ONLY_PINS[i]);
    }

    printBanner();
}

void loop() {
    // 1. Detect state change on any PULLUP pin (Endstops)
    for (size_t i = 0; i < NUM_PULLUP_PINS; ++i) {
        uint8_t pin = INPUT_PULLUP_PINS[i];
        int current = digitalRead(pin);

        if (current != last_pullup_states[i]) {
            last_pullup_states[i] = current;

            Serial.println(F("\n**************************************************************"));
            Serial.printf("🎯 DETECTION ON GPIO %d !\n", pin);
            if (current == LOW) {
                Serial.printf("   State changed to: LOW (0V / CONTACT CLOSED TO GND)\n");
            } else {
                Serial.printf("   State changed to: HIGH (3.3V / CONTACT OPEN / PULLUP)\n");
            }
            Serial.printf("   --> If you just pressed the endstop, this is GPIO %d!\n", pin);
            Serial.println(F("**************************************************************\n"));
        }
    }

    // 2. Detect change on Input-only pins (34-39)
    for (size_t i = 0; i < NUM_INPUT_ONLY_PINS; ++i) {
        uint8_t pin = INPUT_ONLY_PINS[i];
        int current = digitalRead(pin);

        if (current != last_input_states[i]) {
            last_input_states[i] = current;
            Serial.println(F("\n**************************************************************"));
            Serial.printf("🎯 DETECTION ON GPIO %d (Input Only)!\n", pin);
            Serial.printf("   State: %d\n", current);
            Serial.println(F("**************************************************************\n"));
        }
    }

    // 3. Process keyboard commands
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
                Serial.printf("Invalid pin: %s. Use e.g. p26 or p27\n", cmd.c_str());
            }
        }
    }

    delay(25);
}
