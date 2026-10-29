package module

import (
	"context"
	"errors"
	"math"
	"net"
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
	ErrManagerRequired       = errors.New("at least one active responsible manager from the same company is required")
	ErrTargetNotTechnician   = errors.New("target user is not a technician in this company")
	ErrTargetNotClient       = errors.New("one or more target users are not active clients in this company")
)

type ModulePermissionsDTO struct {
	CanEditGeometryAndLocation bool `json:"can_edit_geometry_and_location"`
	CanEditSolarAngle          bool `json:"can_edit_solar_angle"`
	CanEditInterval            bool `json:"can_edit_interval"`
	CanManageAccess            bool `json:"can_manage_access"`
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

	uniqueMgrIDs := deduplicateUUIDs(in.ManagerIDs)
	if len(uniqueMgrIDs) == 0 {
		return ModuleDetailsDTO{}, ErrManagerRequired
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

	// Verify all manager IDs are active managers in the same company
	for _, mgrID := range uniqueMgrIDs {
		mgr, err := qtx.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
			CompanyID: in.CompanyID,
			ID:        mgrID,
		})
		if err != nil || mgr.Role != auth.RoleManager || !mgr.IsActive {
			return ModuleDetailsDTO{}, ErrManagerRequired
		}
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

	for _, mgrID := range uniqueMgrIDs {
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

func (s *Service) resolveUserModuleRelationship(ctx context.Context, q *db.Queries, principal auth.Principal, moduleID, installerID pgtype.UUID) (string, *bool, error) {
	switch principal.Role {
	case auth.RoleManager:
		return RelManager, nil, nil
	case auth.RoleTechnician:
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
		}
	case RelInstallerTechnician:
		return ModulePermissionsDTO{
			CanEditGeometryAndLocation: true,
			CanEditSolarAngle:          true,
			CanEditInterval:            true,
			CanManageAccess:            false,
		}
	case RelSharedTechnician:
		return ModulePermissionsDTO{
			CanEditGeometryAndLocation: false,
			CanEditSolarAngle:          true,
			CanEditInterval:            false,
			CanManageAccess:            false,
		}
	case RelAssignedClient:
		return ModulePermissionsDTO{
			CanEditGeometryAndLocation: false,
			CanEditSolarAngle:          false,
			CanEditInterval:            true,
			CanManageAccess:            false,
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
