package module

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math"
	"net"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
)

const (
	StatusPendingConfiguration = "pending_configuration"
	StatusActive               = "active"
	StatusMaintenance          = "maintenance"
	StatusInactive             = "inactive"

	SourceSensor = "sensor"
	SourceManual = "manual"

	RelManager             = "manager"
	RelInstallerTechnician = "installer_technician"
	RelSharedTechnician    = "shared_technician"
	RelAssignedClient      = "assigned_client"
)

var (
	ErrInvalidInput                  = errors.New("invalid module input")
	ErrNotFound                      = errors.New("module not found")
	ErrForbidden                     = errors.New("insufficient permissions for this module operation")
	ErrMACConflict                   = errors.New("a module with this MAC address is already registered")
	ErrManagerRequired               = errors.New("at least one active responsible manager from the same company is required")
	ErrTechnicianHasNoActiveManagers = errors.New("technician has no active responsible managers")
	ErrTargetNotTechnician           = errors.New("target user is not a technician in this company")
	ErrTargetNotClient               = errors.New("one or more target users are not active clients in this company")
	ErrModuleHasOperationalHistory   = errors.New("module contains operational history or pending operations and cannot be deleted; deactivate it instead")
	ErrStaleConfig                   = errors.New("stale configuration version")
)

type ConfigurationSyncDTO struct {
	State                string  `json:"state"`
	ConfigVersion        int32   `json:"config_version"`
	ConfigAppliedVersion int32   `json:"config_applied_version"`
	ConfigAppliedAt      *string `json:"config_applied_at"`
	ConfigApplyError     *string `json:"config_apply_error"`
}

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

type Service struct {
	database            auth.DB
	queries             *db.Queries
	pingIntervalSeconds int
}

func NewService(database auth.DB) *Service {
	return &Service{
		database:            database,
		queries:             db.New(database),
		pingIntervalSeconds: getDevicePingIntervalSeconds(),
	}
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

func (s *Service) ListActiveCompanyManagers(ctx context.Context, companyID pgtype.UUID) ([]ModuleManagerDTO, error) {
	if !companyID.Valid {
		return nil, ErrInvalidInput
	}
	rows, err := s.queries.ListActiveCompanyManagers(ctx, companyID)
	if err != nil {
		return nil, err
	}
	out := make([]ModuleManagerDTO, 0, len(rows))
	for _, r := range rows {
		out = append(out, ModuleManagerDTO{
			ID:               auth.FormatUUID(r.ID),
			Name:             r.Name,
			Email:            r.Email,
			IsActive:         r.IsActive,
			IsDefaultManager: r.IsDefaultManager,
		})
	}
	return out, nil
}

func (s *Service) ListActiveCompanyClients(ctx context.Context, companyID pgtype.UUID) ([]ModuleClientOptionDTO, error) {
	if !companyID.Valid {
		return nil, ErrInvalidInput
	}
	rows, err := s.queries.ListActiveCompanyClients(ctx, companyID)
	if err != nil {
		return nil, err
	}
	out := make([]ModuleClientOptionDTO, 0, len(rows))
	for _, r := range rows {
		out = append(out, ModuleClientOptionDTO{
			ID:       auth.FormatUUID(r.ID),
			Name:     r.Name,
			Email:    r.Email,
			IsActive: r.IsActive,
		})
	}
	return out, nil
}

func (s *Service) CreateModule(ctx context.Context, in CreateModuleInput) (ModuleDetailsDTO, error) {
	if !in.CompanyID.Valid || !in.InstallerTechnicianID.Valid {
		return ModuleDetailsDTO{}, ErrInvalidInput
	}

	name := strings.TrimSpace(in.Name)
	if name == "" {
		return ModuleDetailsDTO{}, ErrInvalidInput
	}

	normalizedMAC, err := normalizeAndValidateMAC(in.MacAddress)
	if err != nil {
		return ModuleDetailsDTO{}, ErrInvalidInput
	}

	intervalDays := int32(1)
	if in.InspectionIntervalDays != nil {
		if *in.InspectionIntervalDays < 1 {
			return ModuleDetailsDTO{}, ErrInvalidInput
		}
		intervalDays = *in.InspectionIntervalDays
	}

	if err := validateOptionalConfigFields(
		in.PanelLengthCm,
		in.PanelWidthCm,
		in.PanelCount,
		in.PanelSpacingCm,
		in.Latitude,
		in.Longitude,
		in.ElevationM,
		in.AzimuthDeg,
		in.TiltDeg,
		in.AzimuthSource,
		in.TiltSource,
		in.MinimumSolarAngleDeg,
		in.ReservoirNominalCapacityMl,
	); err != nil {
		return ModuleDetailsDTO{}, err
	}

	isComplete := isConfigurationComplete(
		in.PanelLengthCm,
		in.PanelWidthCm,
		in.PanelCount,
		in.PanelSpacingCm,
		in.Latitude,
		in.Longitude,
		in.ElevationM,
		in.AzimuthDeg,
		in.TiltDeg,
		in.AzimuthSource,
		in.TiltSource,
		in.MinimumSolarAngleDeg,
	)

	status := StatusPendingConfiguration
	var configuredAt *time.Time
	if isComplete {
		status = StatusActive
		now := time.Now().UTC()
		configuredAt = &now
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return ModuleDetailsDTO{}, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	// Verify installer is an active technician in the company
	installer, err := qtx.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
		CompanyID: in.CompanyID,
		ID:        in.InstallerTechnicianID,
	})
	if err != nil || installer.Role != auth.RoleTechnician || !installer.IsActive {
		return ModuleDetailsDTO{}, ErrForbidden
	}

	// Aditivo: Automatically associate all active managers responsible for the technician
	assignedManagers, err := qtx.ListManagersByTechnician(ctx, db.ListManagersByTechnicianParams{
		CompanyID:    in.CompanyID,
		TechnicianID: in.InstallerTechnicianID,
	})
	if err != nil {
		return ModuleDetailsDTO{}, err
	}

	activeMgrIDs := make([]pgtype.UUID, 0, len(assignedManagers))
	for _, mgr := range assignedManagers {
		if mgr.IsActive && mgr.CompanyID.Bytes == in.CompanyID.Bytes {
			activeMgrIDs = append(activeMgrIDs, mgr.ID)
		}
	}

	if len(activeMgrIDs) == 0 {
		return ModuleDetailsDTO{}, ErrTechnicianHasNoActiveManagers
	}

	var configVersion int32 = 0
	if isComplete {
		configVersion = 1
	}

	created, err := qtx.CreateModule(ctx, db.CreateModuleParams{
		CompanyID:                  in.CompanyID,
		InstallerTechnicianID:      in.InstallerTechnicianID,
		Name:                       name,
		MacAddress:                 normalizedMAC,
		IsActive:                   true,
		MonitoringStatus:           status,
		PanelLengthCm:              floatPtrToNumeric(in.PanelLengthCm),
		PanelWidthCm:               floatPtrToNumeric(in.PanelWidthCm),
		PanelCount:                 int32PtrToPgInt4(in.PanelCount),
		PanelSpacingCm:             floatPtrToNumeric(in.PanelSpacingCm),
		Latitude:                   floatPtrToPgFloat8(in.Latitude),
		Longitude:                  floatPtrToPgFloat8(in.Longitude),
		ElevationM:                 floatPtrToPgFloat8(in.ElevationM),
		AzimuthDeg:                 floatPtrToNumeric(in.AzimuthDeg),
		TiltDeg:                    floatPtrToNumeric(in.TiltDeg),
		AzimuthSource:              stringPtrToPgText(in.AzimuthSource),
		TiltSource:                 stringPtrToPgText(in.TiltSource),
		MinimumSolarAngleDeg:       floatPtrToNumeric(in.MinimumSolarAngleDeg),
		InspectionIntervalDays:     intervalDays,
		ReservoirNominalCapacityMl: floatPtrToNumeric(in.ReservoirNominalCapacityMl),
		ConfiguredAt:               configuredAt,
		ConfigVersion:              configVersion,
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return ModuleDetailsDTO{}, ErrMACConflict
		}
		return ModuleDetailsDTO{}, err
	}

	for _, mgrID := range activeMgrIDs {
		if _, err := qtx.AddModuleManager(ctx, db.AddModuleManagerParams{
			CompanyID: in.CompanyID,
			ModuleID:  created.ID,
			ManagerID: mgrID,
		}); err != nil {
			return ModuleDetailsDTO{}, err
		}
	}

	if _, err := qtx.UpsertModuleTechnician(ctx, db.UpsertModuleTechnicianParams{
		CompanyID:    in.CompanyID,
		ModuleID:     created.ID,
		TechnicianID: in.InstallerTechnicianID,
		CanView:      true,
	}); err != nil {
		return ModuleDetailsDTO{}, err
	}

	// Verify and link optional clients (Aditivo - Vínculo de Clients durante a instalação)
	uniqueClientIDs := deduplicateUUIDs(in.ClientIDs)
	for _, cID := range uniqueClientIDs {
		c, err := qtx.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
			CompanyID: in.CompanyID,
			ID:        cID,
		})
		if err != nil || c.Role != auth.RoleClient || !c.IsActive {
			return ModuleDetailsDTO{}, ErrTargetNotClient
		}
		if _, err := qtx.AddModuleClient(ctx, db.AddModuleClientParams{
			CompanyID:               in.CompanyID,
			ModuleID:                created.ID,
			ClientID:                cID,
			OperationalEmailEnabled: true,
		}); err != nil {
			return ModuleDetailsDTO{}, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return ModuleDetailsDTO{}, err
	}

	return s.GetModuleDetails(ctx, auth.Principal{
		ID:        in.InstallerTechnicianID,
		CompanyID: in.CompanyID,
		Role:      auth.RoleTechnician,
	}, created.ID)
}

