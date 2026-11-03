package module

import (
	"context"
	"errors"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

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
