#pragma once

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include "diagnostics/bench_diagnostics.h"

namespace diagnostics {

class WebBufferedConsole : public IConsole {
public:
    explicit WebBufferedConsole(Stream& stream = Serial) : stream_(stream) {}

    void clearBuffer() {
        buffer_.clear();
        preloaded_input_.clear();
    }

    void setPreloadedInput(const std::string& input) {
        preloaded_input_ = input;
    }

    const std::string& getOutput() const {
        return buffer_;
    }

    const std::string& getBuffer() const {
        return buffer_;
    }

    void print(const char* s) override {
        if (!s) return;
        stream_.print(s);
        appendBuffer(s);
    }

    void println(const char* s = "") override {
        stream_.println(s);
        appendBuffer(s);
        appendBuffer("\n");
    }

    void printf(const char* format, ...) override {
        char buf[256];
        va_list args;
        va_start(args, format);
        vsnprintf(buf, sizeof(buf), format, args);
        va_end(args);
        stream_.print(buf);
        appendBuffer(buf);
    }

    bool available() override {
        if (!preloaded_input_.empty()) return true;
        return stream_.available() > 0;
    }

    int read() override {
        if (!preloaded_input_.empty()) {
            char c = preloaded_input_.front();
            preloaded_input_.erase(preloaded_input_.begin());
            return c;
        }
        return stream_.read();
    }

    std::string readLine(uint32_t timeout_ms = 10000) override {
        if (!preloaded_input_.empty()) {
            std::string ret = preloaded_input_;
            preloaded_input_.clear();
            return ret;
        }
        uint32_t start = millis();
        String res = "";
        while (millis() - start < timeout_ms) {
            if (stream_.available() > 0) {
                char c = (char)stream_.read();
                if (c == '\n' || c == '\r') {
                    if (res.length() > 0) break;
                } else {
                    res += c;
                }
            }
            delay(10);
        }
        res.trim();
        return res.c_str();
    }

private:
    void appendBuffer(const char* s) {
        if (!s) return;
        if (buffer_.length() < 32768) {
            buffer_.append(s);
        }
    }

    Stream& stream_;
    std::string buffer_;
    std::string preloaded_input_;
};

class WebDiagnosticsServer {
public:
    WebDiagnosticsServer(BenchDiagnostics* diagnostics, WebBufferedConsole* console)
        : server_(80), diagnostics_(diagnostics), console_(console) {}

    void begin(const char* mdns_hostname = "thermoscan") {
        if (MDNS.begin(mdns_hostname)) {
            MDNS.addService("http", "tcp", 80);
            Serial.printf("[MDNS] Hostname ativo: http://%s.local\n", mdns_hostname);
        }

        server_.on("/", HTTP_GET, [this]() {
            handleRoot();
        });

        server_.on("/api/cmd", HTTP_POST, [this]() {
            handleApiCmd();
        });

        server_.on("/api/status", HTTP_GET, [this]() {
            handleApiStatus();
        });

        server_.begin();
        Serial.println(F("[WEB] Servidor de diagnostico HTTP iniciado na porta 80."));
    }

