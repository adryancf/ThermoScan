#pragma once

#if defined(ARDUINO) || defined(ESP32)

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include "esp_log.h"
#include "diagnostics/bench_diagnostics.h"

namespace diagnostics {

// ============================================================================
// System Log Ring Buffer (Static, Non-blocking, Zero-Heap-Fragmentation)
// ============================================================================
class SystemLogRingBuffer {
public:
    static constexpr size_t BUFFER_SIZE = 32768; // 32 KB persistent log capacity

    void append(const char* data, size_t len) {
        if (!data || len == 0) return;
        portENTER_CRITICAL(&mux_);
        for (size_t i = 0; i < len; ++i) {
            buf_[write_pos_] = data[i];
            write_pos_ = (write_pos_ + 1) % BUFFER_SIZE;
            if (count_ < BUFFER_SIZE) {
                count_++;
            }
        }
        total_written_ += len;
        portEXIT_CRITICAL(&mux_);
    }

    void appendChar(char c) {
        append(&c, 1);
    }

    void clear() {
        portENTER_CRITICAL(&mux_);
        write_pos_ = 0;
        count_ = 0;
        portEXIT_CRITICAL(&mux_);
    }

    String getLogs() {
        String res;
        portENTER_CRITICAL(&mux_);
        if (count_ == 0) {
            portEXIT_CRITICAL(&mux_);
            return res;
        }
        res.reserve(count_ + 1);
        if (count_ < BUFFER_SIZE) {
            for (size_t i = 0; i < write_pos_; ++i) {
                res += buf_[i];
            }
        } else {
            for (size_t i = write_pos_; i < BUFFER_SIZE; ++i) {
                res += buf_[i];
            }
            for (size_t i = 0; i < write_pos_; ++i) {
                res += buf_[i];
            }
        }
        portEXIT_CRITICAL(&mux_);
        return res;
    }

    size_t getCount() const { return count_; }
    size_t getTotalWritten() const { return total_written_; }

private:
    char buf_[BUFFER_SIZE];
    size_t write_pos_{0};
    size_t count_{0};
    size_t total_written_{0};
    portMUX_TYPE mux_ = portMUX_INITIALIZER_UNLOCKED;
};

inline SystemLogRingBuffer& getGlobalLogBuffer() {
    static SystemLogRingBuffer s_log_buffer;
    return s_log_buffer;
}

// ============================================================================
// DualSerialProxy: Mirrors all Serial I/O to both Hardware Serial & Web Buffer
// ============================================================================
class DualSerialProxy : public Stream {
public:
    explicit DualSerialProxy(HardwareSerial& hw = Serial) : hw_(hw) {}

    void begin(unsigned long baud) {
        hw_.begin(baud);
    }

    void begin(unsigned long baud, uint32_t config) {
        hw_.begin(baud, config);
    }

    size_t write(uint8_t c) override {
        getGlobalLogBuffer().appendChar((char)c);
        return hw_.write(c);
    }

    size_t write(const uint8_t *buffer, size_t size) override {
        if (buffer && size > 0) {
            getGlobalLogBuffer().append((const char*)buffer, size);
        }
        return hw_.write(buffer, size);
    }

    int available() override { return hw_.available(); }
    int read() override { return hw_.read(); }
    int peek() override { return hw_.peek(); }
    void flush() override { hw_.flush(); }
    operator bool() const { return (bool)hw_; }

    using Print::write;
private:
    HardwareSerial& hw_;
};

inline DualSerialProxy& getGlobalDualSerial() {
    static DualSerialProxy s_instance(Serial);
    return s_instance;
}

// ============================================================================
// ESP-IDF VFS / Log Hook for automatic capture of ESP_LOG*, log_i, log_e
// ============================================================================
static vprintf_like_t s_orig_vprintf = nullptr;

static int web_log_vprintf_hook(const char *fmt, va_list args) {
    char buf[256];
    va_list copy;
    va_copy(copy, args);
    int len = vsnprintf(buf, sizeof(buf), fmt, copy);
    va_end(copy);
    if (len > 0) {
        getGlobalLogBuffer().append(buf, static_cast<size_t>(len));
    }
    if (s_orig_vprintf) {
        return s_orig_vprintf(fmt, args);
    }
    return vprintf(fmt, args);
}

inline void installEspLogHook() {
    s_orig_vprintf = esp_log_set_vprintf(web_log_vprintf_hook);
}

// ============================================================================
// WebBufferedConsole: Console interface for Bench Diagnostics
// ============================================================================
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

// ============================================================================
// WebDiagnosticsServer: Complete HTTP Diagnostics & Live Web Console Server
// ============================================================================
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

        server_.on("/api/logs", HTTP_GET, [this]() {
            handleApiLogs();
        });

