package module

import (
	"context"
	"fmt"
	"time"

	"backend/internal/db"

	"github.com/jackc/pgx/v5/pgtype"
)

// notifyClientsIntervalChanged sends a mandatory email to ALL Clients assigned
// to [moduleID] whenever its inspection interval changes (SFR51 / SFR53).
// Interval-change emails cannot be disabled by operational_email_enabled.
func (s *Service) notifyClientsIntervalChanged(
	companyID pgtype.UUID,
	moduleID pgtype.UUID,
	moduleName string,
	previousDays int32,
	newDays int32,
	authorName string,
) {
	if s.mailer == nil || !companyID.Valid || !moduleID.Valid {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		clients, err := s.queries.ListClientsByModule(ctx, db.ListClientsByModuleParams{
			CompanyID: companyID,
			ModuleID:  moduleID,
		})
		if err != nil || len(clients) == 0 {
			return
		}

		recipients := make([]string, 0, len(clients))
		for _, c := range clients {
			if c.Email != "" {
				recipients = append(recipients, c.Email)
			}
		}
		if len(recipients) == 0 {
			return
		}

		actor := authorName
		if actor == "" {
			actor = "An authorized user"
		}
		subject := fmt.Sprintf("[ThermoScan] Inspection Interval Changed - %s", moduleName)
		body := fmt.Sprintf(
			"Hello,\n\n"+
				"The automatic thermal inspection interval for PV module \"%s\" has been updated.\n\n"+
				"  - Previous interval: Every %d day(s)\n"+
				"  - New interval:      Every %d day(s)\n"+
				"  - Updated by:        %s\n"+
				"  - Timestamp (UTC):   %s\n\n"+
				"The next scheduled inspection has been recalculated automatically without triggering an immediate scan.\n\n"+
				"--\n"+
				"ThermoScan Autonomous Diagnostic System\n"+
				"(Note: Interval-change notifications remain enabled for all assigned clients.)",
			moduleName,
			previousDays,
			newDays,
			actor,
			time.Now().UTC().Format("2006-01-02 15:04 UTC"),
		)
		_ = s.mailer.Send(recipients, subject, body)
	}()
}

// notifyClientsOperationalAlert emails Clients assigned to [moduleID] who have
// operational_email_enabled == true (SFR33, SFR40, SFR42, SFR53).
func (s *Service) notifyClientsOperationalAlert(
	companyID pgtype.UUID,
	moduleID pgtype.UUID,
	moduleName string,
	subject string,
	body string,
) {
	if s.mailer == nil || !companyID.Valid || !moduleID.Valid {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		clients, err := s.queries.ListClientsByModule(ctx, db.ListClientsByModuleParams{
			CompanyID: companyID,
			ModuleID:  moduleID,
		})
		if err != nil || len(clients) == 0 {
			return
		}

		recipients := make([]string, 0, len(clients))
		for _, c := range clients {
			if c.OperationalEmailEnabled && c.Email != "" {
				recipients = append(recipients, c.Email)
			}
		}
		if len(recipients) == 0 {
			return
		}

		fullBody := fmt.Sprintf(
			"Hello,\n\n%s\n\nModule: %s\nTimestamp (UTC): %s\n\n--\nThermoScan Autonomous Diagnostic System\n(You can disable operational alerts for this module in the ThermoScan app settings.)",
			body,
			moduleName,
			time.Now().UTC().Format("2006-01-02 15:04 UTC"),
		)
		_ = s.mailer.Send(recipients, subject, fullBody)
	}()
}
