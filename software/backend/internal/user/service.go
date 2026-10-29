package user

import (
	"context"
	"errors"
	"strings"
	"time"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
)

var (
	ErrInvalidInput          = errors.New("invalid input")
	ErrNotFound              = errors.New("user not found")
	ErrEmailConflict         = errors.New("email is already in use")
	ErrInvalidManagerLink    = errors.New("technician must have at least one active manager from the same company")
	ErrCannotModifyManager        = errors.New("managers cannot deactivate or reset passwords of other managers")
	ErrTargetNotTechnician        = errors.New("target user is not a technician")
	ErrUserHasOperationalHistory = errors.New("user has associated operational history or installed modules and cannot be deleted; deactivate the account instead")
)

type ManagerSummaryDTO struct {
	ID               string `json:"id"`
	Name             string `json:"name"`
	Email            string `json:"email"`
	IsActive         bool   `json:"is_active"`
	IsDefaultManager bool   `json:"is_default_manager"`
	AssignedAt       string `json:"assigned_at"`
}

type UserDetailsDTO struct {
	User     auth.UserDTO        `json:"user"`
	Managers []ManagerSummaryDTO `json:"managers,omitempty"`
}

type CreateUserInput struct {
	CompanyID  pgtype.UUID
	Name       string
	Email      string
	Role       string
	ManagerIDs []pgtype.UUID
}

type CreateUserResult struct {
	User              auth.UserDTO `json:"user"`
	ManagerIDs        []string     `json:"manager_ids,omitempty"`
	TemporaryPassword string       `json:"temporary_password"`
}

