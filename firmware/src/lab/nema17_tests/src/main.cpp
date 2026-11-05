#include <Arduino.h>

const int EN = 21, STEP = 19, DIR = 18;

void setup() {
  pinMode(EN, OUTPUT);
  pinMode(STEP, OUTPUT);
  pinMode(DIR, OUTPUT);
  digitalWrite(EN, LOW);
  digitalWrite(DIR, HIGH);
}

void loop() {
  for (int i = 0; i < 200; i++) {
    digitalWrite(STEP, HIGH);
    delayMicroseconds(1000);
    digitalWrite(STEP, LOW);
    delayMicroseconds(1000);
  }
  digitalWrite(DIR, !digitalRead(DIR));
  delay(500);
}
