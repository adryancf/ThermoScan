package module

import (
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

type ConfigurationSyncDTO struct {
	State                string  `json:"state"`
	ConfigVersion        int32   `json:"config_version"`
	ConfigAppliedVersion int32   `json:"config_applied_version"`
	ConfigAppliedAt      *string `json:"config_applied_at"`
	ConfigApplyError     *string `json:"config_apply_error"`
}

type ModulePermissionsDTO struct {
	CanEditGeometryAndLocation bool `json:"can_edit_geometry_and_location"`
	CanEditSolarAngle          bool `json:"can_edit_solar_angle"`
	CanEditInterval            bool `json:"can_edit_interval"`
	CanManageAccess            bool `json:"can_manage_access"`
	CanDelete                  bool `json:"can_delete"`
}

type ModuleDTO struct {
	ID                         string               `json:"id"`
	CompanyID                  string               `json:"company_id"`
	InstallerTechnicianID      string               `json:"installer_technician_id"`
	InstallerName              string               `json:"installer_name"`
	InstallerEmail             string               `json:"installer_email"`
	Name                       string               `json:"name"`
	MacAddress                 string               `json:"mac_address"`
	IsActive                   bool                 `json:"is_active"`
	MonitoringStatus           string               `json:"monitoring_status"`
	PanelLengthCm              *float64             `json:"panel_length_cm"`
	PanelWidthCm               *float64             `json:"panel_width_cm"`
	PanelCount                 *int32               `json:"panel_count"`
	PanelSpacingCm             *float64             `json:"panel_spacing_cm"`
	Latitude                   *float64             `json:"latitude"`
	Longitude                  *float64             `json:"longitude"`
	ElevationM                 *float64             `json:"elevation_m"`
	AzimuthDeg                 *float64             `json:"azimuth_deg"`
	TiltDeg                    *float64             `json:"tilt_deg"`
	AzimuthSource              *string              `json:"azimuth_source"`
	TiltSource                 *string              `json:"tilt_source"`
	MinimumSolarAngleDeg       *float64             `json:"minimum_solar_angle_deg"`
	InspectionIntervalDays     int32                `json:"inspection_interval_days"`
	ReservoirNominalCapacityMl *float64             `json:"reservoir_nominal_capacity_ml"`
	TotalLengthCm              *float64             `json:"total_length_cm,omitempty"`
	PowerSensors               any                  `json:"power_sensors,omitempty"`
	ConfiguredAt               *string              `json:"configured_at"`
	NextInspectionAt           *string              `json:"next_inspection_at,omitempty"`
	CreatedAt                  string               `json:"created_at"`
	UpdatedAt                  string               `json:"updated_at"`
	UserRelationship           string               `json:"user_relationship"`
	Permissions                ModulePermissionsDTO `json:"permissions"`
	OperationalEmailEnabled    *bool                `json:"operational_email_enabled,omitempty"`
	ConfigurationSync          ConfigurationSyncDTO `json:"configuration_sync"`
	PingIntervalSeconds        int                  `json:"ping_interval_seconds"`
	OnlineWindowSeconds        int                  `json:"online_window_seconds"`
	IsOnline                   bool                 `json:"is_online"`
	LastPingAt                 *string              `json:"last_ping_at,omitempty"`
}

type ModuleManagerDTO struct {
	ID               string `json:"id"`
	Name             string `json:"name"`
	Email            string `json:"email"`
	IsActive         bool   `json:"is_active"`
	IsDefaultManager bool   `json:"is_default_manager"`
	AssignedAt       string `json:"assigned_at,omitempty"`
}

type ModuleTechnicianAccessDTO struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Email       string `json:"email"`
	IsActive    bool   `json:"is_active"`
	IsInstaller bool   `json:"is_installer"`
	CanView     bool   `json:"can_view"`
}

type ModuleClientAccessDTO struct {
	ID                      string `json:"id"`
	Name                    string `json:"name"`
	Email                   string `json:"email"`
	IsActive                bool   `json:"is_active"`
	IsAssigned              bool   `json:"is_assigned"`
	OperationalEmailEnabled bool   `json:"operational_email_enabled"`
}

