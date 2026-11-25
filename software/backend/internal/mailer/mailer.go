package mailer

import (
	"fmt"
	"log/slog"
	"net"
	"net/smtp"
	"strings"
	"time"
)

// Sender dispatches notification emails to one or more recipients.
type Sender interface {
	Send(to []string, subject, body string) error
}

// SMTPConfig holds SMTP relay settings loaded from environment variables.
type SMTPConfig struct {
	Host string
	Port string
	User string
	Pass string
	From string
}

type noopSender struct {
	logger *slog.Logger
}

func (n *noopSender) Send(to []string, subject, _ string) error {
	if n.logger != nil {
		n.logger.Info(
			"email dispatch skipped (SMTP_HOST not configured)",
			slog.Any("to", to),
			slog.String("subject", subject),
		)
	}
	return nil
}

type smtpSender struct {
	cfg    SMTPConfig
	logger *slog.Logger
}

// NewSMTPSender returns an SMTP-backed Sender when cfg.Host is non-empty,
// or a safe logging no-op sender otherwise.
func NewSMTPSender(cfg SMTPConfig, logger *slog.Logger) Sender {
	cfg.Host = strings.TrimSpace(cfg.Host)
	cfg.Port = strings.TrimSpace(cfg.Port)
	cfg.From = strings.TrimSpace(cfg.From)
	if cfg.Port == "" {
		cfg.Port = "1025"
	}
	if cfg.From == "" {
		cfg.From = "no-reply@thermoscan.local"
	}
	if cfg.Host == "" {
		return &noopSender{logger: logger}
	}
	return &smtpSender{cfg: cfg, logger: logger}
}

// FormatMessage builds a clean RFC 5322 email payload.
func FormatMessage(from string, to []string, subject, body string) []byte {
	cleanSubject := strings.ReplaceAll(strings.ReplaceAll(subject, "\r", ""), "\n", " ")
	headers := []string{
		fmt.Sprintf("From: ThermoScan <%s>", from),
		fmt.Sprintf("To: %s", strings.Join(to, ", ")),
		fmt.Sprintf("Subject: %s", cleanSubject),
		fmt.Sprintf("Date: %s", time.Now().UTC().Format(time.RFC1123Z)),
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=UTF-8",
	}
	return []byte(strings.Join(headers, "\r\n") + "\r\n\r\n" + body + "\r\n")
}

func (s *smtpSender) Send(to []string, subject, body string) error {
	recipients := make([]string, 0, len(to))
	seen := make(map[string]struct{}, len(to))
	for _, raw := range to {
		addr := strings.TrimSpace(raw)
		if addr == "" {
			continue
		}
		key := strings.ToLower(addr)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		recipients = append(recipients, addr)
	}
	if len(recipients) == 0 {
		return nil
	}

	addr := net.JoinHostPort(s.cfg.Host, s.cfg.Port)
	msg := FormatMessage(s.cfg.From, recipients, subject, body)

	var auth smtp.Auth
	if s.cfg.User != "" {
		auth = smtp.PlainAuth("", s.cfg.User, s.cfg.Pass, s.cfg.Host)
	}

	err := smtp.SendMail(addr, auth, s.cfg.From, recipients, msg)
	if err != nil {
		if s.logger != nil {
			s.logger.Warn(
				"failed to send SMTP email",
				slog.String("addr", addr),
				slog.Any("to", recipients),
				slog.String("subject", subject),
				slog.String("error", err.Error()),
			)
		}
		return err
	}

	if s.logger != nil {
		s.logger.Info(
			"email sent via SMTP",
			slog.String("addr", addr),
			slog.Any("to", recipients),
			slog.String("subject", subject),
		)
	}
	return nil
}
