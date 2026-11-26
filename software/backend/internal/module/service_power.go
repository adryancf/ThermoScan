package module

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"strings"
	"time"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func sanitizeFiniteFloatPtr(v *float64) *float64 {
	if v == nil || math.IsNaN(*v) || math.IsInf(*v, 0) {
		return nil
	}
	f := *v
	return &f
}

func (s *Service) recordPowerReadingsTx(ctx context.Context, qtx *db.Queries, moduleID pgtype.UUID, readings []PowerReadingInput) error {
	now := time.Now().UTC()
	maxReadings := len(readings)
	if maxReadings > 16 {
		maxReadings = 16
	}
	snapshot := make([]LivePowerReadingDTO, 0, maxReadings)
	seenPanels := make(map[int32]int, maxReadings)
	var latestAt time.Time
	hasAnyValid := false

	for _, r := range readings[:maxReadings] {
		if r.PanelIndex < 1 {
			continue
		}
		measuredAt := now
		if r.MeasuredAt >= 1000000000 {
			candidate := time.Unix(int64(r.MeasuredAt), 0).UTC()
			if !candidate.After(now.Add(5 * time.Minute)) {
				measuredAt = candidate
			}
		}
		if measuredAt.After(latestAt) {
			latestAt = measuredAt
		}

		v := sanitizeFiniteFloatPtr(r.VoltageV)
		a := sanitizeFiniteFloatPtr(r.CurrentA)
		w := sanitizeFiniteFloatPtr(r.PowerW)

		// Reject physically impossible INA228 readings (e.g., 0xFFFFFF I2C bus glitch -> 52428.80V / 262144W)
		if (v != nil && (*v < 0 || *v > 85.0)) || (w != nil && (*w < 0 || *w > 10000.0)) {
			v = nil
			a = nil
			w = nil
		}

		if _, err := qtx.InsertPowerReading(ctx, db.InsertPowerReadingParams{
			ModuleID:   moduleID,
			PanelIndex: r.PanelIndex,
			VoltageV:   floatPtrToPgFloat8(v),
			CurrentA:   floatPtrToPgFloat8(a),
			PowerW:     floatPtrToPgFloat8(w),
			MeasuredAt: measuredAt,
		}); err != nil {
			return err
		}

		if v != nil || a != nil || w != nil {
			hasAnyValid = true
		}

		entry := LivePowerReadingDTO{
			PanelIndex: r.PanelIndex,
			VoltageV:   v,
			CurrentA:   a,
			PowerW:     w,
			MeasuredAt: measuredAt.UTC().Format(time.RFC3339),
		}
		if idx, exists := seenPanels[r.PanelIndex]; exists {
			snapshot[idx] = entry
		} else {
			seenPanels[r.PanelIndex] = len(snapshot)
			snapshot = append(snapshot, entry)
		}
	}

	// Preserve previous valid Live Electrical Monitor snapshot when all readings in this ping are N/A
	if len(snapshot) == 0 || !hasAnyValid {
		return nil
	}

	if latestAt.IsZero() {
		latestAt = now
	}
	rawJSON, err := json.Marshal(snapshot)
	if err != nil {
		return err
	}
	return qtx.UpdateModuleLatestPower(ctx, db.UpdateModuleLatestPowerParams{
		ID:                  moduleID,
		LatestPowerReadings: rawJSON,
		LatestPowerAt:       &latestAt,
	})
}

func resolvePowerRange(rangeParam string, now time.Time) (string, *time.Time, int64) {
	switch strings.ToLower(strings.TrimSpace(rangeParam)) {
	case "1h":
		t := now.Add(-1 * time.Hour)
		return "1h", &t, 15
	case "24h", "":
		t := now.Add(-24 * time.Hour)
		return "24h", &t, 600
	case "7d":
		t := now.Add(-7 * 24 * time.Hour)
		return "7d", &t, 3600
	case "30d":
		t := now.Add(-30 * 24 * time.Hour)
		return "30d", &t, 14400
	case "all":
		return "all", nil, 0
	default:
		t := now.Add(-24 * time.Hour)
		return "24h", &t, 600
	}
}

