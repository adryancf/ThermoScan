package module

import (
	"context"
	"errors"
	"strings"
	"time"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func (s *Service) ListCleanings(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, limit, offset int32) ([]CleaningDTO, error) {
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

	_, _, err = s.resolveUserModuleRelationship(ctx, s.queries, principal, row.ID, row.InstallerTechnicianID)
	if err != nil {
		return nil, err
	}

	rows, err := s.queries.ListCleaningOperationsByModule(ctx, db.ListCleaningOperationsByModuleParams{
		ModuleID: moduleID,
		Limit:    limit,
		Offset:   offset,
	})
	if err != nil {
		return nil, err
	}

	out := make([]CleaningDTO, 0, len(rows))
	for _, c := range rows {
		var startedAtStr, endedAtStr *string
		if c.StartedAt != nil {
			s := c.StartedAt.UTC().Format(time.RFC3339)
			startedAtStr = &s
		}
		if c.EndedAt != nil {
			e := c.EndedAt.UTC().Format(time.RFC3339)
			endedAtStr = &e
		}

		out = append(out, CleaningDTO{
			ID:                 auth.FormatUUID(c.ID),
			ModuleID:           auth.FormatUUID(c.ModuleID),
			AnomalyEventID:     auth.FormatUUID(c.AnomalyEventID),
			SourceEventID:      auth.FormatUUID(c.SourceEventID),
			TargetXPositionCM:  c.TargetXPositionCm,
			PumpActuated:       c.PumpActuated,
			AttemptNumber:      pgInt4ToInt32Ptr(c.AttemptNumber),
			StartedAt:          startedAtStr,
			EndedAt:            endedAtStr,
			DurationSeconds:    c.DurationSeconds,
			EstimatedWaterML:   c.EstimatedWaterVolumeMl,
			Status:             c.Status,
			FailureReason:      pgTextToStringPtr(c.FailureReason),
			PostCleaningResult: c.PostCleaningResult,
			CreatedAt:          c.CreatedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
}

func (s *Service) IngestCleaning(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, input IngestCleaningInput) (*CleaningDTO, error) {
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

	_, _, err = s.resolveUserModuleRelationship(ctx, s.queries, principal, row.ID, row.InstallerTechnicianID)
	if err != nil {
		return nil, err
	}

	var anomID pgtype.UUID
	now := time.Now().UTC()

	// 1. Resolve authentic anomaly event (never fabricated!)
	if input.AnomalyEventID != nil && strings.TrimSpace(*input.AnomalyEventID) != "" {
		parsed, err := auth.ParseUUID(strings.TrimSpace(*input.AnomalyEventID))
		if err != nil {
			return nil, ErrInvalidInput
		}
		a, err := s.queries.GetAnomalyEventByID(ctx, db.GetAnomalyEventByIDParams{
			ID:       parsed,
			ModuleID: moduleID,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return nil, ErrNotFound
			}
			return nil, err
		}
		anomID = a.ID
	} else {
		// Look up latest open anomaly for this module
		a, err := s.queries.GetLatestOpenAnomalyEventByModule(ctx, moduleID)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return nil, ErrNotFound
			}
			return nil, err
		}
		anomID = a.ID
	}

	// 2. Validate cleaning status
	status := strings.TrimSpace(input.Status)
	if status == "" {
		return nil, ErrInvalidInput
	}
	postRes := strings.TrimSpace(input.PostCleaningResult)
	if postRes == "" {
		if status == "completed" {
			postRes = "resolved"
		} else {
			postRes = "unresolved"
		}
	}

	var attemptNum pgtype.Int4
	if input.PumpActuated {
		num := int32(1)
		if input.AttemptNumber != nil && *input.AttemptNumber >= 1 && *input.AttemptNumber <= 3 {
			num = int32(*input.AttemptNumber)
		}
		attemptNum = pgtype.Int4{Int32: num, Valid: true}
	}

	var startedAtPtr *time.Time
	var endedAtPtr *time.Time
	if status != "refused" && status != "scheduled" {
		sTime := now.Add(-time.Duration(input.DurationSeconds) * time.Second)
		eTime := now
		startedAtPtr = &sTime
		endedAtPtr = &eTime
	}

	cleanEventID := newRandomUUID()
	var failReason pgtype.Text
	if input.FailureReason != nil && strings.TrimSpace(*input.FailureReason) != "" {
		failReason = pgtype.Text{String: strings.TrimSpace(*input.FailureReason), Valid: true}
	} else if status == "refused" || status == "failed" {
		failReason = pgtype.Text{String: "Water reservoir depleted", Valid: true}
	}

	clean, err := s.queries.CreateCleaningOperation(ctx, db.CreateCleaningOperationParams{
		ModuleID:               moduleID,
		AnomalyEventID:         anomID,
		SourceEventID:          cleanEventID,
		TargetXPositionCm:      floatPtrToNumeric(&input.TargetXPositionCm),
		PumpActuated:           input.PumpActuated,
		AttemptNumber:          attemptNum,
		StartedAt:              startedAtPtr,
		EndedAt:                endedAtPtr,
		DurationSeconds:        floatPtrToNumeric(&input.DurationSeconds),
		EstimatedWaterVolumeMl: floatPtrToNumeric(&input.EstimatedWaterVolumeMl),
		Status:                 status,
		FailureReason:          failReason,
		PostCleaningResult:     postRes,
	})
	if err != nil {
		return nil, err
	}

	// 3. Update anomaly event status based on authentic cleaning result
	newAnomStatus := "open"
	var closedAt *time.Time
	if postRes == "resolved" {
		newAnomStatus = "resolved"
		closedAt = &now
	} else if postRes == "unresolved" {
		newAnomStatus = "unresolved"
		closedAt = &now
	}
	attemptsInc := int32(0)
	if input.PumpActuated {
		attemptsInc = 1
	}
	_, _ = s.queries.UpdateAnomalyEventStatus(ctx, db.UpdateAnomalyEventStatusParams{
		Status:                newAnomStatus,
		ActuatedAttemptsCount: attemptsInc,
		ClosedAt:              closedAt,
		ID:                    anomID,
		ModuleID:              moduleID,
	})

	var attPtr *int32
	if clean.AttemptNumber.Valid {
		attPtr = &clean.AttemptNumber.Int32
	}
	var fReason *string
	if clean.FailureReason.Valid {
		fReason = &clean.FailureReason.String
	}
	var startStr *string
	if clean.StartedAt != nil {
		s := clean.StartedAt.UTC().Format(time.RFC3339)
		startStr = &s
	}
	var endStr *string
	if clean.EndedAt != nil {
		e := clean.EndedAt.UTC().Format(time.RFC3339)
		endStr = &e
	}

	return &CleaningDTO{
		ID:                 auth.FormatUUID(clean.ID),
		ModuleID:           auth.FormatUUID(clean.ModuleID),
		AnomalyEventID:     auth.FormatUUID(clean.AnomalyEventID),
		SourceEventID:      auth.FormatUUID(clean.SourceEventID),
		TargetXPositionCM:  clean.TargetXPositionCm,
		PumpActuated:       clean.PumpActuated,
		AttemptNumber:      attPtr,
		StartedAt:          startStr,
		EndedAt:            endStr,
		DurationSeconds:    clean.DurationSeconds,
		EstimatedWaterML:   clean.EstimatedWaterVolumeMl,
		Status:             clean.Status,
		FailureReason:      fReason,
		PostCleaningResult: clean.PostCleaningResult,
		CreatedAt:          clean.CreatedAt.UTC().Format(time.RFC3339),
	}, nil
}
