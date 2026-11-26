package module

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func computeConfigurationSync(configVersion, configAppliedVersion int32, configAppliedAt *time.Time, configApplyError *string) ConfigurationSyncDTO {
	state := "pending"
	if configApplyError != nil && strings.TrimSpace(*configApplyError) != "" {
		state = "failed"
	} else if configAppliedVersion == configVersion {
		state = "synced"
	}

	var appliedAtStr *string
	if configAppliedAt != nil {
		s := configAppliedAt.UTC().Format(time.RFC3339)
		appliedAtStr = &s
	}

	return ConfigurationSyncDTO{
		State:                state,
		ConfigVersion:        configVersion,
		ConfigAppliedVersion: configAppliedVersion,
		ConfigAppliedAt:      appliedAtStr,
		ConfigApplyError:     configApplyError,
	}
}

const DefaultPingIntervalSeconds = 5

func getDevicePingIntervalSeconds() int {
	valStr := os.Getenv("DEVICE_PING_INTERVAL_SECONDS")
	if valStr != "" {
		if val, err := strconv.Atoi(strings.TrimSpace(valStr)); err == nil && val > 0 {
			return val
		}
	}
	return DefaultPingIntervalSeconds
}

func (s *Service) PingIntervalSeconds() int {
	if s.pingIntervalSeconds <= 0 {
		return DefaultPingIntervalSeconds
	}
	return s.pingIntervalSeconds
}

func (s *Service) OnlineWindowSeconds() int {
	return 3 * s.PingIntervalSeconds()
}

func (s *Service) IsOnline(lastPingAt *time.Time) bool {
	if lastPingAt == nil {
		return false
	}
	window := time.Duration(s.OnlineWindowSeconds()) * time.Second
	return time.Since(*lastPingAt) < window
}

