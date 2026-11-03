package module

import (
	"net/http"

	"backend/internal/auth"
	"backend/internal/httpjson"
)

func (h *Handler) handleListAlerts(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	summary, err := h.service.ListActiveAlerts(r.Context(), principal)
	if err != nil {
		httpjson.WriteError(w, http.StatusInternalServerError, "failed to list alerts: "+err.Error(), "INTERNAL_ERROR")
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, summary)
}
