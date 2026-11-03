package module

import (
	"context"
	"math"
	"sort"
	"strconv"
	"time"

	"backend/internal/auth"
	"backend/internal/db"
)

func (s *Service) ListActiveAlerts(ctx context.Context, principal auth.Principal) (*AlertsSummaryDTO, error) {
	if !principal.CompanyID.Valid {
		return nil, ErrForbidden
	}

	anoms, err := s.queries.ListActiveAnomaliesForCompany(ctx, principal.CompanyID)
	if err != nil {
		return nil, err
	}

	waterWarnings, err := s.queries.ListActiveWaterWarningsForCompany(ctx, principal.CompanyID)
	if err != nil {
		return nil, err
	}

	alerts := make([]AlertDTO, 0, len(anoms)+len(waterWarnings))
	criticalCount := 0
	warningCount := 0

	for _, a := range anoms {
		if principal.Role == auth.RoleTechnician && a.InstallerTechnicianID.Bytes != principal.ID.Bytes {
			acc, err := s.queries.GetModuleTechnicianAccess(ctx, db.GetModuleTechnicianAccessParams{
				CompanyID:    principal.CompanyID,
				ModuleID:     a.ModuleID,
				TechnicianID: principal.ID,
			})
			if err != nil || !acc.CanView {
				continue
			}
		}

		maxT, _ := strconv.ParseFloat(a.MaxTemperatureC, 64)
		baseT, _ := strconv.ParseFloat(a.BaselineTemperatureC, 64)
		xPos, _ := strconv.ParseFloat(a.XPositionCm, 64)
		delta := maxT - baseT
		if delta < 0 {
			delta = 0
		}
		delta = math.Round(delta*10.0) / 10.0

		severity := "warning"
		if delta >= 10.0 {
			severity = "critical"
			criticalCount++
		} else {
			warningCount++
		}

		xPosRounded := math.Round(xPos*10.0) / 10.0
		metaText := "Delta: +" + strconv.FormatFloat(delta, 'f', 1, 64) + "°C vs Baseline"
		desc := "Thermal anomaly confirmed at coordinate X=" + strconv.FormatFloat(xPosRounded, 'f', 1, 64) + " cm. Wash attempts registered: " + strconv.Itoa(int(a.ActuatedAttemptsCount)) + " of 3."

		alerts = append(alerts, AlertDTO{
			ID:          auth.FormatUUID(a.ID),
			ModuleID:    auth.FormatUUID(a.ModuleID),
			ModuleName:  a.ModuleName,
			Severity:    severity,
			Type:        "hotspot_unresolved",
			Title:       "Hotspot Unresolved: " + a.ModuleName,
			Description: desc,
			MetaText:    metaText,
			XPositionCm: &xPosRounded,
			DeltaC:      &delta,
			CreatedAt:   a.DetectedAt.UTC().Format(time.RFC3339),
		})
	}

	for _, w := range waterWarnings {
		if principal.Role == auth.RoleTechnician && w.InstallerTechnicianID.Bytes != principal.ID.Bytes {
			acc, err := s.queries.GetModuleTechnicianAccess(ctx, db.GetModuleTechnicianAccessParams{
				CompanyID:    principal.CompanyID,
				ModuleID:     w.ModuleID,
				TechnicianID: principal.ID,
			})
			if err != nil || !acc.CanView {
				continue
			}
		}

		warningCount++
		alerts = append(alerts, AlertDTO{
			ID:          auth.FormatUUID(w.ID),
			ModuleID:    auth.FormatUUID(w.ModuleID),
			ModuleName:  w.ModuleName,
			Severity:    "warning",
			Type:        "reservoir_low",
			Title:       "Reservoir Low: " + w.ModuleName,
			Description: "Capacitive binary water sensor tripped (water_available=false). Water level is below safety minimum threshold. Autonomous wash cycles are blocked until manual refill.",
			MetaText:    "Safety Interlock: Wash Cycles Blocked",
			CreatedAt:   w.MeasuredAt.UTC().Format(time.RFC3339),
		})
	}

	sort.Slice(alerts, func(i, j int) bool {
		return alerts[i].CreatedAt > alerts[j].CreatedAt
	})

	return &AlertsSummaryDTO{
		Total:    len(alerts),
		Critical: criticalCount,
		Warning:  warningCount,
		Alerts:   alerts,
	}, nil
}