func (s *Service) GetDeviceStatus(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) (*DeviceStatusDTO, error) {
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

	var configuredAtStr *string
	if row.ConfiguredAt != nil {
		c := row.ConfiguredAt.UTC().Format(time.RFC3339)
		configuredAtStr = &c
	}
	var nextInspectionAtStr *string
	if row.NextInspectionAt != nil {
		n := row.NextInspectionAt.UTC().Format(time.RFC3339)
		nextInspectionAtStr = &n
	}
	var verificationReadyAtStr *string
	if row.VerificationReadyAt != nil {
		v := row.VerificationReadyAt.UTC().Format(time.RFC3339)
		verificationReadyAtStr = &v
	}
	isConfigured := row.ConfiguredAt != nil && row.MonitoringStatus != StatusPendingConfiguration

	isOnline := false
	var lastSeenTime *time.Time
	onlineWindow := time.Duration(s.OnlineWindowSeconds()) * time.Second

	if row.LastPingAt != nil {
		lastSeenTime = row.LastPingAt
		if s.IsOnline(row.LastPingAt) {
			isOnline = true
		}
	}

	var configApplyErr *string
	if row.ConfigApplyError.Valid && strings.TrimSpace(row.ConfigApplyError.String) != "" {
		errStr := row.ConfigApplyError.String
		configApplyErr = &errStr
	}
	syncDTO := computeConfigurationSync(
		row.ConfigVersion,
		row.ConfigAppliedVersion,
		row.ConfigAppliedAt,
		configApplyErr,
	)

	var firmwareStateUpdatedAtStr *string
	if row.FirmwareStateUpdatedAt != nil {
		str := row.FirmwareStateUpdatedAt.UTC().Format(time.RFC3339)
		firmwareStateUpdatedAtStr = &str
	}

	var localizedReadingAtStr *string
	var localizedReadingXCm *float64
	if row.LocalizedReadingAt != nil {
		lr := row.LocalizedReadingAt.UTC().Format(time.RFC3339)
		localizedReadingAtStr = &lr
		x := row.LocalizedReadingXCm
		localizedReadingXCm = &x
	}

	dto := &DeviceStatusDTO{
		ModuleID:            auth.FormatUUID(row.ID),
		MACAddress:          row.MacAddress,
		MonitoringStatus:    row.MonitoringStatus,
		IsConfigured:        isConfigured,
		ConfiguredAt:        configuredAtStr,
		WaterStatus:         "unknown",
		LimitsCheckPassed:   row.LimitsCheckPassed,
		ThermalSensorActive: row.ThermalSensorActive,
		NextInspectionAt:    nextInspectionAtStr,
		VerificationReadyAt: verificationReadyAtStr,
		ConfigurationSync:   syncDTO,
		ManualCleaningPending:   row.ManualCleaningPending,
		ManualCleaningTargetXCm: numericToFloatPtr(row.ManualCleaningTargetXCm),
		ManualReadingPending:    row.ManualReadingPending,
		ManualReadingTargetXCm:  numericToFloatPtr(row.ManualReadingTargetXCm),
		LocalizedReadingAt:      localizedReadingAtStr,
		LocalizedReadingXCm:     localizedReadingXCm,
		ResetPending:            row.ResetPending,
		PingIntervalSeconds:     s.PingIntervalSeconds(),
		OnlineWindowSeconds:     s.OnlineWindowSeconds(),
		FirmwareState:           row.FirmwareState,
		FirmwareStateDetail:     pgTextToStringPtr(row.FirmwareStateDetail),
		FirmwareStateUpdatedAt:  firmwareStateUpdatedAtStr,
	}

	if hasPending, err := s.queries.HasPendingScheduledInspection(ctx, moduleID); err == nil && hasPending {
		dto.ManualInspectionPending = true
	}

	resReading, err := s.queries.GetLatestReservoirReadingByModule(ctx, moduleID)
	if err == nil {
		if lastSeenTime == nil || resReading.MeasuredAt.After(*lastSeenTime) {
			t := resReading.MeasuredAt
			lastSeenTime = &t
		}
		dto.WaterAvailable = pgBoolToBoolPtr(resReading.WaterAvailable)
		if resReading.WaterAvailable.Valid && resReading.WaterAvailable.Bool {
			dto.WaterStatus = "available"
		} else if resReading.WaterAvailable.Valid && !resReading.WaterAvailable.Bool {
			dto.WaterStatus = "insufficient"
		}
		if time.Since(resReading.MeasuredAt) < onlineWindow {
			isOnline = true
		}
	}

	measurements, err := s.queries.ListMeasurementsByModule(ctx, db.ListMeasurementsByModuleParams{
		ModuleID: moduleID,
		Limit:    1,
		Offset:   0,
	})
	if err == nil && len(measurements) > 0 {
		m := measurements[0]
		mTime := m.MeasuredAt.UTC().Format(time.RFC3339)
		dto.LatestMeasurementAt = &mTime
		if lastSeenTime == nil || m.MeasuredAt.After(*lastSeenTime) {
			t := m.MeasuredAt
			lastSeenTime = &t
		}
		if time.Since(m.MeasuredAt) < onlineWindow {
			isOnline = true
		}
	}

	dto.IsOnline = isOnline
	if lastSeenTime != nil {
		lsStr := lastSeenTime.UTC().Format(time.RFC3339)
		dto.LastSeenAt = &lsStr
	}

	return dto, nil
}

