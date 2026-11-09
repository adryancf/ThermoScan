package module

import (
	"context"
	"fmt"
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

		var localXPtr *float64
		if pLen, pErr := strconv.ParseFloat(a.ModulePanelLengthCm, 64); pErr == nil && pLen > 0 {
			cnt := int32(1)
			if a.ModulePanelCount.Valid && a.ModulePanelCount.Int32 > 0 {
				cnt = a.ModulePanelCount.Int32
			}
			spc := 0.0
			if pSpc, sErr := strconv.ParseFloat(a.ModulePanelSpacingCm, 64); sErr == nil && pSpc > 0 {
				spc = pSpc
			}
			posRes := ResolvePanelPosition(cnt, pLen, spc, xPos)
			if !posRes.InGap {
				lx := math.Round(posRes.LocalXCm*100.0) / 100.0
				localXPtr = &lx
			}
		}

		xPosRounded := math.Round(xPos*10.0) / 10.0
		title := fmt.Sprintf("Hotspot Unresolved: %s (Panel %d)", a.ModuleName, a.PanelIndex)
		metaText := fmt.Sprintf("Delta: +%s°C vs Baseline • Panel %d (X=%scm)", strconv.FormatFloat(delta, 'f', 1, 64), a.PanelIndex, strconv.FormatFloat(xPosRounded, 'f', 1, 64))
		desc := fmt.Sprintf("Thermal anomaly confirmed on panel %d at coordinate X=%s cm. Wash attempts registered: %d of 3.", a.PanelIndex, strconv.FormatFloat(xPosRounded, 'f', 1, 64), a.ActuatedAttemptsCount)
		panelIdx := a.PanelIndex

		var inspIDPtr *string
		if a.InspectionID.Valid {
			idStr := auth.FormatUUID(a.InspectionID)
			inspIDPtr = &idStr
		}

		var inspDatePtr *string
		if a.InspectionStartedAt != nil && !a.InspectionStartedAt.IsZero() {
			dStr := a.InspectionStartedAt.UTC().Format(time.RFC3339)
			inspDatePtr = &dStr
		}

		maxTRounded := math.Round(maxT*10.0) / 10.0
		baseTRounded := math.Round(baseT*10.0) / 10.0
		washAttempts := a.ActuatedAttemptsCount

		alerts = append(alerts, AlertDTO{
			ID:                   auth.FormatUUID(a.ID),
			ModuleID:             auth.FormatUUID(a.ModuleID),
			ModuleName:           a.ModuleName,
			Severity:             severity,
			Type:                 "hotspot_unresolved",
			Title:                title,
			Description:          desc,
			MetaText:             metaText,
			PanelIndex:           &panelIdx,
			XPositionCm:          &xPosRounded,
			LocalXPositionCM:     localXPtr,
			LocalXCm:             localXPtr,
			DeltaC:               &delta,
			CreatedAt:            a.DetectedAt.UTC().Format(time.RFC3339),
			InspectionID:         inspIDPtr,
			InspectionDate:       inspDatePtr,
			MaxTemperatureC:      &maxTRounded,
			BaselineTemperatureC: &baseTRounded,
			WashAttemptsCount:    &washAttempts,
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