type ModuleDetailsDTO struct {
	Module              ModuleDTO                   `json:"module"`
	ResponsibleManagers []ModuleManagerDTO          `json:"responsible_managers"`
	CompanyManagers     []ModuleManagerDTO          `json:"company_managers,omitempty"`
	CompanyTechnicians  []ModuleTechnicianAccessDTO `json:"company_technicians,omitempty"`
	CompanyClients      []ModuleClientAccessDTO     `json:"company_clients,omitempty"`
	ConfigurationSync   ConfigurationSyncDTO        `json:"configuration_sync"`
	PingIntervalSeconds int                         `json:"ping_interval_seconds"`
	OnlineWindowSeconds int                         `json:"online_window_seconds"`
}

type IntervalChangeLogDTO struct {
	ID                   string `json:"id"`
	ModuleID             string `json:"module_id"`
	AuthorUserID         string `json:"author_user_id"`
	AuthorName           string `json:"author_name"`
	AuthorEmail          string `json:"author_email"`
	AuthorRole           string `json:"author_role"`
	PreviousIntervalDays int32  `json:"previous_interval_days"`
	NewIntervalDays      int32  `json:"new_interval_days"`
	ChangedAt            string `json:"changed_at"`
}

type ModuleClientOptionDTO struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Email    string `json:"email"`
	IsActive bool   `json:"is_active"`
}

type PowerSensorConfigDTO struct {
	PanelIndex int32  `json:"panel_index"`
	I2CAddress string `json:"i2c_address"`
}

type CreateModuleInput struct {
	CompanyID                  pgtype.UUID
	InstallerTechnicianID      pgtype.UUID
	Name                       string
	MacAddress                 string
	ManagerIDs                 []pgtype.UUID
	ClientIDs                  []pgtype.UUID
	PanelLengthCm              *float64
	PanelWidthCm               *float64
	PanelCount                 *int32
	PanelSpacingCm             *float64
	Latitude                   *float64
	Longitude                  *float64
	ElevationM                 *float64
	AzimuthDeg                 *float64
	TiltDeg                    *float64
	AzimuthSource              *string
	TiltSource                 *string
	MinimumSolarAngleDeg       *float64
	InspectionIntervalDays     *int32
	ReservoirNominalCapacityMl *float64
	PowerSensors               []PowerSensorConfigDTO
}

type UpdateConfigurationInput struct {
	Name                       *string
	PanelLengthCm              *float64
	PanelWidthCm               *float64
	PanelCount                 *int32
	PanelSpacingCm             *float64
	Latitude                   *float64
	Longitude                  *float64
	ElevationM                 *float64
	AzimuthDeg                 *float64
	TiltDeg                    *float64
	AzimuthSource              *string
	TiltSource                 *string
	MinimumSolarAngleDeg       *float64
	InspectionIntervalDays     *int32
	ReservoirNominalCapacityMl *float64
	PowerSensors               *[]PowerSensorConfigDTO
	ClientIDs                  *[]pgtype.UUID
}

type MeasurementDTO struct {
	ID                string  `json:"id"`
	ModuleID          string  `json:"module_id"`
	InspectionID      string  `json:"inspection_id"`
	SourceEventID     string  `json:"source_event_id"`
	PanelIndex        *int32  `json:"panel_index,omitempty"`
	MeasuredAt        string  `json:"measured_at"`
	XPositionCM       string  `json:"x_position_cm"`
	LocalXPositionCM  *string `json:"local_x_position_cm,omitempty"`
	MaxTempC          string  `json:"max_temperature_c"`
	VoltageV          *string `json:"voltage_v"`
	CurrentA          *string `json:"current_a"`
	PowerW            *string `json:"power_w"`
	ThermalFrame      any     `json:"thermal_frame,omitempty"`
	ReceivedAt        string  `json:"received_at"`
}

type CleaningDTO struct {
	ID                     string  `json:"id"`
	ModuleID               string  `json:"module_id"`
	AnomalyEventID         string  `json:"anomaly_event_id"`
	SourceEventID          string  `json:"source_event_id"`
	PanelIndex             *int32  `json:"panel_index,omitempty"`
	TargetXPositionCM      string  `json:"target_x_position_cm"`
	LocalXPositionCM       *string `json:"local_x_position_cm,omitempty"`
	LocalTargetXPositionCM *string `json:"local_target_x_position_cm,omitempty"`
	PumpActuated           bool    `json:"pump_actuated"`
	AttemptNumber          *int32  `json:"attempt_number,omitempty"`
	StartedAt              *string `json:"started_at,omitempty"`
	EndedAt                *string `json:"ended_at,omitempty"`
	DurationSeconds        string  `json:"duration_seconds"`
	EstimatedWaterML       string  `json:"estimated_water_volume_ml"`
	Status                 string  `json:"status"`
	FailureReason          *string `json:"failure_reason,omitempty"`
	PostCleaningResult     string  `json:"post_cleaning_result"`
	CreatedAt              string  `json:"created_at"`
}