        server_.on("/api/logs/clear", HTTP_POST, [this]() {
            handleApiLogsClear();
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
<title>ThermoScan - Diagnóstico & Live Serial</title>
<style>
:root{--bg:#10141b;--panel:#17202c;--card:#212d3d;--text:#e2e8f0;--muted:#94a3b8;--primary:#38bdf8;--accent:#f59e0b;--success:#22c55e;--danger:#ef4444;--code-bg:#080c10;}
*{box-sizing:border-box;margin:0;padding:0;font-family:system-ui,-apple-system,sans-serif;}
body{background:var(--bg);color:var(--text);padding:16px;min-height:100vh;}
.container{max-width:980px;margin:0 auto;}
header{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;background:var(--panel);padding:16px 20px;border-radius:12px;margin-bottom:16px;border:1px solid #283548;}
h1{font-size:1.3rem;display:flex;align-items:center;gap:8px;}
.badge{background:var(--card);color:var(--primary);padding:4px 10px;border-radius:20px;font-size:0.8rem;border:1px solid #334155;}
.status-bar{display:flex;gap:12px;flex-wrap:wrap;margin-top:8px;}
.status-pill{font-size:0.8rem;color:var(--muted);}
.status-pill span{color:var(--text);font-weight:600;}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px;margin-bottom:16px;}
button.btn{background:var(--card);color:var(--text);border:1px solid #334155;padding:12px 14px;border-radius:8px;font-size:0.9rem;cursor:pointer;display:flex;align-items:center;gap:8px;transition:all 0.15s;}
button.btn:hover{background:#28394e;border-color:var(--primary);color:#fff;}
button.btn:active{transform:scale(0.98);}
button.btn-primary{background:#0284c7;border-color:#38bdf8;color:#fff;}
button.btn-primary:hover{background:#0369a1;}
button.btn-accent{background:#b45309;border-color:#f59e0b;color:#fff;}
button.btn-accent:hover{background:#92400e;}
.cmd-box{display:flex;gap:8px;margin-bottom:16px;}
.cmd-box input{flex:1;background:var(--panel);border:1px solid #334155;border-radius:8px;padding:12px 16px;color:#fff;font-size:0.95rem;outline:none;}
.cmd-box input:focus{border-color:var(--primary);}
.terminal-wrapper{background:var(--panel);border-radius:12px;padding:16px;border:1px solid #283548;}
.terminal-header{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;margin-bottom:12px;gap:8px;}
.terminal-title{font-size:0.85rem;color:var(--primary);text-transform:uppercase;letter-spacing:1px;font-weight:700;}
.terminal-controls{display:flex;align-items:center;gap:10px;flex-wrap:wrap;}
.btn-sm{background:var(--card);border:1px solid #475569;color:var(--text);padding:6px 12px;border-radius:6px;font-size:0.75rem;cursor:pointer;display:flex;align-items:center;gap:4px;transition:all 0.15s;}
.btn-sm:hover{background:#334155;color:#fff;border-color:var(--primary);}
.btn-danger{border-color:#7f1d1d;color:#f87171;}
.btn-danger:hover{background:#991b1b;color:#fff;}
.checkbox-label{font-size:0.78rem;color:var(--muted);display:flex;align-items:center;gap:5px;cursor:pointer;user-select:none;}
.checkbox-label input{cursor:pointer;}
pre#term{background:var(--code-bg);color:#38bdf8;padding:16px;border-radius:8px;font-family:'Courier New',Consolas,monospace;font-size:0.85rem;line-height:1.45;height:450px;overflow-y:auto;white-space:pre-wrap;word-break:break-word;border:1px solid #1e293b;}
.spinner{display:none;width:14px;height:14px;border:2px solid #fff;border-top-color:transparent;border-radius:50%;animation:spin 0.6s linear infinite;}
@keyframes spin{to{transform:rotate(360deg);}}
.log-badge{background:#0f172a;border:1px solid #334155;padding:3px 8px;border-radius:12px;font-size:0.75rem;color:var(--muted);}
</style>
</head>
<body>
<div class="container">
  <header>
    <div>
      <h1>⚡ ThermoScan <span class="badge">Diagnóstico & Live Logs</span></h1>
      <div class="status-bar" id="statusBar">
        <div class="status-pill">IP: <span id="ip">...</span></div>
        <div class="status-pill">Sinal: <span id="rssi">...</span></div>
        <div class="status-pill">RAM Livre: <span id="heap">...</span></div>
        <div class="status-pill">Buffer Serial: <span id="bufSize">0 KB</span></div>
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
    <button class="btn" onclick="runCmd('diag nozzle-servo')">🎯 Servo Bico Lavagem</button>
    <button class="btn" onclick="runCmd('diag ina')">⚡ Tensão/Corrente (INA219)</button>
    <button class="btn" onclick="runCmd('diag water')">🌊 Nível de Água</button>
    <button class="btn" onclick="runCmd('diag safety')">🛡️ Travas de Segurança</button>
    <button class="btn" onclick="runCmd('diag nvs')">💾 Memória Flash NVS</button>
    <button class="btn" onclick="runCmd('diag clock')">⏱️ Relógio NTP UTC</button>
    <button class="btn" onclick="runCmd('diag backend')">☁️ Ping Backend API</button>
  </div>

  <form class="cmd-box" onsubmit="event.preventDefault();submitCustom();">
    <input type="text" id="customCmd" placeholder="Digite um comando de diagnóstico (ex: diag list, diag scan, diag mlx)...">
    <button type="submit" class="btn btn-primary" id="btnSubmit">
      <div class="spinner" id="spin"></div>
      <span>Enviar</span>
    </button>
  </form>

  <div class="terminal-wrapper">
    <div class="terminal-header">
      <div style="display:flex;align-items:center;gap:12px;">
        <span class="terminal-title">📡 Live Serial Console & Logs</span>
        <span class="log-badge" id="liveIndicator">🟢 Ao Vivo</span>
      </div>
      <div class="terminal-controls">
        <label class="checkbox-label">
          <input type="checkbox" id="liveToggle" checked onchange="toggleLiveStream()"> Streaming (1s)
        </label>
        <label class="checkbox-label">
          <input type="checkbox" id="autoScroll" checked> Auto-Scroll
        </label>
        <button class="btn-sm" onclick="fetchLiveLogs()">🔄 Atualizar</button>
        <button class="btn-sm" onclick="copyLogs()">📋 Copiar</button>
        <button class="btn-sm btn-danger" onclick="clearLiveLogs()">🗑️ Limpar</button>
      </div>
    </div>
    <pre id="term">[SISTEMA] Conectando ao fluxo serial do ThermoScan...</pre>
  </div>
</div>

<script>
const term = document.getElementById('term');
const spin = document.getElementById('spin');
const btnSubmit = document.getElementById('btnSubmit');
const liveIndicator = document.getElementById('liveIndicator');
const bufSizeSpan = document.getElementById('bufSize');

let liveInterval = null;
let isFetchingLogs = false;

function fetchLiveLogs() {
  if (isFetchingLogs) return;
  isFetchingLogs = true;
  fetch('/api/logs')
    .then(r => r.text())
    .then(txt => {
      if (txt.length > 0) {
        term.textContent = txt;
        bufSizeSpan.textContent = Math.round(txt.length / 1024) + ' KB';
        if (document.getElementById('autoScroll').checked) {
          term.scrollTop = term.scrollHeight;
        }
      }
    })
    .catch(() => {})
    .finally(() => { isFetchingLogs = false; });
}

function toggleLiveStream() {
  const enabled = document.getElementById('liveToggle').checked;
  if (enabled) {
    liveIndicator.textContent = '🟢 Ao Vivo';
    liveIndicator.style.color = 'var(--success)';
    if (!liveInterval) {
      liveInterval = setInterval(fetchLiveLogs, 1000);
      fetchLiveLogs();
    }
  } else {
    liveIndicator.textContent = '⏸️ Pausado';
    liveIndicator.style.color = 'var(--accent)';
    if (liveInterval) {
      clearInterval(liveInterval);
      liveInterval = null;
    }
  }
}

function clearLiveLogs() {
  if (!confirm('Deseja realmente limpar o buffer de logs no ESP32?')) return;
  fetch('/api/logs/clear', {method: 'POST'})
    .then(r => r.text())
    .then(txt => {
      term.textContent = txt;
      bufSizeSpan.textContent = '0 KB';
    })
    .catch(e => {
      alert('Falha ao limpar logs: ' + e);
    });
}

function copyLogs() {
  if (navigator.clipboard && term.textContent) {
    navigator.clipboard.writeText(term.textContent)
      .then(() => alert('Logs copiados com sucesso!'))
      .catch(() => alert('Não foi possível copiar automaticamente.'));
  }
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
  spin.style.display = 'inline-block';
  btnSubmit.disabled = true;

  fetch('/api/cmd', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'cmd=' + encodeURIComponent(cmd)
  })
  .then(r => r.text())
  .then(txt => {
    // If live stream is disabled, append result directly
    if (!document.getElementById('liveToggle').checked) {
      term.textContent += '\n' + txt;
      term.scrollTop = term.scrollHeight;
    } else {
      // With live stream, immediate fetch will show all outputs
      setTimeout(fetchLiveLogs, 150);
    }
  })
  .catch(err => {
    term.textContent += '\n[ERRO] Falha de comunicacao HTTP: ' + err;
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
toggleLiveStream();
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

    void handleApiLogs() {
        String logs = getGlobalLogBuffer().getLogs();
        server_.send(200, "text/plain; charset=utf-8", logs);
    }

    void handleApiLogsClear() {
        getGlobalLogBuffer().clear();
        server_.send(200, "text/plain; charset=utf-8", "[LOGS] Buffer limpo com sucesso.\n");
    }

    WebServer server_;
    BenchDiagnostics* diagnostics_{nullptr};
    WebBufferedConsole* console_{nullptr};
};

} // namespace diagnostics

#endif // ARDUINO || ESP32