func (s *Service) RecordDevicePing(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, input RecordDevicePingInput) (*DeviceStatusDTO, error) {
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

	// Update persisted hardware health flags in modules table
	var limitsPassed pgtype.Bool
	if input.LimitsCheckPassed != nil {
		limitsPassed = pgtype.Bool{Bool: *input.LimitsCheckPassed, Valid: true}
	}
	var thermalActive pgtype.Bool
	if input.ThermalSensorActive != nil {
		thermalActive = pgtype.Bool{Bool: *input.ThermalSensorActive, Valid: true}
	}
	_, _ = qtx.UpdateModuleDeviceHealth(ctx, db.UpdateModuleDeviceHealthParams{
		ID:                  moduleID,
		LimitsCheckPassed:   limitsPassed,
		ThermalSensorActive: thermalActive,
		NextInspectionAt:    input.NextInspectionAt,
	})
	if err := qtx.UpdateModuleVerificationReadyAt(ctx, db.UpdateModuleVerificationReadyAtParams{
		ID:                  moduleID,
		VerificationReadyAt: input.VerificationReadyAt,
	}); err != nil {
		return nil, err
	}

	// Only record reservoir ping if water_available was explicitly provided
	if input.WaterAvailable != nil {
		eventID := newRandomUUID()
		_, err = qtx.RecordDeviceHandshakePing(ctx, db.RecordDeviceHandshakePingParams{
			ModuleID:       moduleID,
			SourceEventID:  eventID,
			WaterAvailable: pgtype.Bool{Bool: *input.WaterAvailable, Valid: true},
		})
		if err != nil {
			return nil, err
		}
	}

	if input.ManualCleaningAck != nil && *input.ManualCleaningAck {
		_ = qtx.ClearManualCleaningPending(ctx, moduleID)
	}
	if input.ManualReadingAck != nil && *input.ManualReadingAck {
		_ = qtx.ClearManualReadingPending(ctx, moduleID)
	}
	if input.ResetAck != nil && *input.ResetAck {
		_ = qtx.ClearResetPending(ctx, moduleID)
	}

	if len(input.StateTransitions) > 0 {
		now := time.Now().UTC()
		var lastState string
		var lastDetail *string
		var lastOccurredAt time.Time
		for _, tr := range input.StateTransitions {
			st := strings.TrimSpace(tr.State)
			if st == "" {
				continue
			}
			occurredAt := now
			if tr.OccurredAt >= 1000000000 {
				occurredAt = time.Unix(int64(tr.OccurredAt), 0).UTC()
			}
			if _, err := qtx.InsertModuleStateLog(ctx, db.InsertModuleStateLogParams{
				ModuleID:   moduleID,
				State:      st,
				Detail:     stringPtrToPgText(tr.Detail),
				OccurredAt: occurredAt,
			}); err != nil {
				return nil, err
			}
			lastState = st
			lastDetail = tr.Detail
			lastOccurredAt = occurredAt
		}
		if input.FirmwareState != nil && strings.TrimSpace(*input.FirmwareState) != "" {
			nextState := strings.TrimSpace(*input.FirmwareState)
			if nextState != lastState {
				lastDetail = input.FirmwareStateDetail
			} else if input.FirmwareStateDetail != nil {
				lastDetail = input.FirmwareStateDetail
			}
			lastState = nextState
			if lastOccurredAt.IsZero() {
				lastOccurredAt = now
			}
		}
		if lastState != "" {
			if err := qtx.UpdateModuleFirmwareState(ctx, db.UpdateModuleFirmwareStateParams{
				ID:                     moduleID,
				FirmwareState:          lastState,
				FirmwareStateDetail:    stringPtrToPgText(lastDetail),
				FirmwareStateUpdatedAt: &lastOccurredAt,
			}); err != nil {
				return nil, err
			}
		}
	} else if input.FirmwareState != nil && strings.TrimSpace(*input.FirmwareState) != "" {
		newState := strings.TrimSpace(*input.FirmwareState)
		now := time.Now().UTC()
		if newState != row.FirmwareState {
			if _, err := qtx.InsertModuleStateLog(ctx, db.InsertModuleStateLogParams{
				ModuleID:   moduleID,
				State:      newState,
				Detail:     stringPtrToPgText(input.FirmwareStateDetail),
				OccurredAt: now,
			}); err != nil {
				return nil, err
			}
		}
		if err := qtx.UpdateModuleFirmwareState(ctx, db.UpdateModuleFirmwareStateParams{
			ID:                     moduleID,
			FirmwareState:          newState,
			FirmwareStateDetail:    stringPtrToPgText(input.FirmwareStateDetail),
			FirmwareStateUpdatedAt: &now,
		}); err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return s.GetDeviceStatus(ctx, principal, moduleID)
}

func (s *Service) ListModuleStateLogs(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) ([]ModuleStateLogDTO, error) {
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

	rows, err := s.queries.ListModuleStateLogs(ctx, moduleID)
	if err != nil {
		return nil, err
	}

	out := make([]ModuleStateLogDTO, 0, len(rows))
	for _, r := range rows {
		out = append(out, ModuleStateLogDTO{
			Seq:        r.Seq,
			ID:         auth.FormatUUID(r.ID),
			ModuleID:   auth.FormatUUID(r.ModuleID),
			State:      r.State,
			Detail:     pgTextToStringPtr(r.Detail),
			OccurredAt: r.OccurredAt.UTC().Format(time.RFC3339),
			CreatedAt:  r.CreatedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
}

func (s *Service) ClaimDevice(ctx context.Context, input ClaimDeviceInput) (*ClaimDeviceDTO, error) {
	trimmed := strings.TrimSpace(input.MACAddress)
	if trimmed == "" {
		return nil, ErrInvalidInput
	}
	mac, err := net.ParseMAC(trimmed)
	if err != nil || len(mac) != 6 {
		return nil, ErrInvalidInput
	}

	mod, err := s.queries.GetModuleByMACAddress(ctx, mac)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if !mod.IsActive {
		return nil, ErrForbidden
	}

	// Idempotent device token: reuse existing if already set, or generate new
	deviceToken := ""
	if mod.DeviceToken.Valid && strings.TrimSpace(mod.DeviceToken.String) != "" {
		deviceToken = mod.DeviceToken.String
	} else {
		var randBytes [16]byte
		_, _ = rand.Read(randBytes[:])
		deviceToken = "dev_sec_" + hex.EncodeToString(randBytes[:])

		_, err = s.queries.SetModuleDeviceToken(ctx, db.SetModuleDeviceTokenParams{
			ID:          mod.ID,
			DeviceToken: pgtype.Text{String: deviceToken, Valid: true},
		})
		if err != nil {
			return nil, err
		}
	}

	// Update persisted hardware health flags in modules table
	var limitsPassed pgtype.Bool
	if input.LimitsCheckPassed != nil {
		limitsPassed = pgtype.Bool{Bool: *input.LimitsCheckPassed, Valid: true}
	}
	var thermalActive pgtype.Bool
	if input.ThermalSensorActive != nil {
		thermalActive = pgtype.Bool{Bool: *input.ThermalSensorActive, Valid: true}
	}
	_, _ = s.queries.UpdateModuleDeviceHealth(ctx, db.UpdateModuleDeviceHealthParams{
		ID:                  mod.ID,
		LimitsCheckPassed:   limitsPassed,
		ThermalSensorActive: thermalActive,
	})

	// Only record initial reservoir ping if water_available was explicitly provided
	if input.WaterAvailable != nil {
		eventID := newRandomUUID()
		_, _ = s.queries.RecordDeviceHandshakePing(ctx, db.RecordDeviceHandshakePingParams{
			ModuleID:       mod.ID,
			SourceEventID:  eventID,
			WaterAvailable: pgtype.Bool{Bool: *input.WaterAvailable, Valid: true},
		})
	}

	return &ClaimDeviceDTO{
		ModuleID:               auth.FormatUUID(mod.ID),
		DeviceToken:            deviceToken,
		Status:                 "claimed",
		InspectionIntervalDays: mod.InspectionIntervalDays,
		PingIntervalSeconds:    s.PingIntervalSeconds(),
		Message:                "Device successfully claimed and paired",
	}, nil
}

func (s *Service) GetDeviceConfiguration(ctx context.Context, moduleID pgtype.UUID) (*DeviceConfigurationDTO, error) {
	if !moduleID.Valid {
		return nil, ErrInvalidInput
	}

	mod, err := s.queries.GetModuleByIDForDevice(ctx, moduleID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if !mod.IsActive {
		return nil, ErrForbidden
	}

	pLen := numericToFloatPtr(mod.PanelLengthCm)
	pCnt := pgInt4ToInt32Ptr(mod.PanelCount)
	pSpc := numericToFloatPtr(mod.PanelSpacingCm)
	var totalLengthCm *float64
	if pLen != nil {
		cnt := int32(1)
		if pCnt != nil && *pCnt > 0 {
			cnt = *pCnt
		}
		spc := 0.0
		if pSpc != nil && *pSpc > 0 {
			spc = *pSpc
		}
		tl := CalculateTotalStringLength(cnt, *pLen, spc)
		totalLengthCm = &tl
	}

	var powerSensorsData any
	if len(mod.PowerSensors) > 0 {
		_ = json.Unmarshal(mod.PowerSensors, &powerSensorsData)
	}

	return &DeviceConfigurationDTO{
		ConfigVersion: mod.ConfigVersion,
		Geometry: DeviceGeometryDTO{
			PanelLengthCm:  pLen,
			PanelWidthCm:   numericToFloatPtr(mod.PanelWidthCm),
			PanelCount:     pCnt,
			PanelSpacingCm: pSpc,
			TotalLengthCm:  totalLengthCm,
		},
		Latitude:            pgFloat8ToFloatPtr(mod.Latitude),
		Longitude:           pgFloat8ToFloatPtr(mod.Longitude),
		AzimuthDeg:          numericToFloatPtr(mod.AzimuthDeg),
		TiltDeg:             numericToFloatPtr(mod.TiltDeg),
		MinSolarAngle:       numericToFloatPtr(mod.MinimumSolarAngleDeg),
		IntervalDays:        mod.InspectionIntervalDays,
		PingIntervalSeconds: s.PingIntervalSeconds(),
		HotspotThresholdDeltaC: numericToFloatWithDefault(mod.HotspotThresholdDeltaC, 8.0),
		PowerSensors:        powerSensorsData,
	}, nil
}

func (s *Service) AcknowledgeDeviceConfiguration(ctx context.Context, moduleID pgtype.UUID, req AcknowledgeDeviceConfigurationInput) (*ConfigurationSyncDTO, error) {
	if !moduleID.Valid {
		return nil, ErrInvalidInput
	}

	mod, err := s.queries.GetModuleByIDForDevice(ctx, moduleID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if !mod.IsActive {
		return nil, ErrForbidden
	}

	if req.ConfigVersion != mod.ConfigVersion {
		return nil, ErrStaleConfig
	}

	now := time.Now().UTC()
	var appliedAt *time.Time
	var applyErr pgtype.Text
	appliedVersion := mod.ConfigAppliedVersion

	if req.Applied {
		appliedAt = &now
		appliedVersion = req.ConfigVersion
		applyErr = pgtype.Text{Valid: false}
	} else {
		appliedAt = mod.ConfigAppliedAt
		errText := ""
		if req.Error != nil {
			errText = strings.TrimSpace(*req.Error)
		}
		if errText == "" {
			errText = "device failed to apply configuration"
		}
		applyErr = pgtype.Text{String: errText, Valid: true}
	}

	if err := s.queries.UpdateModuleConfigAck(ctx, db.UpdateModuleConfigAckParams{
		ID:                   moduleID,
		ConfigAppliedVersion: appliedVersion,
		ConfigAppliedAt:      appliedAt,
		ConfigApplyError:     applyErr,
		NextInspectionAt:     req.NextInspectionAt,
	}); err != nil {
		return nil, err
	}

	var applyErrPtr *string
	if applyErr.Valid && applyErr.String != "" {
		applyErrPtr = &applyErr.String
	}
	syncState := computeConfigurationSync(mod.ConfigVersion, appliedVersion, appliedAt, applyErrPtr)
	return &syncState, nil
}

func (s *Service) TriggerManualInspection(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) (*TriggerInspectionDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	mod, err := s.queries.GetModuleByID(ctx, db.GetModuleByIDParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if !mod.IsActive {
		return nil, ErrForbidden
	}

	if mod.MonitoringStatus == StatusPendingConfiguration || mod.ConfiguredAt == nil {
		return nil, ErrInvalidInput
	}

	if _, _, err := s.resolveUserModuleRelationship(ctx, s.queries, principal, mod.ID, mod.InstallerTechnicianID); err != nil {
		return nil, err
	}

	// Check if an inspection is already actively in progress
	latestInsp, err := s.queries.GetLatestInspectionByModule(ctx, moduleID)
	if err == nil && latestInsp.Status == "in_progress" {
		isStale := false
		if !latestInsp.UpdatedAt.IsZero() && time.Since(latestInsp.UpdatedAt) > 15*time.Minute {
			isStale = true
		} else if latestInsp.StartedAt != nil && !latestInsp.StartedAt.IsZero() && time.Since(*latestInsp.StartedAt) > 15*time.Minute {
			isStale = true
		} else if !latestInsp.CreatedAt.IsZero() && time.Since(latestInsp.CreatedAt) > 15*time.Minute {
			isStale = true
		}

		if isStale {
			now := time.Now().UTC()
			finAt := now
			if latestInsp.StartedAt != nil && finAt.Before(*latestInsp.StartedAt) {
				finAt = *latestInsp.StartedAt
			}
			_, _ = s.queries.FinalizeInspection(ctx, db.FinalizeInspectionParams{
				Status:               "failed",
				FinishedAt:           &finAt,
				BaselineTemperatureC: pgtype.Numeric{Valid: false},
				VerificationResult:   pgtype.Text{Valid: false},
				FailureReason:        pgtype.Text{String: "device_timeout_inactivity", Valid: true},
				ID:                   latestInsp.ID,
				ModuleID:             moduleID,
			})
			_ = s.queries.ClearPendingScheduledInspections(ctx, moduleID)
			_, _ = s.queries.UpdateModuleDeviceHealth(ctx, db.UpdateModuleDeviceHealthParams{
				ID: moduleID,
			})
		} else {
			return &TriggerInspectionDTO{
				Success: true,
				Message: "Inspection is already in progress on this module",
				Status:  "in_progress",
			}, nil
		}
	}

	// Check if an inspection is already pending
	hasPending, err := s.queries.HasPendingScheduledInspection(ctx, moduleID)
	if err != nil {
		return nil, err
	}
	if hasPending {
		return &TriggerInspectionDTO{
			Success: true,
			Message: "Inspection is already scheduled and waiting for device check-in",
			Status:  "scheduled",
		}, nil
	}

	// Create new scheduled inspection
	_, err = s.queries.CreateManualScheduledInspection(ctx, moduleID)
	if err != nil {
		return nil, err
	}

	return &TriggerInspectionDTO{
		Success: true,
		Message: "Inspection requested successfully. It will start on the next device check-in.",
		Status:  "scheduled",
	}, nil
}

func (s *Service) TriggerManualCleaning(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, input TriggerCleaningInput) (*TriggerCleaningDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	mod, err := s.queries.GetModuleByID(ctx, db.GetModuleByIDParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if !mod.IsActive {
		return nil, ErrForbidden
	}

	if mod.MonitoringStatus == StatusPendingConfiguration || mod.ConfiguredAt == nil {
		return nil, ErrInvalidInput
	}

	if _, _, err := s.resolveUserModuleRelationship(ctx, s.queries, principal, mod.ID, mod.InstallerTechnicianID); err != nil {
		return nil, err
	}

	pLen := numericToFloatPtr(mod.PanelLengthCm)
	pCnt := pgInt4ToInt32Ptr(mod.PanelCount)
	pSpc := numericToFloatPtr(mod.PanelSpacingCm)
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

	posRes, err := ValidatePanelAndPosition(input.TargetXPositionCm, lenCm, spcCm, cnt, nil)
	if err != nil {
		return nil, err
	}

	targetX := input.TargetXPositionCm
	targetXNumeric := floatPtrToNumeric(&targetX)

	_, err = s.queries.SetManualCleaningPending(ctx, db.SetManualCleaningPendingParams{
		ID:                      moduleID,
		ManualCleaningTargetXCm: targetXNumeric,
	})
	if err != nil {
		return nil, err
	}

	return &TriggerCleaningDTO{
		Success:           true,
		Message:           fmt.Sprintf("Cleaning requested at position %.1f cm (Panel %d). It will start on next device check-in.", targetX, posRes.PanelIndex),
		Status:            "scheduled",
		TargetXPositionCm: targetX,
	}, nil
}

type storedLocalizedReading struct {
	XPositionCm     float64   `json:"x_position_cm"`
	PanelIndex      int32     `json:"panel_index"`
	MeasuredAt      string    `json:"measured_at"`
	MinTemperatureC float64   `json:"min_temperature_c"`
	MaxTemperatureC float64   `json:"max_temperature_c"`
	AvgTemperatureC float64   `json:"avg_temperature_c"`
	ThermalMatrix   []float64 `json:"thermal_matrix"`
}

func (s *Service) TriggerManualReading(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, input TriggerReadingInput) (*TriggerReadingDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	mod, err := s.queries.GetModuleByID(ctx, db.GetModuleByIDParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if !mod.IsActive {
		return nil, ErrForbidden
	}

	if mod.MonitoringStatus == StatusPendingConfiguration || mod.ConfiguredAt == nil {
		return nil, ErrInvalidInput
	}

	if _, _, err := s.resolveUserModuleRelationship(ctx, s.queries, principal, mod.ID, mod.InstallerTechnicianID); err != nil {
		return nil, err
	}

	pLen := numericToFloatPtr(mod.PanelLengthCm)
	pCnt := pgInt4ToInt32Ptr(mod.PanelCount)
	pSpc := numericToFloatPtr(mod.PanelSpacingCm)
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

	posRes, err := ValidatePanelAndPosition(input.TargetXPositionCm, lenCm, spcCm, cnt, nil)
	if err != nil {
		return nil, err
	}

	targetX := input.TargetXPositionCm
	targetXNumeric := floatPtrToNumeric(&targetX)

	_, err = s.queries.SetManualReadingPending(ctx, db.SetManualReadingPendingParams{
		ID:                     moduleID,
		ManualReadingTargetXCm: targetXNumeric,
	})
	if err != nil {
		return nil, err
	}

	return &TriggerReadingDTO{
		Success:           true,
		Message:           fmt.Sprintf("Localized reading requested at position %.1f cm (Panel %d). It will start on next device check-in.", targetX, posRes.PanelIndex),
		TargetXPositionCm: targetX,
		PanelIndex:        posRes.PanelIndex,
	}, nil
}

func (s *Service) RecordLocalizedReading(ctx context.Context, moduleID pgtype.UUID, input SubmitLocalizedReadingInput) (*SubmitLocalizedReadingDTO, error) {
	if !moduleID.Valid {
		return nil, ErrInvalidInput
	}

	if len(input.ThermalMatrix) != 768 {
		return nil, ErrInvalidInput
	}

	if !isFinite(input.XPositionCm) || !isFinite(input.MinTemperatureC) || !isFinite(input.MaxTemperatureC) || !isFinite(input.AvgTemperatureC) {
		return nil, ErrInvalidInput
	}
	for _, v := range input.ThermalMatrix {
		if !isFinite(v) {
			return nil, ErrInvalidInput
		}
	}

	mod, err := s.queries.GetModuleByIDForDevice(ctx, moduleID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if !mod.IsActive {
		return nil, ErrForbidden
	}

	measuredAt := time.Now().UTC()
	if input.MeasuredAt != nil {
		measuredAt = input.MeasuredAt.UTC()
	}

	payload := storedLocalizedReading{
		XPositionCm:     input.XPositionCm,
		PanelIndex:      input.PanelIndex,
		MeasuredAt:      measuredAt.Format(time.RFC3339),
		MinTemperatureC: input.MinTemperatureC,
		MaxTemperatureC: input.MaxTemperatureC,
		AvgTemperatureC: input.AvgTemperatureC,
		ThermalMatrix:   input.ThermalMatrix,
	}
	rawJSON, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	localizedAt, err := s.queries.SaveLocalizedReading(ctx, db.SaveLocalizedReadingParams{
		ID:                     moduleID,
		LocalizedReadingResult: rawJSON,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	atStr := time.Now().UTC().Format(time.RFC3339)
	if localizedAt != nil {
		atStr = localizedAt.UTC().Format(time.RFC3339)
	}

	return &SubmitLocalizedReadingDTO{
		Success:            true,
		LocalizedReadingAt: atStr,
	}, nil
}

func (s *Service) GetLocalizedReading(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) (*LocalizedReadingDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	row, err := s.queries.GetLocalizedReading(ctx, db.GetLocalizedReadingParams{
		ID:        moduleID,
		CompanyID: principal.CompanyID,
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

	if row.LocalizedReadingAt == nil || len(row.LocalizedReadingResult) == 0 {
		return nil, ErrNotFound
	}

	var stored storedLocalizedReading
	if err := json.Unmarshal(row.LocalizedReadingResult, &stored); err != nil {
		return nil, err
	}

	return &LocalizedReadingDTO{
		ModuleID:           auth.FormatUUID(row.ID),
		XPositionCm:        stored.XPositionCm,
		PanelIndex:         stored.PanelIndex,
		MeasuredAt:         stored.MeasuredAt,
		LocalizedReadingAt: row.LocalizedReadingAt.UTC().Format(time.RFC3339),
		MinTemperatureC:    stored.MinTemperatureC,
		MaxTemperatureC:    stored.MaxTemperatureC,
		AvgTemperatureC:    stored.AvgTemperatureC,
		ThermalMatrix:      stored.ThermalMatrix,
	}, nil
}

// ResetRoutine requests an emergency/user reset on the module, aborting any active inspections or cleanings.
func (s *Service) ResetRoutine(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) error {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return ErrForbidden
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	qtx := s.queries.WithTx(tx)

	mod, err := qtx.GetModuleByID(ctx, db.GetModuleByIDParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}

	if !mod.IsActive {
		return ErrForbidden
	}

	if _, _, err := s.resolveUserModuleRelationship(ctx, qtx, principal, mod.ID, mod.InstallerTechnicianID); err != nil {
		return err
	}

	if err := qtx.SetResetPending(ctx, moduleID); err != nil {
		return err
	}
	if err := qtx.AbortActiveInspectionsByModule(ctx, moduleID); err != nil {
		return err
	}
	if err := qtx.AbortActiveCleaningsByModule(ctx, moduleID); err != nil {
		return err
	}

	return tx.Commit(ctx)
}
