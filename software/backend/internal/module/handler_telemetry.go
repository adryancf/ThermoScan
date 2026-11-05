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

func (h *Handler) handleListMeasurements(w http.ResponseWriter, r *http.Request) {
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

	limit := parsePositiveInt32(r.URL.Query().Get("limit"), 50)
	offset := parsePositiveInt32(r.URL.Query().Get("offset"), 0)

	measurements, err := h.service.ListMeasurements(r.Context(), principal, moduleID, limit, offset)
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

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"measurements": measurements,
	})
}

func (h *Handler) handleGetLatestInspection(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	moduleID, err := parseModuleIDParam(r)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	latest, err := h.service.GetLatestInspection(r.Context(), principal, moduleID)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	if latest == nil {
		httpjson.WriteJSON(w, http.StatusOK, map[string]any{
			"latest_inspection": nil,
		})
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"latest_inspection": latest,
	})
}

func (h *Handler) handleListInspectionMeasurements(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	moduleID, err := parseModuleIDParam(r)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	inspectionID, err := auth.ParseUUID(chi.URLParam(r, "inspectionId"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid inspection ID", "INVALID_ID")
		return
	}

	page := parsePositiveInt32(r.URL.Query().Get("page"), 1)
	limit := parsePositiveInt32(r.URL.Query().Get("limit"), 10)

	paged, err := h.service.ListInspectionMeasurementsPaged(r.Context(), principal, moduleID, inspectionID, page, limit)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module or inspection not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, paged)
}

func (h *Handler) handleFinalizeInspection(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	moduleID, err := parseModuleIDParam(r)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	if strings.HasPrefix(principal.Email, "device@") && principal.ID.Bytes != moduleID.Bytes {
		httpjson.WriteError(w, http.StatusForbidden, "device token does not match module", "FORBIDDEN")
		return
	}

	inspSourceEventID, err := auth.ParseUUID(chi.URLParam(r, "inspectionSourceEventId"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid inspection source event ID", "INVALID_ID")
		return
	}

	var req FinalizeInspectionInput
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid json body: "+err.Error(), "INVALID_BODY")
		return
	}

	latest, err := h.service.FinalizeInspection(r.Context(), principal, moduleID, inspSourceEventID, req)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "inspection not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		case errors.Is(err, ErrConflict):
			httpjson.WriteError(w, http.StatusConflict, "conflict with existing inspection", "CONFLICT")
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "invalid inspection finalization data: "+err.Error(), "INVALID_INPUT")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"latest_inspection": latest,
	})
}

func (h *Handler) handleRecordPanelThermalResult(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	moduleID, err := parseModuleIDParam(r)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	if strings.HasPrefix(principal.Email, "device@") && principal.ID.Bytes != moduleID.Bytes {
		httpjson.WriteError(w, http.StatusForbidden, "device token does not match module", "FORBIDDEN")
		return
	}

	inspSourceEventID, err := auth.ParseUUID(chi.URLParam(r, "inspectionSourceEventId"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid inspection source event ID", "INVALID_ID")
		return
	}

	panelIndexRaw := chi.URLParam(r, "panelIndex")
	panelIndex, err := strconv.ParseInt(panelIndexRaw, 10, 32)
	if err != nil || panelIndex < 1 {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid panel index", "INVALID_PANEL_INDEX")
		return
	}

	var req RecordPanelResultInput
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid json body: "+err.Error(), "INVALID_BODY")
		return
	}

	result, err := h.service.RecordPanelThermalResult(r.Context(), principal, moduleID, inspSourceEventID, int32(panelIndex), req)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "inspection not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		case errors.Is(err, ErrInspectionCompleted):
			httpjson.WriteError(w, http.StatusConflict, "inspection already finalized", "INSPECTION_COMPLETED")
		case errors.Is(err, ErrInvalidPanelIndex):
			httpjson.WriteError(w, http.StatusBadRequest, "panel index out of bounds", "INVALID_PANEL_INDEX")
		case errors.Is(err, ErrMeasurementInGap), errors.Is(err, ErrHotspotInGap):
			httpjson.WriteError(w, http.StatusBadRequest, err.Error(), "COORDINATE_IN_GAP")
		case errors.Is(err, ErrPanelIndexMismatch):
			httpjson.WriteError(w, http.StatusBadRequest, err.Error(), "PANEL_INDEX_MISMATCH")
		case errors.Is(err, ErrPositionOutOfBounds):
			httpjson.WriteError(w, http.StatusBadRequest, err.Error(), "POSITION_OUT_OF_BOUNDS")
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "invalid panel result data: "+err.Error(), "INVALID_INPUT")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"panel_result": result,
	})
}

func (h *Handler) handleListInspections(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	moduleID, err := parseModuleIDParam(r)
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module ID", "INVALID_ID")
		return
	}

	limit := parsePositiveInt32(r.URL.Query().Get("limit"), 20)
	offset := parsePositiveInt32(r.URL.Query().Get("offset"), 0)

	inspections, err := h.service.ListInspections(r.Context(), principal, moduleID, limit, offset)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"inspections": inspections,
	})
}