type AlertDTO struct {
	ID               string   `json:"id"`
	ModuleID         string   `json:"module_id"`
	ModuleName       string   `json:"module_name"`
	Severity         string   `json:"severity"` // 'critical', 'warning'
	Type             string   `json:"type"`     // 'hotspot_unresolved', 'reservoir_low'
	Title            string   `json:"title"`
	Description      string   `json:"description"`
	MetaText         string   `json:"meta_text"`
	PanelIndex       *int32   `json:"panel_index,omitempty"`
	XPositionCm      *float64 `json:"x_position_cm,omitempty"`
	LocalXPositionCM *float64 `json:"local_x_position_cm,omitempty"`
	LocalXCm         *float64 `json:"local_x_cm,omitempty"`
	DeltaC           *float64 `json:"delta_c,omitempty"`
	CreatedAt        string   `json:"created_at"`
	InspectionID          *string  `json:"inspection_id,omitempty"`
	InspectionDate        *string  `json:"inspection_date,omitempty"`
	MaxTemperatureC       *float64 `json:"max_temperature_c,omitempty"`
	BaselineTemperatureC  *float64 `json:"baseline_temperature_c,omitempty"`
	WashAttemptsCount     *int32   `json:"wash_attempts_count,omitempty"`
}

type AlertsSummaryDTO struct {
	Total    int        `json:"total"`
	Critical int        `json:"critical"`
	Warning  int        `json:"warning"`
	Alerts   []AlertDTO `json:"alerts"`
}

type InspectionDTO struct {
	ID                   string   `json:"id"`
	ModuleID             string   `json:"module_id"`
	SourceEventID        string   `json:"source_event_id"`
	Type                 string   `json:"type"`
	CleaningOperationID  *string  `json:"cleaning_operation_id,omitempty"`
	BaselineTemperatureC *float64 `json:"baseline_temperature_c,omitempty"`
	ScheduledFor         string   `json:"scheduled_for"`
	StartedAt            *string  `json:"started_at,omitempty"`
	FinishedAt           *string  `json:"finished_at,omitempty"`
	Status               string   `json:"status"`
	FailureReason        *string  `json:"failure_reason,omitempty"`
	VerificationResult   *string  `json:"verification_result,omitempty"`
	CreatedAt            string   `json:"created_at"`
	UpdatedAt            string   `json:"updated_at"`
}

type ConfirmedAnomalyDTO struct {
	ID                            string   `json:"id"`
	ModuleID                      string   `json:"module_id"`
	OriginMeasurementID           string   `json:"origin_measurement_id"`
	ConfirmingMeasurementIDs      []string `json:"confirming_measurement_ids"`
	ConfirmingMeasurementEventIDs []string `json:"confirming_measurement_event_ids,omitempty"`
	SourceEventID                 string   `json:"source_event_id"`
	PanelIndex                    *int32   `json:"panel_index,omitempty"`
	XPositionCM                   float64  `json:"x_position_cm"`
	LocalXPositionCM              *float64 `json:"local_x_position_cm,omitempty"`
	MaxTemperatureC               *float64 `json:"max_temperature_c,omitempty"`
	DeltaTemperatureC             *float64 `json:"delta_temperature_c,omitempty"`
	DetectedAt                    string   `json:"detected_at"`
	Status                        string   `json:"status"`
	ActuatedAttemptsCount         int32    `json:"actuated_attempts_count"`
	RetryPending                  bool     `json:"retry_pending"`
	ClosedAt                      *string  `json:"closed_at,omitempty"`
}

type InspectionPanelResultDTO struct {
	InspectionID          string  `json:"inspection_id"`
	ModuleID              string  `json:"module_id"`
	PanelIndex            int32   `json:"panel_index"`
	BaselineTemperatureC float64 `json:"baseline_temperature_c"`
	TruncatedByMemory     bool    `json:"truncated_by_memory"`
	FinishedAt            string  `json:"finished_at"`
	CreatedAt             string  `json:"created_at"`
}

type RecordPanelResultOutputDTO struct {
	PanelResult        InspectionPanelResultDTO `json:"panel_result"`
	ConfirmedAnomalies []ConfirmedAnomalyDTO    `json:"confirmed_anomalies"`
}

