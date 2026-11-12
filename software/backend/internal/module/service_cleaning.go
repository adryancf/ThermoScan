package module

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
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

	pLen := numericToFloatPtr(row.PanelLengthCm)
	pCnt := pgInt4ToInt32Ptr(row.PanelCount)
	pSpc := numericToFloatPtr(row.PanelSpacingCm)
	cnt := int32(1)
	if pCnt != nil && *pCnt > 0 {
		cnt = *pCnt
	}
	lenCm := 0.0
	if pLen != nil {
		lenCm = *pLen
	}
	spcCm := 0.0
	if pSpc != nil && *pSpc > 0 {
		spcCm = *pSpc
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

		var localTargetXStr *string
		if lenCm > 0 {
			if targetX, err := strconv.ParseFloat(c.TargetXPositionCm, 64); err == nil {
				posRes := ResolvePanelPosition(cnt, lenCm, spcCm, targetX)
				if !posRes.InGap {
					s := strconv.FormatFloat(posRes.LocalXCm, 'f', 2, 64)
					localTargetXStr = &s
				}
			}
		}

		out = append(out, CleaningDTO{
			ID:                     auth.FormatUUID(c.ID),
			ModuleID:               auth.FormatUUID(c.ModuleID),
			AnomalyEventID:         auth.FormatUUID(c.AnomalyEventID),
			SourceEventID:          auth.FormatUUID(c.SourceEventID),
			PanelIndex:             pgInt4ToInt32Ptr(c.PanelIndex),
			TargetXPositionCM:      c.TargetXPositionCm,
			LocalXPositionCM:       localTargetXStr,
			LocalTargetXPositionCM: localTargetXStr,
			PumpActuated:           c.PumpActuated,
			AttemptNumber:          pgInt4ToInt32Ptr(c.AttemptNumber),
			StartedAt:              startedAtStr,
			EndedAt:                endedAtStr,
			DurationSeconds:        c.DurationSeconds,
			EstimatedWaterML:       c.EstimatedWaterVolumeMl,
			Status:                 c.Status,
			FailureReason:          pgTextToStringPtr(c.FailureReason),
			PostCleaningResult:     c.PostCleaningResult,
			CreatedAt:              c.CreatedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
}

func (s *Service) IngestCleaning(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, input IngestCleaningInput) (*CleaningDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	row, err := qtx.GetModuleByIDForUpdate(ctx, db.GetModuleByIDForUpdateParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	_, _, err = s.resolveUserModuleRelationship(ctx, qtx, principal, row.ID, row.InstallerTechnicianID)
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
		a, err := qtx.GetAnomalyEventByID(ctx, db.GetAnomalyEventByIDParams{
			ID:       parsed,
			ModuleID: moduleID,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				aBySrc, errSrc := qtx.GetAnomalyEventBySourceEventID(ctx, db.GetAnomalyEventBySourceEventIDParams{
					SourceEventID: parsed,
					ModuleID:      moduleID,
				})
				if errSrc != nil {
					if errors.Is(errSrc, pgx.ErrNoRows) {
						return nil, ErrNotFound
					}
					return nil, errSrc
				}
				anomID = aBySrc.ID
			} else {
				return nil, err
			}
		} else {
			anomID = a.ID
		}
	} else {
		// Look up latest open anomaly for this module
		a, err := qtx.GetLatestOpenAnomalyEventByModule(ctx, moduleID)
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
	postRes := "pending"
	if !input.PumpActuated {
		p := strings.TrimSpace(input.PostCleaningResult)
		if p == "pending" || p == "resolved" || p == "unresolved" {
			postRes = p
		}
	}

	pLen := numericToFloatPtr(row.PanelLengthCm)
	pCnt := pgInt4ToInt32Ptr(row.PanelCount)
	pSpc := numericToFloatPtr(row.PanelSpacingCm)
	cnt := int32(1)
	if pCnt != nil && *pCnt > 0 {
		cnt = *pCnt
	}
	lenCm := 0.0
	if pLen != nil {
		lenCm = *pLen
	}
	spcCm := 0.0
	if pSpc != nil && *pSpc > 0 {
		spcCm = *pSpc
	}

	var resolvedPanelIndex pgtype.Int4
	if input.PanelIndex != nil {
		if *input.PanelIndex < 1 || *input.PanelIndex > cnt {
			return nil, ErrInvalidInput
		}
		resolvedPanelIndex = pgtype.Int4{Int32: *input.PanelIndex, Valid: true}
	}

	if input.TargetXPositionCm < 0 || !isFinite(input.TargetXPositionCm) {
		return nil, ErrInvalidInput
	}

	isExplicitGapReason := input.FailureReason != nil && strings.TrimSpace(*input.FailureReason) == "target_in_gap"
	if isExplicitGapReason {
		if status != "refused" || input.PumpActuated || (input.AttemptNumber != nil && *input.AttemptNumber != 0) {
			return nil, ErrInvalidInput
		}
		resolvedPanelIndex = pgtype.Int4{Valid: false}
	}

	var failReason pgtype.Text
	if input.FailureReason != nil && strings.TrimSpace(*input.FailureReason) != "" {
		failReason = pgtype.Text{String: strings.TrimSpace(*input.FailureReason), Valid: true}
	} else if status == "refused" || status == "failed" {
		failReason = pgtype.Text{String: "Water reservoir depleted", Valid: true}
	}

	if lenCm > 0 {
		posRes := ResolvePanelPosition(cnt, lenCm, spcCm, input.TargetXPositionCm)
		if !posRes.WithinBounds {
			return nil, ErrInvalidInput
		}
		if posRes.InGap {
			if input.PumpActuated || (input.AttemptNumber != nil && *input.AttemptNumber != 0) {
				return nil, ErrInvalidInput
			}
			status = "refused"
			input.PumpActuated = false
			failReason = pgtype.Text{String: "target_in_gap", Valid: true}
			resolvedPanelIndex = pgtype.Int4{Valid: false}
		} else {
			if isExplicitGapReason {
				return nil, ErrInvalidInput
			}
			if input.PanelIndex != nil && *input.PanelIndex != posRes.PanelIndex {
				return nil, ErrInvalidInput
			}
			resolvedPanelIndex = pgtype.Int4{Int32: posRes.PanelIndex, Valid: true}
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
	if input.SourceEventID != nil && strings.TrimSpace(*input.SourceEventID) != "" {
		parsed, err := auth.ParseUUID(strings.TrimSpace(*input.SourceEventID))
		if err != nil {
			return nil, ErrInvalidInput
		}
		cleanEventID = parsed
	}

	// Idempotency check 1: already exists for this module with this source_event_id
	if existing, err := qtx.GetCleaningOperationBySourceEventID(ctx, db.GetCleaningOperationBySourceEventIDParams{
		ModuleID:      moduleID,
		SourceEventID: cleanEventID,
	}); err == nil {
		_ = tx.Rollback(ctx)
		return cleaningRowToDTO(
			existing.ID, existing.ModuleID, existing.AnomalyEventID, existing.SourceEventID,
			existing.PanelIndex, existing.TargetXPositionCm, existing.PumpActuated,
			existing.AttemptNumber, existing.StartedAt, existing.EndedAt,
			existing.DurationSeconds, existing.EstimatedWaterVolumeMl, existing.Status,
			existing.FailureReason, existing.PostCleaningResult, existing.CreatedAt,
			cnt, lenCm, spcCm,
		), nil
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	// Idempotency check 2: already exists for same anomaly_event_id and attempt_number
	if attemptNum.Valid {
		if existing, err := qtx.GetCleaningOperationByAnomalyAndAttempt(ctx, db.GetCleaningOperationByAnomalyAndAttemptParams{
			AnomalyEventID: anomID,
			AttemptNumber:  attemptNum,
		}); err == nil {
			_ = tx.Rollback(ctx)
			return cleaningRowToDTO(
				existing.ID, existing.ModuleID, existing.AnomalyEventID, existing.SourceEventID,
				existing.PanelIndex, existing.TargetXPositionCm, existing.PumpActuated,
				existing.AttemptNumber, existing.StartedAt, existing.EndedAt,
				existing.DurationSeconds, existing.EstimatedWaterVolumeMl, existing.Status,
				existing.FailureReason, existing.PostCleaningResult, existing.CreatedAt,
				cnt, lenCm, spcCm,
			), nil
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
	}

	clean, err := qtx.CreateCleaningOperation(ctx, db.CreateCleaningOperationParams{
		ModuleID:               moduleID,
		AnomalyEventID:         anomID,
		SourceEventID:          cleanEventID,
		PanelIndex:             resolvedPanelIndex,
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
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			_ = tx.Rollback(ctx)
			if existing, qErr := s.queries.GetCleaningOperationBySourceEventID(ctx, db.GetCleaningOperationBySourceEventIDParams{
				ModuleID:      moduleID,
				SourceEventID: cleanEventID,
			}); qErr == nil {
				return cleaningRowToDTO(
					existing.ID, existing.ModuleID, existing.AnomalyEventID, existing.SourceEventID,
					existing.PanelIndex, existing.TargetXPositionCm, existing.PumpActuated,
					existing.AttemptNumber, existing.StartedAt, existing.EndedAt,
					existing.DurationSeconds, existing.EstimatedWaterVolumeMl, existing.Status,
					existing.FailureReason, existing.PostCleaningResult, existing.CreatedAt,
					cnt, lenCm, spcCm,
				), nil
			}
			if attemptNum.Valid {
				if existing, qErr := s.queries.GetCleaningOperationByAnomalyAndAttempt(ctx, db.GetCleaningOperationByAnomalyAndAttemptParams{
					AnomalyEventID: anomID,
					AttemptNumber:  attemptNum,
				}); qErr == nil {
					return cleaningRowToDTO(
						existing.ID, existing.ModuleID, existing.AnomalyEventID, existing.SourceEventID,
						existing.PanelIndex, existing.TargetXPositionCm, existing.PumpActuated,
						existing.AttemptNumber, existing.StartedAt, existing.EndedAt,
						existing.DurationSeconds, existing.EstimatedWaterVolumeMl, existing.Status,
						existing.FailureReason, existing.PostCleaningResult, existing.CreatedAt,
						cnt, lenCm, spcCm,
					), nil
				}
			}
		}
		return nil, err
	}

	// 3. Update anomaly event (do NOT close anomaly on cleaning ingestion; keep open pending verification inspection)
	attemptsInc := int32(0)
	if input.PumpActuated {
		attemptsInc = 1
	}
	_, _ = qtx.UpdateAnomalyEventStatus(ctx, db.UpdateAnomalyEventStatusParams{
		Status:                "open",
		ActuatedAttemptsCount: attemptsInc,
		ClosedAt:              nil,
		ID:                    anomID,
		ModuleID:              moduleID,
	})

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return cleaningRowToDTO(
		clean.ID, clean.ModuleID, clean.AnomalyEventID, clean.SourceEventID,
		clean.PanelIndex, clean.TargetXPositionCm, clean.PumpActuated,
		clean.AttemptNumber, clean.StartedAt, clean.EndedAt,
		clean.DurationSeconds, clean.EstimatedWaterVolumeMl, clean.Status,
		clean.FailureReason, clean.PostCleaningResult, clean.CreatedAt,
		cnt, lenCm, spcCm,
	), nil
}

func cleaningRowToDTO(
	id, moduleID, anomalyEventID, sourceEventID pgtype.UUID,
	panelIndex pgtype.Int4,
	targetXPositionCm string,
	pumpActuated bool,
	attemptNumber pgtype.Int4,
	startedAt, endedAt *time.Time,
	durationSeconds, estimatedWaterVolumeMl, status string,
	failureReason pgtype.Text,
	postCleaningResult string,
	createdAt time.Time,
	cnt int32, lenCm, spcCm float64,
) *CleaningDTO {
	var localTargetXStr *string
	if lenCm > 0 {
		if targetX, err := strconv.ParseFloat(targetXPositionCm, 64); err == nil {
			posRes := ResolvePanelPosition(cnt, lenCm, spcCm, targetX)
			if !posRes.InGap {
				s := strconv.FormatFloat(posRes.LocalXCm, 'f', 2, 64)
				localTargetXStr = &s
			}
		}
	}

	var attPtr *int32
	if attemptNumber.Valid {
		attPtr = &attemptNumber.Int32
	}
	var fReason *string
	if failureReason.Valid {
		fReason = &failureReason.String
	}
	var startedAtStr, endedAtStr *string
	if startedAt != nil {
		s := startedAt.UTC().Format(time.RFC3339)
		startedAtStr = &s
	}
	if endedAt != nil {
		e := endedAt.UTC().Format(time.RFC3339)
		endedAtStr = &e
	}

	return &CleaningDTO{
		ID:                     auth.FormatUUID(id),
		ModuleID:               auth.FormatUUID(moduleID),
		AnomalyEventID:         auth.FormatUUID(anomalyEventID),
		SourceEventID:          auth.FormatUUID(sourceEventID),
		PanelIndex:             pgInt4ToInt32Ptr(panelIndex),
		TargetXPositionCM:      targetXPositionCm,
		LocalXPositionCM:       localTargetXStr,
		LocalTargetXPositionCM: localTargetXStr,
		PumpActuated:           pumpActuated,
		AttemptNumber:          attPtr,
		StartedAt:              startedAtStr,
		EndedAt:                endedAtStr,
		DurationSeconds:        durationSeconds,
		EstimatedWaterML:       estimatedWaterVolumeMl,
		Status:                 status,
		FailureReason:          fReason,
		PostCleaningResult:     postCleaningResult,
		CreatedAt:              createdAt.UTC().Format(time.RFC3339),
	}
}