func (s *Service) ListModules(ctx context.Context, principal auth.Principal, limit, offset int32) ([]ModuleDTO, error) {
	if !principal.CompanyID.Valid {
		return nil, ErrForbidden
	}
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	switch principal.Role {
	case auth.RoleManager:
		rows, err := s.queries.ListModulesForManager(ctx, db.ListModulesForManagerParams{
			CompanyID: principal.CompanyID,
			Limit:     limit,
			Offset:    offset,
		})
		if err != nil {
			return nil, err
		}
		out := make([]ModuleDTO, 0, len(rows))
		for _, r := range rows {
			out = append(out, s.mapGetModuleRowToDTO(db.GetModuleByIDRow(r), RelManager, nil))
		}
		return out, nil

	case auth.RoleTechnician:
		rows, err := s.queries.ListModulesForTechnician(ctx, db.ListModulesForTechnicianParams{
			CompanyID:    principal.CompanyID,
			TechnicianID: principal.ID,
			Limit:        limit,
			Offset:       offset,
		})
		if err != nil {
			return nil, err
		}
		out := make([]ModuleDTO, 0, len(rows))
		for _, r := range rows {
			rel := RelSharedTechnician
			if r.InstallerTechnicianID.Bytes == principal.ID.Bytes {
				rel = RelInstallerTechnician
			}
			out = append(out, s.mapGetModuleRowToDTO(db.GetModuleByIDRow(r), rel, nil))
		}
		return out, nil

	case auth.RoleClient:
		rows, err := s.queries.ListModulesForClient(ctx, db.ListModulesForClientParams{
			CompanyID: principal.CompanyID,
			ClientID:  principal.ID,
			Limit:     limit,
			Offset:    offset,
		})
		if err != nil {
			return nil, err
		}
		out := make([]ModuleDTO, 0, len(rows))
		for _, r := range rows {
			emailEnabled := r.OperationalEmailEnabled
			baseRow := db.GetModuleByIDRow{
				ID:                         r.ID,
				CompanyID:                  r.CompanyID,
				InstallerTechnicianID:      r.InstallerTechnicianID,
				InstallerName:              r.InstallerName,
				InstallerEmail:             r.InstallerEmail,
				Name:                       r.Name,
				MacAddress:                 r.MacAddress,
				IsActive:                   r.IsActive,
				MonitoringStatus:           r.MonitoringStatus,
				PanelLengthCm:              r.PanelLengthCm,
				PanelWidthCm:               r.PanelWidthCm,
				PanelCount:                 r.PanelCount,
				PanelSpacingCm:             r.PanelSpacingCm,
				Latitude:                   r.Latitude,
				Longitude:                  r.Longitude,
				ElevationM:                 r.ElevationM,
				AzimuthDeg:                 r.AzimuthDeg,
				TiltDeg:                    r.TiltDeg,
				AzimuthSource:              r.AzimuthSource,
				TiltSource:                 r.TiltSource,
				MinimumSolarAngleDeg:       r.MinimumSolarAngleDeg,
				InspectionIntervalDays:     r.InspectionIntervalDays,
				ReservoirNominalCapacityMl: r.ReservoirNominalCapacityMl,
				ConfiguredAt:               r.ConfiguredAt,
				CreatedAt:                  r.CreatedAt,
				UpdatedAt:                  r.UpdatedAt,
				ConfigVersion:              r.ConfigVersion,
				ConfigAppliedVersion:       r.ConfigAppliedVersion,
				ConfigAppliedAt:            r.ConfigAppliedAt,
				ConfigApplyError:           r.ConfigApplyError,
			}
			out = append(out, s.mapGetModuleRowToDTO(baseRow, RelAssignedClient, &emailEnabled))
		}
		return out, nil

	default:
		return nil, ErrForbidden
	}
}

func (s *Service) GetModuleDetails(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) (ModuleDetailsDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return ModuleDetailsDTO{}, ErrForbidden
	}

	row, err := s.queries.GetModuleByID(ctx, db.GetModuleByIDParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ModuleDetailsDTO{}, ErrNotFound
		}
		return ModuleDetailsDTO{}, err
	}

	rel, emailEnabled, err := s.resolveUserModuleRelationship(ctx, s.queries, principal, row.ID, row.InstallerTechnicianID)
	if err != nil {
		return ModuleDetailsDTO{}, err
	}

	mgrRows, err := s.queries.ListManagersByModule(ctx, db.ListManagersByModuleParams{
		CompanyID: principal.CompanyID,
		ModuleID:  moduleID,
	})
	if err != nil {
		return ModuleDetailsDTO{}, err
	}
	respMgrs := make([]ModuleManagerDTO, 0, len(mgrRows))
	assignedMgrSet := make(map[[16]byte]struct{}, len(mgrRows))
	for _, m := range mgrRows {
		assignedMgrSet[m.ID.Bytes] = struct{}{}
		respMgrs = append(respMgrs, ModuleManagerDTO{
			ID:               auth.FormatUUID(m.ID),
			Name:             m.Name,
			Email:            m.Email,
			IsActive:         m.IsActive,
			IsDefaultManager: m.IsDefaultManager,
			AssignedAt:       m.AssignedAt.UTC().Format(time.RFC3339),
		})
	}

	modDTO := s.mapGetModuleRowToDTO(row, rel, emailEnabled)
	details := ModuleDetailsDTO{
		Module:              modDTO,
		ResponsibleManagers: respMgrs,
		ConfigurationSync:   modDTO.ConfigurationSync,
		PingIntervalSeconds: s.PingIntervalSeconds(),
		OnlineWindowSeconds: s.OnlineWindowSeconds(),
	}

	// If caller is a Manager, include company users state for SCR-14 access management
	if principal.Role == auth.RoleManager {
		allUsers, err := s.queries.ListUsersByCompany(ctx, db.ListUsersByCompanyParams{
			CompanyID: principal.CompanyID,
			Limit:     500,
			Offset:    0,
		})
		if err != nil {
			return ModuleDetailsDTO{}, err
		}

		techLinks, err := s.queries.ListTechniciansByModule(ctx, db.ListTechniciansByModuleParams{
			CompanyID: principal.CompanyID,
			ModuleID:  moduleID,
		})
		if err != nil {
			return ModuleDetailsDTO{}, err
		}
		techCanViewMap := make(map[[16]byte]bool, len(techLinks))
		for _, tl := range techLinks {
			techCanViewMap[tl.ID.Bytes] = tl.CanView
		}

		clientLinks, err := s.queries.ListClientsByModule(ctx, db.ListClientsByModuleParams{
			CompanyID: principal.CompanyID,
			ModuleID:  moduleID,
		})
		if err != nil {
			return ModuleDetailsDTO{}, err
		}
		clientMap := make(map[[16]byte]bool, len(clientLinks))
		for _, cl := range clientLinks {
			clientMap[cl.ID.Bytes] = cl.OperationalEmailEnabled
		}

		for _, u := range allUsers {
			switch u.Role {
			case auth.RoleManager:
				if !u.IsActive {
					continue
				}
				details.CompanyManagers = append(details.CompanyManagers, ModuleManagerDTO{
					ID:               auth.FormatUUID(u.ID),
					Name:             u.Name,
					Email:            u.Email,
					IsActive:         u.IsActive,
					IsDefaultManager: u.IsDefaultManager,
				})
			case auth.RoleTechnician:
				canView := techCanViewMap[u.ID.Bytes]
				details.CompanyTechnicians = append(details.CompanyTechnicians, ModuleTechnicianAccessDTO{
					ID:          auth.FormatUUID(u.ID),
					Name:        u.Name,
					Email:       u.Email,
					IsActive:    u.IsActive,
					IsInstaller: u.ID.Bytes == row.InstallerTechnicianID.Bytes,
					CanView:     canView,
				})
			case auth.RoleClient:
				emailPref, assigned := clientMap[u.ID.Bytes]
				details.CompanyClients = append(details.CompanyClients, ModuleClientAccessDTO{
					ID:                      auth.FormatUUID(u.ID),
					Name:                    u.Name,
					Email:                   u.Email,
					IsActive:                u.IsActive,
					IsAssigned:              assigned,
					OperationalEmailEnabled: emailPref,
				})
			}
		}
	}

	return details, nil
}

