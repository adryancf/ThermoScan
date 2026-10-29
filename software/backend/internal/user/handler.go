package user

import (
	"errors"
	"net/http"
	"strconv"

	"backend/internal/auth"
	"backend/internal/db"
	"backend/internal/httpjson"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

type Handler struct {
	service *Service
	queries *db.Queries
	tokens  *auth.TokenManager
}

func NewHandler(service *Service, queries *db.Queries, tokens *auth.TokenManager) *Handler {
	return &Handler{
		service: service,
		queries: queries,
		tokens:  tokens,
	}
}

func (h *Handler) RegisterRoutes(r chi.Router) {
	r.Route("/users", func(r chi.Router) {
		r.Use(auth.Authenticate(h.queries, h.tokens))
		r.Use(auth.RequirePasswordChanged)
		r.Use(auth.RequireRoles(auth.RoleManager))

		r.Post("/", h.handleCreateUser)
		r.Get("/", h.handleListUsers)
		r.Get("/{userID}", h.handleGetUser)
		r.Patch("/{userID}/status", h.handleSetUserStatus)
		r.Post("/{userID}/reset-password", h.handleResetUserPassword)
		r.Put("/{userID}/managers", h.handleSetTechnicianManagers)
		r.Delete("/{userID}", h.handleDeleteUser)
	})
}

type createUserRequest struct {
	Name       string   `json:"name"`
	Email      string   `json:"email"`
	Role       string   `json:"role"`
	ManagerIDs []string `json:"manager_ids"`
}

func (h *Handler) handleCreateUser(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	var req createUserRequest
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid request payload", "INVALID_PAYLOAD")
		return
	}

	mgrUUIDs := make([]pgtype.UUID, 0, len(req.ManagerIDs))
	for _, rawID := range req.ManagerIDs {
		u, err := auth.ParseUUID(rawID)
		if err != nil {
			httpjson.WriteError(w, http.StatusBadRequest, "invalid manager_ids UUID", "INVALID_INPUT")
			return
		}
		mgrUUIDs = append(mgrUUIDs, u)
	}

	res, err := h.service.CreateUser(r.Context(), CreateUserInput{
		CompanyID:  principal.CompanyID,
		Name:       req.Name,
		Email:      req.Email,
		Role:       req.Role,
		ManagerIDs: mgrUUIDs,
	})
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "valid name, email, and role (manager, technician, client) are required", "INVALID_INPUT")
		case errors.Is(err, ErrInvalidManagerLink):
			httpjson.WriteError(w, http.StatusBadRequest, "technician must be linked to at least one active manager from the same company", "INVALID_MANAGER_LINK")
		case errors.Is(err, ErrEmailConflict):
			httpjson.WriteError(w, http.StatusConflict, "email is already in use", "EMAIL_CONFLICT")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusCreated, res)
}

func (h *Handler) handleListUsers(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	roleFilter := r.URL.Query().Get("role")
	limit := parsePositiveInt32(r.URL.Query().Get("limit"), 50)
	offset := parsePositiveInt32(r.URL.Query().Get("offset"), 0)

	users, err := h.service.ListUsers(r.Context(), principal.CompanyID, roleFilter, limit, offset)
	if err != nil {
		if errors.Is(err, ErrInvalidInput) {
			httpjson.WriteError(w, http.StatusBadRequest, "invalid role filter", "INVALID_INPUT")
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"users": users,
	})
}

func (h *Handler) handleGetUser(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	userID, err := auth.ParseUUID(chi.URLParam(r, "userID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid user ID", "INVALID_ID")
		return
	}

	res, err := h.service.GetUser(r.Context(), principal.CompanyID, userID)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			httpjson.WriteError(w, http.StatusNotFound, "user not found", "NOT_FOUND")
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, res)
}

type setUserStatusRequest struct {
	IsActive *bool `json:"is_active"`
}

func (h *Handler) handleSetUserStatus(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	userID, err := auth.ParseUUID(chi.URLParam(r, "userID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid user ID", "INVALID_ID")
		return
	}

	var req setUserStatusRequest
	if err := httpjson.DecodeJSON(r, &req); err != nil || req.IsActive == nil {
		httpjson.WriteError(w, http.StatusBadRequest, "is_active boolean is required", "INVALID_PAYLOAD")
		return
	}

	updated, err := h.service.SetUserStatus(r.Context(), principal.CompanyID, userID, *req.IsActive)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "user not found", "NOT_FOUND")
		case errors.Is(err, ErrCannotModifyManager):
			httpjson.WriteError(w, http.StatusForbidden, "managers can only change status of technicians or clients", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, updated)
}

func (h *Handler) handleResetUserPassword(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	userID, err := auth.ParseUUID(chi.URLParam(r, "userID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid user ID", "INVALID_ID")
		return
	}

	res, err := h.service.ResetUserPassword(r.Context(), principal.CompanyID, userID)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "user not found", "NOT_FOUND")
		case errors.Is(err, ErrCannotModifyManager):
			httpjson.WriteError(w, http.StatusForbidden, "managers can only reset passwords of technicians or clients", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, res)
}

type setTechnicianManagersRequest struct {
	ManagerIDs []string `json:"manager_ids"`
}

func (h *Handler) handleSetTechnicianManagers(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	technicianID, err := auth.ParseUUID(chi.URLParam(r, "userID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid user ID", "INVALID_ID")
		return
	}

	var req setTechnicianManagersRequest
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid request payload", "INVALID_PAYLOAD")
		return
	}

	mgrUUIDs := make([]pgtype.UUID, 0, len(req.ManagerIDs))
	for _, rawID := range req.ManagerIDs {
		u, err := auth.ParseUUID(rawID)
		if err != nil {
			httpjson.WriteError(w, http.StatusBadRequest, "invalid manager_ids UUID", "INVALID_INPUT")
			return
		}
		mgrUUIDs = append(mgrUUIDs, u)
	}

	managers, err := h.service.SetTechnicianManagers(r.Context(), principal.CompanyID, technicianID, mgrUUIDs)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "user not found", "NOT_FOUND")
		case errors.Is(err, ErrTargetNotTechnician):
			httpjson.WriteError(w, http.StatusBadRequest, "target user is not a technician", "NOT_A_TECHNICIAN")
		case errors.Is(err, ErrInvalidManagerLink):
			httpjson.WriteError(w, http.StatusBadRequest, "at least one active manager from the same company is required", "INVALID_MANAGER_LINK")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"managers": managers,
	})
}

func (h *Handler) handleDeleteUser(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	userUUID, err := auth.ParseUUID(chi.URLParam(r, "userID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid user id", "INVALID_INPUT")
		return
	}

	err = h.service.DeleteUser(r.Context(), principal.CompanyID, userUUID)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "user not found", "NOT_FOUND")
		case errors.Is(err, ErrCannotModifyManager):
			httpjson.WriteError(w, http.StatusForbidden, "managers cannot be deleted", "CANNOT_DELETE_MANAGER")
		case errors.Is(err, ErrUserHasOperationalHistory):
			httpjson.WriteError(w, http.StatusConflict, "user cannot be deleted because they have associated operational history or installed modules; deactivate the account instead", "USER_HAS_OPERATIONAL_HISTORY")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func parsePositiveInt32(s string, defaultVal int32) int32 {
	if s == "" {
		return defaultVal
	}
	v, err := strconv.ParseInt(s, 10, 32)
	if err != nil || v < 0 {
		return defaultVal
	}
	return int32(v)
}
