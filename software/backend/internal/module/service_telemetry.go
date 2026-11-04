package module

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"strconv"
	"time"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

var (
	ErrInspectionCompleted = errors.New("inspection already finalized")
	ErrBatchTooLarge       = errors.New("telemetry batch exceeds maximum limit of 10 items")
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

	rows, err := s.queries.ListMeasurementsByModule(ctx, db.ListMeasurementsByModuleParams{
		ModuleID: moduleID,
		Limit:    limit,
		Offset:   offset,
	})
	if err != nil {
		return nil, err
	}

	out := make([]MeasurementDTO, 0, len(rows))
	for _, m := range rows {
		var thermalFrameData any
		if len(m.ThermalFrame) > 0 {
			_ = json.Unmarshal(m.ThermalFrame, &thermalFrameData)
		}

		out = append(out, MeasurementDTO{
			ID:              auth.FormatUUID(m.ID),
			ModuleID:        auth.FormatUUID(m.ModuleID),
			InspectionID:    auth.FormatUUID(m.InspectionID),
			SourceEventID:   auth.FormatUUID(m.SourceEventID),
			MeasuredAt:      m.MeasuredAt.UTC().Format(time.RFC3339),
			XPositionCM:     m.XPositionCm,
			MaxTempC:        m.MaxTemperatureC,
			HotspotDetected: m.HotspotDetected,
			VoltageV:        m.VoltageV,
			CurrentA:        m.CurrentA,
			PowerW:          m.PowerW,
			ThermalFrame:    thermalFrameData,
			ReceivedAt:      m.ReceivedAt.UTC().Format(time.RFC3339),
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
	if limit > 20 {
		limit = 20
	}
	offset := (page - 1) * limit

	totalCount, err := s.queries.CountMeasurementsByInspection(ctx, db.CountMeasurementsByInspectionParams{
		InspectionID: inspectionID,
		ModuleID:     moduleID,
	})
	if err != nil {
		return nil, err
	}

	rows, err := s.queries.ListMeasurementsByInspectionPaged(ctx, db.ListMeasurementsByInspectionPagedParams{
		InspectionID: inspectionID,
		ModuleID:     moduleID,
		Limit:        limit,
		Offset:       offset,
	})
	if err != nil {
		return nil, err
	}

	items := make([]MeasurementDTO, 0, len(rows))
	for _, m := range rows {
		var thermalFrameData any
		if len(m.ThermalFrame) > 0 {
			_ = json.Unmarshal(m.ThermalFrame, &thermalFrameData)
		}

		items = append(items, MeasurementDTO{
			ID:              auth.FormatUUID(m.ID),
			ModuleID:        auth.FormatUUID(m.ModuleID),
			InspectionID:    auth.FormatUUID(m.InspectionID),
			SourceEventID:   auth.FormatUUID(m.SourceEventID),
			MeasuredAt:      m.MeasuredAt.UTC().Format(time.RFC3339),
			XPositionCM:     m.XPositionCm,
			MaxTempC:        m.MaxTemperatureC,
			HotspotDetected: m.HotspotDetected,
			VoltageV:        m.VoltageV,
			CurrentA:        m.CurrentA,
			PowerW:          m.PowerW,
			ThermalFrame:    thermalFrameData,
			ReceivedAt:      m.ReceivedAt.UTC().Format(time.RFC3339),
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

		anomalies = append(anomalies, ConfirmedAnomalyDTO{
			ID:                       auth.FormatUUID(a.ID),
			ModuleID:                 auth.FormatUUID(a.ModuleID),
			OriginMeasurementID:      auth.FormatUUID(a.OriginMeasurementID),
			ConfirmingMeasurementIDs: confirmingIDs,
			SourceEventID:            auth.FormatUUID(a.SourceEventID),
			XPositionCM:              xPos,
			DetectedAt:               a.DetectedAt.UTC().Format(time.RFC3339),
			Status:                   a.Status,
			ActuatedAttemptsCount:    a.ActuatedAttemptsCount,
			RetryPending:             a.RetryPending,
			ClosedAt:                 closedAtStr,
		})
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
				MeasuredAt:      input.MeasuredAt,
				XPositionCm:     input.XPositionCm,
				MaxTemperatureC: input.MaxTemperatureC,
				HotspotDetected: input.HotspotDetected,
				VoltageV:        input.VoltageV,
				CurrentA:        input.CurrentA,
				PowerW:          input.PowerW,
				ThermalFrame:    input.ThermalFrame,
			},
		}
	}

	if len(items) == 0 {
		return nil, ErrInvalidInput
	}
	if len(items) > 10 {
		return nil, ErrBatchTooLarge
	}

	// Validate intra-batch uniqueness of source_event_id
	seenSourceIDs := make(map[string]struct{}, len(items))
	for _, f := range items {
		if f.SourceEventID == "" && len(items) > 1 {
			return nil, ErrInvalidInput
		}
		if f.SourceEventID != "" {
			if _, exists := seenSourceIDs[f.SourceEventID]; exists {
				return nil, ErrInvalidInput
			}
			seenSourceIDs[f.SourceEventID] = struct{}{}
		}
	}

	// Validate bounds and finite values
	panelLength := numericToFloatPtr(row.PanelLengthCm)
	for _, f := range items {
		if f.XPositionCm < 0 {
			return nil, ErrInvalidInput
		}
		if panelLength != nil && f.XPositionCm > *panelLength {
			return nil, ErrInvalidInput
		}
		if !isFinite(f.XPositionCm) || !isFinite(f.VoltageV) || !isFinite(f.CurrentA) || !isFinite(f.MaxTemperatureC) {
			return nil, ErrInvalidInput
		}
		if f.PowerW != nil && !isFinite(*f.PowerW) {
			return nil, ErrInvalidInput
		}
		if len(f.ThermalFrame) != 32*24 {
			return nil, ErrInvalidInput
		}
		for _, v := range f.ThermalFrame {
			if v != nil && !isFinite(*v) {
				return nil, ErrInvalidInput
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

	var inspSourceUUID pgtype.UUID
	if input.InspectionSourceEventID != nil && *input.InspectionSourceEventID != "" {
		inspSourceUUID, err = auth.ParseUUID(*input.InspectionSourceEventID)
		if err != nil {
			return nil, ErrInvalidInput
		}

		existingInsp, err := qtx.GetInspectionBySourceEventID(ctx, db.GetInspectionBySourceEventIDParams{
			ModuleID:      moduleID,
			SourceEventID: inspSourceUUID,
		})
		if err == nil {
			inspID = existingInsp.ID
		} else if errors.Is(err, pgx.ErrNoRows) {
			schedFor := now
			if input.InspectionScheduledFor != nil {
				schedFor = input.InspectionScheduledFor.UTC()
			}
			startedAt := now
			if input.InspectionStartedAt != nil {
				startedAt = input.InspectionStartedAt.UTC()
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
		} else {
			return nil, err
		}
	} else {
		// Standalone telemetry without inspection_source_event_id
		inspSourceUUID = newRandomUUID()
		schedFor := now
		if input.InspectionScheduledFor != nil {
			schedFor = input.InspectionScheduledFor.UTC()
		}
		startedAt := now
		if input.InspectionStartedAt != nil {
			startedAt = input.InspectionStartedAt.UTC()
		}

		newInsp, err := qtx.CreateInspection(ctx, db.CreateInspectionParams{
			ModuleID:            moduleID,
			SourceEventID:       inspSourceUUID,
			Type:                inspType,
			CleaningOperationID: cleanOpUUID,
			ScheduledFor:        schedFor,
			StartedAt:           &startedAt,
			FinishedAt:          &now,
			Status:              "completed",
		})
		if err != nil {
			return nil, err
		}
		inspID = newInsp.ID
	}

	// 3. Ingest each measurement frame (chunked upload, idempotent via ON CONFLICT)
	var primaryMeasRow *db.CreateMeasurementRow

	for _, f := range items {
		fMeasuredAt := now
		if f.MeasuredAt != nil && !f.MeasuredAt.IsZero() {
			fMeasuredAt = f.MeasuredAt.UTC()
		}

		powerW := f.VoltageV * f.CurrentA
		if f.PowerW != nil && *f.PowerW > 0 {
			powerW = *f.PowerW
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

		meas, err := qtx.CreateMeasurement(ctx, db.CreateMeasurementParams{
			ModuleID:        moduleID,
			InspectionID:    inspID,
			SourceEventID:   measSourceUUID,
			MeasuredAt:      fMeasuredAt,
			XPositionCm:     floatPtrToNumeric(&f.XPositionCm),
			MaxTemperatureC: floatPtrToNumeric(&f.MaxTemperatureC),
			HotspotDetected: f.HotspotDetected,
			VoltageV:        floatPtrToNumeric(&f.VoltageV),
			CurrentA:        floatPtrToNumeric(&f.CurrentA),
			PowerW:          floatPtrToNumeric(&powerW),
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
				meas = db.CreateMeasurementRow(existingMeas)
			} else {
				return nil, err
			}
		}

		if primaryMeasRow == nil || f.HotspotDetected {
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

	return &MeasurementDTO{
		ID:              auth.FormatUUID(meas.ID),
		ModuleID:        auth.FormatUUID(meas.ModuleID),
		InspectionID:    auth.FormatUUID(meas.InspectionID),
		SourceEventID:   auth.FormatUUID(meas.SourceEventID),
		MeasuredAt:      meas.MeasuredAt.UTC().Format(time.RFC3339),
		XPositionCM:     meas.XPositionCm,
		MaxTempC:        meas.MaxTemperatureC,
		HotspotDetected: meas.HotspotDetected,
		VoltageV:        meas.VoltageV,
		CurrentA:        meas.CurrentA,
		PowerW:          meas.PowerW,
		ThermalFrame:    thermalFrameData,
		ReceivedAt:      meas.ReceivedAt.UTC().Format(time.RFC3339),
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

	// Validate confirmed hotspots input
	for _, ch := range input.ConfirmedHotspots {
		if ch.OriginMeasurementEventID == "" {
			return nil, ErrInvalidInput
		}
		if len(ch.ConfirmingEventIDs) < 2 {
			return nil, ErrInvalidInput
		}
		seenConfirming := make(map[string]struct{}, len(ch.ConfirmingEventIDs))
		foundOrigin := false
		for _, cidStr := range ch.ConfirmingEventIDs {
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
		if panelLength != nil && ch.GlobalXPositionCm > *panelLength {
			return nil, ErrInvalidInput
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
				ClosedAt:     &now,
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
				if origAnomaly.ActuatedAttemptsCount >= 3 {
					_, err = qtx.UpdateAnomalyEventVerification(ctx, db.UpdateAnomalyEventVerificationParams{
						Status:       "unresolved",
						RetryPending: false,
						RetryReason:  pgtype.Text{Valid: false},
						ClosedAt:     &now,
						ID:           origAnomaly.ID,
						ModuleID:     moduleID,
					})
				} else {
					_, err = qtx.UpdateAnomalyEventVerification(ctx, db.UpdateAnomalyEventVerificationParams{
						Status:       "open",
						RetryPending: false,
						RetryReason:  pgtype.Text{Valid: false},
						ClosedAt:     nil,
						ID:           origAnomaly.ID,
						ModuleID:     moduleID,
					})
				}
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
			} else if origAnomaly.ActuatedAttemptsCount >= 3 {
				_, err = qtx.UpdateAnomalyEventVerification(ctx, db.UpdateAnomalyEventVerificationParams{
					Status:       "unresolved",
					RetryPending: false,
					RetryReason:  pgtype.Text{Valid: false},
					ClosedAt:     &now,
					ID:           origAnomaly.ID,
					ModuleID:     moduleID,
				})
				if err != nil {
					return nil, err
				}
			}
		}
	}

	_, err = qtx.FinalizeInspection(ctx, db.FinalizeInspectionParams{
		Status:               "completed",
		FinishedAt:           &finAt,
		BaselineTemperatureC: floatPtrToNumeric(&input.BaselineTemperatureC),
		VerificationResult:   verifResultPg,
		ID:                   insp.ID,
		ModuleID:             moduleID,
	})
	if err != nil {
		return nil, err
	}

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
			if mRow.MeasuredAt.After(maxMeasuredAt) {
				maxMeasuredAt = mRow.MeasuredAt
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

		_, err = qtx.CreateAnomalyEvent(ctx, db.CreateAnomalyEventParams{
			ModuleID:                 moduleID,
			OriginMeasurementID:      originMeasID,
			ConfirmingMeasurementIds: confirmingUUIDs,
			SourceEventID:            anomSourceUUID,
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
