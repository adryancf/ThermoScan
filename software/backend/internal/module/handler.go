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

func (h *Handler) RegisterRoutes(r chi.Router) {
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
		r.Put("/{moduleID}/managers", h.handleSetModuleManagers)
		r.Put("/{moduleID}/technicians/{technicianID}", h.handleSetTechnicianAccess)
		r.Put("/{moduleID}/clients", h.handleSetModuleClients)
		r.Patch("/{moduleID}/email-preferences", h.handleUpdateClientEmailPreference)
	})
}

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

type createModuleRequest struct {
	Name                       string   `json:"name"`
	MacAddress                 string   `json:"mac_address"`
	ManagerIDs                 []string `json:"manager_ids"`
	ClientIDs                  []string `json:"client_ids,omitempty"`
	PanelLengthCm              *float64 `json:"panel_length_cm"`
	PanelWidthCm               *float64 `json:"panel_width_cm"`
	PanelCount                 *int32   `json:"panel_count"`
	PanelSpacingCm             *float64 `json:"panel_spacing_cm"`
	Latitude                   *float64 `json:"latitude"`
	Longitude                  *float64 `json:"longitude"`
	ElevationM                 *float64 `json:"elevation_m"`
	AzimuthDeg                 *float64 `json:"azimuth_deg"`
	TiltDeg                    *float64 `json:"tilt_deg"`
	AzimuthSource              *string  `json:"azimuth_source"`
	TiltSource                 *string  `json:"tilt_source"`
	MinimumSolarAngleDeg       *float64 `json:"minimum_solar_angle_deg"`
	InspectionIntervalDays     *int32   `json:"inspection_interval_days"`
	ReservoirNominalCapacityMl *float64 `json:"reservoir_nominal_capacity_ml"`
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
	})
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidInput):
			httpjson.WriteError(w, http.StatusBadRequest, "valid module name, MAC address, and configuration values are required", "INVALID_INPUT")
		case errors.Is(err, ErrManagerRequired):
			httpjson.WriteError(w, http.StatusBadRequest, "at least one active manager from the same company is required", "MODULE_MANAGER_REQUIRED")
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
	Name                       *string   `json:"name"`
	PanelLengthCm              *float64  `json:"panel_length_cm"`
	PanelWidthCm               *float64  `json:"panel_width_cm"`
	PanelCount                 *int32    `json:"panel_count"`
	PanelSpacingCm             *float64  `json:"panel_spacing_cm"`
	Latitude                   *float64  `json:"latitude"`
	Longitude                  *float64  `json:"longitude"`
	ElevationM                 *float64  `json:"elevation_m"`
	AzimuthDeg                 *float64  `json:"azimuth_deg"`
	TiltDeg                    *float64  `json:"tilt_deg"`
	AzimuthSource              *string   `json:"azimuth_source"`
	TiltSource                 *string   `json:"tilt_source"`
	MinimumSolarAngleDeg       *float64  `json:"minimum_solar_angle_deg"`
	InspectionIntervalDays     *int32    `json:"inspection_interval_days"`
	ReservoirNominalCapacityMl *float64  `json:"reservoir_nominal_capacity_ml"`
	ClientIDs                  *[]string `json:"client_ids,omitempty"`
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
