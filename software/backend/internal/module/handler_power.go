package module

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"backend/internal/auth"
	"backend/internal/httpjson"

	"github.com/go-chi/chi/v5"
)

func parseOptionalPanelIndexQuery(r *http.Request) (*int32, error) {
	raw := strings.TrimSpace(r.URL.Query().Get("panel_index"))
	if raw == "" {
		return nil, nil
	}
	v, err := strconv.Atoi(raw)
	if err != nil || v < 1 {
		return nil, ErrInvalidInput
	}
	iv := int32(v)
	return &iv, nil
}

func (h *Handler) handleGetPowerReadingsSeries(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	moduleID, err := auth.ParseUUID(chi.URLParam(r, "moduleID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	panelIndex, err := parseOptionalPanelIndexQuery(r)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid panel_index", "INVALID_INPUT")
		return
	}

	rangeParam := r.URL.Query().Get("range")
	res, err := h.service.GetPowerReadingsSeries(r.Context(), principal, moduleID, rangeParam, panelIndex)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "invalid query parameters", "INVALID_INPUT")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, res)
}

func (h *Handler) handleListPowerReadings(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	moduleID, err := auth.ParseUUID(chi.URLParam(r, "moduleID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	panelIndex, err := parseOptionalPanelIndexQuery(r)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid panel_index", "INVALID_INPUT")
		return
	}

	page := 1
	if rawPage := strings.TrimSpace(r.URL.Query().Get("page")); rawPage != "" {
		if parsed, err := strconv.Atoi(rawPage); err == nil && parsed > 0 {
			page = parsed
		}
	}
	limit := 20
	if rawLimit := strings.TrimSpace(r.URL.Query().Get("limit")); rawLimit != "" {
		if parsed, err := strconv.Atoi(rawLimit); err == nil && parsed > 0 {
			limit = parsed
		}
	}

	rangeParam := r.URL.Query().Get("range")
	res, err := h.service.ListPowerReadings(r.Context(), principal, moduleID, rangeParam, panelIndex, page, limit)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "invalid query parameters", "INVALID_INPUT")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, res)
}
