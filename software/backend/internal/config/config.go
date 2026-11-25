package config

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strings"
)

type Config struct {
	DatabaseURL         string
	JWTSecret           string
	APIPort             string
	BootstrapAdminName  string
	BootstrapAdminEmail string
	SMTPHost            string
	SMTPPort            string
	SMTPUser            string
	SMTPPass            string
	SMTPFrom            string
}

// Load reads configuration from environment variables, falling back to .env or ../.env
// for local development convenience when variables are not already set in the process environment.
func Load() (Config, error) {
	loadDotEnvIfPresent(".env", "../.env")

	cfg := Config{
		DatabaseURL:         strings.TrimSpace(os.Getenv("DATABASE_URL")),
		JWTSecret:           strings.TrimSpace(os.Getenv("JWT_SECRET")),
		APIPort:             strings.TrimSpace(os.Getenv("API_PORT")),
		BootstrapAdminName:  strings.TrimSpace(os.Getenv("BOOTSTRAP_ADMIN_NAME")),
		BootstrapAdminEmail: strings.ToLower(strings.TrimSpace(os.Getenv("BOOTSTRAP_ADMIN_EMAIL"))),
		SMTPHost:            strings.TrimSpace(os.Getenv("SMTP_HOST")),
		SMTPPort:            strings.TrimSpace(os.Getenv("SMTP_PORT")),
		SMTPUser:            strings.TrimSpace(os.Getenv("SMTP_USER")),
		SMTPPass:            os.Getenv("SMTP_PASS"),
		SMTPFrom:            strings.TrimSpace(os.Getenv("SMTP_FROM")),
	}

	if cfg.APIPort == "" {
		cfg.APIPort = "8080"
	}
	if cfg.BootstrapAdminName == "" {
		cfg.BootstrapAdminName = "System Admin"
	}

	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("DATABASE_URL is required")
	}
	if cfg.JWTSecret == "" {
		return Config{}, errors.New("JWT_SECRET is required")
	}

	return cfg, nil
}

func loadDotEnvIfPresent(paths ...string) {
	for _, p := range paths {
		f, err := os.Open(p)
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			key, val, ok := strings.Cut(line, "=")
			if !ok {
				continue
			}
			key = strings.TrimSpace(key)
			val = strings.Trim(strings.TrimSpace(val), `"'`)
			if key != "" && os.Getenv(key) == "" {
				_ = os.Setenv(key, fmt.Sprint(val))
			}
		}
		_ = f.Close()
		return
	}
}
