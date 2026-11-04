#ifndef THERMOSCAN_HAL_NATIVE_NET_COMPAT_H
#define THERMOSCAN_HAL_NATIVE_NET_COMPAT_H

#if !defined(ARDUINO) && !defined(ESP32)

#include <string>
#include <vector>
#include <map>
#include <sstream>
#include <iostream>
#include <cstring>
#include <cstdlib>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>

using String = std::string;
static const int HTTP_CODE_OK = 200;
static const int HTTP_CODE_CREATED = 201;
static const int WL_CONNECTED = 3;

class NativeWiFiClass {
public:
    std::string macAddress() const { return mac_; }
    void setMacAddress(const std::string& mac) { mac_ = mac; }
    int status() const { return connected_ ? WL_CONNECTED : 0; }
    void setConnected(bool c) { connected_ = c; }

private:
    std::string mac_{"02:00:00:00:00:01"};
    bool connected_{true};
};

inline NativeWiFiClass& getGlobalNativeWiFi() {
    static NativeWiFiClass wifi_instance;
    return wifi_instance;
}

#define WiFi getGlobalNativeWiFi()

class HTTPClient {
public:
    HTTPClient() = default;
    ~HTTPClient() { end(); }

    bool begin(const std::string& url) {
        url_ = url;
        headers_.clear();
        response_body_.clear();
        return parseUrl(url);
    }

    void addHeader(const std::string& name, const std::string& value) {
        headers_[name] = value;
    }

    int POST(const std::string& body) {
        return executeRequest("POST", body);
    }

    int GET() {
        return executeRequest("GET", "");
    }

    const std::string& getString() const {
        return response_body_;
    }

    void end() {
        if (sock_ >= 0) {
            close(sock_);
            sock_ = -1;
        }
    }

private:
    std::string url_;
    std::string host_{"localhost"};
    int port_{80};
    std::string path_{"/"};
    std::map<std::string, std::string> headers_;
    std::string response_body_;
    int sock_{-1};

    bool parseUrl(const std::string& url) {
        std::string s = url;
        size_t proto_pos = s.find("://");
        if (proto_pos != std::string::npos) {
            std::string proto = s.substr(0, proto_pos);
            if (proto == "https") {
                port_ = 443;
            } else {
                port_ = 80;
            }
            s = s.substr(proto_pos + 3);
        } else {
            port_ = 80;
        }

        size_t path_pos = s.find('/');
        std::string host_port;
        if (path_pos != std::string::npos) {
            host_port = s.substr(0, path_pos);
            path_ = s.substr(path_pos);
        } else {
            host_port = s;
            path_ = "/";
        }

        size_t colon_pos = host_port.find(':');
        if (colon_pos != std::string::npos) {
            host_ = host_port.substr(0, colon_pos);
            port_ = std::atoi(host_port.substr(colon_pos + 1).c_str());
        } else {
            host_ = host_port;
        }
        return true;
    }

    int executeRequest(const std::string& method, const std::string& body) {
        end();
        struct addrinfo hints{}, *res = nullptr;
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;

        std::string port_str = std::to_string(port_);
        int err = getaddrinfo(host_.c_str(), port_str.c_str(), &hints, &res);
        if (err != 0 || res == nullptr) {
            return -1;
        }

        sock_ = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (sock_ < 0) {
            freeaddrinfo(res);
            return -1;
        }

        struct timeval tv{10, 0}; // 10 second timeout
        setsockopt(sock_, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(sock_, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        if (connect(sock_, res->ai_addr, res->ai_addrlen) < 0) {
            freeaddrinfo(res);
            end();
            return -1;
        }
        freeaddrinfo(res);

        std::ostringstream req;
        req << method << " " << path_ << " HTTP/1.1\r\n";
        req << "Host: " << host_ << ":" << port_ << "\r\n";
        req << "User-Agent: ThermoScan-Firmware-Native/1.0\r\n";
        req << "Connection: close\r\n";

        for (const auto& kv : headers_) {
            req << kv.first << ": " << kv.second << "\r\n";
        }

        if (method == "POST" || !body.empty()) {
            req << "Content-Length: " << body.length() << "\r\n";
        }
        req << "\r\n";
        if (method == "POST" || !body.empty()) {
            req << body;
        }

        std::string req_str = req.str();
        ssize_t sent = 0;
        size_t total = req_str.size();
        while (sent < static_cast<ssize_t>(total)) {
            ssize_t n = send(sock_, req_str.c_str() + sent, total - sent, 0);
            if (n <= 0) {
                end();
                return -1;
            }
            sent += n;
        }

        // Receive response
        std::string raw_response;
        char buffer[4096];
        while (true) {
            ssize_t n = recv(sock_, buffer, sizeof(buffer) - 1, 0);
            if (n > 0) {
                buffer[n] = '\0';
                raw_response.append(buffer, n);
            } else {
                break;
            }
        }
        end();

        if (raw_response.empty()) {
            return -1;
        }

        // Parse status line: HTTP/1.x <code> ...
        int status_code = 0;
        size_t line_end = raw_response.find("\r\n");
        if (line_end != std::string::npos) {
            std::string status_line = raw_response.substr(0, line_end);
            size_t first_space = status_line.find(' ');
            if (first_space != std::string::npos) {
                status_code = std::atoi(status_line.substr(first_space + 1, 3).c_str());
            }
        }

        // Parse body after headers
        size_t header_end = raw_response.find("\r\n\r\n");
        if (header_end != std::string::npos) {
            response_body_ = raw_response.substr(header_end + 4);
        } else {
            size_t alt_end = raw_response.find("\n\n");
            if (alt_end != std::string::npos) {
                response_body_ = raw_response.substr(alt_end + 2);
            } else {
                response_body_.clear();
            }
        }

        return status_code;
    }
};

#endif // !ARDUINO && !ESP32

#endif // THERMOSCAN_HAL_NATIVE_NET_COMPAT_H