type ResetPasswordResult struct {
	User              auth.UserDTO `json:"user"`
	TemporaryPassword string       `json:"temporary_password"`
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

func (s *Service) CreateUser(ctx context.Context, in CreateUserInput) (CreateUserResult, error) {
	if !in.CompanyID.Valid {
		return CreateUserResult{}, ErrInvalidInput
	}

	name := strings.TrimSpace(in.Name)
	email := auth.NormalizeAndValidateEmail(in.Email)
	role := strings.TrimSpace(in.Role)

	if name == "" || email == "" {
		return CreateUserResult{}, ErrInvalidInput
	}

	switch role {
	case auth.RoleManager, auth.RoleClient:
		if len(in.ManagerIDs) > 0 {
			return CreateUserResult{}, ErrInvalidInput
		}
	case auth.RoleTechnician:
		if len(in.ManagerIDs) == 0 {
			return CreateUserResult{}, ErrInvalidManagerLink
		}
	default:
		return CreateUserResult{}, ErrInvalidInput
	}

	uniqueMgrIDs := deduplicateUUIDs(in.ManagerIDs)
	if role == auth.RoleTechnician && len(uniqueMgrIDs) == 0 {
		return CreateUserResult{}, ErrInvalidManagerLink
	}

	tempPass, err := auth.GenerateTemporaryPassword()
	if err != nil {
		return CreateUserResult{}, err
	}
	passHash, err := auth.HashPassword(tempPass)
	if err != nil {
		return CreateUserResult{}, err
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return CreateUserResult{}, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	if role == auth.RoleTechnician {
		for _, mgrID := range uniqueMgrIDs {
			mgr, err := qtx.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
				CompanyID: in.CompanyID,
				ID:        mgrID,
			})
			if err != nil || mgr.Role != auth.RoleManager || !mgr.IsActive {
				return CreateUserResult{}, ErrInvalidManagerLink
			}
		}
	}

	created, err := qtx.CreateUser(ctx, db.CreateUserParams{
		CompanyID:          in.CompanyID,
		Name:               name,
		Email:              email,
		PasswordHash:       passHash,
		Role:               role,
		IsActive:           true,
		IsDefaultManager:   false,
		MustChangePassword: true,
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return CreateUserResult{}, ErrEmailConflict
		}
		return CreateUserResult{}, err
	}

	var assignedMgrIDs []string
	if role == auth.RoleTechnician {
		assignedMgrIDs = make([]string, 0, len(uniqueMgrIDs))
		for _, mgrID := range uniqueMgrIDs {
			_, err := qtx.AddTechnicianManager(ctx, db.AddTechnicianManagerParams{
				CompanyID:    in.CompanyID,
				TechnicianID: created.ID,
				ManagerID:    mgrID,
			})
			if err != nil {
				return CreateUserResult{}, err
			}
			assignedMgrIDs = append(assignedMgrIDs, auth.FormatUUID(mgrID))
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return CreateUserResult{}, err
	}

	compIDStr := auth.FormatUUID(in.CompanyID)
	return CreateUserResult{
		User: auth.UserDTO{
			ID:                 auth.FormatUUID(created.ID),
			CompanyID:          &compIDStr,
			Name:               created.Name,
			Email:              created.Email,
			Role:               created.Role,
			IsActive:           created.IsActive,
			IsDefaultManager:   created.IsDefaultManager,
			MustChangePassword: created.MustChangePassword,
			CreatedAt:          created.CreatedAt.UTC().Format(time.RFC3339),
			UpdatedAt:          created.UpdatedAt.UTC().Format(time.RFC3339),
		},
		ManagerIDs:        assignedMgrIDs,
		TemporaryPassword: tempPass,
	}, nil
}

func (s *Service) ListUsers(ctx context.Context, companyID pgtype.UUID, roleFilter string, limit, offset int32) ([]auth.UserDTO, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	var roleArg pgtype.Text
	trimmedRole := strings.TrimSpace(roleFilter)
	if trimmedRole != "" {
		switch trimmedRole {
		case auth.RoleManager, auth.RoleTechnician, auth.RoleClient:
			roleArg = pgtype.Text{String: trimmedRole, Valid: true}
		default:
			return nil, ErrInvalidInput
		}
	}

	rows, err := s.queries.ListUsersByCompany(ctx, db.ListUsersByCompanyParams{
		CompanyID: companyID,
		Limit:     limit,
		Offset:    offset,
		Role:      roleArg,
	})
	if err != nil {
		return nil, err
	}

	compIDStr := auth.FormatUUID(companyID)
	out := make([]auth.UserDTO, 0, len(rows))
	for _, r := range rows {
		cID := compIDStr
		out = append(out, auth.UserDTO{
			ID:                 auth.FormatUUID(r.ID),
			CompanyID:          &cID,
			Name:               r.Name,
			Email:              r.Email,
			Role:               r.Role,
			IsActive:           r.IsActive,
			IsDefaultManager:   r.IsDefaultManager,
			MustChangePassword: r.MustChangePassword,
			CreatedAt:          r.CreatedAt.UTC().Format(time.RFC3339),
			UpdatedAt:          r.UpdatedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
}

func (s *Service) GetUser(ctx context.Context, companyID, userID pgtype.UUID) (UserDetailsDTO, error) {
	u, err := s.queries.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
		CompanyID: companyID,
		ID:        userID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return UserDetailsDTO{}, ErrNotFound
		}
		return UserDetailsDTO{}, err
	}

	compIDStr := auth.FormatUUID(companyID)
	res := UserDetailsDTO{
		User: auth.UserDTO{
			ID:                 auth.FormatUUID(u.ID),
			CompanyID:          &compIDStr,
			Name:               u.Name,
			Email:              u.Email,
			Role:               u.Role,
			IsActive:           u.IsActive,
			IsDefaultManager:   u.IsDefaultManager,
			MustChangePassword: u.MustChangePassword,
			CreatedAt:          u.CreatedAt.UTC().Format(time.RFC3339),
			UpdatedAt:          u.UpdatedAt.UTC().Format(time.RFC3339),
		},
	}

	if u.Role == auth.RoleTechnician {
		mgrRows, err := s.queries.ListManagersByTechnician(ctx, db.ListManagersByTechnicianParams{
			CompanyID:    companyID,
			TechnicianID: u.ID,
		})
		if err != nil {
			return UserDetailsDTO{}, err
		}
		res.Managers = make([]ManagerSummaryDTO, 0, len(mgrRows))
		for _, m := range mgrRows {
			res.Managers = append(res.Managers, ManagerSummaryDTO{
				ID:               auth.FormatUUID(m.ID),
				Name:             m.Name,
				Email:            m.Email,
				IsActive:         m.IsActive,
				IsDefaultManager: m.IsDefaultManager,
				AssignedAt:       m.AssignedAt.UTC().Format(time.RFC3339),
			})
		}
	}

	return res, nil
}

func (s *Service) SetUserStatus(ctx context.Context, companyID, userID pgtype.UUID, isActive bool) (auth.UserDTO, error) {
	tx, err := s.database.Begin(ctx)
	if err != nil {
		return auth.UserDTO{}, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	target, err := qtx.GetCompanyUserByIDForUpdate(ctx, db.GetCompanyUserByIDForUpdateParams{
		CompanyID: companyID,
		ID:        userID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return auth.UserDTO{}, ErrNotFound
		}
		return auth.UserDTO{}, err
	}

	if target.Role != auth.RoleTechnician && target.Role != auth.RoleClient {
		return auth.UserDTO{}, ErrCannotModifyManager
	}

	updated, err := qtx.SetCompanyUserActiveStatus(ctx, db.SetCompanyUserActiveStatusParams{
		CompanyID: companyID,
		ID:        userID,
		IsActive:  isActive,
	})
	if err != nil {
		return auth.UserDTO{}, err
	}

	if !isActive {
		if err := qtx.RevokeAllUserAuthSessions(ctx, userID); err != nil {
			return auth.UserDTO{}, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return auth.UserDTO{}, err
	}

	compIDStr := auth.FormatUUID(companyID)
	return auth.UserDTO{
		ID:                 auth.FormatUUID(updated.ID),
		CompanyID:          &compIDStr,
		Name:               updated.Name,
		Email:              updated.Email,
		Role:               updated.Role,
		IsActive:           updated.IsActive,
		IsDefaultManager:   updated.IsDefaultManager,
		MustChangePassword: updated.MustChangePassword,
		CreatedAt:          updated.CreatedAt.UTC().Format(time.RFC3339),
		UpdatedAt:          updated.UpdatedAt.UTC().Format(time.RFC3339),
	}, nil
}

func (s *Service) ResetUserPassword(ctx context.Context, companyID, userID pgtype.UUID) (ResetPasswordResult, error) {
	tx, err := s.database.Begin(ctx)
	if err != nil {
		return ResetPasswordResult{}, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	target, err := qtx.GetCompanyUserByIDForUpdate(ctx, db.GetCompanyUserByIDForUpdateParams{
		CompanyID: companyID,
		ID:        userID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ResetPasswordResult{}, ErrNotFound
		}
		return ResetPasswordResult{}, err
	}

	if target.Role != auth.RoleTechnician && target.Role != auth.RoleClient {
		return ResetPasswordResult{}, ErrCannotModifyManager
	}

	tempPass, err := auth.GenerateTemporaryPassword()
	if err != nil {
		return ResetPasswordResult{}, err
	}
	passHash, err := auth.HashPassword(tempPass)
	if err != nil {
		return ResetPasswordResult{}, err
	}

	updated, err := qtx.UpdateUserPassword(ctx, db.UpdateUserPasswordParams{
		ID:                 target.ID,
		PasswordHash:       passHash,
		MustChangePassword: true,
	})
	if err != nil {
		return ResetPasswordResult{}, err
	}

	if err := qtx.RevokeAllUserAuthSessions(ctx, target.ID); err != nil {
		return ResetPasswordResult{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return ResetPasswordResult{}, err
	}

	compIDStr := auth.FormatUUID(companyID)
	return ResetPasswordResult{
		User: auth.UserDTO{
			ID:                 auth.FormatUUID(updated.ID),
			CompanyID:          &compIDStr,
			Name:               updated.Name,
			Email:              updated.Email,
			Role:               updated.Role,
			IsActive:           updated.IsActive,
			IsDefaultManager:   updated.IsDefaultManager,
			MustChangePassword: updated.MustChangePassword,
			CreatedAt:          updated.CreatedAt.UTC().Format(time.RFC3339),
			UpdatedAt:          updated.UpdatedAt.UTC().Format(time.RFC3339),
		},
		TemporaryPassword: tempPass,
	}, nil
}

func (s *Service) SetTechnicianManagers(ctx context.Context, companyID, technicianID pgtype.UUID, managerIDs []pgtype.UUID) ([]ManagerSummaryDTO, error) {
	uniqueMgrIDs := deduplicateUUIDs(managerIDs)
	if len(uniqueMgrIDs) == 0 {
		return nil, ErrInvalidManagerLink
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	tech, err := qtx.GetCompanyUserByIDForUpdate(ctx, db.GetCompanyUserByIDForUpdateParams{
		CompanyID: companyID,
		ID:        technicianID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if tech.Role != auth.RoleTechnician {
		return nil, ErrTargetNotTechnician
	}

	for _, mgrID := range uniqueMgrIDs {
		mgr, err := qtx.GetCompanyUserByID(ctx, db.GetCompanyUserByIDParams{
			CompanyID: companyID,
			ID:        mgrID,
		})
		if err != nil || mgr.Role != auth.RoleManager || !mgr.IsActive {
			return nil, ErrInvalidManagerLink
		}
	}

	if err := qtx.DeleteAllManagersForTechnician(ctx, db.DeleteAllManagersForTechnicianParams{
		CompanyID:    companyID,
		TechnicianID: technicianID,
	}); err != nil {
		return nil, err
	}

	for _, mgrID := range uniqueMgrIDs {
		if _, err := qtx.AddTechnicianManager(ctx, db.AddTechnicianManagerParams{
			CompanyID:    companyID,
			TechnicianID: technicianID,
			ManagerID:    mgrID,
		}); err != nil {
			return nil, err
		}
	}

	mgrRows, err := qtx.ListManagersByTechnician(ctx, db.ListManagersByTechnicianParams{
		CompanyID:    companyID,
		TechnicianID: technicianID,
	})
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	out := make([]ManagerSummaryDTO, 0, len(mgrRows))
	for _, m := range mgrRows {
		out = append(out, ManagerSummaryDTO{
			ID:               auth.FormatUUID(m.ID),
			Name:             m.Name,
			Email:            m.Email,
			IsActive:         m.IsActive,
			IsDefaultManager: m.IsDefaultManager,
			AssignedAt:       m.AssignedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
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

func (s *Service) DeleteUser(ctx context.Context, companyID, userID pgtype.UUID) error {
	if !companyID.Valid || !userID.Valid {
		return ErrInvalidInput
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	target, err := qtx.GetCompanyUserByIDForUpdate(ctx, db.GetCompanyUserByIDForUpdateParams{
		CompanyID: companyID,
		ID:        userID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}

	// Aditivo: Manager pode excluir definitivamente Technicians e Clients da própria empresa.
	// Managers e System Admins não podem ser excluídos por este aditivo.
	if target.Role != auth.RoleTechnician && target.Role != auth.RoleClient {
		return ErrCannotModifyManager
	}

	// Check operational history
	history, err := qtx.CheckUserOperationalHistory(ctx, db.CheckUserOperationalHistoryParams{
		CompanyID: companyID,
		UserID:    userID,
	})
	if err != nil {
		return err
	}

	if history.InstalledModulesCount > 0 || history.AuthoredIntervalLogsCount > 0 {
		return ErrUserHasOperationalHistory
	}

	// Invalidate/delete sessions and devices
	if err := qtx.DeleteAllUserAuthSessions(ctx, userID); err != nil {
		return err
	}
	if err := qtx.DeleteAllUserDevices(ctx, userID); err != nil {
		return err
	}

	// Remove administrative associations
	if target.Role == auth.RoleTechnician {
		if err := qtx.DeleteAllManagersForTechnician(ctx, db.DeleteAllManagersForTechnicianParams{
			CompanyID:    companyID,
			TechnicianID: userID,
		}); err != nil {
			return err
		}
		if err := qtx.DeleteAllModuleAssignmentsForTechnician(ctx, db.DeleteAllModuleAssignmentsForTechnicianParams{
			CompanyID:    companyID,
			TechnicianID: userID,
		}); err != nil {
			return err
		}
	} else if target.Role == auth.RoleClient {
		if err := qtx.DeleteAllModuleAssignmentsForClient(ctx, db.DeleteAllModuleAssignmentsForClientParams{
			CompanyID: companyID,
			ClientID:  userID,
		}); err != nil {
			return err
		}
	}

	if err := qtx.DeleteAllNotificationsForUser(ctx, db.DeleteAllNotificationsForUserParams{
		CompanyID: companyID,
		UserID:    userID,
	}); err != nil {
		return err
	}

	if err := qtx.DeleteCompanyUser(ctx, db.DeleteCompanyUserParams{
		CompanyID: companyID,
		ID:        userID,
	}); err != nil {
		return err
	}

	return tx.Commit(ctx)
}
