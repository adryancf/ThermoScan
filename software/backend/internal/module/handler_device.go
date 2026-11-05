package module

import (
	"errors"
	"net/http"
	"strings"

	"backend/internal/auth"
	"backend/internal/httpjson"

	"github.com/go-chi/chi/v5"
)

func (h *Handler) handleGetDeviceStatus(w http.ResponseWriter, r *http.Request) {
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

	status, err := h.service.GetDeviceStatus(r.Context(), principal, moduleID)
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
		"device_status": status,
	})
}

func (h *Handler) handleClaimDevice(w http.ResponseWriter, r *http.Request) {
	var req ClaimDeviceInput
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid json body: "+err.Error(), "INVALID_BODY")
		return
	}

	res, err := h.service.ClaimDevice(r.Context(), req)
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "invalid mac address format", "INVALID_INPUT")
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "device not registered on backend", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "device is deactivated", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "failed to claim device: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, res)
}

func (h *Handler) handleRecordDevicePing(w http.ResponseWriter, r *http.Request) {
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

	var req RecordDevicePingInput
	_ = httpjson.DecodeJSON(r, &req)

	status, err := h.service.RecordDevicePing(r.Context(), principal, moduleID, req)
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
		"device_status": status,
	})
}

func (h *Handler) handleGetDeviceConfiguration(w http.ResponseWriter, r *http.Request) {
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

	cfg, err := h.service.GetDeviceConfiguration(r.Context(), moduleID)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		case errors.Is(err, ErrBatchTooLarge):
			httpjson.WriteError(w, http.StatusBadRequest, "telemetry batch exceeds maximum limit of 5 items", "BATCH_TOO_LARGE")
		case errors.Is(err, ErrConflict):
			httpjson.WriteError(w, http.StatusConflict, "conflict with existing measurement", "CONFLICT")
		case errors.Is(err, ErrMeasurementInGap):
			httpjson.WriteError(w, http.StatusBadRequest, err.Error(), "COORDINATE_IN_GAP")
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "invalid telemetry input: "+err.Error(), "INVALID_INPUT")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, cfg)
}

func (h *Handler) handleAcknowledgeDeviceConfiguration(w http.ResponseWriter, r *http.Request) {
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

	var req AcknowledgeDeviceConfigurationInput
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid json body: "+err.Error(), "INVALID_BODY")
		return
	}

	syncState, err := h.service.AcknowledgeDeviceConfiguration(r.Context(), moduleID, req)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		case errors.Is(err, ErrStaleConfig):
			httpjson.WriteError(w, http.StatusConflict, "stale configuration version", "STALE_CONFIG")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"configuration_sync": syncState,
		"message":            "configuration acknowledgment recorded",
	})
}

func (h *Handler) handleIngestTelemetry(w http.ResponseWriter, r *http.Request) {
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

	var req IngestTelemetryInput
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid json body: "+err.Error(), "INVALID_BODY")
		return
	}

	meas, err := h.service.IngestTelemetry(r.Context(), principal, moduleID, req)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		case errors.Is(err, ErrBatchTooLarge):
			httpjson.WriteError(w, http.StatusBadRequest, "telemetry batch exceeds maximum limit of 5 items", "BATCH_TOO_LARGE")
		case errors.Is(err, ErrConflict):
			httpjson.WriteError(w, http.StatusConflict, "conflict with existing measurement", "CONFLICT")
		case errors.Is(err, ErrMeasurementInGap):
			httpjson.WriteError(w, http.StatusBadRequest, err.Error(), "COORDINATE_IN_GAP")
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "invalid telemetry input: "+err.Error(), "INVALID_INPUT")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusCreated, map[string]any{
		"measurement": meas,
	})
}

func (h *Handler) handleIngestCleaning(w http.ResponseWriter, r *http.Request) {
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

	var req IngestCleaningInput
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid json body: "+err.Error(), "INVALID_BODY")
		return
	}

	clean, err := h.service.IngestCleaning(r.Context(), principal, moduleID, req)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
		case errors.Is(err, ErrBatchTooLarge):
			httpjson.WriteError(w, http.StatusBadRequest, "telemetry batch exceeds maximum limit of 5 items", "BATCH_TOO_LARGE")
		case errors.Is(err, ErrConflict):
			httpjson.WriteError(w, http.StatusConflict, "conflict with existing measurement", "CONFLICT")
		case errors.Is(err, ErrMeasurementInGap):
			httpjson.WriteError(w, http.StatusBadRequest, err.Error(), "COORDINATE_IN_GAP")
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "invalid telemetry input: "+err.Error(), "INVALID_INPUT")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error: "+err.Error(), "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusCreated, map[string]any{
		"cleaning": clean,
	})
}
