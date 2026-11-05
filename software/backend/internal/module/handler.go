package module

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

func parseModuleIDParam(r *http.Request) (pgtype.UUID, error) {
	raw := chi.URLParam(r, "id")
	if raw == "" {
		raw = chi.URLParam(r, "moduleID")
	}
	return auth.ParseUUID(raw)
}

func (h *Handler) RegisterRoutes(r chi.Router) {
	// Dedicated devices route group
	r.Route("/devices", func(r chi.Router) {
		r.Post("/claim", h.handleClaimDevice)

		r.Group(func(r chi.Router) {
			r.Use(auth.Authenticate(h.queries, h.tokens))
			r.Route("/{id}", func(r chi.Router) {
				r.Get("/configuration", h.handleGetDeviceConfiguration)
				r.Post("/configuration/ack", h.handleAcknowledgeDeviceConfiguration)
				r.Post("/ping", h.handleRecordDevicePing)
				r.Post("/telemetry", h.handleIngestTelemetry)
				r.Post("/inspections/{inspectionSourceEventId}/panels/{panelIndex}/result", h.handleRecordPanelThermalResult)
				r.Post("/inspections/{inspectionSourceEventId}/finalize", h.handleFinalizeInspection)
				r.Post("/cleanings", h.handleIngestCleaning)
			})
		})
	})

	r.Route("/alerts", func(r chi.Router) {
		r.Use(auth.Authenticate(h.queries, h.tokens))
		r.Use(auth.RequirePasswordChanged)
		r.Use(auth.RequireRoles(auth.RoleManager, auth.RoleTechnician, auth.RoleClient))

		r.Get("/", h.handleListAlerts)
	})

	r.Route("/modules", func(r chi.Router) {
		r.Use(auth.Authenticate(h.queries, h.tokens))
		r.Use(auth.RequirePasswordChanged)
		r.Use(auth.RequireRoles(auth.RoleManager, auth.RoleTechnician, auth.RoleClient))

		r.Get("/company-managers", h.handleListActiveCompanyManagers)
		r.Get("/company-clients", h.handleListActiveCompanyClients)
		r.Post("/", h.handleCreateModule)
		r.Get("/", h.handleListModules)
		r.Get("/{moduleID}", h.handleGetModule)
		r.Patch("/{moduleID}/configuration", h.handleUpdateConfiguration)
		r.Get("/{moduleID}/interval-logs", h.handleListIntervalChangeLogs)
		r.Get("/{moduleID}/measurements", h.handleListMeasurements)
		r.Get("/{moduleID}/cleanings", h.handleListCleanings)
		r.Get("/{moduleID}/inspections", h.handleListInspections)
		r.Get("/{moduleID}/latest-inspection", h.handleGetLatestInspection)
		r.Get("/{moduleID}/inspections/{inspectionId}/measurements", h.handleListInspectionMeasurements)
		r.Get("/{moduleID}/device-status", h.handleGetDeviceStatus)
		r.Post("/{moduleID}/device-ping", h.handleRecordDevicePing)
		r.Get("/{moduleID}/device-configuration", h.handleGetDeviceConfiguration)
		r.Post("/{moduleID}/device-configuration/ack", h.handleAcknowledgeDeviceConfiguration)
		r.Post("/{moduleID}/telemetry", h.handleIngestTelemetry)
		r.Post("/{moduleID}/inspections/{inspectionSourceEventId}/panels/{panelIndex}/result", h.handleRecordPanelThermalResult)
		r.Post("/{moduleID}/inspections/{inspectionSourceEventId}/finalize", h.handleFinalizeInspection)
		r.Post("/{moduleID}/cleanings", h.handleIngestCleaning)
		r.Put("/{moduleID}/managers", h.handleSetModuleManagers)
		r.Put("/{moduleID}/technicians/{technicianID}", h.handleSetTechnicianAccess)
		r.Put("/{moduleID}/clients", h.handleSetModuleClients)
		r.Patch("/{moduleID}/email-preferences", h.handleUpdateClientEmailPreference)
		r.Delete("/{moduleID}", h.handleDeleteModule)
	})
}

