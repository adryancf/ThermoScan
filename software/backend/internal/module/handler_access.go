package module

import (
	"errors"
	"net/http"

	"backend/internal/auth"
	"backend/internal/httpjson"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func (h *Handler) handleListActiveCompanyManagers(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}
	if principal.Role != auth.RoleTechnician && principal.Role != auth.RoleManager {
		httpjson.WriteError(w, http.StatusForbidden, "only technicians and managers can list company managers", "FORBIDDEN")
		return
	}

	managers, err := h.service.ListActiveCompanyManagers(r.Context(), principal.CompanyID)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"managers": managers,
	})
}

func (h *Handler) handleListActiveCompanyClients(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}
	if principal.Role != auth.RoleTechnician && principal.Role != auth.RoleManager {
		httpjson.WriteError(w, http.StatusForbidden, "only technicians and managers can list company clients", "FORBIDDEN")
		return
	}

	clients, err := h.service.ListActiveCompanyClients(r.Context(), principal.CompanyID)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"clients": clients,
	})
}

type setModuleManagersRequest struct {
	ManagerIDs []string `json:"manager_ids"`
}

func (h *Handler) handleSetModuleManagers(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}
	if principal.Role != auth.RoleManager {
		httpjson.WriteError(w, http.StatusForbidden, "only managers can update module responsible managers", "FORBIDDEN")
		return
	}

	moduleID, err := auth.ParseUUID(chi.URLParam(r, "moduleID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	var req setModuleManagersRequest
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

	details, err := h.service.SetModuleManagers(r.Context(), principal, moduleID, mgrUUIDs)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrManagerRequired):
			httpjson.WriteError(w, http.StatusBadRequest, "at least one active manager from the same company is required", "MODULE_MANAGER_REQUIRED")
		case errors.Is(err, ErrTechnicianHasNoActiveManagers):
			httpjson.WriteError(w, http.StatusUnprocessableEntity, "technician has no active responsible managers; please contact a manager", "NO_ACTIVE_MANAGERS")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "only managers can update module responsible managers", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, details)
}

type setTechnicianAccessRequest struct {
	CanView *bool `json:"can_view"`
}

func (h *Handler) handleSetTechnicianAccess(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}
	if principal.Role != auth.RoleManager {
		httpjson.WriteError(w, http.StatusForbidden, "only managers can manage technician access", "FORBIDDEN")
		return
	}

	moduleID, err := auth.ParseUUID(chi.URLParam(r, "moduleID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}
	technicianID, err := auth.ParseUUID(chi.URLParam(r, "technicianID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid technician ID", "INVALID_ID")
		return
	}

	var req setTechnicianAccessRequest
	if err := httpjson.DecodeJSON(r, &req); err != nil || req.CanView == nil {
		httpjson.WriteError(w, http.StatusBadRequest, "can_view boolean is required", "INVALID_PAYLOAD")
		return
	}

	details, err := h.service.SetTechnicianAccess(r.Context(), principal, moduleID, technicianID, *req.CanView)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module or technician not found", "NOT_FOUND")
		case errors.Is(err, ErrTargetNotTechnician):
			httpjson.WriteError(w, http.StatusBadRequest, "target user is not a technician in this company", "NOT_A_TECHNICIAN")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "only managers can manage technician access", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, details)
}

type setModuleClientsRequest struct {
	ClientIDs []string `json:"client_ids"`
}

func (h *Handler) handleSetModuleClients(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}
	if principal.Role != auth.RoleManager {
		httpjson.WriteError(w, http.StatusForbidden, "only managers can manage assigned clients", "FORBIDDEN")
		return
	}

	moduleID, err := auth.ParseUUID(chi.URLParam(r, "moduleID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	var req setModuleClientsRequest
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid request payload", "INVALID_PAYLOAD")
		return
	}

	clientUUIDs := make([]pgtype.UUID, 0, len(req.ClientIDs))
	for _, rawID := range req.ClientIDs {
		u, err := auth.ParseUUID(rawID)
		if err != nil {
			httpjson.WriteError(w, http.StatusBadRequest, "invalid client_ids UUID", "INVALID_INPUT")
			return
		}
		clientUUIDs = append(clientUUIDs, u)
	}

	details, err := h.service.SetModuleClients(r.Context(), principal, moduleID, clientUUIDs)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrTargetNotClient):
			httpjson.WriteError(w, http.StatusBadRequest, "all client_ids must belong to clients in this company", "INVALID_CLIENT_LINK")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "only managers can manage assigned clients", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, details)
}

type updateEmailPreferenceRequest struct {
	OperationalEmailEnabled *bool `json:"operational_email_enabled"`
}

func (h *Handler) handleUpdateClientEmailPreference(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}
	if principal.Role != auth.RoleClient {
		httpjson.WriteError(w, http.StatusForbidden, "only assigned clients can update operational email preferences", "FORBIDDEN")
		return
	}

	moduleID, err := auth.ParseUUID(chi.URLParam(r, "moduleID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	var req updateEmailPreferenceRequest
	if err := httpjson.DecodeJSON(r, &req); err != nil || req.OperationalEmailEnabled == nil {
		httpjson.WriteError(w, http.StatusBadRequest, "operational_email_enabled boolean is required", "INVALID_PAYLOAD")
		return
	}

	details, err := h.service.UpdateClientEmailPreference(r.Context(), principal, moduleID, *req.OperationalEmailEnabled)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, details)
}