type LatestInspectionDTO struct {
	Inspection         InspectionDTO              `json:"inspection"`
	TotalMeasurements  int64                      `json:"total_measurements"`
	ConfirmedAnomalies []ConfirmedAnomalyDTO      `json:"confirmed_anomalies"`
	PanelResults       []InspectionPanelResultDTO `json:"panel_results,omitempty"`
}

type PaginationMetadataDTO struct {
	Page        int   `json:"page"`
	Limit       int   `json:"limit"`
	TotalCount  int64 `json:"total_count"`
	TotalPages  int   `json:"total_pages"`
	HasNextPage bool  `json:"has_next_page"`
}

type PagedMeasurementsDTO struct {
	Pagination   PaginationMetadataDTO `json:"pagination"`
	Measurements []MeasurementDTO      `json:"measurements"`
}

type DeviceStatusDTO struct {
	ModuleID            string               `json:"module_id"`
	MACAddress          string               `json:"mac_address"`
	MonitoringStatus    string               `json:"monitoring_status"`
	IsConfigured        bool                 `json:"is_configured"`
	ConfiguredAt        *string              `json:"configured_at,omitempty"`
	IsOnline            bool                 `json:"is_online"`
	LastSeenAt          *string              `json:"last_seen_at,omitempty"`
	WaterAvailable      *bool                `json:"water_available,omitempty"`
	WaterStatus         string               `json:"water_status"`
	LimitsCheckPassed   bool                 `json:"limits_check_passed"`
	ThermalSensorActive bool                 `json:"thermal_sensor_active"`
	LatestMeasurementAt    *string              `json:"latest_measurement_at,omitempty"`
	NextInspectionAt       *string              `json:"next_inspection_at,omitempty"`
	ConfigurationSync      ConfigurationSyncDTO `json:"configuration_sync"`
	ManualInspectionPending bool                 `json:"manual_inspection_pending"`
	PingIntervalSeconds    int                  `json:"ping_interval_seconds"`
	OnlineWindowSeconds    int                  `json:"online_window_seconds"`
}

type RecordDevicePingInput struct {
	WaterAvailable      *bool      `json:"water_available"`
	LimitsCheckPassed   *bool      `json:"limits_check_passed"`
	ThermalSensorActive *bool      `json:"thermal_sensor_active"`
	NextInspectionAt    *time.Time `json:"next_inspection_at,omitempty"`
}

type ClaimDeviceInput struct {
	MACAddress          string `json:"mac_address"`
	FirmwareVersion     string `json:"firmware_version"`
	WaterAvailable      *bool  `json:"water_available"`
	LimitsCheckPassed   *bool  `json:"limits_check_passed"`
	ThermalSensorActive *bool  `json:"thermal_sensor_active"`
}

type ClaimDeviceDTO struct {
	ModuleID               string `json:"module_id"`
	DeviceToken            string `json:"device_token"`
	Status                 string `json:"status"`
	InspectionIntervalDays int32  `json:"inspection_interval_days"`
	PingIntervalSeconds    int    `json:"ping_interval_seconds"`
	Message                string `json:"message"`
}

type TriggerInspectionDTO struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Status  string `json:"status"`
}

type DeviceGeometryDTO struct {
	PanelLengthCm  *float64 `json:"panel_length_cm"`
	PanelWidthCm   *float64 `json:"panel_width_cm"`
	PanelCount     *int32   `json:"panel_count"`
	PanelSpacingCm *float64 `json:"panel_spacing_cm"`
	TotalLengthCm  *float64 `json:"total_length_cm,omitempty"`
}

type DeviceConfigurationDTO struct {
	ConfigVersion       int32             `json:"config_version"`
	Geometry            DeviceGeometryDTO `json:"geometry"`
	Latitude            *float64          `json:"latitude,omitempty"`
	Longitude           *float64          `json:"longitude,omitempty"`
	AzimuthDeg          *float64          `json:"azimuth_deg,omitempty"`
	TiltDeg             *float64          `json:"tilt_deg,omitempty"`
	MinSolarAngle       *float64          `json:"min_solar_angle"`
	IntervalDays        int32             `json:"interval_days"`
	PingIntervalSeconds int               `json:"ping_interval_seconds"`
	PowerSensors        any               `json:"power_sensors,omitempty"`
}

type AcknowledgeDeviceConfigurationInput struct {
	ConfigVersion    int32      `json:"config_version"`
	Applied          bool       `json:"applied"`
	Checksum         string     `json:"checksum"`
	Error            *string    `json:"error,omitempty"`
	NextInspectionAt *time.Time `json:"next_inspection_at,omitempty"`
}

