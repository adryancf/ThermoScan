// #include <Arduino.h>
// #include <Wire.h>
// #include <math.h>
// #include <Adafruit_MLX90640.h>

// Adafruit_MLX90640 mlx;
// float frame[32 * 24];

// void setup() {
//   Serial.begin(115200);
//   delay(1000);

//   Wire.begin(21, 22);      // SDA, SCL — ESP32 clássico
//   Wire.setClock(100000);   // Começa com I2C a 100 kHz

//   Serial.println("Iniciando MLX90640...");

//   if (!mlx.begin(0x33, &Wire)) {
//     Serial.println("ERRO: sensor nao iniciou. Confira os contatos.");
//     while (true) delay(1000);
//   }

//   mlx.setMode(MLX90640_CHESS);
//   mlx.setRefreshRate(MLX90640_2_HZ);

//   Serial.println("Sensor iniciado. Aponte para o ambiente e depois para a mao.");
// }

// void loop() {
//   if (mlx.getFrame(frame) != 0) {
//     Serial.println("ERRO: nao consegui ler um quadro. Verifique os contatos.");
//     delay(1000);
//     return;
//   }

//   float menor = INFINITY;
//   float maior = -INFINITY;
//   int validos = 0;

//   for (int i = 0; i < 32 * 24; i++) {
//     if (!isfinite(frame[i])) continue;

//     if (frame[i] < menor) menor = frame[i];
//     if (frame[i] > maior) maior = frame[i];
//     validos++;
//   }

//   Serial.print("Ambiente: ");
//   Serial.print(mlx.getTa(false), 1);
//   Serial.print(" C | Menor: ");
//   Serial.print(menor, 1);
//   Serial.print(" C | Maior: ");
//   Serial.print(maior, 1);
//   Serial.print(" C | Centro: ");
//   Serial.print(frame[12 * 32 + 16], 1);
//   Serial.print(" C | Pixels validos: ");
//   Serial.print(validos);
//   Serial.println("/768");

//   delay(500);
// }