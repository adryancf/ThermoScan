package mailer

import (
	"crypto/tls"
	"fmt"
	"log/slog"
	"net"
	"net/smtp"
	"strings"
	"time"
)

const (
	smtpDialTimeout  = 5 * time.Second
	smtpTotalTimeout = 10 * time.Second
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

	err := sendMailWithTimeout(addr, s.cfg.Host, auth, s.cfg.From, recipients, msg)
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

func sendMailWithTimeout(addr, host string, auth smtp.Auth, from string, to []string, msg []byte) error {
	conn, err := net.DialTimeout("tcp", addr, smtpDialTimeout)
	if err != nil {
		return err
	}
	defer conn.Close()

	_ = conn.SetDeadline(time.Now().Add(smtpTotalTimeout))

	client, err := smtp.NewClient(conn, host)
	if err != nil {
		return err
	}
	defer client.Close()

	if ok, _ := client.Extension("STARTTLS"); ok {
		if err := client.StartTLS(&tls.Config{ServerName: host}); err != nil {
			return err
		}
	}
	if auth != nil {
		if ok, _ := client.Extension("AUTH"); ok {
			if err := client.Auth(auth); err != nil {
				return err
			}
		}
	}
	if err := client.Mail(from); err != nil {
		return err
	}
	for _, rcpt := range to {
		if err := client.Rcpt(rcpt); err != nil {
			return err
		}
	}
	w, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(msg); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return client.Quit()
}
