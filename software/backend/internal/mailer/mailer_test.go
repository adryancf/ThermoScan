package mailer

import (
	"strings"
	"testing"
)

func TestFormatMessageAndNoopSender(t *testing.T) {
	raw := string(FormatMessage(
		"no-reply@thermoscan.local",
		[]string{"client1@example.com", "client2@example.com"},
		"Inspection Interval Updated\r\nInjected",
		"Hello from ThermoScan.",
	))

	if !strings.Contains(raw, "From: ThermoScan <no-reply@thermoscan.local>") {
		t.Fatalf("missing From header: %s", raw)
	}
	if !strings.Contains(raw, "To: client1@example.com, client2@example.com") {
		t.Fatalf("missing To header: %s", raw)
	}
	if strings.Contains(raw, "Updated\r\nInjected") {
		t.Fatalf("subject CRLF injection was not sanitized: %s", raw)
	}
	if !strings.Contains(raw, "Hello from ThermoScan.") {
		t.Fatalf("missing body: %s", raw)
	}

	sender := NewSMTPSender(SMTPConfig{}, nil)
	if err := sender.Send([]string{"client@example.com"}, "Test", "Body"); err != nil {
		t.Fatalf("noop sender should not fail: %v", err)
	}
}