func (s *Service) UpdateConfiguration(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, in UpdateConfigurationInput) (ModuleDetailsDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return ModuleDetailsDTO{}, ErrForbidden
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return ModuleDetailsDTO{}, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	current, err := qtx.GetModuleByIDForUpdate(ctx, db.GetModuleByIDForUpdateParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ModuleDetailsDTO{}, ErrNotFound
		}
		return ModuleDetailsDTO{}, err
	}

	rel, _, err := s.resolveUserModuleRelationship(ctx, qtx, principal, current.ID, current.InstallerTechnicianID)
	if err != nil {
		return ModuleDetailsDTO{}, err
	}
	perms := permissionsForRelationship(rel)

	hasGeometryOrLocationEdit := in.Name != nil ||
		in.PanelLengthCm != nil ||
		in.PanelWidthCm != nil ||
		in.PanelCount != nil ||
		in.PanelSpacingCm != nil ||
		in.Latitude != nil ||
		in.Longitude != nil ||
		in.ElevationM != nil ||
		in.AzimuthDeg != nil ||
		in.TiltDeg != nil ||
		in.AzimuthSource != nil ||
		in.TiltSource != nil ||
		in.ReservoirNominalCapacityMl != nil

	hasSolarAngleEdit := in.MinimumSolarAngleDeg != nil
	hasIntervalEdit := in.InspectionIntervalDays != nil
	hasClientEdit := in.ClientIDs != nil

	if !hasGeometryOrLocationEdit && !hasSolarAngleEdit && !hasIntervalEdit && !hasClientEdit {
		return ModuleDetailsDTO{}, ErrInvalidInput
	}

	if hasGeometryOrLocationEdit && !perms.CanEditGeometryAndLocation {
		return ModuleDetailsDTO{}, ErrForbidden
	}
	if hasSolarAngleEdit && !perms.CanEditSolarAngle {
		return ModuleDetailsDTO{}, ErrForbidden
	}
	if hasIntervalEdit && !perms.CanEditInterval {
		return ModuleDetailsDTO{}, ErrForbidden
	}
	if hasClientEdit {
		// Aditivo: Em rascunhos, o instalador pode alterar essa seleção enquanto possuir acesso efetivo e a instalação ainda não estiver concluída.
		// Após a conclusão, somente o Manager pode incluir ou remover Clients do módulo.
		if current.MonitoringStatus != StatusPendingConfiguration && principal.Role != auth.RoleManager {
			return ModuleDetailsDTO{}, ErrForbidden
		}
	}

	// Merge incoming fields onto existing configuration
	name := current.Name
	if in.Name != nil {
		trimmed := strings.TrimSpace(*in.Name)
		if trimmed == "" {
			return ModuleDetailsDTO{}, ErrInvalidInput
		}
		name = trimmed
	}

	panelLength := numericToFloatPtr(current.PanelLengthCm)
	if in.PanelLengthCm != nil {
		panelLength = in.PanelLengthCm
	}
	panelWidth := numericToFloatPtr(current.PanelWidthCm)
	if in.PanelWidthCm != nil {
		panelWidth = in.PanelWidthCm
	}
	panelCount := pgInt4ToInt32Ptr(current.PanelCount)
	if in.PanelCount != nil {
		panelCount = in.PanelCount
	}
	panelSpacing := numericToFloatPtr(current.PanelSpacingCm)
	if in.PanelSpacingCm != nil {
		panelSpacing = in.PanelSpacingCm
	}
	latitude := pgFloat8ToFloatPtr(current.Latitude)
	if in.Latitude != nil {
		latitude = in.Latitude
	}
	longitude := pgFloat8ToFloatPtr(current.Longitude)
	if in.Longitude != nil {
		longitude = in.Longitude
	}
	elevation := pgFloat8ToFloatPtr(current.ElevationM)
	if in.ElevationM != nil {
		elevation = in.ElevationM
	}
	azimuth := numericToFloatPtr(current.AzimuthDeg)
	if in.AzimuthDeg != nil {
		azimuth = in.AzimuthDeg
	}
	tilt := numericToFloatPtr(current.TiltDeg)
	if in.TiltDeg != nil {
		tilt = in.TiltDeg
	}
	azimuthSource := pgTextToStringPtr(current.AzimuthSource)
	if in.AzimuthSource != nil {
		azimuthSource = in.AzimuthSource
	}
	tiltSource := pgTextToStringPtr(current.TiltSource)
	if in.TiltSource != nil {
		tiltSource = in.TiltSource
	}
	minSolarAngle := numericToFloatPtr(current.MinimumSolarAngleDeg)
	if in.MinimumSolarAngleDeg != nil {
		minSolarAngle = in.MinimumSolarAngleDeg
	}
	reservoirCap := numericToFloatPtr(current.ReservoirNominalCapacityMl)
	if in.ReservoirNominalCapacityMl != nil {
		reservoirCap = in.ReservoirNominalCapacityMl
	}

	intervalDays := current.InspectionIntervalDays
	if in.InspectionIntervalDays != nil {
		if *in.InspectionIntervalDays < 1 {
			return ModuleDetailsDTO{}, ErrInvalidInput
		}
		intervalDays = *in.InspectionIntervalDays
	}

	if err := validateOptionalConfigFields(
		panelLength,
		panelWidth,
		panelCount,
		panelSpacing,
		latitude,
		longitude,
		elevation,
		azimuth,
		tilt,
		azimuthSource,
		tiltSource,
		minSolarAngle,
		reservoirCap,
	); err != nil {
		return ModuleDetailsDTO{}, err
	}

	isComplete := isConfigurationComplete(
		panelLength,
		panelWidth,
		panelCount,
		panelSpacing,
		latitude,
		longitude,
		elevation,
		azimuth,
		tilt,
		azimuthSource,
		tiltSource,
		minSolarAngle,
	)

	status := current.MonitoringStatus
	configuredAt := current.ConfiguredAt
	if status == StatusPendingConfiguration && isComplete && current.IsActive {
		status = StatusActive
		now := time.Now().UTC()
		configuredAt = &now
	} else if status == StatusActive && !isComplete {
		return ModuleDetailsDTO{}, ErrInvalidInput
	} else if isComplete && configuredAt == nil {
		now := time.Now().UTC()
		configuredAt = &now
	}

	_, err = qtx.UpdateModuleConfiguration(ctx, db.UpdateModuleConfigurationParams{
		CompanyID:                  principal.CompanyID,
		ID:                         moduleID,
		Name:                       name,
		MonitoringStatus:           status,
		PanelLengthCm:              floatPtrToNumeric(panelLength),
		PanelWidthCm:               floatPtrToNumeric(panelWidth),
		PanelCount:                 int32PtrToPgInt4(panelCount),
		PanelSpacingCm:             floatPtrToNumeric(panelSpacing),
		Latitude:                   floatPtrToPgFloat8(latitude),
		Longitude:                  floatPtrToPgFloat8(longitude),
		ElevationM:                 floatPtrToPgFloat8(elevation),
		AzimuthDeg:                 floatPtrToNumeric(azimuth),
		TiltDeg:                    floatPtrToNumeric(tilt),
		AzimuthSource:              stringPtrToPgText(azimuthSource),
		TiltSource:                 stringPtrToPgText(tiltSource),
		MinimumSolarAngleDeg:       floatPtrToNumeric(minSolarAngle),
		InspectionIntervalDays:     intervalDays,
		ReservoirNominalCapacityMl: floatPtrToNumeric(reservoirCap),
		ConfiguredAt:               configuredAt,
	})
	if err != nil {
		return ModuleDetailsDTO{}, err
	}

	if intervalDays != current.InspectionIntervalDays {
		if _, err := qtx.CreateIntervalChangeLog(ctx, db.CreateIntervalChangeLogParams{
			CompanyID:            principal.CompanyID,
			ModuleID:             moduleID,
			AuthorUserID:         principal.ID,
			PreviousIntervalDays: current.InspectionIntervalDays,
			NewIntervalDays:      intervalDays,
		}); err != nil {
			return ModuleDetailsDTO{}, err
		}
	}

	if in.ClientIDs != nil {
		uniqueClientIDs := deduplicateUUIDs(*in.ClientIDs)
		for _, cID := range uniqueClientIDs {
			c, err := qtx.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
				CompanyID: principal.CompanyID,
				ID:        cID,
			})
			if err != nil || c.Role != auth.RoleClient || !c.IsActive {
				return ModuleDetailsDTO{}, ErrTargetNotClient
			}
		}

		if err := qtx.DeleteAllClientsForModule(ctx, db.DeleteAllClientsForModuleParams{
			CompanyID: principal.CompanyID,
			ModuleID:  moduleID,
		}); err != nil {
			return ModuleDetailsDTO{}, err
		}

		for _, cID := range uniqueClientIDs {
			if _, err := qtx.AddModuleClient(ctx, db.AddModuleClientParams{
				CompanyID:               principal.CompanyID,
				ModuleID:                moduleID,
				ClientID:                cID,
				OperationalEmailEnabled: true,
			}); err != nil {
				return ModuleDetailsDTO{}, err
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return ModuleDetailsDTO{}, err
	}

	return s.GetModuleDetails(ctx, principal, moduleID)
}