type createModuleRequest struct {
	Name                       string                 `json:"name"`
	MacAddress                 string                 `json:"mac_address"`
	ManagerIDs                 []string               `json:"manager_ids,omitempty"`
	ClientIDs                  []string               `json:"client_ids,omitempty"`
	PanelLengthCm              *float64               `json:"panel_length_cm"`
	PanelWidthCm               *float64               `json:"panel_width_cm"`
	PanelCount                 *int32                 `json:"panel_count"`
	PanelSpacingCm             *float64               `json:"panel_spacing_cm"`
	Latitude                   *float64               `json:"latitude"`
	Longitude                  *float64               `json:"longitude"`
	ElevationM                 *float64               `json:"elevation_m"`
	AzimuthDeg                 *float64               `json:"azimuth_deg"`
	TiltDeg                    *float64               `json:"tilt_deg"`
	AzimuthSource              *string                `json:"azimuth_source"`
	TiltSource                 *string                `json:"tilt_source"`
	MinimumSolarAngleDeg       *float64               `json:"minimum_solar_angle_deg"`
	InspectionIntervalDays     *int32                 `json:"inspection_interval_days"`
	ReservoirNominalCapacityMl *float64               `json:"reservoir_nominal_capacity_ml"`
	PowerSensors               []PowerSensorConfigDTO `json:"power_sensors,omitempty"`
}

func (h *Handler) handleCreateModule(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}
	if principal.Role != auth.RoleTechnician {
		httpjson.WriteError(w, http.StatusForbidden, "only technicians can initiate module installation", "FORBIDDEN")
		return
	}

	var req createModuleRequest
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

	clientUUIDs := make([]pgtype.UUID, 0, len(req.ClientIDs))
	for _, rawID := range req.ClientIDs {
		u, err := auth.ParseUUID(rawID)
		if err != nil {
			httpjson.WriteError(w, http.StatusBadRequest, "invalid client_ids UUID", "INVALID_INPUT")
			return
		}
		clientUUIDs = append(clientUUIDs, u)
	}

	res, err := h.service.CreateModule(r.Context(), CreateModuleInput{
		CompanyID:                  principal.CompanyID,
		InstallerTechnicianID:      principal.ID,
		Name:                       req.Name,
		MacAddress:                 req.MacAddress,
		ManagerIDs:                 mgrUUIDs,
		ClientIDs:                  clientUUIDs,
		PanelLengthCm:              req.PanelLengthCm,
		PanelWidthCm:               req.PanelWidthCm,
		PanelCount:                 req.PanelCount,
		PanelSpacingCm:             req.PanelSpacingCm,
		Latitude:                   req.Latitude,
		Longitude:                  req.Longitude,
		ElevationM:                 req.ElevationM,
		AzimuthDeg:                 req.AzimuthDeg,
		TiltDeg:                    req.TiltDeg,
		AzimuthSource:              req.AzimuthSource,
		TiltSource:                 req.TiltSource,
		MinimumSolarAngleDeg:       req.MinimumSolarAngleDeg,
		InspectionIntervalDays:     req.InspectionIntervalDays,
		ReservoirNominalCapacityMl: req.ReservoirNominalCapacityMl,
		PowerSensors:               req.PowerSensors,
	})
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "valid module name, MAC address, and configuration values are required", "INVALID_INPUT")
		case errors.Is(err, ErrManagerRequired):
			httpjson.WriteError(w, http.StatusBadRequest, "at least one active manager from the same company is required", "MODULE_MANAGER_REQUIRED")
		case errors.Is(err, ErrTechnicianHasNoActiveManagers):
			httpjson.WriteError(w, http.StatusUnprocessableEntity, "technician has no active responsible managers; please contact a manager", "NO_ACTIVE_MANAGERS")
		case errors.Is(err, ErrTargetNotClient):
			httpjson.WriteError(w, http.StatusBadRequest, "all client_ids must belong to active clients in this company", "INVALID_CLIENT_LINK")
		case errors.Is(err, ErrMACConflict):
			httpjson.WriteError(w, http.StatusConflict, "a module with this MAC address is already registered", "MAC_CONFLICT")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "only active technicians can install modules", "FORBIDDEN")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusCreated, res)
}

func (h *Handler) handleListModules(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	limit := parsePositiveInt32(r.URL.Query().Get("limit"), 50)
	offset := parsePositiveInt32(r.URL.Query().Get("offset"), 0)

	modules, err := h.service.ListModules(r.Context(), principal, limit, offset)
	if err != nil {
		if errors.Is(err, ErrForbidden) {
			httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
			return
		}
		httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, map[string]any{
		"modules": modules,
	})
}

