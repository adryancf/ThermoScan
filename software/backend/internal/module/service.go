package module

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math"
	"net"
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
	ErrInvalidInput          = errors.New("invalid module input")
	ErrNotFound              = errors.New("module not found")
	ErrForbidden             = errors.New("insufficient permissions for this module operation")
	ErrMACConflict           = errors.New("a module with this MAC address is already registered")
	ErrManagerRequired             = errors.New("at least one active responsible manager from the same company is required")
	ErrTechnicianHasNoActiveManagers = errors.New("technician has no active responsible managers")
	ErrTargetNotTechnician         = errors.New("target user is not a technician in this company")
	ErrTargetNotClient             = errors.New("one or more target users are not active clients in this company")
	ErrModuleHasOperationalHistory = errors.New("module contains operational history or pending operations and cannot be deleted; deactivate it instead")
)

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

type Service struct {
	database auth.DB
	queries  *db.Queries
}

func NewService(database auth.DB) *Service {
	return &Service{
		database: database,
		queries:  db.New(database),
	}
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
			out = append(out, mapGetModuleRowToDTO(db.GetModuleByIDRow(r), RelManager, nil))
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
			out = append(out, mapGetModuleRowToDTO(db.GetModuleByIDRow(r), rel, nil))
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
			}
			out = append(out, mapGetModuleRowToDTO(baseRow, RelAssignedClient, &emailEnabled))
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

	details := ModuleDetailsDTO{
		Module:              mapGetModuleRowToDTO(row, rel, emailEnabled),
		ResponsibleManagers: respMgrs,
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

func mapGetModuleRowToDTO(r db.GetModuleByIDRow, rel string, operationalEmailEnabled *bool) ModuleDTO {
	var configuredAtStr *string
	if r.ConfiguredAt != nil {
		s := r.ConfiguredAt.UTC().Format(time.RFC3339)
		configuredAtStr = &s
	}

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
	BandIndex       int     `json:"band_index"`
	StartXCm        float64 `json:"start_x_cm"`
	EndXCm          float64 `json:"end_x_cm"`
	MaxTemperatureC float64 `json:"max_temperature_c"`
	AvgTemperatureC float64 `json:"avg_temperature_c"`
	HasHotspot      bool    `json:"has_hotspot"`
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

		if count > 0 {
			avgTemp = math.Round((avgTemp/float64(count))*10) / 10
		} else {
			avgTemp = 35.0
			if maxTemp == 0.0 {
				maxTemp = 36.5
			}
		}

		bands = append(bands, ThermalBandDTO{
			BandIndex:       b + 1,
			StartXCm:        math.Round(startX*10) / 10,
			EndXCm:          math.Round(endX*10) / 10,
			MaxTemperatureC: math.Round(maxTemp*10) / 10,
			AvgTemperatureC: avgTemp,
			HasHotspot:      hasHotspot,
		})
	}
	return bands
}