func (s *Service) ListIntervalChangeLogs(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, limit, offset int32) ([]IntervalChangeLogDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
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

	if _, _, err := s.resolveUserModuleRelationship(ctx, s.queries, principal, mod.ID, mod.InstallerTechnicianID); err != nil {
		return nil, err
	}

	rows, err := s.queries.ListIntervalChangeLogsByModule(ctx, db.ListIntervalChangeLogsByModuleParams{
		CompanyID: principal.CompanyID,
		ModuleID:  moduleID,
		Limit:     limit,
		Offset:    offset,
	})
	if err != nil {
		return nil, err
	}

	out := make([]IntervalChangeLogDTO, 0, len(rows))
	for _, r := range rows {
		out = append(out, IntervalChangeLogDTO{
			ID:                   auth.FormatUUID(r.ID),
			ModuleID:             auth.FormatUUID(r.ModuleID),
			AuthorUserID:         auth.FormatUUID(r.AuthorUserID),
			AuthorName:           r.AuthorName,
			AuthorEmail:          r.AuthorEmail,
			AuthorRole:           r.AuthorRole,
			PreviousIntervalDays: r.PreviousIntervalDays,
			NewIntervalDays:      r.NewIntervalDays,
			ChangedAt:            r.ChangedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
}

func (s *Service) SetModuleManagers(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, managerIDs []pgtype.UUID) (ModuleDetailsDTO, error) {
	if principal.Role != auth.RoleManager || !principal.CompanyID.Valid || !moduleID.Valid {
		return ModuleDetailsDTO{}, ErrForbidden
	}

	uniqueMgrIDs := deduplicateUUIDs(managerIDs)
	if len(uniqueMgrIDs) == 0 {
		return ModuleDetailsDTO{}, ErrManagerRequired
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return ModuleDetailsDTO{}, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	if _, err := qtx.GetModuleByIDForUpdate(ctx, db.GetModuleByIDForUpdateParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	}); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ModuleDetailsDTO{}, ErrNotFound
		}
		return ModuleDetailsDTO{}, err
	}

	for _, mgrID := range uniqueMgrIDs {
		mgr, err := qtx.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
			CompanyID: principal.CompanyID,
			ID:        mgrID,
		})
		if err != nil || mgr.Role != auth.RoleManager || !mgr.IsActive {
			return ModuleDetailsDTO{}, ErrManagerRequired
		}
	}

	if err := qtx.DeleteAllManagersForModule(ctx, db.DeleteAllManagersForModuleParams{
		CompanyID: principal.CompanyID,
		ModuleID:  moduleID,
	}); err != nil {
		return ModuleDetailsDTO{}, err
	}

	for _, mgrID := range uniqueMgrIDs {
		if _, err := qtx.AddModuleManager(ctx, db.AddModuleManagerParams{
			CompanyID: principal.CompanyID,
			ModuleID:  moduleID,
			ManagerID: mgrID,
		}); err != nil {
			return ModuleDetailsDTO{}, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return ModuleDetailsDTO{}, err
	}

	return s.GetModuleDetails(ctx, principal, moduleID)
}

func (s *Service) SetTechnicianAccess(ctx context.Context, principal auth.Principal, moduleID, technicianID pgtype.UUID, canView bool) (ModuleDetailsDTO, error) {
	if principal.Role != auth.RoleManager || !principal.CompanyID.Valid || !moduleID.Valid || !technicianID.Valid {
		return ModuleDetailsDTO{}, ErrForbidden
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return ModuleDetailsDTO{}, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	if _, err := qtx.GetModuleByIDForUpdate(ctx, db.GetModuleByIDForUpdateParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	}); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ModuleDetailsDTO{}, ErrNotFound
		}
		return ModuleDetailsDTO{}, err
	}

	tech, err := qtx.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
		CompanyID: principal.CompanyID,
		ID:        technicianID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ModuleDetailsDTO{}, ErrNotFound
		}
		return ModuleDetailsDTO{}, err
	}
	if tech.Role != auth.RoleTechnician {
		return ModuleDetailsDTO{}, ErrTargetNotTechnician
	}

	if _, err := qtx.UpsertModuleTechnician(ctx, db.UpsertModuleTechnicianParams{
		CompanyID:    principal.CompanyID,
		ModuleID:     moduleID,
		TechnicianID: technicianID,
		CanView:      canView,
	}); err != nil {
		return ModuleDetailsDTO{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return ModuleDetailsDTO{}, err
	}

	return s.GetModuleDetails(ctx, principal, moduleID)
}

