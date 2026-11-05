package module

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

var (
	ErrInspectionCompleted = errors.New("inspection already finalized")
	ErrBatchTooLarge       = errors.New("telemetry batch exceeds maximum limit of 5 items")
)

func (s *Service) ListMeasurements(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, limit, offset int32) ([]MeasurementDTO, error) {
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

	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	if offset < 0 {
		offset = 0
	}

	rows, err := s.queries.ListMeasurementsByModule(ctx, db.ListMeasurementsByModuleParams{
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

	out := make([]MeasurementDTO, 0, len(rows))
	for _, m := range rows {
		var thermalFrameData any
		if len(m.ThermalFrame) > 0 {
			_ = json.Unmarshal(m.ThermalFrame, &thermalFrameData)
		}

		var localXStr *string
		if lenCm > 0 {
			if xVal, pErr := strconv.ParseFloat(m.XPositionCm, 64); pErr == nil {
				posRes := ResolvePanelPosition(cnt, lenCm, spcCm, xVal)
				if !posRes.InGap {
					s := strconv.FormatFloat(posRes.LocalXCm, 'f', 2, 64)
					localXStr = &s
				}
			}
		}
		pIdx := m.PanelIndex

		out = append(out, MeasurementDTO{
			ID:               auth.FormatUUID(m.ID),
			ModuleID:         auth.FormatUUID(m.ModuleID),
			InspectionID:     auth.FormatUUID(m.InspectionID),
			SourceEventID:    auth.FormatUUID(m.SourceEventID),
			PanelIndex:       &pIdx,
			MeasuredAt:       m.MeasuredAt.UTC().Format(time.RFC3339),
			XPositionCM:      m.XPositionCm,
			LocalXPositionCM: localXStr,
			MaxTempC:         m.MaxTemperatureC,
			VoltageV:         numericToStringPtr(m.VoltageV),
			CurrentA:         numericToStringPtr(m.CurrentA),
			PowerW:           numericToStringPtr(m.PowerW),
			ThermalFrame:     thermalFrameData,
			ReceivedAt:       m.ReceivedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
}

func (s *Service) ListInspectionMeasurementsPaged(
	ctx context.Context,
	principal auth.Principal,
	moduleID pgtype.UUID,
	inspectionID pgtype.UUID,
	page, limit int32,
	panelIndex *int32,
) (*PagedMeasurementsDTO, error) {
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

	if page < 1 {
		page = 1
	}
	if limit <= 0 {
		limit = 10
	}
	if limit > 200 {
		limit = 200
	}
	offset := (page - 1) * limit

	var panelIdxParam pgtype.Int4
	if panelIndex != nil {
		if *panelIndex < 1 {
			return nil, ErrInvalidPanelIndex
		}
		panelIdxParam = pgtype.Int4{Int32: *panelIndex, Valid: true}
	}

	totalCount, err := s.queries.CountMeasurementsByInspection(ctx, db.CountMeasurementsByInspectionParams{
		InspectionID: inspectionID,
		ModuleID:     moduleID,
		PanelIndex:   panelIdxParam,
	})
	if err != nil {
		return nil, err
	}

	rows, err := s.queries.ListMeasurementsByInspectionPaged(ctx, db.ListMeasurementsByInspectionPagedParams{
		InspectionID: inspectionID,
		ModuleID:     moduleID,
		PanelIndex:   panelIdxParam,
		Limit:        limit,
		Offset:       offset,
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

	items := make([]MeasurementDTO, 0, len(rows))
	for _, m := range rows {
		var thermalFrameData any
		if len(m.ThermalFrame) > 0 {
			_ = json.Unmarshal(m.ThermalFrame, &thermalFrameData)
		}

		var localXStr *string
		if lenCm > 0 {
			if xVal, pErr := strconv.ParseFloat(m.XPositionCm, 64); pErr == nil {
				posRes := ResolvePanelPosition(cnt, lenCm, spcCm, xVal)
				if !posRes.InGap {
					s := strconv.FormatFloat(posRes.LocalXCm, 'f', 2, 64)
					localXStr = &s
				}
			}
		}
		pIdx := m.PanelIndex

		items = append(items, MeasurementDTO{
			ID:               auth.FormatUUID(m.ID),
			ModuleID:         auth.FormatUUID(m.ModuleID),
			InspectionID:     auth.FormatUUID(m.InspectionID),
			SourceEventID:    auth.FormatUUID(m.SourceEventID),
			PanelIndex:       &pIdx,
			MeasuredAt:       m.MeasuredAt.UTC().Format(time.RFC3339),
			XPositionCM:      m.XPositionCm,
			LocalXPositionCM: localXStr,
			MaxTempC:         m.MaxTemperatureC,
			VoltageV:         numericToStringPtr(m.VoltageV),
			CurrentA:         numericToStringPtr(m.CurrentA),
			PowerW:           numericToStringPtr(m.PowerW),
			ThermalFrame:     thermalFrameData,
			ReceivedAt:       m.ReceivedAt.UTC().Format(time.RFC3339),
		})
	}

	totalPages := 0
	if totalCount > 0 {
		totalPages = int(math.Ceil(float64(totalCount) / float64(limit)))
	}
	hasNextPage := int(page) < totalPages

	return &PagedMeasurementsDTO{
		Pagination: PaginationMetadataDTO{
			Page:        int(page),
			Limit:       int(limit),
			TotalCount:  totalCount,
			TotalPages:  totalPages,
			HasNextPage: hasNextPage,
		},
		Measurements: items,
	}, nil
}

func (s *Service) GetLatestInspection(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) (*LatestInspectionDTO, error) {
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

	inspRow, err := s.queries.GetLatestInspectionByModule(ctx, moduleID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}

	totalMeas, err := s.queries.CountMeasurementsByInspection(ctx, db.CountMeasurementsByInspectionParams{
		InspectionID: inspRow.ID,
		ModuleID:     moduleID,
	})
	if err != nil {
		return nil, err
	}

	anomRows, err := s.queries.ListAnomaliesByInspection(ctx, db.ListAnomaliesByInspectionParams{
		InspectionID: inspRow.ID,
		ModuleID:     moduleID,
	})
	if err != nil {
		return nil, err
	}

	var baseTempPtr *float64
	if inspRow.BaselineTemperatureC != "" {
		if bVal, err := strconv.ParseFloat(inspRow.BaselineTemperatureC, 64); err == nil {
			baseTempPtr = &bVal
		}
	}

	var startedAtStr, finishedAtStr, cleanOpIDStr *string
	if inspRow.StartedAt != nil {
		s := inspRow.StartedAt.UTC().Format(time.RFC3339)
		startedAtStr = &s
	}
	if inspRow.FinishedAt != nil {
		f := inspRow.FinishedAt.UTC().Format(time.RFC3339)
		finishedAtStr = &f
	}
	if inspRow.CleaningOperationID.Valid {
		c := auth.FormatUUID(inspRow.CleaningOperationID)
		cleanOpIDStr = &c
	}
	var verifResult *string
	if inspRow.VerificationResult.Valid {
		verifResult = &inspRow.VerificationResult.String
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

	anomalies := make([]ConfirmedAnomalyDTO, 0, len(anomRows))
	for _, a := range anomRows {
		xPos, _ := strconv.ParseFloat(a.XPositionCm, 64)
		confirmingIDs := make([]string, 0, len(a.ConfirmingMeasurementIds))
		for _, cid := range a.ConfirmingMeasurementIds {
			confirmingIDs = append(confirmingIDs, auth.FormatUUID(cid))
		}

		var closedAtStr *string
		if a.ClosedAt != nil {
			c := a.ClosedAt.UTC().Format(time.RFC3339)
			closedAtStr = &c
		}

		var localXPtr *float64
		if lenCm > 0 {
			posRes := ResolvePanelPosition(cnt, lenCm, spcCm, xPos)
			if !posRes.InGap {
				localXPtr = &posRes.LocalXCm
			}
		}
		pIdx := a.PanelIndex

		anomalies = append(anomalies, ConfirmedAnomalyDTO{
			ID:                       auth.FormatUUID(a.ID),
			ModuleID:                 auth.FormatUUID(a.ModuleID),
			OriginMeasurementID:      auth.FormatUUID(a.OriginMeasurementID),
			ConfirmingMeasurementIDs: confirmingIDs,
			SourceEventID:            auth.FormatUUID(a.SourceEventID),
			PanelIndex:               &pIdx,
			XPositionCM:              xPos,
			LocalXPositionCM:         localXPtr,
			DetectedAt:               a.DetectedAt.UTC().Format(time.RFC3339),
			Status:                   a.Status,
			ActuatedAttemptsCount:    a.ActuatedAttemptsCount,
			RetryPending:             a.RetryPending,
			ClosedAt:                 closedAtStr,
		})
	}

	panelResultsRows, err := s.queries.ListInspectionPanelResults(ctx, db.ListInspectionPanelResultsParams{
		InspectionID: inspRow.ID,
		ModuleID:     moduleID,
	})
	var panelResults []InspectionPanelResultDTO
	if err == nil && len(panelResultsRows) > 0 {
		panelResults = make([]InspectionPanelResultDTO, 0, len(panelResultsRows))
		for _, pr := range panelResultsRows {
			bVal, _ := strconv.ParseFloat(pr.BaselineTemperatureC, 64)
			panelResults = append(panelResults, InspectionPanelResultDTO{
				InspectionID:          auth.FormatUUID(pr.InspectionID),
				ModuleID:              auth.FormatUUID(pr.ModuleID),
				PanelIndex:            pr.PanelIndex,
				BaselineTemperatureC: bVal,
				TruncatedByMemory:     pr.TruncatedByMemory,
				FinishedAt:            pr.FinishedAt.UTC().Format(time.RFC3339),
				CreatedAt:             pr.CreatedAt.UTC().Format(time.RFC3339),
			})
		}
	}

	return &LatestInspectionDTO{
		Inspection: InspectionDTO{
			ID:                   auth.FormatUUID(inspRow.ID),
			ModuleID:             auth.FormatUUID(inspRow.ModuleID),
			SourceEventID:        auth.FormatUUID(inspRow.SourceEventID),
			Type:                 inspRow.Type,
			CleaningOperationID:  cleanOpIDStr,
			BaselineTemperatureC: baseTempPtr,
			ScheduledFor:         inspRow.ScheduledFor.UTC().Format(time.RFC3339),
			StartedAt:            startedAtStr,
			FinishedAt:           finishedAtStr,
			Status:               inspRow.Status,
			VerificationResult:   verifResult,
			CreatedAt:            inspRow.CreatedAt.UTC().Format(time.RFC3339),
			UpdatedAt:            inspRow.UpdatedAt.UTC().Format(time.RFC3339),
		},
		TotalMeasurements:  totalMeas,
		ConfirmedAnomalies: anomalies,
		PanelResults:       panelResults,
	}, nil
}

func (s *Service) IngestTelemetry(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, input IngestTelemetryInput) (*MeasurementDTO, error) {
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

	// 1. Gather upload frames
	var items []IngestMeasurementItemInput
	if len(input.Batch) > 0 {
		items = input.Batch
	} else if len(input.Measurements) > 0 {
		items = input.Measurements
	} else if len(input.ThermalFrame) > 0 {
		sourceID := ""
		if input.SourceEventID != nil {
			sourceID = *input.SourceEventID
		}
		items = []IngestMeasurementItemInput{
			{
				SourceEventID:   sourceID,
				PanelIndex:      input.PanelIndex,
				MeasuredAt:      input.MeasuredAt,
				XPositionCm:     input.XPositionCm,
				MaxTemperatureC: input.MaxTemperatureC,
				VoltageV:        input.VoltageV,
				CurrentA:        input.CurrentA,
				PowerW:          input.PowerW,
				ThermalFrame:    input.ThermalFrame,
			},
		}
	}

	if len(items) == 0 {
		return nil, fmt.Errorf("%w: batch cannot be empty", ErrInvalidInput)
	}
	if len(items) > 5 {
		return nil, ErrBatchTooLarge
	}

	// Validate mandatory inspection_source_event_id
	if input.InspectionSourceEventID == nil || strings.TrimSpace(*input.InspectionSourceEventID) == "" {
		return nil, fmt.Errorf("%w: inspection_source_event_id is required", ErrInvalidInput)
	}
	inspSourceUUID, err := auth.ParseUUID(strings.TrimSpace(*input.InspectionSourceEventID))
	if err != nil {
		return nil, fmt.Errorf("%w: invalid inspection_source_event_id UUID: %w", ErrInvalidInput, err)
	}

	// Validate intra-batch uniqueness of source_event_id
	seenSourceIDs := make(map[string]struct{}, len(items))
	for _, f := range items {
		if f.SourceEventID == "" && len(items) > 1 {
			return nil, fmt.Errorf("%w: source_event_id is required for batch items", ErrInvalidInput)
		}
		if f.SourceEventID != "" {
			if _, exists := seenSourceIDs[f.SourceEventID]; exists {
				return nil, fmt.Errorf("%w: duplicate source_event_id %q in batch", ErrInvalidInput, f.SourceEventID)
			}
			seenSourceIDs[f.SourceEventID] = struct{}{}
		}
	}

	// Validate bounds and finite values
	panelLength := numericToFloatPtr(row.PanelLengthCm)
	panelCount := pgInt4ToInt32Ptr(row.PanelCount)
	panelSpacing := numericToFloatPtr(row.PanelSpacingCm)
	cnt := int32(1)
	if panelCount != nil && *panelCount > 0 {
		cnt = *panelCount
	}
	lenCm := 0.0
	if panelLength != nil {
		lenCm = *panelLength
	}
	spcCm := 0.0
	if panelSpacing != nil && *panelSpacing > 0 {
		spcCm = *panelSpacing
	}

	for _, f := range items {
		if f.PanelIndex != nil && (*f.PanelIndex < 1 || *f.PanelIndex > cnt) {
			return nil, fmt.Errorf("%w: item panel_index %d must be between 1 and %d", ErrInvalidInput, *f.PanelIndex, cnt)
		}
		if f.XPositionCm < 0 {
			return nil, fmt.Errorf("%w: x_position_cm (%.1f) cannot be negative", ErrInvalidInput, f.XPositionCm)
		}
		if lenCm > 0 {
			posRes := ResolvePanelPosition(cnt, lenCm, spcCm, f.XPositionCm)
			if !posRes.WithinBounds {
				maxLen := CalculateTotalStringLength(cnt, lenCm, spcCm)
				return nil, fmt.Errorf("%w: x_position_cm (%.1f) exceeds module string length (%.1f)", ErrInvalidInput, f.XPositionCm, maxLen)
			}
			if posRes.InGap {
				return nil, fmt.Errorf("%w: x_position_cm (%.1f) falls inside inter-panel gap", ErrMeasurementInGap, f.XPositionCm)
			}
			if f.PanelIndex != nil && *f.PanelIndex != posRes.PanelIndex {
				return nil, fmt.Errorf("%w: item panel_index %d does not match rail position panel %d", ErrInvalidInput, *f.PanelIndex, posRes.PanelIndex)
			}
		}
		if !isFinite(f.XPositionCm) || !isFinite(f.MaxTemperatureC) {
			return nil, fmt.Errorf("%w: x_position_cm and max_temperature_c must be finite numbers", ErrInvalidInput)
		}
		if !isFinitePtr(f.VoltageV) || !isFinitePtr(f.CurrentA) || !isFinitePtr(f.PowerW) {
			return nil, fmt.Errorf("%w: electrical readings must be finite numbers or null", ErrInvalidInput)
		}
		if len(f.ThermalFrame) != 32*24 {
			return nil, fmt.Errorf("%w: thermal frame must have exactly 768 pixels (got %d)", ErrInvalidInput, len(f.ThermalFrame))
		}
		for _, v := range f.ThermalFrame {
			if v != nil && !isFinite(*v) {
				return nil, fmt.Errorf("%w: thermal frame pixels must be finite numbers or null", ErrInvalidInput)
			}
		}
	}

	now := time.Now().UTC()

	// 2. Resolve or create Inspection session
	var inspID pgtype.UUID
	inspType := "scheduled"
	if input.InspectionType != nil && *input.InspectionType != "" {
		inspType = *input.InspectionType
	}

	var cleanOpUUID pgtype.UUID
	if input.CleaningOperationID != nil && *input.CleaningOperationID != "" {
		cleanOpUUID, err = auth.ParseUUID(*input.CleaningOperationID)
		if err != nil {
			return nil, ErrInvalidInput
		}
	}

	if inspType == "verification" {
		if !cleanOpUUID.Valid {
			return nil, ErrInvalidInput
		}
		cleanOp, err := qtx.GetCleaningOperationByID(ctx, db.GetCleaningOperationByIDParams{
			ID:       cleanOpUUID,
			ModuleID: moduleID,
		})
		if err != nil {
			return nil, ErrInvalidInput
		}
		if !cleanOp.PumpActuated || cleanOp.PostCleaningResult != "pending" {
			return nil, ErrInvalidInput
		}
	}

	existingInsp, err := qtx.GetInspectionBySourceEventID(ctx, db.GetInspectionBySourceEventIDParams{
		ModuleID:      moduleID,
		SourceEventID: inspSourceUUID,
	})
	if err == nil {
		inspID = existingInsp.ID
	} else if errors.Is(err, pgx.ErrNoRows) {
		startedAt := now
		if input.StartedAt != nil && !input.StartedAt.IsZero() {
			startedAt = input.StartedAt.UTC()
		} else if input.InspectionStartedAt != nil && !input.InspectionStartedAt.IsZero() {
			startedAt = input.InspectionStartedAt.UTC()
		}

		schedFor := startedAt
		if input.ScheduledFor != nil && !input.ScheduledFor.IsZero() {
			schedFor = input.ScheduledFor.UTC()
		} else if input.InspectionScheduledFor != nil && !input.InspectionScheduledFor.IsZero() {
			schedFor = input.InspectionScheduledFor.UTC()
		}

		newInsp, err := qtx.CreateInspection(ctx, db.CreateInspectionParams{
			ModuleID:            moduleID,
			SourceEventID:       inspSourceUUID,
			Type:                inspType,
			CleaningOperationID: cleanOpUUID,
			ScheduledFor:        schedFor,
			StartedAt:           &startedAt,
			FinishedAt:          nil,
			Status:              "in_progress",
		})
		if err != nil {
			return nil, err
		}
		inspID = newInsp.ID
		if inspType == "scheduled" {
			_ = qtx.ClearPendingScheduledInspections(ctx, moduleID)
		}
	} else {
		return nil, err
	}

	// 3. Ingest each measurement frame (chunked upload, idempotent via ON CONFLICT)
	var primaryMeasRow *db.CreateMeasurementRow

	for _, f := range items {
		fMeasuredAt := now
		if f.MeasuredAt != nil && !f.MeasuredAt.IsZero() {
			fMeasuredAt = f.MeasuredAt.UTC()
		}

		var powerW *float64
		if f.PowerW != nil {
			powerW = f.PowerW
		} else if f.VoltageV != nil && f.CurrentA != nil {
			calcP := *f.VoltageV * *f.CurrentA
			powerW = &calcP
		}

		frameBytes, err := json.Marshal(f.ThermalFrame)
		if err != nil {
			return nil, err
		}

		var measSourceUUID pgtype.UUID
		if f.SourceEventID != "" {
			measSourceUUID, err = auth.ParseUUID(f.SourceEventID)
			if err != nil {
				return nil, ErrInvalidInput
			}
		} else {
			measSourceUUID = newRandomUUID()
		}

		itemPanelIndex := int32(1)
		if lenCm > 0 {
			posRes := ResolvePanelPosition(cnt, lenCm, spcCm, f.XPositionCm)
			itemPanelIndex = posRes.PanelIndex
		} else if f.PanelIndex != nil && *f.PanelIndex > 0 {
			itemPanelIndex = *f.PanelIndex
		}

		meas, err := qtx.CreateMeasurement(ctx, db.CreateMeasurementParams{
			ModuleID:        moduleID,
			InspectionID:    inspID,
			SourceEventID:   measSourceUUID,
			PanelIndex:      itemPanelIndex,
			MeasuredAt:      fMeasuredAt,
			XPositionCm:     floatPtrToNumeric(&f.XPositionCm),
			MaxTemperatureC: floatPtrToNumeric(&f.MaxTemperatureC),
			VoltageV:        floatPtrToNumeric(f.VoltageV),
			CurrentA:        floatPtrToNumeric(f.CurrentA),
			PowerW:          floatPtrToNumeric(powerW),
			ThermalFrame:    frameBytes,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				existingMeas, getErr := qtx.GetMeasurementBySourceEventID(ctx, db.GetMeasurementBySourceEventIDParams{
					ModuleID:      moduleID,
					SourceEventID: measSourceUUID,
				})
				if getErr != nil {
					return nil, getErr
				}

				// Strict deterministic idempotency comparison
				// 1. x_position_cm: diff < 1e-3
				existX, pErr := strconv.ParseFloat(existingMeas.XPositionCm, 64)
				if pErr != nil || math.Abs(existX-f.XPositionCm) >= 1e-3 {
					return nil, ErrConflict
				}

				// 2. max_temperature_c: diff < 1e-3
				existMaxTemp, pErr := strconv.ParseFloat(existingMeas.MaxTemperatureC, 64)
				if pErr != nil || math.Abs(existMaxTemp-f.MaxTemperatureC) >= 1e-3 {
					return nil, ErrConflict
				}

				// 3. voltage_v: both null or diff < 1e-3
				existVoltage := numericToFloatPtr(existingMeas.VoltageV)
				if (existVoltage == nil && f.VoltageV != nil) || (existVoltage != nil && f.VoltageV == nil) {
					return nil, ErrConflict
				}
				if existVoltage != nil && f.VoltageV != nil && math.Abs(*existVoltage-*f.VoltageV) >= 1e-3 {
					return nil, ErrConflict
				}

				// 4. current_a: both null or diff < 1e-3
				existCurrent := numericToFloatPtr(existingMeas.CurrentA)
				if (existCurrent == nil && f.CurrentA != nil) || (existCurrent != nil && f.CurrentA == nil) {
					return nil, ErrConflict
				}
				if existCurrent != nil && f.CurrentA != nil && math.Abs(*existCurrent-*f.CurrentA) >= 1e-3 {
					return nil, ErrConflict
				}

				// 5. power_w: both null or diff < 1e-3
				existPower := numericToFloatPtr(existingMeas.PowerW)
				if (existPower == nil && powerW != nil) || (existPower != nil && powerW == nil) {
					return nil, ErrConflict
				}
				if existPower != nil && powerW != nil && math.Abs(*existPower-*powerW) >= 1e-3 {
					return nil, ErrConflict
				}

				// 6. thermal_frame: exactly 768 positions, nulls at same indices, values diff < 1e-3
				var existFrame []*float64
				if unmarshalErr := json.Unmarshal(existingMeas.ThermalFrame, &existFrame); unmarshalErr != nil {
					return nil, unmarshalErr
				}
				if len(existFrame) != 768 || len(f.ThermalFrame) != 768 {
					return nil, ErrConflict
				}
				for i := 0; i < 768; i++ {
					v1 := existFrame[i]
					v2 := f.ThermalFrame[i]
					if (v1 == nil && v2 != nil) || (v1 != nil && v2 == nil) {
						return nil, ErrConflict
					}
					if v1 != nil && v2 != nil && math.Abs(*v1-*v2) >= 1e-3 {
						return nil, ErrConflict
					}
				}

				// 7. panel_index: exact match
				if existingMeas.PanelIndex != itemPanelIndex {
					return nil, ErrConflict
				}

				meas = db.CreateMeasurementRow{
					ID:              existingMeas.ID,
					ModuleID:        existingMeas.ModuleID,
					InspectionID:    existingMeas.InspectionID,
					SourceEventID:   existingMeas.SourceEventID,
					PanelIndex:      existingMeas.PanelIndex,
					MeasuredAt:      existingMeas.MeasuredAt,
					XPositionCm:     existingMeas.XPositionCm,
					MaxTemperatureC: existingMeas.MaxTemperatureC,
					VoltageV:        existingMeas.VoltageV,
					CurrentA:        existingMeas.CurrentA,
					PowerW:          existingMeas.PowerW,
					ThermalFrame:    existingMeas.ThermalFrame,
					ReceivedAt:      existingMeas.ReceivedAt,
				}
			} else {
				return nil, err
			}
		}

		if primaryMeasRow == nil {
			primaryMeasRow = &meas
		}
	}

	// 4. Update device online timestamp
	_, _ = qtx.UpdateModuleDeviceHealth(ctx, db.UpdateModuleDeviceHealthParams{
		ID: moduleID,
	})

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	meas := primaryMeasRow
	var thermalFrameData any
	if len(meas.ThermalFrame) > 0 {
		_ = json.Unmarshal(meas.ThermalFrame, &thermalFrameData)
	}

	var localXStr *string
	if lenCm > 0 {
		if xVal, pErr := strconv.ParseFloat(meas.XPositionCm, 64); pErr == nil {
			posRes := ResolvePanelPosition(cnt, lenCm, spcCm, xVal)
			if !posRes.InGap {
				s := strconv.FormatFloat(posRes.LocalXCm, 'f', 2, 64)
				localXStr = &s
			}
		}
	}
	pIdx := meas.PanelIndex

	return &MeasurementDTO{
		ID:               auth.FormatUUID(meas.ID),
		ModuleID:         auth.FormatUUID(meas.ModuleID),
		InspectionID:     auth.FormatUUID(meas.InspectionID),
		SourceEventID:    auth.FormatUUID(meas.SourceEventID),
		PanelIndex:       &pIdx,
		MeasuredAt:       meas.MeasuredAt.UTC().Format(time.RFC3339),
		XPositionCM:      meas.XPositionCm,
		LocalXPositionCM: localXStr,
		MaxTempC:         meas.MaxTemperatureC,
		VoltageV:         numericToStringPtr(meas.VoltageV),
		CurrentA:         numericToStringPtr(meas.CurrentA),
		PowerW:           numericToStringPtr(meas.PowerW),
		ThermalFrame:     thermalFrameData,
		ReceivedAt:       meas.ReceivedAt.UTC().Format(time.RFC3339),
	}, nil
}

func (s *Service) FinalizeInspection(
	ctx context.Context,
	principal auth.Principal,
	moduleID pgtype.UUID,
	inspSourceEventID pgtype.UUID,
	input FinalizeInspectionInput,
) (*LatestInspectionDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid || !inspSourceEventID.Valid {
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

	insp, err := qtx.GetInspectionBySourceEventID(ctx, db.GetInspectionBySourceEventIDParams{
		ModuleID:      moduleID,
		SourceEventID: inspSourceEventID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	// Idempotency check: if inspection is already completed, return existing state
	if insp.Status == "completed" {
		_ = tx.Rollback(ctx)
		return s.GetLatestInspection(ctx, principal, moduleID)
	}

	panelLength := numericToFloatPtr(row.PanelLengthCm)
	panelCount := pgInt4ToInt32Ptr(row.PanelCount)
	panelSpacing := numericToFloatPtr(row.PanelSpacingCm)
	cnt := int32(1)
	if panelCount != nil && *panelCount > 0 {
		cnt = *panelCount
	}
	lenCm := 0.0
	if panelLength != nil {
		lenCm = *panelLength
	}
	spcCm := 0.0
	if panelSpacing != nil && *panelSpacing > 0 {
		spcCm = *panelSpacing
	}

	// Validate confirmed hotspots input
	for _, ch := range input.ConfirmedHotspots {
		if ch.OriginMeasurementEventID == "" {
			return nil, ErrInvalidInput
		}
		if _, err := auth.ParseUUID(ch.OriginMeasurementEventID); err != nil {
			return nil, ErrInvalidInput
		}
		if len(ch.ConfirmingEventIDs) < 2 {
			return nil, ErrInvalidInput
		}
		seenConfirming := make(map[string]struct{}, len(ch.ConfirmingEventIDs))
		foundOrigin := false
		for _, cidStr := range ch.ConfirmingEventIDs {
			if cidStr == "" {
				return nil, ErrInvalidInput
			}
			if _, err := auth.ParseUUID(cidStr); err != nil {
				return nil, ErrInvalidInput
			}
			seenConfirming[cidStr] = struct{}{}
			if cidStr == ch.OriginMeasurementEventID {
				foundOrigin = true
			}
		}
		if len(seenConfirming) < 2 || !foundOrigin {
			return nil, ErrInvalidInput
		}
		if ch.RowIndex != nil {
			if *ch.RowIndex < 0 || *ch.RowIndex > 23 {
				return nil, ErrInvalidInput
			}
		}
		if ch.GlobalXPositionCm < 0 || !isFinite(ch.GlobalXPositionCm) || !isFinite(ch.MaxTemperatureC) {
			return nil, ErrInvalidInput
		}
		if ch.PanelIndex != nil && (*ch.PanelIndex < 1 || *ch.PanelIndex > cnt) {
			return nil, ErrInvalidInput
		}
		if lenCm > 0 {
			posRes := ResolvePanelPosition(cnt, lenCm, spcCm, ch.GlobalXPositionCm)
			if !posRes.WithinBounds {
				return nil, fmt.Errorf("%w: hotspot position outside string bounds", ErrInvalidInput)
			}
			if posRes.InGap {
				return nil, fmt.Errorf("%w: hotspot position falls inside inter-panel gap", ErrHotspotInGap)
			}
			if ch.PanelIndex != nil && *ch.PanelIndex != posRes.PanelIndex {
				return nil, fmt.Errorf("%w: hotspot panel_index %d does not match position panel %d", ErrInvalidInput, *ch.PanelIndex, posRes.PanelIndex)
			}
		}
		if ch.SourceEventID != "" {
			if _, err := auth.ParseUUID(ch.SourceEventID); err != nil {
				return nil, ErrInvalidInput
			}
		}
	}

	now := time.Now().UTC()
	finAt := now
	if input.FinishedAt != nil && !input.FinishedAt.IsZero() {
		finAt = input.FinishedAt.UTC()
	}

	var verifResultPg pgtype.Text
	var origAnomaly db.GetAnomalyEventByIDRow
	if insp.Type == "verification" {
		if !insp.CleaningOperationID.Valid {
			return nil, ErrInvalidInput
		}
		cleanOp, err := qtx.GetCleaningOperationByID(ctx, db.GetCleaningOperationByIDParams{
			ID:       insp.CleaningOperationID,
			ModuleID: moduleID,
		})
		if err != nil {
			return nil, ErrInvalidInput
		}
		origAnomaly, err = qtx.GetAnomalyEventByID(ctx, db.GetAnomalyEventByIDParams{
			ID:       cleanOp.AnomalyEventID,
			ModuleID: moduleID,
		})
		if err != nil {
			return nil, ErrInvalidInput
		}

		hotspotPersists := false
		origX, origXErr := strconv.ParseFloat(origAnomaly.XPositionCm, 64)
		for _, ch := range input.ConfirmedHotspots {
			if ch.SourceEventID != "" && auth.FormatUUID(origAnomaly.SourceEventID) == ch.SourceEventID {
				hotspotPersists = true
				break
			}
			if origXErr == nil && math.Abs(ch.GlobalXPositionCm-origX) <= 1.0 {
				hotspotPersists = true
				break
			}
		}
		if !hotspotPersists && len(input.ConfirmedHotspots) > 0 {
			hotspotPersists = true
		}
		if !hotspotPersists {
			existingAnoms, _ := qtx.ListAnomaliesByInspection(ctx, db.ListAnomaliesByInspectionParams{
				InspectionID: insp.ID,
				ModuleID:     moduleID,
			})
			if len(existingAnoms) > 0 {
				hotspotPersists = true
			}
		}
		if !hotspotPersists && len(origAnomaly.ConfirmingMeasurementIds) > 0 {
			inspMeas, _ := qtx.ListMeasurementsByInspectionPaged(ctx, db.ListMeasurementsByInspectionPagedParams{
				InspectionID: insp.ID,
				ModuleID:     moduleID,
				Limit:        200,
				Offset:       0,
			})
			if len(inspMeas) > 0 {
				confirmingSet := make(map[[16]byte]struct{}, len(origAnomaly.ConfirmingMeasurementIds))
				for _, cid := range origAnomaly.ConfirmingMeasurementIds {
					confirmingSet[cid.Bytes] = struct{}{}
				}
				for _, im := range inspMeas {
					if _, ok := confirmingSet[im.ID.Bytes]; ok {
						hotspotPersists = true
						break
					}
				}
			}
		}

		closedAt := now
		if closedAt.Before(origAnomaly.DetectedAt) {
			closedAt = origAnomaly.DetectedAt
		}

		if !hotspotPersists {
			verifResultPg = pgtype.Text{String: "resolved", Valid: true}
			_, err = qtx.UpdateCleaningOperationPostResult(ctx, db.UpdateCleaningOperationPostResultParams{
				PostCleaningResult: "resolved",
				ID:                 cleanOp.ID,
				ModuleID:           moduleID,
			})
			if err != nil {
				return nil, err
			}
			_, err = qtx.UpdateAnomalyEventVerification(ctx, db.UpdateAnomalyEventVerificationParams{
				Status:       "resolved",
				RetryPending: false,
				RetryReason:  pgtype.Text{Valid: false},
				ClosedAt:     &closedAt,
				ID:           origAnomaly.ID,
				ModuleID:     moduleID,
			})
			if err != nil {
				return nil, err
			}
		} else {
			verifResultPg = pgtype.Text{String: "unresolved", Valid: true}
			_, err = qtx.UpdateCleaningOperationPostResult(ctx, db.UpdateCleaningOperationPostResultParams{
				PostCleaningResult: "unresolved",
				ID:                 cleanOp.ID,
				ModuleID:           moduleID,
			})
			if err != nil {
				return nil, err
			}

			if cleanOp.Status == "completed" {
				_, err = qtx.UpdateAnomalyEventVerification(ctx, db.UpdateAnomalyEventVerificationParams{
					Status:       "unresolved",
					RetryPending: false,
					RetryReason:  pgtype.Text{Valid: false},
					ClosedAt:     &closedAt,
					ID:           origAnomaly.ID,
					ModuleID:     moduleID,
				})
				if err != nil {
					return nil, err
				}
			} else if cleanOp.Status == "failed" && origAnomaly.ActuatedAttemptsCount < 3 {
				_, err = qtx.UpdateAnomalyEventVerification(ctx, db.UpdateAnomalyEventVerificationParams{
					Status:       "open",
					RetryPending: true,
					RetryReason:  pgtype.Text{String: "Interrupted cleaning - retry pending verification", Valid: true},
					ClosedAt:     nil,
					ID:           origAnomaly.ID,
					ModuleID:     moduleID,
				})
				if err != nil {
					return nil, err
				}
			} else {
				_, err = qtx.UpdateAnomalyEventVerification(ctx, db.UpdateAnomalyEventVerificationParams{
					Status:       "unresolved",
					RetryPending: false,
					RetryReason:  pgtype.Text{Valid: false},
					ClosedAt:     &closedAt,
					ID:           origAnomaly.ID,
					ModuleID:     moduleID,
				})
				if err != nil {
					return nil, err
				}
			}
		}
	}

	panelResults, _ := qtx.ListInspectionPanelResults(ctx, db.ListInspectionPanelResultsParams{
		InspectionID: insp.ID,
		ModuleID:     moduleID,
	})
	baselineTemp := input.BaselineTemperatureC
	if baselineTemp <= 0 && len(panelResults) > 0 {
		sum := 0.0
		for _, pr := range panelResults {
			val, _ := strconv.ParseFloat(pr.BaselineTemperatureC, 64)
			sum += val
		}
		baselineTemp = sum / float64(len(panelResults))
	}
	if len(panelResults) == 0 && cnt == 1 {
		_, err = qtx.UpsertInspectionPanelResult(ctx, db.UpsertInspectionPanelResultParams{
			InspectionID:         insp.ID,
			ModuleID:             moduleID,
			PanelIndex:           1,
			BaselineTemperatureC: floatPtrToNumeric(&baselineTemp),
			TruncatedByMemory:    false,
			FinishedAt:           finAt,
		})
		if err != nil {
			return nil, err
		}
	}

	_, err = qtx.FinalizeInspection(ctx, db.FinalizeInspectionParams{
		Status:               "completed",
		FinishedAt:           &finAt,
		BaselineTemperatureC: floatPtrToNumeric(&baselineTemp),
		VerificationResult:   verifResultPg,
		ID:                   insp.ID,
		ModuleID:             moduleID,
	})
	if err != nil {
		return nil, err
	}
	_ = qtx.ClearPendingScheduledInspections(ctx, moduleID)

	// Process confirmed hotspots
	for _, ch := range input.ConfirmedHotspots {
		if insp.Type == "verification" && origAnomaly.ID.Valid {
			origX, origXErr := strconv.ParseFloat(origAnomaly.XPositionCm, 64)
			if (ch.SourceEventID != "" && auth.FormatUUID(origAnomaly.SourceEventID) == ch.SourceEventID) ||
				(origXErr == nil && math.Abs(ch.GlobalXPositionCm-origX) <= 1.0) {
				continue
			}
		}

		origSourceUUID, err := auth.ParseUUID(ch.OriginMeasurementEventID)
		if err != nil {
			return nil, ErrInvalidInput
		}
		origMeasRow, err := qtx.GetMeasurementBySourceEventID(ctx, db.GetMeasurementBySourceEventIDParams{
			ModuleID:      moduleID,
			SourceEventID: origSourceUUID,
		})
		if err != nil || origMeasRow.InspectionID.Bytes != insp.ID.Bytes {
			return nil, ErrInvalidInput
		}
		originMeasID := origMeasRow.ID

		confirmingUUIDs := make([]pgtype.UUID, 0, len(ch.ConfirmingEventIDs))
		distinctMeasIDs := make(map[[16]byte]struct{}, len(ch.ConfirmingEventIDs))
		var maxMeasuredAt time.Time

		for _, cidStr := range ch.ConfirmingEventIDs {
			cidUUID, err := auth.ParseUUID(cidStr)
			if err != nil {
				return nil, ErrInvalidInput
			}
			mRow, err := qtx.GetMeasurementBySourceEventID(ctx, db.GetMeasurementBySourceEventIDParams{
				ModuleID:      moduleID,
				SourceEventID: cidUUID,
			})
			if err != nil || mRow.InspectionID.Bytes != insp.ID.Bytes {
				return nil, ErrInvalidInput
			}
			confirmingUUIDs = append(confirmingUUIDs, mRow.ID)
			distinctMeasIDs[mRow.ID.Bytes] = struct{}{}
			if maxMeasuredAt.IsZero() || mRow.MeasuredAt.After(maxMeasuredAt) {
				maxMeasuredAt = mRow.MeasuredAt
			}
		}

		if len(distinctMeasIDs) < 2 {
			return nil, ErrInvalidInput
		}

		detectedAt := maxMeasuredAt
		if ch.DetectedAt != nil && !ch.DetectedAt.IsZero() {
			detectedAt = ch.DetectedAt.UTC()
		}

		var anomSourceUUID pgtype.UUID
		if ch.SourceEventID != "" {
			anomSourceUUID, err = auth.ParseUUID(ch.SourceEventID)
			if err != nil {
				return nil, ErrInvalidInput
			}
		} else {
			anomSourceUUID = newRandomUUID()
		}

		anomPanelIndex := origMeasRow.PanelIndex
		if lenCm > 0 {
			posRes := ResolvePanelPosition(cnt, lenCm, spcCm, ch.GlobalXPositionCm)
			anomPanelIndex = posRes.PanelIndex
		} else if ch.PanelIndex != nil && *ch.PanelIndex > 0 {
			anomPanelIndex = *ch.PanelIndex
		}

		_, err = qtx.CreateAnomalyEvent(ctx, db.CreateAnomalyEventParams{
			ModuleID:                 moduleID,
			OriginMeasurementID:      originMeasID,
			ConfirmingMeasurementIds: confirmingUUIDs,
			SourceEventID:            anomSourceUUID,
			PanelIndex:               anomPanelIndex,
			XPositionCm:              floatPtrToNumeric(&ch.GlobalXPositionCm),
			DetectedAt:               detectedAt,
			Status:                   "open",
			ActuatedAttemptsCount:    0,
			RetryPending:             false,
		})
		if err != nil {
			return nil, err
		}
	}

	_, _ = qtx.UpdateModuleDeviceHealth(ctx, db.UpdateModuleDeviceHealthParams{
		ID: moduleID,
	})

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return s.GetLatestInspection(ctx, principal, moduleID)
}

func (s *Service) RecordPanelThermalResult(
	ctx context.Context,
	principal auth.Principal,
	moduleID pgtype.UUID,
	inspSourceEventID pgtype.UUID,
	panelIndex int32,
	input RecordPanelResultInput,
) (*RecordPanelResultOutputDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid || !inspSourceEventID.Valid {
		return nil, ErrForbidden
	}
	if panelIndex < 1 {
		return nil, ErrInvalidPanelIndex
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

	maxPanels := int32(1)
	if row.PanelCount.Valid && row.PanelCount.Int32 > 0 {
		maxPanels = row.PanelCount.Int32
	}
	if panelIndex > maxPanels {
		return nil, ErrInvalidPanelIndex
	}

	insp, err := qtx.GetInspectionBySourceEventID(ctx, db.GetInspectionBySourceEventIDParams{
		ModuleID:      moduleID,
		SourceEventID: inspSourceEventID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if insp.Status == "completed" {
		return nil, ErrInspectionCompleted
	}

	var origAnomaly db.GetAnomalyEventByIDRow
	if insp.Type == "verification" && insp.CleaningOperationID.Valid {
		if cleanOp, cErr := qtx.GetCleaningOperationByID(ctx, db.GetCleaningOperationByIDParams{
			ID:       insp.CleaningOperationID,
			ModuleID: moduleID,
		}); cErr == nil {
			origAnomaly, _ = qtx.GetAnomalyEventByID(ctx, db.GetAnomalyEventByIDParams{
				ID:       cleanOp.AnomalyEventID,
				ModuleID: moduleID,
			})
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

	// Validate hotspots for this panel
	for _, ch := range input.ConfirmedHotspots {
		if ch.OriginMeasurementEventID == "" || len(ch.ConfirmingEventIDs) < 2 {
			return nil, ErrInvalidInput
		}
		if _, err := auth.ParseUUID(ch.OriginMeasurementEventID); err != nil {
			return nil, ErrInvalidInput
		}
		seenConfirming := make(map[string]struct{}, len(ch.ConfirmingEventIDs))
		foundOrigin := false
		for _, cidStr := range ch.ConfirmingEventIDs {
			if cidStr == "" {
				return nil, ErrInvalidInput
			}
			if _, err := auth.ParseUUID(cidStr); err != nil {
				return nil, ErrInvalidInput
			}
			seenConfirming[cidStr] = struct{}{}
			if cidStr == ch.OriginMeasurementEventID {
				foundOrigin = true
			}
		}
		if len(seenConfirming) < 2 || !foundOrigin {
			return nil, ErrInvalidInput
		}
		if ch.RowIndex != nil && (*ch.RowIndex < 0 || *ch.RowIndex > 23) {
			return nil, ErrInvalidInput
		}
		if ch.GlobalXPositionCm < 0 || !isFinite(ch.GlobalXPositionCm) || !isFinite(ch.MaxTemperatureC) {
			return nil, ErrInvalidInput
		}
		if ch.PanelIndex != nil && *ch.PanelIndex != panelIndex {
			return nil, ErrPanelIndexMismatch
		}
		if lenCm > 0 {
			posRes := ResolvePanelPosition(cnt, lenCm, spcCm, ch.GlobalXPositionCm)
			if !posRes.WithinBounds {
				return nil, ErrPositionOutOfBounds
			}
			if posRes.InGap {
				return nil, ErrHotspotInGap
			}
			if posRes.PanelIndex != panelIndex {
				return nil, ErrPanelIndexMismatch
			}
		}
	}

	finAt := time.Now().UTC()
	if input.FinishedAt != nil && !input.FinishedAt.IsZero() {
		finAt = input.FinishedAt.UTC()
	}

	panelResultRow, err := qtx.UpsertInspectionPanelResult(ctx, db.UpsertInspectionPanelResultParams{
		InspectionID:         insp.ID,
		ModuleID:             moduleID,
		PanelIndex:           panelIndex,
		BaselineTemperatureC: floatPtrToNumeric(&input.BaselineTemperatureC),
		TruncatedByMemory:    input.TruncatedByMemory,
		FinishedAt:           finAt,
	})
	if err != nil {
		return nil, err
	}

	confirmedAnomaliesOut := make([]ConfirmedAnomalyDTO, 0, len(input.ConfirmedHotspots))

	// Record confirmed hotspots for this panel
	for _, ch := range input.ConfirmedHotspots {
		origSourceUUID, err := auth.ParseUUID(ch.OriginMeasurementEventID)
		if err != nil {
			return nil, ErrInvalidInput
		}
		origMeasRow, err := qtx.GetMeasurementBySourceEventID(ctx, db.GetMeasurementBySourceEventIDParams{
			ModuleID:      moduleID,
			SourceEventID: origSourceUUID,
		})
		if err != nil || origMeasRow.InspectionID.Bytes != insp.ID.Bytes {
			return nil, ErrInvalidInput
		}

		confirmingUUIDs := make([]pgtype.UUID, 0, len(ch.ConfirmingEventIDs))
		distinctMeasIDs := make(map[[16]byte]struct{}, len(ch.ConfirmingEventIDs))
		var maxMeasuredAt time.Time

		for _, cidStr := range ch.ConfirmingEventIDs {
			cidUUID, err := auth.ParseUUID(cidStr)
			if err != nil {
				return nil, ErrInvalidInput
			}
			mRow, err := qtx.GetMeasurementBySourceEventID(ctx, db.GetMeasurementBySourceEventIDParams{
				ModuleID:      moduleID,
				SourceEventID: cidUUID,
			})
			if err != nil || mRow.InspectionID.Bytes != insp.ID.Bytes {
				return nil, ErrInvalidInput
			}
			confirmingUUIDs = append(confirmingUUIDs, mRow.ID)
			distinctMeasIDs[mRow.ID.Bytes] = struct{}{}
			if maxMeasuredAt.IsZero() || mRow.MeasuredAt.After(maxMeasuredAt) {
				maxMeasuredAt = mRow.MeasuredAt
			}
		}

		if len(distinctMeasIDs) < 2 {
			return nil, ErrInvalidInput
		}

		var localXPtr *float64
		if lenCm > 0 {
			posRes := ResolvePanelPosition(cnt, lenCm, spcCm, ch.GlobalXPositionCm)
			if !posRes.InGap {
				lx := math.Round(posRes.LocalXCm*100.0) / 100.0
				localXPtr = &lx
			}
		}
		maxTempVal := ch.MaxTemperatureC
		deltaTempVal := math.Round((ch.MaxTemperatureC-input.BaselineTemperatureC)*100.0) / 100.0
		eventIDsCopy := make([]string, len(ch.ConfirmingEventIDs))
		copy(eventIDsCopy, ch.ConfirmingEventIDs)

		if insp.Type == "verification" && origAnomaly.ID.Valid {
			origX, origXErr := strconv.ParseFloat(origAnomaly.XPositionCm, 64)
			if (ch.SourceEventID != "" && auth.FormatUUID(origAnomaly.SourceEventID) == ch.SourceEventID) ||
				(origXErr == nil && math.Abs(ch.GlobalXPositionCm-origX) <= 1.0) {
				updatedOrig, uErr := qtx.AppendConfirmingMeasurementsToAnomaly(ctx, db.AppendConfirmingMeasurementsToAnomalyParams{
					NewMeasurementIds: confirmingUUIDs,
					ID:                origAnomaly.ID,
					ModuleID:          moduleID,
				})
				if uErr != nil {
					return nil, uErr
				}
				confirmingStrs := make([]string, 0, len(updatedOrig.ConfirmingMeasurementIds))
				for _, cid := range updatedOrig.ConfirmingMeasurementIds {
					confirmingStrs = append(confirmingStrs, auth.FormatUUID(cid))
				}
				pIdx := updatedOrig.PanelIndex
				var closedAtStr *string
				if updatedOrig.ClosedAt != nil {
					c := updatedOrig.ClosedAt.UTC().Format(time.RFC3339)
					closedAtStr = &c
				}
				confirmedAnomaliesOut = append(confirmedAnomaliesOut, ConfirmedAnomalyDTO{
					ID:                            auth.FormatUUID(updatedOrig.ID),
					ModuleID:                      auth.FormatUUID(updatedOrig.ModuleID),
					OriginMeasurementID:           auth.FormatUUID(updatedOrig.OriginMeasurementID),
					ConfirmingMeasurementIDs:      confirmingStrs,
					ConfirmingMeasurementEventIDs: eventIDsCopy,
					SourceEventID:                 auth.FormatUUID(updatedOrig.SourceEventID),
					PanelIndex:                    &pIdx,
					XPositionCM:                   ch.GlobalXPositionCm,
					LocalXPositionCM:              localXPtr,
					MaxTemperatureC:               &maxTempVal,
					DeltaTemperatureC:             &deltaTempVal,
					DetectedAt:                    updatedOrig.DetectedAt.UTC().Format(time.RFC3339),
					Status:                        updatedOrig.Status,
					ActuatedAttemptsCount:         updatedOrig.ActuatedAttemptsCount,
					RetryPending:                  updatedOrig.RetryPending,
					ClosedAt:                      closedAtStr,
				})
				continue
			}
		}

		detectedAt := maxMeasuredAt
		if ch.DetectedAt != nil && !ch.DetectedAt.IsZero() {
			detectedAt = ch.DetectedAt.UTC()
		}

		var anomSourceUUID pgtype.UUID
		if ch.SourceEventID != "" {
			anomSourceUUID, err = auth.ParseUUID(ch.SourceEventID)
			if err != nil {
				return nil, ErrInvalidInput
			}
		} else {
			anomSourceUUID = newRandomUUID()
		}

		createdAnom, err := qtx.CreateAnomalyEvent(ctx, db.CreateAnomalyEventParams{
			ModuleID:                 moduleID,
			OriginMeasurementID:      origMeasRow.ID,
			ConfirmingMeasurementIds: confirmingUUIDs,
			SourceEventID:            anomSourceUUID,
			PanelIndex:               panelIndex,
			XPositionCm:              floatPtrToNumeric(&ch.GlobalXPositionCm),
			DetectedAt:               detectedAt,
			Status:                   "open",
			ActuatedAttemptsCount:    0,
			RetryPending:             false,
		})
		if err != nil {
			return nil, err
		}

		confirmingStrs := make([]string, 0, len(createdAnom.ConfirmingMeasurementIds))
		for _, cid := range createdAnom.ConfirmingMeasurementIds {
			confirmingStrs = append(confirmingStrs, auth.FormatUUID(cid))
		}
		pIdx := createdAnom.PanelIndex
		var closedAtStr *string
		if createdAnom.ClosedAt != nil {
			c := createdAnom.ClosedAt.UTC().Format(time.RFC3339)
			closedAtStr = &c
		}
		confirmedAnomaliesOut = append(confirmedAnomaliesOut, ConfirmedAnomalyDTO{
			ID:                            auth.FormatUUID(createdAnom.ID),
			ModuleID:                      auth.FormatUUID(createdAnom.ModuleID),
			OriginMeasurementID:           auth.FormatUUID(createdAnom.OriginMeasurementID),
			ConfirmingMeasurementIDs:      confirmingStrs,
			ConfirmingMeasurementEventIDs: eventIDsCopy,
			SourceEventID:                 auth.FormatUUID(createdAnom.SourceEventID),
			PanelIndex:                    &pIdx,
			XPositionCM:                   ch.GlobalXPositionCm,
			LocalXPositionCM:              localXPtr,
			MaxTemperatureC:               &maxTempVal,
			DeltaTemperatureC:             &deltaTempVal,
			DetectedAt:                    createdAnom.DetectedAt.UTC().Format(time.RFC3339),
			Status:                        createdAnom.Status,
			ActuatedAttemptsCount:         createdAnom.ActuatedAttemptsCount,
			RetryPending:                  createdAnom.RetryPending,
			ClosedAt:                      closedAtStr,
		})
	}

	_, _ = qtx.UpdateModuleDeviceHealth(ctx, db.UpdateModuleDeviceHealthParams{
		ID: moduleID,
	})

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	bTemp, _ := strconv.ParseFloat(panelResultRow.BaselineTemperatureC, 64)
	return &RecordPanelResultOutputDTO{
		PanelResult: InspectionPanelResultDTO{
			InspectionID:          auth.FormatUUID(panelResultRow.InspectionID),
			ModuleID:              auth.FormatUUID(panelResultRow.ModuleID),
			PanelIndex:            panelResultRow.PanelIndex,
			BaselineTemperatureC: bTemp,
			TruncatedByMemory:     panelResultRow.TruncatedByMemory,
			FinishedAt:            panelResultRow.FinishedAt.UTC().Format(time.RFC3339),
			CreatedAt:             panelResultRow.CreatedAt.UTC().Format(time.RFC3339),
		},
		ConfirmedAnomalies: confirmedAnomaliesOut,
	}, nil
}

func (s *Service) ListInspections(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, limit, offset int32) ([]InspectionDTO, error) {
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

	if limit <= 0 {
		limit = 20
	}
	if limit > 50 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	rows, err := s.queries.ListInspectionsByModule(ctx, db.ListInspectionsByModuleParams{
		ModuleID: moduleID,
		Limit:    limit,
		Offset:   offset,
	})
	if err != nil {
		return nil, err
	}

	out := make([]InspectionDTO, 0, len(rows))
	for _, inspRow := range rows {
		var baseTempPtr *float64
		if inspRow.BaselineTemperatureC != "" {
			if bVal, err := strconv.ParseFloat(inspRow.BaselineTemperatureC, 64); err == nil {
				baseTempPtr = &bVal
			}
		}

		var startedAtStr, finishedAtStr, cleanOpIDStr *string
		if inspRow.StartedAt != nil {
			s := inspRow.StartedAt.UTC().Format(time.RFC3339)
			startedAtStr = &s
		}
		if inspRow.FinishedAt != nil {
			f := inspRow.FinishedAt.UTC().Format(time.RFC3339)
			finishedAtStr = &f
		}
		if inspRow.CleaningOperationID.Valid {
			c := auth.FormatUUID(inspRow.CleaningOperationID)
			cleanOpIDStr = &c
		}
		var verifResult *string
		if inspRow.VerificationResult.Valid {
			verifResult = &inspRow.VerificationResult.String
		}

		out = append(out, InspectionDTO{
			ID:                   auth.FormatUUID(inspRow.ID),
			ModuleID:             auth.FormatUUID(inspRow.ModuleID),
			SourceEventID:        auth.FormatUUID(inspRow.SourceEventID),
			Type:                 inspRow.Type,
			CleaningOperationID:  cleanOpIDStr,
			BaselineTemperatureC: baseTempPtr,
			ScheduledFor:         inspRow.ScheduledFor.UTC().Format(time.RFC3339),
			StartedAt:            startedAtStr,
			FinishedAt:           finishedAtStr,
			Status:               inspRow.Status,
			VerificationResult:   verifResult,
			CreatedAt:            inspRow.CreatedAt.UTC().Format(time.RFC3339),
			UpdatedAt:            inspRow.UpdatedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
}
