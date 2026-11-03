package module

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
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

const DefaultPingIntervalSeconds = 300

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

	dto := &DeviceStatusDTO{
		ModuleID:            auth.FormatUUID(row.ID),
		MACAddress:          row.MacAddress,
		MonitoringStatus:    row.MonitoringStatus,
		IsConfigured:        isConfigured,
		ConfiguredAt:        configuredAtStr,
		WaterStatus:         "unknown",
		LimitsCheckPassed:   row.LimitsCheckPassed,
		ThermalSensorActive: row.ThermalSensorActive,
		ConfigurationSync:   syncDTO,
		PingIntervalSeconds: s.PingIntervalSeconds(),
		OnlineWindowSeconds: s.OnlineWindowSeconds(),
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
	})

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

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return s.GetDeviceStatus(ctx, principal, moduleID)
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

	return &DeviceConfigurationDTO{
		ConfigVersion: mod.ConfigVersion,
		Geometry: DeviceGeometryDTO{
			PanelLengthCm:  numericToFloatPtr(mod.PanelLengthCm),
			PanelWidthCm:   numericToFloatPtr(mod.PanelWidthCm),
			PanelCount:     pgInt4ToInt32Ptr(mod.PanelCount),
			PanelSpacingCm: numericToFloatPtr(mod.PanelSpacingCm),
		},
		MinSolarAngle:       numericToFloatPtr(mod.MinimumSolarAngleDeg),
		IntervalDays:        mod.InspectionIntervalDays,
		PingIntervalSeconds: s.PingIntervalSeconds(),
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