type DeviceStatusDTO struct {
	ModuleID            string  `json:"module_id"`
	MACAddress          string  `json:"mac_address"`
	MonitoringStatus    string  `json:"monitoring_status"`
	IsConfigured        bool    `json:"is_configured"`
	ConfiguredAt        *string `json:"configured_at,omitempty"`
	IsOnline            bool    `json:"is_online"`
	LastSeenAt          *string `json:"last_seen_at,omitempty"`
	WaterAvailable      *bool   `json:"water_available,omitempty"`
	WaterStatus         string  `json:"water_status"`
	LimitsCheckPassed   bool    `json:"limits_check_passed"`
	ThermalSensorActive bool    `json:"thermal_sensor_active"`
	LatestMeasurementAt *string `json:"latest_measurement_at,omitempty"`
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

	dto := &DeviceStatusDTO{
		ModuleID:         auth.FormatUUID(row.ID),
		MACAddress:       row.MacAddress,
		MonitoringStatus: row.MonitoringStatus,
		IsConfigured:     isConfigured,
		ConfiguredAt:     configuredAtStr,
		WaterStatus:      "unknown",
	}

	resReading, err := s.queries.GetLatestReservoirReadingByModule(ctx, moduleID)
	if err == nil {
		lastSeen := resReading.MeasuredAt.UTC().Format(time.RFC3339)
		dto.LastSeenAt = &lastSeen
		dto.WaterAvailable = pgBoolToBoolPtr(resReading.WaterAvailable)
		if resReading.WaterAvailable.Valid && resReading.WaterAvailable.Bool {
			dto.WaterStatus = "available"
		} else if resReading.WaterAvailable.Valid && !resReading.WaterAvailable.Bool {
			dto.WaterStatus = "insufficient"
		}
		if time.Since(resReading.MeasuredAt) < time.Hour {
			dto.IsOnline = true
			dto.LimitsCheckPassed = true
			dto.ThermalSensorActive = true
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
		if dto.LastSeenAt == nil || m.MeasuredAt.After(resReading.MeasuredAt) {
			dto.LastSeenAt = &mTime
			if time.Since(m.MeasuredAt) < time.Hour {
				dto.IsOnline = true
				dto.LimitsCheckPassed = true
				dto.ThermalSensorActive = true
			}
		}
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

	waterAvail := true
	if input.WaterAvailable != nil {
		waterAvail = *input.WaterAvailable
	}

	eventID := newRandomUUID()
	_, err = s.queries.RecordDeviceHandshakePing(ctx, db.RecordDeviceHandshakePingParams{
		ModuleID:       moduleID,
		SourceEventID:  eventID,
		WaterAvailable: pgtype.Bool{Bool: waterAvail, Valid: true},
	})
	if err != nil {
		return nil, err
	}

	dto, err := s.GetDeviceStatus(ctx, principal, moduleID)
	if err != nil {
		return nil, err
	}
	if input.LimitsCheckPassed != nil {
		dto.LimitsCheckPassed = *input.LimitsCheckPassed
	}
	if input.ThermalSensorActive != nil {
		dto.ThermalSensorActive = *input.ThermalSensorActive
	}
	return dto, nil
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

	// Generate high-entropy device secret
	var randBytes [16]byte
	_, _ = rand.Read(randBytes[:])
	deviceToken := "dev_sec_" + hex.EncodeToString(randBytes[:])

	updated, err := s.queries.SetModuleDeviceToken(ctx, db.SetModuleDeviceTokenParams{
		ID:          mod.ID,
		DeviceToken: pgtype.Text{String: deviceToken, Valid: true},
	})
	if err != nil {
		return nil, err
	}

	waterAvail := true
	if input.WaterAvailable != nil {
		waterAvail = *input.WaterAvailable
	}

	// Record initial handshake ping
	eventID := newRandomUUID()
	_, _ = s.queries.RecordDeviceHandshakePing(ctx, db.RecordDeviceHandshakePingParams{
		ModuleID:       mod.ID,
		SourceEventID:  eventID,
		WaterAvailable: pgtype.Bool{Bool: waterAvail, Valid: true},
	})

	return &ClaimDeviceDTO{
		ModuleID:               auth.FormatUUID(updated.ID),
		DeviceToken:            deviceToken,
		Status:                 "claimed",
		InspectionIntervalDays: updated.InspectionIntervalDays,
		Message:                "Device successfully claimed and paired",
	}, nil
}

type IngestTelemetryInput struct {
	MeasuredAt           *time.Time             `json:"measured_at"`
	XPositionCm          float64                `json:"x_position_cm"`
	BaselineTemperatureC float64                `json:"baseline_temperature_c"`
	MaxTemperatureC      float64                `json:"max_temperature_c"`
	HotspotDetected      bool                   `json:"hotspot_detected"`
	HotspotConfirmed     bool                   `json:"hotspot_confirmed"`
	VoltageV             float64                `json:"voltage_v"`
	CurrentA             float64                `json:"current_a"`
	PowerW               *float64               `json:"power_w"`
	ThermalFrame         []float64              `json:"thermal_frame"`
	ThermalMap           []float64              `json:"thermal_map"`
	WidthPixels          int                    `json:"width_pixels"`
	HeightPixels         int                    `json:"height_pixels"`
	Batch                []IngestTelemetryInput `json:"batch"`
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
		if len(data) < 32*24 {
			data = make([]float64, 32*24)
			for i := range data {
				data[i] = f.BaselineTemperatureC
			}
			if f.HotspotDetected {
				data[12*32+16] = f.MaxTemperatureC
				data[12*32+17] = f.MaxTemperatureC - 1.5
				data[13*32+16] = f.MaxTemperatureC - 2.0
			}
		}
		bands := []ThermalBandDTO{
			{
				BandIndex:       1,
				StartXCm:        0.0,
				EndXCm:          5.0,
				MaxTemperatureC: f.MaxTemperatureC,
				AvgTemperatureC: f.BaselineTemperatureC,
				HasHotspot:      f.HotspotDetected,
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
		if len(frameData) < 32*24 {
			frameData = make([]float64, 32*24)
			for i := range frameData {
				frameData[i] = f.BaselineTemperatureC
			}
			if f.HotspotDetected {
				frameData[12*32+16] = f.MaxTemperatureC
				frameData[12*32+17] = f.MaxTemperatureC - 1.5
				frameData[13*32+16] = f.MaxTemperatureC - 2.0
			}
		}

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

		avgTemp := 0.0
		if count > 0 {
			avgTemp = math.Round((sumTemp/float64(count))*10.0) / 10.0
		} else {
			avgTemp = maxTemp
		}

		bands = append(bands, ThermalBandDTO{
			BandIndex:       b + 1,
			StartXCm:        math.Round(startX*10.0) / 10.0,
			EndXCm:          math.Round(endX*10.0) / 10.0,
			MaxTemperatureC: math.Round(maxTemp*10.0) / 10.0,
			AvgTemperatureC: avgTemp,
			HasHotspot:      hasHotspot,
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

	now := time.Now().UTC()
	measuredAt := now
	if framesToProcess[0].MeasuredAt != nil && !framesToProcess[0].MeasuredAt.IsZero() {
		measuredAt = framesToProcess[0].MeasuredAt.UTC()
	}

	// 1. Create inspection session
	inspEventID := newRandomUUID()
	insp, err := s.queries.CreateInspection(ctx, db.CreateInspectionParams{
		ModuleID:      moduleID,
		SourceEventID: inspEventID,
		Type:          "scheduled",
		ScheduledFor:  measuredAt.Add(-5 * time.Minute),
		StartedAt:     &measuredAt,
		FinishedAt:    &now,
		Status:        "completed",
	})
	if err != nil {
		return nil, err
	}

	var primaryMeasRow *db.CreateMeasurementRow

	// 2. Ingest each measurement frame
	for _, f := range framesToProcess {
		fMeasuredAt := now
		if f.MeasuredAt != nil && !f.MeasuredAt.IsZero() {
			fMeasuredAt = f.MeasuredAt.UTC()
		}

		powerW := f.VoltageV * f.CurrentA
		if f.PowerW != nil && *f.PowerW > 0 {
			powerW = *f.PowerW
		}

		frameFloats := f.ThermalFrame
		if len(frameFloats) < 32*24 {
			frameFloats = make([]float64, 32*24)
			for i := range frameFloats {
				frameFloats[i] = f.BaselineTemperatureC
			}
			if f.HotspotDetected {
				frameFloats[12*32+16] = f.MaxTemperatureC
				frameFloats[12*32+17] = f.MaxTemperatureC - 1.2
				frameFloats[13*32+16] = f.MaxTemperatureC - 2.0
			}
		}
		frameBytes, err := json.Marshal(frameFloats)
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

		// If hotspot detected, create anomaly event
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

	// 3. Run multi-frame stitching with 60% overlap algorithm & 5cm bands
	totalCols, totalRows, compositeData, _ := stitchThermalFrames(framesToProcess)
	compositeBytes, _ := json.Marshal(compositeData)
	_, _ = s.queries.CreateInspectionThermalMap(ctx, db.CreateInspectionThermalMapParams{
		InspectionID:     insp.ID,
		WidthPixels:      totalCols,
		HeightPixels:     totalRows,
		TemperaturesC:    compositeBytes,
		AlgorithmVersion: "overlap-60-blend-v1.0",
	})

	// 4. Record device ping
	pingEventID := newRandomUUID()
	_, _ = s.queries.RecordDeviceHandshakePing(ctx, db.RecordDeviceHandshakePingParams{
		ModuleID:       moduleID,
		SourceEventID:  pingEventID,
		WaterAvailable: pgtype.Bool{Bool: true, Valid: true},
	})

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

	// 1. Ensure an inspection & measurement exists
	measurements, err := s.queries.ListMeasurementsByModule(ctx, db.ListMeasurementsByModuleParams{
		ModuleID: moduleID,
		Limit:    1,
		Offset:   0,
	})
	var originMeasID pgtype.UUID
	now := time.Now().UTC()
	if err == nil && len(measurements) > 0 {
		originMeasID = measurements[0].ID
	} else {
		// Create placeholder inspection & measurement
		inspEventID := newRandomUUID()
		insp, err := s.queries.CreateInspection(ctx, db.CreateInspectionParams{
			ModuleID:      moduleID,
			SourceEventID: inspEventID,
			Type:          "scheduled",
			ScheduledFor:  now.Add(-10 * time.Minute),
			StartedAt:     &now,
			FinishedAt:    &now,
			Status:        "completed",
		})
		if err != nil {
			return nil, err
		}
		frameBytes, _ := json.Marshal([]float64{35.0, 36.0, 48.0})
		measEventID := newRandomUUID()
		meas, err := s.queries.CreateMeasurement(ctx, db.CreateMeasurementParams{
			ModuleID:             moduleID,
			InspectionID:         insp.ID,
			SourceEventID:        measEventID,
			MeasuredAt:           now,
			XPositionCm:          floatPtrToNumeric(&input.TargetXPositionCm),
			BaselineTemperatureC: floatPtrToNumeric(floatPtr(36.0)),
			MaxTemperatureC:      floatPtrToNumeric(floatPtr(48.5)),
			HotspotDetected:      true,
			HotspotConfirmed:     true,
			VoltageV:             floatPtrToNumeric(floatPtr(18.0)),
			CurrentA:             floatPtrToNumeric(floatPtr(4.0)),
			PowerW:               floatPtrToNumeric(floatPtr(72.0)),
			ThermalFrame:         frameBytes,
		})
		if err != nil {
			return nil, err
		}
		originMeasID = meas.ID
	}

	// 2. Create anomaly event
	anomEventID := newRandomUUID()
	anom, err := s.queries.CreateAnomalyEvent(ctx, db.CreateAnomalyEventParams{
		ModuleID:              moduleID,
		OriginMeasurementID:   originMeasID,
		SourceEventID:         anomEventID,
		XPositionCm:           floatPtrToNumeric(&input.TargetXPositionCm),
		DetectedAt:            now.Add(-2 * time.Minute),
		Status:                "open",
		ActuatedAttemptsCount: 1,
		RetryPending:          false,
	})
	if err != nil {
		return nil, err
	}

	// 3. Create cleaning operation
	status := input.Status
	if status == "" {
		status = "completed"
	}
	postRes := input.PostCleaningResult
	if postRes == "" {
		postRes = "resolved"
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
		s := now.Add(-time.Duration(input.DurationSeconds) * time.Second)
		e := now
		startedAtPtr = &s
		endedAtPtr = &e
	}

	cleanEventID := newRandomUUID()
	var failReason pgtype.Text
	if input.FailureReason != nil {
		failReason = pgtype.Text{String: *input.FailureReason, Valid: true}
	} else if status == "refused" || status == "failed" {
		failReason = pgtype.Text{String: "Water reservoir depleted", Valid: true}
	}

	clean, err := s.queries.CreateCleaningOperation(ctx, db.CreateCleaningOperationParams{
		ModuleID:               moduleID,
		AnomalyEventID:         anom.ID,
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