func (s *Service) SetModuleClients(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, clientIDs []pgtype.UUID) (ModuleDetailsDTO, error) {
	if principal.Role != auth.RoleManager || !principal.CompanyID.Valid || !moduleID.Valid {
		return ModuleDetailsDTO{}, ErrForbidden
	}

	uniqueClientIDs := deduplicateUUIDs(clientIDs)

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return ModuleDetailsDTO{}, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	if _, err := qtx.GetModuleByIDForUpdate(ctx, db.GetModuleByIDForUpdateParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	}); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ModuleDetailsDTO{}, ErrNotFound
		}
		return ModuleDetailsDTO{}, err
	}

	for _, cID := range uniqueClientIDs {
		u, err := qtx.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
			CompanyID: principal.CompanyID,
			ID:        cID,
		})
		if err != nil || u.Role != auth.RoleClient {
			return ModuleDetailsDTO{}, ErrTargetNotClient
		}
	}

	existingClients, err := qtx.ListClientsByModule(ctx, db.ListClientsByModuleParams{
		CompanyID: principal.CompanyID,
		ModuleID:  moduleID,
	})
	if err != nil {
		return ModuleDetailsDTO{}, err
	}
	existingEmailPref := make(map[[16]byte]bool, len(existingClients))
	for _, ec := range existingClients {
		existingEmailPref[ec.ID.Bytes] = ec.OperationalEmailEnabled
	}

	if err := qtx.DeleteAllClientsForModule(ctx, db.DeleteAllClientsForModuleParams{
		CompanyID: principal.CompanyID,
		ModuleID:  moduleID,
	}); err != nil {
		return ModuleDetailsDTO{}, err
	}

	for _, cID := range uniqueClientIDs {
		emailPref, ok := existingEmailPref[cID.Bytes]
		if !ok {
			emailPref = true
		}
		if _, err := qtx.AddModuleClient(ctx, db.AddModuleClientParams{
			CompanyID:               principal.CompanyID,
			ModuleID:                moduleID,
			ClientID:                cID,
			OperationalEmailEnabled: emailPref,
		}); err != nil {
			return ModuleDetailsDTO{}, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return ModuleDetailsDTO{}, err
	}

	return s.GetModuleDetails(ctx, principal, moduleID)
}

func (s *Service) UpdateClientEmailPreference(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, enabled bool) (ModuleDetailsDTO, error) {
	if principal.Role != auth.RoleClient || !principal.CompanyID.Valid || !moduleID.Valid {
		return ModuleDetailsDTO{}, ErrForbidden
	}

	_, err := s.queries.UpdateModuleClientEmailPreference(ctx, db.UpdateModuleClientEmailPreferenceParams{
		CompanyID:               principal.CompanyID,
		ModuleID:                moduleID,
		ClientID:                principal.ID,
		OperationalEmailEnabled: enabled,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ModuleDetailsDTO{}, ErrNotFound
		}
		return ModuleDetailsDTO{}, err
	}

	return s.GetModuleDetails(ctx, principal, moduleID)
}

func (s *Service) DeleteModule(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) error {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return ErrInvalidInput
	}
	if !principal.IsActive {
		return ErrForbidden
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	mod, err := qtx.GetModuleByIDForUpdate(ctx, db.GetModuleByIDForUpdateParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}

	switch principal.Role {
	case auth.RoleManager:
		// Manager of the same company is authorized.
	case auth.RoleTechnician:
		// Must be the recorded installer technician.
		if mod.InstallerTechnicianID.Bytes != principal.ID.Bytes {
			return ErrForbidden
		}
		// AND must currently have active effective access (can_view = true).
		techAccess, err := qtx.GetModuleTechnicianAccess(ctx, db.GetModuleTechnicianAccessParams{
			CompanyID:    principal.CompanyID,
			ModuleID:     moduleID,
			TechnicianID: principal.ID,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrForbidden
			}
			return err
		}
		if !techAccess.CanView {
			return ErrForbidden
		}
	default:
		return ErrForbidden
	}

	history, err := qtx.CheckModuleOperationalHistory(ctx, moduleID)
	if err != nil {
		return err
	}

	if history.InspectionsCount > 0 ||
		history.MeasurementsCount > 0 ||
		history.AnomaliesCount > 0 ||
		history.CleaningsCount > 0 ||
		history.ReservoirReadingsCount > 0 ||
		history.IntervalChangeLogsCount > 0 ||
		history.PendingInspectionsCount > 0 ||
		history.PendingCleaningsCount > 0 {
		return ErrModuleHasOperationalHistory
	}

	if err := qtx.DeleteAllManagersForModule(ctx, db.DeleteAllManagersForModuleParams{
		CompanyID: principal.CompanyID,
		ModuleID:  moduleID,
	}); err != nil {
		return err
	}

	if err := qtx.DeleteAllTechniciansForModule(ctx, db.DeleteAllTechniciansForModuleParams{
		CompanyID: principal.CompanyID,
		ModuleID:  moduleID,
	}); err != nil {
		return err
	}

	if err := qtx.DeleteAllClientsForModule(ctx, db.DeleteAllClientsForModuleParams{
		CompanyID: principal.CompanyID,
		ModuleID:  moduleID,
	}); err != nil {
		return err
	}

	if err := qtx.DeleteAllNotificationsForModule(ctx, db.DeleteAllNotificationsForModuleParams{
		CompanyID: principal.CompanyID,
		ModuleID:  moduleID,
	}); err != nil {
		return err
	}

	if err := qtx.DeleteModule(ctx, db.DeleteModuleParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	}); err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (s *Service) resolveUserModuleRelationship(ctx context.Context, q *db.Queries, principal auth.Principal, moduleID, installerID pgtype.UUID) (string, *bool, error) {
	switch principal.Role {
	case auth.RoleManager:
		return RelManager, nil, nil
	case auth.RoleTechnician:
		if principal.ID.Bytes == moduleID.Bytes {
			return RelInstallerTechnician, nil, nil
		}
		access, err := q.GetModuleTechnicianAccess(ctx, db.GetModuleTechnicianAccessParams{
			CompanyID:    principal.CompanyID,
			ModuleID:     moduleID,
			TechnicianID: principal.ID,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return "", nil, ErrNotFound
			}
			return "", nil, err
		}
		if !access.CanView {
			return "", nil, ErrNotFound
		}
		if installerID.Bytes == principal.ID.Bytes {
			return RelInstallerTechnician, nil, nil
		}
		return RelSharedTechnician, nil, nil
	case auth.RoleClient:
		assignment, err := q.GetModuleClientAssignment(ctx, db.GetModuleClientAssignmentParams{
			CompanyID: principal.CompanyID,
			ModuleID:  moduleID,
			ClientID:  principal.ID,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return "", nil, ErrNotFound
			}
			return "", nil, err
		}
		enabled := assignment.OperationalEmailEnabled
		return RelAssignedClient, &enabled, nil
	default:
		return "", nil, ErrForbidden
	}
}

func permissionsForRelationship(rel string) ModulePermissionsDTO {
	switch rel {
	case RelManager:
		return ModulePermissionsDTO{
			CanEditGeometryAndLocation: true,
			CanEditSolarAngle:          true,
			CanEditInterval:            true,
			CanManageAccess:            true,
			CanDelete:                  true,
		}
	case RelInstallerTechnician:
		return ModulePermissionsDTO{
			CanEditGeometryAndLocation: true,
			CanEditSolarAngle:          true,
			CanEditInterval:            true,
			CanManageAccess:            false,
			CanDelete:                  true,
		}
	case RelSharedTechnician:
		return ModulePermissionsDTO{
			CanEditGeometryAndLocation: false,
			CanEditSolarAngle:          true,
			CanEditInterval:            false,
			CanManageAccess:            false,
			CanDelete:                  false,
		}
	case RelAssignedClient:
		return ModulePermissionsDTO{
			CanEditGeometryAndLocation: false,
			CanEditSolarAngle:          false,
			CanEditInterval:            true,
			CanManageAccess:            false,
			CanDelete:                  false,
		}
	default:
		return ModulePermissionsDTO{}
	}
}

