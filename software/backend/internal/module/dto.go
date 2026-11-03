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
	ConfiguredAt               *string              `json:"configured_at"`
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
	ClientIDs                  *[]pgtype.UUID
}

type MeasurementDTO struct {
	ID               string `json:"id"`
	ModuleID         string `json:"module_id"`
	InspectionID     string `json:"inspection_id"`
	SourceEventID    string `json:"source_event_id"`
	MeasuredAt       string `json:"measured_at"`
	XPositionCM      string `json:"x_position_cm"`
	BaselineTempC    string `json:"baseline_temperature_c"`
	MaxTempC         string `json:"max_temperature_c"`
	HotspotDetected  bool   `json:"hotspot_detected"`
	HotspotConfirmed bool   `json:"hotspot_confirmed"`
	VoltageV         string `json:"voltage_v"`
	CurrentA         string `json:"current_a"`
	PowerW           string `json:"power_w"`
	ReceivedAt       string `json:"received_at"`
}

type CleaningDTO struct {
	ID                 string  `json:"id"`
	ModuleID           string  `json:"module_id"`
	AnomalyEventID     string  `json:"anomaly_event_id"`
	SourceEventID      string  `json:"source_event_id"`
	TargetXPositionCM  string  `json:"target_x_position_cm"`
	PumpActuated       bool    `json:"pump_actuated"`
	AttemptNumber      *int32  `json:"attempt_number,omitempty"`
	StartedAt          *string `json:"started_at,omitempty"`
	EndedAt            *string `json:"ended_at,omitempty"`
	DurationSeconds    string  `json:"duration_seconds"`
	EstimatedWaterML   string  `json:"estimated_water_volume_ml"`
	Status             string  `json:"status"`
	FailureReason      *string `json:"failure_reason,omitempty"`
	PostCleaningResult string  `json:"post_cleaning_result"`
	CreatedAt          string  `json:"created_at"`
}

type ThermalBandDTO struct {
	BandIndex       int      `json:"band_index"`
	StartXCm        float64  `json:"start_x_cm"`
	EndXCm          float64  `json:"end_x_cm"`
	MaxTemperatureC *float64 `json:"max_temperature_c"`
	AvgTemperatureC *float64 `json:"avg_temperature_c"`
	HasHotspot      bool     `json:"has_hotspot"`
	HasData         bool     `json:"has_data"`
}

type AlertDTO struct {
	ID          string   `json:"id"`
	ModuleID    string   `json:"module_id"`
	ModuleName  string   `json:"module_name"`
	Severity    string   `json:"severity"` // 'critical', 'warning'
	Type        string   `json:"type"`     // 'hotspot_unresolved', 'reservoir_low'
	Title       string   `json:"title"`
	Description string   `json:"description"`
	MetaText    string   `json:"meta_text"`
	XPositionCm *float64 `json:"x_position_cm,omitempty"`
	DeltaC      *float64 `json:"delta_c,omitempty"`
	CreatedAt   string   `json:"created_at"`
}

type AlertsSummaryDTO struct {
	Total    int        `json:"total"`
	Critical int        `json:"critical"`
	Warning  int        `json:"warning"`
	Alerts   []AlertDTO `json:"alerts"`
}

type ThermalMapDTO struct {
	ID               string           `json:"id"`
	InspectionID     string           `json:"inspection_id"`
	WidthPixels      int32            `json:"width_pixels"`
	HeightPixels     int32            `json:"height_pixels"`
	TemperaturesC    any              `json:"temperatures_c"`
	AlgorithmVersion string           `json:"algorithm_version"`
	Bands            []ThermalBandDTO `json:"bands"`
	GeneratedAt      string           `json:"generated_at"`
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
	LatestMeasurementAt *string              `json:"latest_measurement_at,omitempty"`
	ConfigurationSync   ConfigurationSyncDTO `json:"configuration_sync"`
	PingIntervalSeconds int                  `json:"ping_interval_seconds"`
	OnlineWindowSeconds int                  `json:"online_window_seconds"`
}

type RecordDevicePingInput struct {
	WaterAvailable      *bool `json:"water_available"`
	LimitsCheckPassed   *bool `json:"limits_check_passed"`
	ThermalSensorActive *bool `json:"thermal_sensor_active"`
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

type DeviceGeometryDTO struct {
	PanelLengthCm  *float64 `json:"panel_length_cm"`
	PanelWidthCm   *float64 `json:"panel_width_cm"`
	PanelCount     *int32   `json:"panel_count"`
	PanelSpacingCm *float64 `json:"panel_spacing_cm"`
}

type DeviceConfigurationDTO struct {
	ConfigVersion       int32             `json:"config_version"`
	Geometry            DeviceGeometryDTO `json:"geometry"`
	MinSolarAngle       *float64          `json:"min_solar_angle"`
	IntervalDays        int32             `json:"interval_days"`
	PingIntervalSeconds int               `json:"ping_interval_seconds"`
}

type AcknowledgeDeviceConfigurationInput struct {
	ConfigVersion int32   `json:"config_version"`
	Applied       bool    `json:"applied"`
	Checksum      string  `json:"checksum"`
	Error         *string `json:"error,omitempty"`
}

type IngestTelemetryInput struct {
	MeasuredAt             *time.Time             `json:"measured_at"`
	InspectionScheduledFor *time.Time             `json:"inspection_scheduled_for"`
	InspectionStartedAt    *time.Time             `json:"inspection_started_at"`
	InspectionType         *string                `json:"inspection_type"`
	WaterAvailable         *bool                  `json:"water_available"`
	XPositionCm            float64                `json:"x_position_cm"`
	BaselineTemperatureC   float64                `json:"baseline_temperature_c"`
	MaxTemperatureC        float64                `json:"max_temperature_c"`
	HotspotDetected        bool                   `json:"hotspot_detected"`
	HotspotConfirmed       bool                   `json:"hotspot_confirmed"`
	VoltageV               float64                `json:"voltage_v"`
	CurrentA               float64                `json:"current_a"`
	PowerW                 *float64               `json:"power_w"`
	ThermalFrame           []float64              `json:"thermal_frame"`
	ThermalMap             []float64              `json:"thermal_map"`
	WidthPixels            int                    `json:"width_pixels"`
	HeightPixels           int                    `json:"height_pixels"`
	Batch                  []IngestTelemetryInput `json:"batch"`
}

type IngestCleaningInput struct {
	AnomalyEventID         *string `json:"anomaly_event_id"`
	TargetXPositionCm      float64 `json:"target_x_position_cm"`
	PumpActuated           bool    `json:"pump_actuated"`
	AttemptNumber          *int    `json:"attempt_number"`
	DurationSeconds        float64 `json:"duration_seconds"`
	EstimatedWaterVolumeMl float64 `json:"estimated_water_volume_ml"`
	Status                 string  `json:"status"`
	FailureReason          *string `json:"failure_reason"`
	PostCleaningResult     string  `json:"post_cleaning_result"`
}
