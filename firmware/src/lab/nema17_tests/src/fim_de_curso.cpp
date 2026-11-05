// #include <Arduino.h>

// // ---------- Motor / DRV8825 ----------
// const int EN   = 21;   // LOW = driver habilitado
// const int STEP = 19;   // Cada pulso = 1 passo
// const int DIR  = 18;   // Sentido de rotação

// // ---------- Fim de curso ----------
// const int FIM_CURSO = 22;
// const bool STATUS_FIM_DE_CURSO = true; // true  = apertado lê LOW  (fio entre GPIO e GND, usando INPUT_PULLUP) | false = apertado lê HIGH

// // ---------- Movimento ----------
// const int PASSOS_PARA_VOLTAR = 20;
// const int INTERVALO_US = 1000;     // meio período do pulso; 1000 us = 500 passos/s

// // Direção inicial de movimento
// const int DIRECAO_INICIAL = HIGH;

// void darPassos(int passos, int direcao) {
//   digitalWrite(DIR, direcao);

//   for (int i = 0; i < passos; i++) {
//     digitalWrite(STEP, HIGH);
//     delayMicroseconds(INTERVALO_US);
//     digitalWrite(STEP, LOW);
//     delayMicroseconds(INTERVALO_US);
//   }
// }

// bool fimDeCursoApertado() {
//   int leitura = digitalRead(FIM_CURSO);

//   if (STATUS_FIM_DE_CURSO) {
//     return leitura == LOW;
//   } else {
//     return leitura == HIGH;
//   }
// }

// void setup() {
//   Serial.begin(115200);

//   pinMode(EN, OUTPUT);
//   pinMode(STEP, OUTPUT);
//   pinMode(DIR, OUTPUT);

//   pinMode(FIM_CURSO, INPUT_PULLUP);

//   digitalWrite(EN, LOW); // habilita o DRV8825
//   digitalWrite(DIR, DIRECAO_INICIAL);

//   Serial.println("Pronto. Motor vai andar ate o fim de curso.");
// }

// void loop() {
//   digitalWrite(DIR, DIRECAO_INICIAL);

//   digitalWrite(STEP, HIGH);
//   delayMicroseconds(INTERVALO_US);
//   digitalWrite(STEP, LOW);
//   delayMicroseconds(INTERVALO_US);

//   if (fimDeCursoApertado()) {
//     Serial.println("Fim de curso acionado.");

//     int direcaoVolta = !DIRECAO_INICIAL;
//     darPassos(PASSOS_PARA_VOLTAR, direcaoVolta);

//     Serial.println("Parado.");
//     while (true) {
//       // Para definitivamente
//       delay(100);
//     }
//   }
// }