func (s *Service) mapGetModuleRowToDTO(r db.GetModuleByIDRow, rel string, operationalEmailEnabled *bool) ModuleDTO {
	var configuredAtStr *string
	if r.ConfiguredAt != nil {
		str := r.ConfiguredAt.UTC().Format(time.RFC3339)
		configuredAtStr = &str
	}

	var configApplyErr *string
	if r.ConfigApplyError.Valid && strings.TrimSpace(r.ConfigApplyError.String) != "" {
		errStr := r.ConfigApplyError.String
		configApplyErr = &errStr
	}
	configSync := computeConfigurationSync(
		r.ConfigVersion,
		r.ConfigAppliedVersion,
		r.ConfigAppliedAt,
		configApplyErr,
	)

	return ModuleDTO{
		ID:                         auth.FormatUUID(r.ID),
		CompanyID:                  auth.FormatUUID(r.CompanyID),
		InstallerTechnicianID:      auth.FormatUUID(r.InstallerTechnicianID),
		InstallerName:              r.InstallerName,
		InstallerEmail:             r.InstallerEmail,
		Name:                       r.Name,
		MacAddress:                 strings.ToUpper(r.MacAddress),
		IsActive:                   r.IsActive,
		MonitoringStatus:           r.MonitoringStatus,
		PanelLengthCm:              numericToFloatPtr(r.PanelLengthCm),
		PanelWidthCm:               numericToFloatPtr(r.PanelWidthCm),
		PanelCount:                 pgInt4ToInt32Ptr(r.PanelCount),
		PanelSpacingCm:             numericToFloatPtr(r.PanelSpacingCm),
		Latitude:                   pgFloat8ToFloatPtr(r.Latitude),
		Longitude:                  pgFloat8ToFloatPtr(r.Longitude),
		ElevationM:                 pgFloat8ToFloatPtr(r.ElevationM),
		AzimuthDeg:                 numericToFloatPtr(r.AzimuthDeg),
		TiltDeg:                    numericToFloatPtr(r.TiltDeg),
		AzimuthSource:              pgTextToStringPtr(r.AzimuthSource),
		TiltSource:                 pgTextToStringPtr(r.TiltSource),
		MinimumSolarAngleDeg:       numericToFloatPtr(r.MinimumSolarAngleDeg),
		InspectionIntervalDays:     r.InspectionIntervalDays,
		ReservoirNominalCapacityMl: numericToFloatPtr(r.ReservoirNominalCapacityMl),
		ConfiguredAt:               configuredAtStr,
		CreatedAt:                  r.CreatedAt.UTC().Format(time.RFC3339),
		UpdatedAt:                  r.UpdatedAt.UTC().Format(time.RFC3339),
		UserRelationship:           rel,
		Permissions:                permissionsForRelationship(rel),
		OperationalEmailEnabled:    operationalEmailEnabled,
		ConfigurationSync:          configSync,
		PingIntervalSeconds:        s.PingIntervalSeconds(),
		OnlineWindowSeconds:        s.OnlineWindowSeconds(),
	}
}

func normalizeAndValidateMAC(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", ErrInvalidInput
	}
	hw, err := net.ParseMAC(trimmed)
	if err != nil || len(hw) != 6 {
		return "", ErrInvalidInput
	}
	return strings.ToLower(hw.String()), nil
}

func validateOptionalConfigFields(
	panelLengthCm *float64,
	panelWidthCm *float64,
	panelCount *int32,
	panelSpacingCm *float64,
	latitude *float64,
	longitude *float64,
	elevationM *float64,
	azimuthDeg *float64,
	tiltDeg *float64,
	azimuthSource *string,
	tiltSource *string,
	minSolarAngleDeg *float64,
	reservoirCapMl *float64,
) error {
	if panelLengthCm != nil && (!isFinite(*panelLengthCm) || *panelLengthCm <= 0) {
		return ErrInvalidInput
	}
	if panelWidthCm != nil && (!isFinite(*panelWidthCm) || *panelWidthCm <= 0) {
		return ErrInvalidInput
	}
	if panelCount != nil && *panelCount <= 0 {
		return ErrInvalidInput
	}
	if panelSpacingCm != nil && (!isFinite(*panelSpacingCm) || *panelSpacingCm < 0) {
		return ErrInvalidInput
	}
	if latitude != nil && (!isFinite(*latitude) || *latitude < -90 || *latitude > 90) {
		return ErrInvalidInput
	}
	if longitude != nil && (!isFinite(*longitude) || *longitude < -180 || *longitude > 180) {
		return ErrInvalidInput
	}
	if elevationM != nil && !isFinite(*elevationM) {
		return ErrInvalidInput
	}
	if azimuthDeg != nil && (!isFinite(*azimuthDeg) || *azimuthDeg < 0 || *azimuthDeg >= 360) {
		return ErrInvalidInput
	}
	if tiltDeg != nil && (!isFinite(*tiltDeg) || *tiltDeg < 0 || *tiltDeg > 90) {
		return ErrInvalidInput
	}
	if azimuthSource != nil {
		s := strings.TrimSpace(*azimuthSource)
		if s != SourceSensor && s != SourceManual {
			return ErrInvalidInput
		}
	}
	if tiltSource != nil {
		s := strings.TrimSpace(*tiltSource)
		if s != SourceSensor && s != SourceManual {
			return ErrInvalidInput
		}
	}
	if minSolarAngleDeg != nil && (!isFinite(*minSolarAngleDeg) || *minSolarAngleDeg < 0 || *minSolarAngleDeg > 90) {
		return ErrInvalidInput
	}
	if reservoirCapMl != nil && (!isFinite(*reservoirCapMl) || *reservoirCapMl <= 0) {
		return ErrInvalidInput
	}
	return nil
}

func isConfigurationComplete(
	panelLengthCm *float64,
	panelWidthCm *float64,
	panelCount *int32,
	panelSpacingCm *float64,
	latitude *float64,
	longitude *float64,
	elevationM *float64,
	azimuthDeg *float64,
	tiltDeg *float64,
	azimuthSource *string,
	tiltSource *string,
	minSolarAngleDeg *float64,
) bool {
	return panelLengthCm != nil &&
		panelWidthCm != nil &&
		panelCount != nil &&
		panelSpacingCm != nil &&
		latitude != nil &&
		longitude != nil &&
		elevationM != nil &&
		azimuthDeg != nil &&
		tiltDeg != nil &&
		azimuthSource != nil &&
		tiltSource != nil &&
		minSolarAngleDeg != nil
}

func isFinite(v float64) bool {
	return !math.IsNaN(v) && !math.IsInf(v, 0)
}

func floatPtr(v float64) *float64 {
	return &v
}

func floatPtrToNumeric(v *float64) pgtype.Numeric {
	if v == nil {
		return pgtype.Numeric{Valid: false}
	}
	var n pgtype.Numeric
	_ = n.Scan(strconv.FormatFloat(*v, 'f', 3, 64))
	return n
}

func numericToFloatPtr(n pgtype.Numeric) *float64 {
	if !n.Valid {
		return nil
	}
	f, err := n.Float64Value()
	if err != nil || !f.Valid {
		return nil
	}
	val := f.Float64
	return &val
}

func floatPtrToPgFloat8(v *float64) pgtype.Float8 {
	if v == nil {
		return pgtype.Float8{Valid: false}
	}
	return pgtype.Float8{Float64: *v, Valid: true}
}

func pgFloat8ToFloatPtr(f pgtype.Float8) *float64 {
	if !f.Valid {
		return nil
	}
	val := f.Float64
	return &val
}

func int32PtrToPgInt4(v *int32) pgtype.Int4 {
	if v == nil {
		return pgtype.Int4{Valid: false}
	}
	return pgtype.Int4{Int32: *v, Valid: true}
}

func pgInt4ToInt32Ptr(i pgtype.Int4) *int32 {
	if !i.Valid {
		return nil
	}
	val := i.Int32
	return &val
}

func stringPtrToPgText(v *string) pgtype.Text {
	if v == nil {
		return pgtype.Text{Valid: false}
	}
	return pgtype.Text{String: strings.TrimSpace(*v), Valid: true}
}

func pgTextToStringPtr(t pgtype.Text) *string {
	if !t.Valid {
		return nil
	}
	val := t.String
	return &val
}

