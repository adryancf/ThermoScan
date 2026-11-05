#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_MLX90640.h>

Adafruit_MLX90640 mlx;
float frame[32 * 24];

void setup() {
  Serial.begin(115200);
  delay(1000);

  Wire.begin(21, 22);    // SDA, SCL
  Wire.setClock(400000);

  if (!mlx.begin(0x33, &Wire)) {
    Serial.println("ERRO: sensor nao iniciou. Confira os contatos.");
    while (true) delay(1000);
  }

  mlx.setMode(MLX90640_CHESS);
  mlx.setRefreshRate(MLX90640_4_HZ);
}

void loop() {
  if (mlx.getFrame(frame) != 0) {
    return;
  }

  Serial.print("FRAME");
  for (int i = 0; i < 32 * 24; i++) {
    Serial.print(",");
    Serial.print(frame[i], 2);
  }
  Serial.println();
}