func (s *Service) GetPowerReadingsSeries(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, rangeParam string, panelIndex *int32) (*PowerReadingsSeriesDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	row, err := s.queries.GetModuleByID(ctx, db.GetModuleByIDParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if _, _, err := s.resolveUserModuleRelationship(ctx, s.queries, principal, row.ID, row.InstallerTechnicianID); err != nil {
		return nil, err
	}

	if panelIndex != nil && *panelIndex < 1 {
		return nil, ErrInvalidInput
	}

	now := time.Now().UTC()
	normalizedRange, since, bucketSeconds := resolvePowerRange(rangeParam, now)

	var panelParam pgtype.Int4
	if panelIndex != nil {
		panelParam = pgtype.Int4{Int32: *panelIndex, Valid: true}
	}

	stats, err := s.queries.GetPowerReadingStatsByModule(ctx, db.GetPowerReadingStatsByModuleParams{
		ModuleID:   moduleID,
		PanelIndex: panelParam,
		Since:      since,
	})
	if err != nil {
		return nil, err
	}

	summary := PowerSeriesSummaryDTO{
		TotalReadings: stats.TotalReadings,
	}
	if stats.ValidPowerReadings > 0 {
		peak := stats.PeakPowerW
		avg := stats.AvgPowerW
		summary.PeakPowerW = &peak
		summary.AvgPowerW = &avg
	}
	if stats.ValidVoltageReadings > 0 {
		avgV := stats.AvgVoltageV
		summary.AvgVoltageV = &avgV
	}
	if stats.ValidCurrentReadings > 0 {
		avgA := stats.AvgCurrentA
		summary.AvgCurrentA = &avgA
	}
	if stats.TotalReadings > 0 {
		firstStr := stats.FirstReadingAt.UTC().Format(time.RFC3339)
		lastStr := stats.LastReadingAt.UTC().Format(time.RFC3339)
		summary.FirstReadingAt = &firstStr
		summary.LastReadingAt = &lastStr
	}

	if bucketSeconds <= 0 {
		if stats.TotalReadings > 0 {
			spanSec := int64(stats.LastReadingAt.Sub(stats.FirstReadingAt).Seconds())
			if spanSec <= 3600 {
				bucketSeconds = 15
			} else {
				bucketSeconds = spanSec / 180
				if bucketSeconds < 15 {
					bucketSeconds = 15
				}
			}
		} else {
			bucketSeconds = 3600
		}
	}

	points := make([]PowerSeriesPointDTO, 0)
	if stats.TotalReadings > 0 {
		seriesRows, err := s.queries.GetPowerReadingSeriesByModule(ctx, db.GetPowerReadingSeriesByModuleParams{
			BucketSeconds: bucketSeconds,
			ModuleID:      moduleID,
			PanelIndex:    panelParam,
			Since:         since,
		})
		if err != nil {
			return nil, err
		}

		// When aggregating multiple panels ("All Panels"), recalculate period peak/avg from series buckets
		// so that multi-panel totals reflect string power & current accurately rather than single-panel stats.
		if panelIndex == nil && len(seriesRows) > 0 {
			var maxPower float64
			var sumPower float64
			var validPowerBuckets int64
			var sumCurrent float64
			var validCurrentBuckets int64
			var sumVoltage float64
			var validVoltageBuckets int64
			for _, sr := range seriesRows {
				if sr.ValidWCount > 0 {
					if validPowerBuckets == 0 || sr.PeakPowerW > maxPower {
						maxPower = sr.PeakPowerW
					}
					sumPower += sr.PowerW
					validPowerBuckets++
				}
				if sr.ValidACount > 0 {
					sumCurrent += sr.CurrentA
					validCurrentBuckets++
				}
				if sr.ValidVCount > 0 {
					sumVoltage += sr.VoltageV
					validVoltageBuckets++
				}
			}
			if validPowerBuckets > 0 {
				avgP := sumPower / float64(validPowerBuckets)
				summary.PeakPowerW = &maxPower
				summary.AvgPowerW = &avgP
			}
			if validCurrentBuckets > 0 {
				avgA := sumCurrent / float64(validCurrentBuckets)
				summary.AvgCurrentA = &avgA
			}
			if validVoltageBuckets > 0 {
				avgV := sumVoltage / float64(validVoltageBuckets)
				summary.AvgVoltageV = &avgV
			}
		}

		points = make([]PowerSeriesPointDTO, 0, len(seriesRows))
		for _, sr := range seriesRows {
			pt := PowerSeriesPointDTO{
				BucketAt:    sr.BucketAt.UTC().Format(time.RFC3339),
				SampleCount: sr.SampleCount,
			}
			if sr.ValidVCount > 0 {
				v := sr.VoltageV
				pt.VoltageV = &v
			}
			if sr.ValidACount > 0 {
				a := sr.CurrentA
				pt.CurrentA = &a
			}
			if sr.ValidWCount > 0 {
				w := sr.PowerW
				pw := sr.PeakPowerW
				pt.PowerW = &w
				pt.PeakPowerW = &pw
			}
			points = append(points, pt)
		}
	}

	return &PowerReadingsSeriesDTO{
		Range:         normalizedRange,
		PanelIndex:    panelIndex,
		BucketSeconds: bucketSeconds,
		Summary:       summary,
		Points:        points,
	}, nil
}

func (s *Service) ListPowerReadings(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, rangeParam string, panelIndex *int32, page, limit int) (*PowerReadingsListDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	row, err := s.queries.GetModuleByID(ctx, db.GetModuleByIDParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if _, _, err := s.resolveUserModuleRelationship(ctx, s.queries, principal, row.ID, row.InstallerTechnicianID); err != nil {
		return nil, err
	}

	if panelIndex != nil && *panelIndex < 1 {
		return nil, ErrInvalidInput
	}

	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}

	normalizedRange, since, _ := resolvePowerRange(rangeParam, time.Now().UTC())
	var panelParam pgtype.Int4
	if panelIndex != nil {
		panelParam = pgtype.Int4{Int32: *panelIndex, Valid: true}
	}

	total, err := s.queries.CountPowerReadingsByModule(ctx, db.CountPowerReadingsByModuleParams{
		ModuleID:   moduleID,
		PanelIndex: panelParam,
		Since:      since,
	})
	if err != nil {
		return nil, err
	}

	offset64 := int64(page-1) * int64(limit)
	if offset64 < 0 || offset64 > math.MaxInt32 {
		totalPages := int((total + int64(limit) - 1) / int64(limit))
		if totalPages < 1 {
			totalPages = 1
		}
		return &PowerReadingsListDTO{
			Range:      normalizedRange,
			PanelIndex: panelIndex,
			Items:      []PowerReadingDTO{},
			Pagination: PaginationMetadataDTO{
				Page:        page,
				Limit:       limit,
				TotalCount:  total,
				TotalPages:  totalPages,
				HasNextPage: false,
			},
		}, nil
	}
	offset := int32(offset64)
	rows, err := s.queries.ListPowerReadingsByModule(ctx, db.ListPowerReadingsByModuleParams{
		ModuleID:   moduleID,
		PanelIndex: panelParam,
		Since:      since,
		LimitRows:  int32(limit),
		OffsetRows: offset,
	})
	if err != nil {
		return nil, err
	}

	items := make([]PowerReadingDTO, 0, len(rows))
	for _, r := range rows {
		items = append(items, PowerReadingDTO{
			ID:         auth.FormatUUID(r.ID),
			ModuleID:   auth.FormatUUID(r.ModuleID),
			PanelIndex: r.PanelIndex,
			VoltageV:   pgFloat8ToFloatPtr(r.VoltageV),
			CurrentA:   pgFloat8ToFloatPtr(r.CurrentA),
			PowerW:     pgFloat8ToFloatPtr(r.PowerW),
			MeasuredAt: r.MeasuredAt.UTC().Format(time.RFC3339),
			ReceivedAt: r.ReceivedAt.UTC().Format(time.RFC3339),
		})
	}

	totalPages := int((total + int64(limit) - 1) / int64(limit))
	if totalPages < 1 {
		totalPages = 1
	}

	return &PowerReadingsListDTO{
		Range:      normalizedRange,
		PanelIndex: panelIndex,
		Items:      items,
		Pagination: PaginationMetadataDTO{
			Page:        page,
			Limit:       limit,
			TotalCount:  total,
			TotalPages:  totalPages,
			HasNextPage: page < totalPages,
		},
	}, nil
}