func deduplicateUUIDs(in []pgtype.UUID) []pgtype.UUID {
	seen := make(map[[16]byte]struct{}, len(in))
	out := make([]pgtype.UUID, 0, len(in))
	for _, id := range in {
		if !id.Valid {
			continue
		}
		if _, ok := seen[id.Bytes]; ok {
			continue
		}
		seen[id.Bytes] = struct{}{}
		out = append(out, id)
	}
	return out
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
		out = append(out, MeasurementDTO{
			ID:               auth.FormatUUID(m.ID),
			ModuleID:         auth.FormatUUID(m.ModuleID),
			InspectionID:     auth.FormatUUID(m.InspectionID),
			SourceEventID:    auth.FormatUUID(m.SourceEventID),
			MeasuredAt:       m.MeasuredAt.UTC().Format(time.RFC3339),
			XPositionCM:      m.XPositionCm,
			BaselineTempC:    m.BaselineTemperatureC,
			MaxTempC:         m.MaxTemperatureC,
			HotspotDetected:  m.HotspotDetected,
			HotspotConfirmed: m.HotspotConfirmed,
			VoltageV:         m.VoltageV,
			CurrentA:         m.CurrentA,
			PowerW:           m.PowerW,
			ReceivedAt:       m.ReceivedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
}

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

func (s *Service) GetLatestThermalMap(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) (*ThermalMapDTO, error) {
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

	tm, err := s.queries.GetLatestThermalMapByModule(ctx, moduleID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}

	measurements, _ := s.queries.ListMeasurementsByModule(ctx, db.ListMeasurementsByModuleParams{
		ModuleID: moduleID,
		Limit:    100,
		Offset:   0,
	})
	bands := computeBandsFromMeasurements(tm.WidthPixels, measurements)

	return &ThermalMapDTO{
		ID:               auth.FormatUUID(tm.ID),
		InspectionID:     auth.FormatUUID(tm.InspectionID),
		WidthPixels:      tm.WidthPixels,
		HeightPixels:     tm.HeightPixels,
		TemperaturesC:    tm.TemperaturesC,
		AlgorithmVersion: tm.AlgorithmVersion,
		Bands:            bands,
		GeneratedAt:      tm.GeneratedAt.UTC().Format(time.RFC3339),
	}, nil
}

func computeBandsFromMeasurements(widthPixels int32, measurements []db.ListMeasurementsByModuleRow) []ThermalBandDTO {
	totalCols := int(widthPixels)
	if totalCols <= 0 {
		totalCols = 32
	}

	var totalLengthCm float64
	if totalCols <= 32 {
		totalLengthCm = 5.0
	} else {
		steps := float64(totalCols-32) / 13.0
		totalLengthCm = 5.0 + steps*2.0
	}

	numBands := int(math.Ceil(totalLengthCm / 5.0))
	if numBands < 1 {
		numBands = 1
	}

	bands := make([]ThermalBandDTO, 0, numBands)
	for b := 0; b < numBands; b++ {
		startX := float64(b) * 5.0
		endX := startX + 5.0
		if endX > totalLengthCm {
			endX = totalLengthCm
		}

		hasHotspot := false
		maxTemp := 0.0
		avgTemp := 0.0
		count := 0

		for _, m := range measurements {
			x, _ := strconv.ParseFloat(m.XPositionCm, 64)
			mT, _ := strconv.ParseFloat(m.MaxTemperatureC, 64)
			bT, _ := strconv.ParseFloat(m.BaselineTemperatureC, 64)
			if x >= startX && x < endX {
				if m.HotspotDetected {
					hasHotspot = true
				}
				if mT > maxTemp {
					maxTemp = mT
				}
				avgTemp += bT
				count++
			}
		}

		var maxTempPtr *float64
		var avgTempPtr *float64
		hasData := false

		if count > 0 {
			hasData = true
			a := math.Round((avgTemp/float64(count))*10) / 10
			m := math.Round(maxTemp*10) / 10
			avgTempPtr = &a
			maxTempPtr = &m
		}

		bands = append(bands, ThermalBandDTO{
			BandIndex:       b + 1,
			StartXCm:        math.Round(startX*10) / 10,
			EndXCm:          math.Round(endX*10) / 10,
			MaxTemperatureC: maxTempPtr,
			AvgTemperatureC: avgTempPtr,
			HasHotspot:      hasHotspot,
			HasData:         hasData,
		})
	}
	return bands
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

func newRandomUUID() pgtype.UUID {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return pgtype.UUID{Bytes: b, Valid: true}
}

func pgBoolToBoolPtr(b pgtype.Bool) *bool {
	if !b.Valid {
		return nil
	}
	val := b.Bool
	return &val
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

type RecordDevicePingInput struct {
	WaterAvailable      *bool `json:"water_available"`
	LimitsCheckPassed   *bool `json:"limits_check_passed"`
	ThermalSensorActive *bool `json:"thermal_sensor_active"`
}

func (s *Service) RecordDevicePing(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, input RecordDevicePingInput) (*DeviceStatusDTO, error) {
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
		ID:                  moduleID,
		LimitsCheckPassed:   limitsPassed,
		ThermalSensorActive: thermalActive,
	})

	// Only record reservoir ping if water_available was explicitly provided
	if input.WaterAvailable != nil {
		eventID := newRandomUUID()
		_, err = s.queries.RecordDeviceHandshakePing(ctx, db.RecordDeviceHandshakePingParams{
			ModuleID:       moduleID,
			SourceEventID:  eventID,
			WaterAvailable: pgtype.Bool{Bool: *input.WaterAvailable, Valid: true},
		})
		if err != nil {
			return nil, err
		}
	}

	return s.GetDeviceStatus(ctx, principal, moduleID)
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

type AcknowledgeDeviceConfigurationInput struct {
	ConfigVersion int32   `json:"config_version"`
	Applied       bool    `json:"applied"`
	Checksum      string  `json:"checksum"`
	Error         *string `json:"error,omitempty"`
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

func stitchThermalFrames(frames []IngestTelemetryInput) (int32, int32, []float64, []ThermalBandDTO) {
	if len(frames) == 0 {
		return 32, 24, make([]float64, 32*24), nil
	}

	sort.Slice(frames, func(i, j int) bool {
		return frames[i].XPositionCm < frames[j].XPositionCm
	})

	if len(frames) == 1 {
		f := frames[0]
		data := f.ThermalFrame
		maxT := f.MaxTemperatureC
		baseT := f.BaselineTemperatureC
		bands := []ThermalBandDTO{
			{
				BandIndex:       1,
				StartXCm:        0.0,
				EndXCm:          5.0,
				MaxTemperatureC: &maxT,
				AvgTemperatureC: &baseT,
				HasHotspot:      f.HotspotDetected,
				HasData:         true,
			},
		}
		return 32, 24, data, bands
	}

	colsPerStep := 13
	totalCols := 32 + (len(frames)-1)*colsPerStep
	totalRows := 24

	composite := make([]float64, totalCols*totalRows)
	weights := make([]float64, totalCols*totalRows)

	for frameIdx, f := range frames {
		frameData := f.ThermalFrame
		colOffset := frameIdx * colsPerStep

		for r := 0; r < totalRows; r++ {
			for c := 0; c < 32; c++ {
				targetCol := colOffset + c
				if targetCol >= totalCols {
					continue
				}
				targetIdx := r*totalCols + targetCol
				srcIdx := r*32 + c

				w := 1.0
				if c < 13 && frameIdx > 0 {
					w = float64(c+1) / 13.0
				} else if c >= (32-13) && frameIdx < len(frames)-1 {
					w = float64(32-c) / 13.0
				}
				if w < 0.05 {
					w = 0.05
				}

				composite[targetIdx] += frameData[srcIdx] * w
				weights[targetIdx] += w
			}
		}
	}

	for i := range composite {
		if weights[i] > 0 {
			composite[i] = math.Round((composite[i]/weights[i])*10.0) / 10.0
		}
	}

	minX := frames[0].XPositionCm
	maxX := frames[len(frames)-1].XPositionCm + 5.0
	totalLengthCm := maxX - minX
	if totalLengthCm <= 0 {
		totalLengthCm = 5.0
	}

	numBands := int(math.Ceil(totalLengthCm / 5.0))
	if numBands < 1 {
		numBands = 1
	}

	bands := make([]ThermalBandDTO, 0, numBands)
	for b := 0; b < numBands; b++ {
		startX := minX + float64(b)*5.0
		endX := startX + 5.0
		if endX > maxX {
			endX = maxX
		}

		maxTemp := 0.0
		sumTemp := 0.0
		count := 0
		hasHotspot := false

		for _, f := range frames {
			centerFrameX := f.XPositionCm + 2.5
			if centerFrameX >= startX && centerFrameX <= endX {
				if f.HotspotDetected {
					hasHotspot = true
				}
				if f.MaxTemperatureC > maxTemp {
					maxTemp = f.MaxTemperatureC
				}
			}
		}

		colStart := int(float64(b) * 5.0 / totalLengthCm * float64(totalCols))
		colEnd := int(float64(b+1) * 5.0 / totalLengthCm * float64(totalCols))
		if colEnd > totalCols {
			colEnd = totalCols
		}
		for r := 0; r < totalRows; r++ {
			for c := colStart; c < colEnd; c++ {
				t := composite[r*totalCols+c]
				if t > maxTemp {
					maxTemp = t
				}
				sumTemp += t
				count++
			}
		}

		var avgTempPtr *float64
		var maxTempPtr *float64
		hasData := false

		if count > 0 {
			hasData = true
			a := math.Round((sumTemp/float64(count))*10.0) / 10.0
			m := math.Round(maxTemp*10.0) / 10.0
			avgTempPtr = &a
			maxTempPtr = &m
		}

		bands = append(bands, ThermalBandDTO{
			BandIndex:       b + 1,
			StartXCm:        math.Round(startX*10.0) / 10.0,
			EndXCm:          math.Round(endX*10.0) / 10.0,
			MaxTemperatureC: maxTempPtr,
			AvgTemperatureC: avgTempPtr,
			HasHotspot:      hasHotspot,
			HasData:         hasData,
		})
	}

	return int32(totalCols), int32(totalRows), composite, bands
}

func (s *Service) IngestTelemetry(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, input IngestTelemetryInput) (*MeasurementDTO, error) {
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

	framesToProcess := input.Batch
	if len(framesToProcess) == 0 {
		framesToProcess = []IngestTelemetryInput{input}
	}

	for _, f := range framesToProcess {
		if len(f.ThermalFrame) != 32*24 {
			return nil, ErrInvalidInput
		}
	}

	now := time.Now().UTC()
	measuredAt := now
	if framesToProcess[0].MeasuredAt != nil && !framesToProcess[0].MeasuredAt.IsZero() {
		measuredAt = framesToProcess[0].MeasuredAt.UTC()
	}

	inspType := "scheduled"
	if input.InspectionType != nil && *input.InspectionType != "" {
		inspType = *input.InspectionType
	}
	schedFor := measuredAt
	if input.InspectionScheduledFor != nil {
		schedFor = *input.InspectionScheduledFor
	}
	startedAt := measuredAt
	if input.InspectionStartedAt != nil {
		startedAt = *input.InspectionStartedAt
	}

	// 1. Create inspection session with real timestamps
	inspEventID := newRandomUUID()
	insp, err := s.queries.CreateInspection(ctx, db.CreateInspectionParams{
		ModuleID:      moduleID,
		SourceEventID: inspEventID,
		Type:          inspType,
		ScheduledFor:  schedFor,
		StartedAt:     &startedAt,
		FinishedAt:    &now,
		Status:        "completed",
	})
	if err != nil {
		return nil, err
	}

	var primaryMeasRow *db.CreateMeasurementRow

	// 2. Ingest each measurement frame with authentic sensor data
	for _, f := range framesToProcess {
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

		measEventID := newRandomUUID()
		meas, err := s.queries.CreateMeasurement(ctx, db.CreateMeasurementParams{
			ModuleID:             moduleID,
			InspectionID:         insp.ID,
			SourceEventID:        measEventID,
			MeasuredAt:           fMeasuredAt,
			XPositionCm:          floatPtrToNumeric(&f.XPositionCm),
			BaselineTemperatureC: floatPtrToNumeric(&f.BaselineTemperatureC),
			MaxTemperatureC:      floatPtrToNumeric(&f.MaxTemperatureC),
			HotspotDetected:      f.HotspotDetected,
			HotspotConfirmed:     f.HotspotConfirmed,
			VoltageV:             floatPtrToNumeric(&f.VoltageV),
			CurrentA:             floatPtrToNumeric(&f.CurrentA),
			PowerW:               floatPtrToNumeric(&powerW),
			ThermalFrame:         frameBytes,
		})
		if err != nil {
			return nil, err
		}

		if primaryMeasRow == nil || f.HotspotDetected {
			primaryMeasRow = &meas
		}

		// If hotspot detected, register real anomaly event
		if f.HotspotDetected {
			anomEventID := newRandomUUID()
			_, _ = s.queries.CreateAnomalyEvent(ctx, db.CreateAnomalyEventParams{
				ModuleID:              moduleID,
				OriginMeasurementID:   meas.ID,
				SourceEventID:         anomEventID,
				XPositionCm:           floatPtrToNumeric(&f.XPositionCm),
				DetectedAt:            fMeasuredAt,
				Status:                "open",
				ActuatedAttemptsCount: 0,
				RetryPending:          false,
			})
		}
	}

	// 3. Run multi-frame stitching with authentic overlap-60 blending
	totalCols, totalRows, compositeData, _ := stitchThermalFrames(framesToProcess)
	compositeBytes, _ := json.Marshal(compositeData)
	_, _ = s.queries.CreateInspectionThermalMap(ctx, db.CreateInspectionThermalMapParams{
		InspectionID:     insp.ID,
		WidthPixels:      totalCols,
		HeightPixels:     totalRows,
		TemperaturesC:    compositeBytes,
		AlgorithmVersion: "overlap-60-blend-v1.0",
	})

	// 4. Update device online timestamp (without overwriting water_available!)
	_, _ = s.queries.UpdateModuleDeviceHealth(ctx, db.UpdateModuleDeviceHealthParams{
		ID: moduleID,
	})
	if input.WaterAvailable != nil {
		pingEventID := newRandomUUID()
		_, _ = s.queries.RecordDeviceHandshakePing(ctx, db.RecordDeviceHandshakePingParams{
			ModuleID:       moduleID,
			SourceEventID:  pingEventID,
			WaterAvailable: pgtype.Bool{Bool: *input.WaterAvailable, Valid: true},
		})
	}

	meas := primaryMeasRow
	return &MeasurementDTO{
		ID:               auth.FormatUUID(meas.ID),
		ModuleID:         auth.FormatUUID(meas.ModuleID),
		InspectionID:     auth.FormatUUID(meas.InspectionID),
		SourceEventID:    auth.FormatUUID(meas.SourceEventID),
		MeasuredAt:       meas.MeasuredAt.UTC().Format(time.RFC3339),
		XPositionCM:      meas.XPositionCm,
		BaselineTempC:    meas.BaselineTemperatureC,
		MaxTempC:         meas.MaxTemperatureC,
		HotspotDetected:  meas.HotspotDetected,
		HotspotConfirmed: meas.HotspotConfirmed,
		VoltageV:         meas.VoltageV,
		CurrentA:         meas.CurrentA,
		PowerW:           meas.PowerW,
		ReceivedAt:       meas.ReceivedAt.UTC().Format(time.RFC3339),
	}, nil
}

type IngestCleaningInput struct {
	AnomalyEventID         *string  `json:"anomaly_event_id"`
	TargetXPositionCm      float64  `json:"target_x_position_cm"`
	PumpActuated           bool     `json:"pump_actuated"`
	AttemptNumber          *int     `json:"attempt_number"`
	DurationSeconds        float64  `json:"duration_seconds"`
	EstimatedWaterVolumeMl float64  `json:"estimated_water_volume_ml"`
	Status                 string   `json:"status"`
	FailureReason          *string  `json:"failure_reason"`
	PostCleaningResult     string   `json:"post_cleaning_result"`
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

		xPosRounded := math.Round(xPos*10.0) / 10.0
		metaText := "Delta: +" + strconv.FormatFloat(delta, 'f', 1, 64) + "°C vs Baseline"
		desc := "Thermal anomaly confirmed at coordinate X=" + strconv.FormatFloat(xPosRounded, 'f', 1, 64) + " cm. Wash attempts registered: " + strconv.Itoa(int(a.ActuatedAttemptsCount)) + " of 3."

		alerts = append(alerts, AlertDTO{
			ID:          auth.FormatUUID(a.ID),
			ModuleID:    auth.FormatUUID(a.ModuleID),
			ModuleName:  a.ModuleName,
			Severity:    severity,
			Type:        "hotspot_unresolved",
			Title:       "Hotspot Unresolved: " + a.ModuleName,
			Description: desc,
			MetaText:    metaText,
			XPositionCm: &xPosRounded,
			DeltaC:      &delta,
			CreatedAt:   a.DetectedAt.UTC().Format(time.RFC3339),
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