type IngestMeasurementItemInput struct {
	SourceEventID   string     `json:"source_event_id"`
	PanelIndex      *int32     `json:"panel_index,omitempty"`
	MeasuredAt      *time.Time `json:"measured_at"`
	XPositionCm     float64    `json:"x_position_cm"`
	MaxTemperatureC float64    `json:"max_temperature_c"`
	VoltageV        *float64   `json:"voltage_v"`
	CurrentA        *float64   `json:"current_a"`
	PowerW          *float64   `json:"power_w"`
	ThermalFrame    []*float64 `json:"thermal_frame"`
}

type IngestTelemetryInput struct {
	InspectionSourceEventID *string                      `json:"inspection_source_event_id"`
	InspectionScheduledFor  *time.Time                   `json:"inspection_scheduled_for"`
	ScheduledFor            *time.Time                   `json:"scheduled_for"`
	InspectionStartedAt     *time.Time                   `json:"inspection_started_at"`
	StartedAt               *time.Time                   `json:"started_at"`
	InspectionType          *string                      `json:"inspection_type"`
	CleaningOperationID     *string                      `json:"cleaning_operation_id"`
	// Unit of thermal_frame pixels: "celsius" (default, legacy floats) or
	// "decicelsius" (integers in tenths of °C, e.g. 275 == 27.5 °C). Stored values are always °C.
	ThermalFrameUnit        *string                      `json:"thermal_frame_unit"`
	// Single item shorthand:
	SourceEventID           *string                      `json:"source_event_id"`
	PanelIndex              *int32                       `json:"panel_index,omitempty"`
	MeasuredAt              *time.Time                   `json:"measured_at"`
	XPositionCm             float64                      `json:"x_position_cm"`
	MaxTemperatureC         float64                      `json:"max_temperature_c"`
	VoltageV                *float64                     `json:"voltage_v"`
	CurrentA                *float64                     `json:"current_a"`
	PowerW                  *float64                     `json:"power_w"`
	ThermalFrame            []*float64                   `json:"thermal_frame"`
	// Chunked batch uploads (max 5 items per upload):
	Measurements            []IngestMeasurementItemInput `json:"measurements"`
	Batch                   []IngestMeasurementItemInput `json:"batch"`
}

type FinalizeInspectionInput struct {
	Status                *string                 `json:"status,omitempty"`
	FailureReason         *string                 `json:"failure_reason,omitempty"`
	FinishedAt            *time.Time              `json:"finished_at"`
	BaselineTemperatureC float64                 `json:"baseline_temperature_c"`
	ConfirmedHotspots     []ConfirmedHotspotInput `json:"confirmed_hotspots"`
}

type AbortInspectionInput struct {
	FailureReason string `json:"failure_reason"`
}

type RecordPanelResultInput struct {
	BaselineTemperatureC float64                 `json:"baseline_temperature_c"`
	TruncatedByMemory     bool                    `json:"truncated_by_memory"`
	FinishedAt            *time.Time              `json:"finished_at,omitempty"`
	ConfirmedHotspots     []ConfirmedHotspotInput `json:"confirmed_hotspots,omitempty"`
}

type ConfirmedHotspotInput struct {
	SourceEventID            string     `json:"source_event_id"`
	PanelIndex               *int32     `json:"panel_index,omitempty"`
	GlobalXPositionCm        float64    `json:"global_x_position_cm"`
	RowIndex                 *int       `json:"row_index"`
	MaxTemperatureC          float64    `json:"max_temperature_c"`
	DetectedAt               *time.Time `json:"detected_at"`
	OriginMeasurementEventID string     `json:"origin_measurement_event_id"`
	ConfirmingEventIDs       []string   `json:"confirming_event_ids"`
}

type IngestCleaningInput struct {
	AnomalyEventID         *string `json:"anomaly_event_id"`
	PanelIndex             *int32  `json:"panel_index,omitempty"`
	TargetXPositionCm      float64 `json:"target_x_position_cm"`
	PumpActuated           bool    `json:"pump_actuated"`
	AttemptNumber          *int    `json:"attempt_number"`
	DurationSeconds        float64 `json:"duration_seconds"`
	EstimatedWaterVolumeMl float64 `json:"estimated_water_volume_ml"`
	Status                 string  `json:"status"`
	FailureReason          *string `json:"failure_reason"`
	PostCleaningResult     string  `json:"post_cleaning_result"`
}