    void tick() {
        server_.handleClient();
    }

private:
    void handleRoot() {
        static const char HTML[] PROGMEM = R"rawliteral(<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>ThermoScan - Diagnóstico de Bancada</title>
<style>
:root{--bg:#121820;--panel:#1b2430;--card:#243040;--text:#e2e8f0;--muted:#94a3b8;--primary:#38bdf8;--accent:#f59e0b;--success:#22c55e;--danger:#ef4444;--code-bg:#0b0f14;}
*{box-sizing:border-box;margin:0;padding:0;font-family:system-ui,-apple-system,sans-serif;}
body{background:var(--bg);color:var(--text);padding:16px;min-height:100vh;}
.container{max-width:960px;margin:0 auto;}
header{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;background:var(--panel);padding:16px 20px;border-radius:12px;margin-bottom:16px;border:1px solid #2d3748;}
h1{font-size:1.3rem;display:flex;align-items:center;gap:8px;}
.badge{background:var(--card);color:var(--primary);padding:4px 10px;border-radius:20px;font-size:0.8rem;border:1px solid #334155;}
.status-bar{display:flex;gap:12px;flex-wrap:wrap;margin-top:8px;}
.status-pill{font-size:0.8rem;color:var(--muted);}
.status-pill span{color:var(--text);font-weight:600;}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px;margin-bottom:16px;}
button.btn{background:var(--card);color:var(--text);border:1px solid #334155;padding:12px 14px;border-radius:8px;font-size:0.9rem;cursor:pointer;display:flex;align-items:center;gap:8px;transition:all 0.15s;}
button.btn:hover{background:#2d3c50;border-color:var(--primary);color:#fff;}
button.btn:active{transform:scale(0.98);}
button.btn-primary{background:#0284c7;border-color:#38bdf8;color:#fff;}
button.btn-primary:hover{background:#0369a1;}
button.btn-accent{background:#b45309;border-color:#f59e0b;color:#fff;}
button.btn-accent:hover{background:#92400e;}
.cmd-box{display:flex;gap:8px;margin-bottom:16px;}
.cmd-box input{flex:1;background:var(--panel);border:1px solid #334155;border-radius:8px;padding:12px 16px;color:#fff;font-size:0.95rem;outline:none;}
.cmd-box input:focus{border-color:var(--primary);}
.terminal-wrapper{background:var(--panel);border-radius:12px;padding:16px;border:1px solid #2d3748;}
.terminal-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;}
.terminal-title{font-size:0.85rem;color:var(--muted);text-transform:uppercase;letter-spacing:1px;font-weight:700;}
.btn-sm{background:transparent;border:1px solid #475569;color:var(--muted);padding:4px 10px;border-radius:6px;font-size:0.75rem;cursor:pointer;}
.btn-sm:hover{background:#334155;color:#fff;}
pre#term{background:var(--code-bg);color:#38bdf8;padding:16px;border-radius:8px;font-family:'Courier New',monospace;font-size:0.85rem;line-height:1.45;height:400px;overflow-y:auto;white-space:pre-wrap;word-break:break-word;border:1px solid #1e293b;}
.spinner{display:none;width:14px;height:14px;border:2px solid #fff;border-top-color:transparent;border-radius:50%;animation:spin 0.6s linear infinite;}
@keyframes spin{to{transform:rotate(360deg);}}
</style>
</head>
<body>
<div class="container">
  <header>
    <div>
      <h1>⚡ ThermoScan <span class="badge">Diagnóstico v1.4.2</span></h1>
      <div class="status-bar" id="statusBar">
        <div class="status-pill">IP: <span id="ip">...</span></div>
        <div class="status-pill">Sinal: <span id="rssi">...</span></div>
        <div class="status-pill">RAM Livre: <span id="heap">...</span></div>
      </div>
    </div>
    <div style="margin-top:8px;">
      <button class="btn btn-primary" onclick="runCmd('diag all')">🚀 Rodar Todos (diag all)</button>
    </div>
  </header>

  <div class="grid">
    <button class="btn" onclick="runCmd('diag mlx')">🌡️ Câmera MLX90640</button>
    <button class="btn" onclick="runCmd('diag motor')">⚙️ Motor NEMA17 (+2cm)</button>
    <button class="btn" onclick="runCmd('diag homing')">🏠 Fim de Curso (Homing)</button>
    <button class="btn btn-accent" onclick="runCmd('diag pump')">💧 Bomba d'Água (Pulso)</button>
    <button class="btn" onclick="runCmd('diag camera-servo')">📐 Servo Câmera (Tilt)</button>
    <button class="btn" onclick="runCmd('diag ina')">⚡ Tensão/Corrente (INA219)</button>
    <button class="btn" onclick="runCmd('diag water')">🌊 Nível de Água</button>
    <button class="btn" onclick="runCmd('diag safety')">🛡️ Travas de Segurança</button>
    <button class="btn" onclick="runCmd('diag nvs')">💾 Memória Flash NVS</button>
    <button class="btn" onclick="runCmd('diag clock')">⏱️ Relógio NTP UTC</button>
    <button class="btn" onclick="runCmd('diag wifi')">📶 Conexão Wi-Fi</button>
    <button class="btn" onclick="runCmd('diag backend')">☁️ Ping Backend API</button>
  </div>

  <form class="cmd-box" onsubmit="event.preventDefault();submitCustom();">
    <input type="text" id="customCmd" placeholder="Digite um comando livre (ex: diag list, diag mlx)...">
    <button type="submit" class="btn btn-primary" id="btnSubmit">
      <div class="spinner" id="spin"></div>
      <span>Enviar</span>
    </button>
  </form>

  <div class="terminal-wrapper">
    <div class="terminal-header">
      <div class="terminal-title">Console de Saída</div>
      <button class="btn-sm" onclick="clearTerm()">Limpar</button>
    </div>
    <pre id="term">[SISTEMA] Conectado ao ThermoScan. Selecione um teste ou digite um comando.</pre>
  </div>
</div>

<script>
const term = document.getElementById('term');
const spin = document.getElementById('spin');
const btnSubmit = document.getElementById('btnSubmit');

function clearTerm() { term.textContent = ''; }

function appendTerm(txt) {
  term.textContent += '\n' + txt;
  term.scrollTop = term.scrollHeight;
}

function updateStatus() {
  fetch('/api/status')
    .then(r => r.json())
    .then(d => {
      document.getElementById('ip').textContent = d.ip || '-';
      document.getElementById('rssi').textContent = (d.rssi || 0) + ' dBm';
      document.getElementById('heap').textContent = Math.round((d.free_heap || 0)/1024) + ' KB';
    }).catch(() => {});
}

function runCmd(cmd) {
  if (!cmd) return;
  appendTerm('\n>>> Executando: ' + cmd + '...');
  spin.style.display = 'inline-block';
  btnSubmit.disabled = true;

  fetch('/api/cmd', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'cmd=' + encodeURIComponent(cmd)
  })
  .then(r => r.text())
  .then(txt => {
    appendTerm(txt);
  })
  .catch(err => {
    appendTerm('[ERRO] Falha de comunicacao HTTP: ' + err);
  })
  .finally(() => {
    spin.style.display = 'none';
    btnSubmit.disabled = false;
    updateStatus();
  });
}

function submitCustom() {
  const inp = document.getElementById('customCmd');
  const val = inp.value.trim();
  if (val) {
    runCmd(val);
    inp.value = '';
  }
}

updateStatus();
setInterval(updateStatus, 8000);
</script>
</body>
</html>)rawliteral";

        server_.send(200, "text/html; charset=utf-8", HTML);
    }

    void handleApiCmd() {
        if (!server_.hasArg("cmd")) {
            server_.send(400, "text/plain", "Parametro 'cmd' ausente.");
            return;
        }

        String cmd = server_.arg("cmd");
        cmd.trim();

        if (console_) {
            console_->clearBuffer();
            // Motor e bomba exigem confirmação ('s') no terminal; na web pré-autorizamos
            console_->setPreloadedInput("s\n");
        }

        if (diagnostics_) {
            diagnostics_->handleCommand(cmd.c_str());
        }

        std::string out = console_ ? console_->getOutput() : "Comando executado.";
        server_.send(200, "text/plain; charset=utf-8", out.c_str());
    }

    void handleApiStatus() {
        char buf[160];
        snprintf(buf, sizeof(buf),
                 "{\"ip\":\"%s\",\"rssi\":%d,\"free_heap\":%u}",
                 WiFi.localIP().toString().c_str(),
                 WiFi.RSSI(),
                 ESP.getFreeHeap());
        server_.send(200, "application/json", buf);
    }

    WebServer server_;
    BenchDiagnostics* diagnostics_{nullptr};
    WebBufferedConsole* console_{nullptr};
};

} // namespace diagnostics

#endif // ARDUINO || ESP32