func (h *Handler) handleGetModule(w http.ResponseWriter, r *http.Request) {
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

	details, err := h.service.GetModuleDetails(r.Context(), principal, moduleID)
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

type updateConfigurationRequest struct {
	Name                       *string                  `json:"name"`
	PanelLengthCm              *float64                 `json:"panel_length_cm"`
	PanelWidthCm               *float64                 `json:"panel_width_cm"`
	PanelCount                 *int32                   `json:"panel_count"`
	PanelSpacingCm             *float64                 `json:"panel_spacing_cm"`
	Latitude                   *float64                 `json:"latitude"`
	Longitude                  *float64                 `json:"longitude"`
	ElevationM                 *float64                 `json:"elevation_m"`
	AzimuthDeg                 *float64                 `json:"azimuth_deg"`
	TiltDeg                    *float64                 `json:"tilt_deg"`
	AzimuthSource              *string                  `json:"azimuth_source"`
	TiltSource                 *string                  `json:"tilt_source"`
	MinimumSolarAngleDeg       *float64                 `json:"minimum_solar_angle_deg"`
	InspectionIntervalDays     *int32                   `json:"inspection_interval_days"`
	ReservoirNominalCapacityMl *float64                 `json:"reservoir_nominal_capacity_ml"`
	PowerSensors               *[]PowerSensorConfigDTO  `json:"power_sensors,omitempty"`
	ClientIDs                  *[]string                `json:"client_ids,omitempty"`
}

func (h *Handler) handleUpdateConfiguration(w http.ResponseWriter, r *http.Request) {
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

	var req updateConfigurationRequest
	if err := httpjson.DecodeJSON(r, &req); err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid request payload", "INVALID_PAYLOAD")
		return
	}

	var parsedClientUUIDs *[]pgtype.UUID
	if req.ClientIDs != nil {
		clientUUIDs := make([]pgtype.UUID, 0, len(*req.ClientIDs))
		for _, rawID := range *req.ClientIDs {
			u, err := auth.ParseUUID(rawID)
			if err != nil {
				httpjson.WriteError(w, http.StatusBadRequest, "invalid client_ids UUID", "INVALID_INPUT")
				return
			}
			clientUUIDs = append(clientUUIDs, u)
		}
		parsedClientUUIDs = &clientUUIDs
	}

	details, err := h.service.UpdateConfiguration(r.Context(), principal, moduleID, UpdateConfigurationInput{
		Name:                       req.Name,
		PanelLengthCm:              req.PanelLengthCm,
		PanelWidthCm:               req.PanelWidthCm,
		PanelCount:                 req.PanelCount,
		PanelSpacingCm:             req.PanelSpacingCm,
		Latitude:                   req.Latitude,
		Longitude:                  req.Longitude,
		ElevationM:                 req.ElevationM,
		AzimuthDeg:                 req.AzimuthDeg,
		TiltDeg:                    req.TiltDeg,
		AzimuthSource:              req.AzimuthSource,
		TiltSource:                 req.TiltSource,
		MinimumSolarAngleDeg:       req.MinimumSolarAngleDeg,
		InspectionIntervalDays:     req.InspectionIntervalDays,
		ReservoirNominalCapacityMl: req.ReservoirNominalCapacityMl,
		PowerSensors:               req.PowerSensors,
		ClientIDs:                  parsedClientUUIDs,
	})
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "you do not have permission to edit these configuration fields", "FORBIDDEN")
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "invalid module configuration values", "INVALID_INPUT")
		case errors.Is(err, ErrTargetNotClient):
			httpjson.WriteError(w, http.StatusBadRequest, "all client_ids must belong to active clients in this company", "INVALID_CLIENT_LINK")
		default:
			httpjson.WriteError(w, http.StatusInternalServerError, "internal server error", "INTERNAL_ERROR")
		}
		return
	}

	httpjson.WriteJSON(w, http.StatusOK, details)
}

func (h *Handler) handleListIntervalChangeLogs(w http.ResponseWriter, r *http.Request) {
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

	logs, err := h.service.ListIntervalChangeLogs(r.Context(), principal, moduleID, limit, offset)
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
		"logs": logs,
	})
}

func (h *Handler) handleDeleteModule(w http.ResponseWriter, r *http.Request) {
	principal, ok := auth.PrincipalFromContext(r.Context())
	if !ok || !principal.CompanyID.Valid {
		httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
		return
	}

	moduleID, err := auth.ParseUUID(chi.URLParam(r, "moduleID"))
	if err != nil {
		httpjson.WriteError(w, http.StatusBadRequest, "invalid module id", "INVALID_INPUT")
		return
	}

	err = h.service.DeleteModule(r.Context(), principal, moduleID)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			httpjson.WriteError(w, http.StatusNotFound, "module not found", "NOT_FOUND")
		case errors.Is(err, ErrForbidden):
			httpjson.WriteError(w, http.StatusForbidden, "you do not have permission to delete this module", "FORBIDDEN")
		case errors.Is(err, ErrModuleHasPendingOperations):
			httpjson.WriteError(w, http.StatusConflict, "module cannot be deleted while physical operations or inspections are scheduled or in progress", "MODULE_HAS_PENDING_OPERATIONS")
		case errors.Is(err, ErrModuleHasOperationalHistory):
			httpjson.WriteError(w, http.StatusConflict, "installer technicians cannot delete modules with operational history (inspections, measurements, or cleanings)", "MODULE_HAS_HISTORY")
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
