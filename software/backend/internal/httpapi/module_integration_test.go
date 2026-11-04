package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"backend/internal/auth"
	"backend/internal/company"
	"backend/internal/db"
	"backend/internal/httpapi"
	"backend/internal/module"
	"backend/internal/user"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestModulePermissionsAndLifecycleIntegration(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	conn, err := pgx.Connect(ctx, testDBURL())
	if err != nil {
		t.Skipf("PostgreSQL not reachable for integration test: %v", err)
	}
	defer conn.Close(ctx)

	tx, err := conn.Begin(ctx)
	if err != nil {
		t.Fatalf("failed to begin tx: %v", err)
	}
	defer tx.Rollback(ctx)

	q := db.New(tx)
	tokens := auth.NewTokenManager("module-integration-secret-key-2026")

	adminPass := "AdminPass#2026"
	adminHash, err := auth.HashPassword(adminPass)
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	adminEmail := "sysadmin.modtest@thermoscan.local"
	if _, err := q.CreateUser(ctx, db.CreateUserParams{
		CompanyID:          pgtype.UUID{Valid: false},
		Name:               "System Admin",
		Email:              adminEmail,
		PasswordHash:       adminHash,
		Role:               auth.RoleSystemAdmin,
		IsActive:           true,
		IsDefaultManager:   false,
		MustChangePassword: false,
	}); err != nil {
		t.Fatalf("CreateUser (system_admin): %v", err)
	}

	router := httpapi.NewRouter(httpapi.Dependencies{
		AuthHandler:    auth.NewHandler(auth.NewService(tx, tokens), q, tokens),
		CompanyHandler: company.NewHandler(company.NewService(tx), q, tokens),
		UserHandler:    user.NewHandler(user.NewService(tx), q, tokens),
		ModuleHandler:  module.NewHandler(module.NewService(tx), q, tokens),
	})

	doJSON := func(method, path, bearer string, body any) *httptest.ResponseRecorder {
		var buf bytes.Buffer
		if body != nil {
			if err := json.NewEncoder(&buf).Encode(body); err != nil {
				t.Fatalf("encode body: %v", err)
			}
		}
		req := httptest.NewRequest(method, path, &buf)
		req.Header.Set("Content-Type", "application/json")
		if bearer != "" {
			req.Header.Set("Authorization", "Bearer "+bearer)
		}
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		return rec
	}

	loginAndActivate := func(email, tempPass, newPass string) auth.AuthResponse {
		rec := doJSON(http.MethodPost, "/api/v1/auth/login", "", map[string]string{
			"email":    email,
			"password": tempPass,
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("login(%s) failed (%d): %s", email, rec.Code, rec.Body.String())
		}
		var resp auth.AuthResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("decode login: %v", err)
		}
		if resp.User.MustChangePassword {
			rec = doJSON(http.MethodPost, "/api/v1/auth/change-password", resp.AccessToken, map[string]string{
				"current_password": tempPass,
				"new_password":     newPass,
			})
			if rec.Code != http.StatusOK {
				t.Fatalf("change-password(%s) failed (%d): %s", email, rec.Code, rec.Body.String())
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
				t.Fatalf("decode change-password: %v", err)
			}
		}
		return resp
	}

	// 1. Login as System Admin and create Company A & Company B
	adminAuth := loginAndActivate(adminEmail, adminPass, adminPass)

	rec := doJSON(http.MethodPost, "/api/v1/companies", adminAuth.AccessToken, map[string]string{
		"name":          "Company A Solar",
		"manager_name":  "Manager A1",
		"manager_email": "mgr.a1@modtest.local",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create Company A failed (%d): %s", rec.Code, rec.Body.String())
	}
	var compA company.CreateCompanyResult
	_ = json.Unmarshal(rec.Body.Bytes(), &compA)

	rec = doJSON(http.MethodPost, "/api/v1/companies", adminAuth.AccessToken, map[string]string{
		"name":          "Company B Solar",
		"manager_name":  "Manager B1",
		"manager_email": "mgr.b1@modtest.local",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create Company B failed (%d): %s", rec.Code, rec.Body.String())
	}
	var compB company.CreateCompanyResult
	_ = json.Unmarshal(rec.Body.Bytes(), &compB)

	mgrAAuth := loginAndActivate("mgr.a1@modtest.local", compA.TemporaryPassword, "MgrA1#Pass2026")
	mgrBAuth := loginAndActivate("mgr.b1@modtest.local", compB.TemporaryPassword, "MgrB1#Pass2026")

	// System Admin is forbidden from accessing /api/v1/modules
	rec = doJSON(http.MethodGet, "/api/v1/modules", adminAuth.AccessToken, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for System Admin on GET /modules, got %d", rec.Code)
	}

	// 2. Manager A1 creates Manager A2, Technician T1 (installer), Technician T2 (shared), and Client C1
	rec = doJSON(http.MethodPost, "/api/v1/users", mgrAAuth.AccessToken, map[string]any{
		"name":  "Manager A2",
		"email": "mgr.a2@modtest.local",
		"role":  "manager",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create Manager A2 failed: %s", rec.Body.String())
	}
	var mgrA2Res user.CreateUserResult
	_ = json.Unmarshal(rec.Body.Bytes(), &mgrA2Res)

	rec = doJSON(http.MethodPost, "/api/v1/users", mgrAAuth.AccessToken, map[string]any{
		"name":        "Tech T1 Installer",
		"email":       "tech.t1@modtest.local",
		"role":        "technician",
		"manager_ids": []string{compA.DefaultManager.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create Tech T1 failed: %s", rec.Body.String())
	}
	var tech1Res user.CreateUserResult
	_ = json.Unmarshal(rec.Body.Bytes(), &tech1Res)

	rec = doJSON(http.MethodPost, "/api/v1/users", mgrAAuth.AccessToken, map[string]any{
		"name":        "Tech T2 Shared",
		"email":       "tech.t2@modtest.local",
		"role":        "technician",
		"manager_ids": []string{compA.DefaultManager.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create Tech T2 failed: %s", rec.Body.String())
	}
	var tech2Res user.CreateUserResult
	_ = json.Unmarshal(rec.Body.Bytes(), &tech2Res)

	rec = doJSON(http.MethodPost, "/api/v1/users", mgrAAuth.AccessToken, map[string]any{
		"name":  "Client C1",
		"email": "client.c1@modtest.local",
		"role":  "client",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create Client C1 failed: %s", rec.Body.String())
	}
	var client1Res user.CreateUserResult
	_ = json.Unmarshal(rec.Body.Bytes(), &client1Res)

	tech1Auth := loginAndActivate("tech.t1@modtest.local", tech1Res.TemporaryPassword, "TechT1#Pass2026")
	tech2Auth := loginAndActivate("tech.t2@modtest.local", tech2Res.TemporaryPassword, "TechT2#Pass2026")
	client1Auth := loginAndActivate("client.c1@modtest.local", client1Res.TemporaryPassword, "ClientC1#Pass2026")

	// 3. Tech T1 lists all active company managers (both Manager A1 and Manager A2 should be returned)
	rec = doJSON(http.MethodGet, "/api/v1/modules/company-managers", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on GET /modules/company-managers, got %d: %s", rec.Code, rec.Body.String())
	}
	var mgrListResp struct {
		Managers []module.ModuleManagerDTO `json:"managers"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &mgrListResp)
	if len(mgrListResp.Managers) != 2 {
		t.Fatalf("expected 2 active company managers, got %d", len(mgrListResp.Managers))
	}

	// 4. Manager cannot create a module (only Technician can)
	rec = doJSON(http.MethodPost, "/api/v1/modules", mgrAAuth.AccessToken, map[string]any{
		"name":        "Forbidden Module",
		"mac_address": "AA:BB:CC:DD:EE:01",
		"manager_ids": []string{compA.DefaultManager.ID},
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when Manager creates module, got %d", rec.Code)
	}

	// 5. Aditivo: Tech T1 creates a draft module without specifying manager_ids;
	// managers are automatically associated from technician_managers
	rec = doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":        "PV-001 Roof Array",
		"mac_address": "aa:bb:cc:dd:ee:01",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 when Tech T1 creates draft module, got %d: %s", rec.Code, rec.Body.String())
	}
	var modCreated module.ModuleDetailsDTO
	_ = json.Unmarshal(rec.Body.Bytes(), &modCreated)
	if modCreated.Module.MonitoringStatus != module.StatusPendingConfiguration {
		t.Fatalf("expected status pending_configuration, got %s", modCreated.Module.MonitoringStatus)
	}
	if modCreated.Module.UserRelationship != module.RelInstallerTechnician {
		t.Fatalf("expected relationship installer_technician, got %s", modCreated.Module.UserRelationship)
	}
	if len(modCreated.ResponsibleManagers) != 1 || modCreated.ResponsibleManagers[0].ID != compA.DefaultManager.ID {
		t.Fatalf("expected responsible manager to be automatically assigned as %s, got %+v", compA.DefaultManager.ID, modCreated.ResponsibleManagers)
	}

	// Aditivo: Technician with no active responsible managers is blocked with 422
	rec = doJSON(http.MethodPost, "/api/v1/users", mgrAAuth.AccessToken, map[string]any{
		"name":        "Unassigned Tech",
		"email":       "orphan.tech@modtest.local",
		"role":        "technician",
		"manager_ids": []string{compA.DefaultManager.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create orphan tech failed: %s", rec.Body.String())
	}
	var orphanTechRes user.CreateUserResult
	_ = json.Unmarshal(rec.Body.Bytes(), &orphanTechRes)
	orphanTechAuth := loginAndActivate("orphan.tech@modtest.local", orphanTechRes.TemporaryPassword, "OrphanTech#2026")

	// Disassociate all managers from this technician to test the edge case
	if _, err := tx.Exec(ctx, "DELETE FROM technician_managers WHERE technician_id = $1", orphanTechRes.User.ID); err != nil {
		t.Fatalf("delete technician_managers failed: %v", err)
	}

	rec = doJSON(http.MethodPost, "/api/v1/modules", orphanTechAuth.AccessToken, map[string]any{
		"name":        "Blocked Module",
		"mac_address": "12:34:56:78:90:AB",
	})
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422 when technician has no active managers, got %d: %s", rec.Code, rec.Body.String())
	}

	// Duplicate MAC is rejected with 409
	rec = doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":        "Duplicate MAC Module",
		"mac_address": "AA:BB:CC:DD:EE:01",
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 on duplicate MAC, got %d", rec.Code)
	}

	// 6. Tech T1 completes module configuration -> transitions to active
	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+modCreated.Module.ID+"/configuration", tech1Auth.AccessToken, map[string]any{
		"panel_length_cm":          195.5,
		"panel_width_cm":           99.2,
		"panel_count":              8,
		"panel_spacing_cm":         2.5,
		"latitude":                 -25.4395,
		"longitude":                -49.2687,
		"elevation_m":              934.0,
		"azimuth_deg":              12.5,
		"tilt_deg":                 23.0,
		"azimuth_source":           "sensor",
		"tilt_source":              "manual",
		"minimum_solar_angle_deg":  15.0,
		"inspection_interval_days": 7,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on completing configuration, got %d: %s", rec.Code, rec.Body.String())
	}
	var modCompleted module.ModuleDetailsDTO
	_ = json.Unmarshal(rec.Body.Bytes(), &modCompleted)
	if modCompleted.Module.MonitoringStatus != module.StatusActive {
		t.Fatalf("expected status active after full config, got %s", modCompleted.Module.MonitoringStatus)
	}
	if modCompleted.Module.ConfiguredAt == nil {
		t.Fatalf("expected configured_at to be set")
	}

	// 7. Tech T2 (unshared) and Client C1 (unassigned) cannot view the module
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID, tech2Auth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for unshared Tech T2, got %d", rec.Code)
	}
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID, client1Auth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for unassigned Client C1, got %d", rec.Code)
	}

	// 8. Manager A1 grants Tech T2 shared access -> Tech T2 can edit solar angle, but NOT interval or geometry
	rec = doJSON(http.MethodPut, "/api/v1/modules/"+modCreated.Module.ID+"/technicians/"+tech2Res.User.ID, mgrAAuth.AccessToken, map[string]any{
		"can_view": true,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 granting Tech T2 access, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+modCreated.Module.ID+"/configuration", tech2Auth.AccessToken, map[string]any{
		"minimum_solar_angle_deg": 20.0,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 when shared Tech T2 edits minimum_solar_angle_deg, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+modCreated.Module.ID+"/configuration", tech2Auth.AccessToken, map[string]any{
		"inspection_interval_days": 15,
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when shared Tech T2 tries to edit inspection_interval_days, got %d", rec.Code)
	}

	// 9. Manager A1 assigns Client C1 -> Client C1 can edit inspection_interval_days and toggle email preferences, but NOT solar angle
	rec = doJSON(http.MethodPut, "/api/v1/modules/"+modCreated.Module.ID+"/clients", mgrAAuth.AccessToken, map[string]any{
		"client_ids": []string{client1Res.User.ID},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 assigning Client C1, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+modCreated.Module.ID+"/configuration", client1Auth.AccessToken, map[string]any{
		"inspection_interval_days": 15,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 when assigned Client C1 edits inspection_interval_days, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+modCreated.Module.ID+"/configuration", client1Auth.AccessToken, map[string]any{
		"minimum_solar_angle_deg": 25.0,
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when Client C1 tries to edit minimum_solar_angle_deg, got %d", rec.Code)
	}

	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+modCreated.Module.ID+"/email-preferences", client1Auth.AccessToken, map[string]any{
		"operational_email_enabled": false,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 when Client C1 updates email preference, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify interval change logs contain both changes (1 -> 7 by Tech T1, and 7 -> 15 by Client C1)
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/interval-logs", client1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on GET /interval-logs, got %d: %s", rec.Code, rec.Body.String())
	}
	var logsResp struct {
		Logs []module.IntervalChangeLogDTO `json:"logs"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &logsResp)
	if len(logsResp.Logs) != 2 {
		t.Fatalf("expected 2 interval change logs, got %d", len(logsResp.Logs))
	}

	// 10. Manager A1 revokes installer Tech T1's access -> Tech T1 immediately loses view and edit access
	rec = doJSON(http.MethodPut, "/api/v1/modules/"+modCreated.Module.ID+"/technicians/"+tech1Res.User.ID, mgrAAuth.AccessToken, map[string]any{
		"can_view": false,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 revoking installer Tech T1 access, got %d", rec.Code)
	}

	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID, tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for revoked installer Tech T1 on GET, got %d", rec.Code)
	}
	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+modCreated.Module.ID+"/configuration", tech1Auth.AccessToken, map[string]any{
		"panel_count": 10,
	})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for revoked installer Tech T1 on PATCH, got %d", rec.Code)
	}

	// Re-granting installer Tech T1 access restores installer editing privileges
	rec = doJSON(http.MethodPut, "/api/v1/modules/"+modCreated.Module.ID+"/technicians/"+tech1Res.User.ID, mgrAAuth.AccessToken, map[string]any{
		"can_view": true,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 re-granting installer Tech T1 access, got %d", rec.Code)
	}
	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+modCreated.Module.ID+"/configuration", tech1Auth.AccessToken, map[string]any{
		"panel_count": 10,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 when re-granted installer Tech T1 edits panel_count, got %d: %s", rec.Code, rec.Body.String())
	}

	// 11. Manager cannot remove all responsible managers (minimum 1 required)
	rec = doJSON(http.MethodPut, "/api/v1/modules/"+modCreated.Module.ID+"/managers", mgrAAuth.AccessToken, map[string]any{
		"manager_ids": []string{},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 when setting empty manager_ids, got %d", rec.Code)
	}

	// 12. Cross-company isolation: Company B Manager cannot access Company A module
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID, mgrBAuth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 when Company B Manager requests Company A module, got %d", rec.Code)
	}

	// 13. Aditivo: Technician queries active company clients and links clients during module installation
	rec = doJSON(http.MethodGet, "/api/v1/modules/company-clients", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for technician getting company-clients, got %d: %s", rec.Code, rec.Body.String())
	}
	var clientOptsRes struct {
		Clients []struct {
			ID    string `json:"id"`
			Name  string `json:"name"`
			Email string `json:"email"`
		} `json:"clients"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &clientOptsRes); err != nil {
		t.Fatalf("unmarshal client options: %v", err)
	}
	if len(clientOptsRes.Clients) == 0 {
		t.Fatalf("expected at least 1 client in company A, got 0")
	}

	// Technician creates a new module and links Client 1 directly during installation
	rec = doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":        "Array Omega",
		"mac_address": "AA:BB:CC:DD:EE:02",
		"manager_ids": []string{compA.DefaultManager.ID},
		"client_ids":  []string{client1Res.User.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 creating module with client_ids, got %d: %s", rec.Code, rec.Body.String())
	}
	var modWithClient struct {
		Module struct {
			ID               string `json:"id"`
			MonitoringStatus string `json:"monitoring_status"`
		} `json:"module"`
		CompanyClients []struct {
			ID         string `json:"id"`
			IsAssigned bool   `json:"is_assigned"`
		} `json:"company_clients"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &modWithClient); err != nil {
		t.Fatalf("unmarshal module with client: %v", err)
	}
	if modWithClient.Module.MonitoringStatus != "pending_configuration" {
		t.Fatalf("expected pending_configuration, got %s", modWithClient.Module.MonitoringStatus)
	}

	// Client 1 can now immediately see this module
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modWithClient.Module.ID, client1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for Client 1 accessing newly linked module, got %d", rec.Code)
	}

	// Technician updates draft module to change client_ids
	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+modWithClient.Module.ID+"/configuration", tech1Auth.AccessToken, map[string]any{
		"client_ids": []string{},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 updating client_ids on pending_configuration module, got %d: %s", rec.Code, rec.Body.String())
	}

	// Cross-company client link rejected
	rec = doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":        "Array Zeta",
		"mac_address": "AA:BB:CC:DD:EE:03",
		"manager_ids": []string{compA.DefaultManager.ID},
		"client_ids":  []string{compB.DefaultManager.ID}, // Not a client of company A
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 when linking invalid client, got %d", rec.Code)
	}

	// 14. Aditivo de negócio: Exclusão de módulos e cadastros
	// A) Módulo com operações pendentes não pode ser excluído nem por Manager (409 MODULE_HAS_PENDING_OPERATIONS)
	var pendingInspID string
	err = tx.QueryRow(ctx, "INSERT INTO inspections (module_id, type, scheduled_for, status) VALUES ($1, 'scheduled', NOW(), 'scheduled') RETURNING id", modCreated.Module.ID).Scan(&pendingInspID)
	if err != nil {
		t.Fatalf("failed to insert pending inspection: %v", err)
	}

	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+modCreated.Module.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 when deleting module with pending operations, got %d: %s", rec.Code, rec.Body.String())
	}
	var errPendingResp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &errPendingResp)
	if errPendingResp["code"] != "MODULE_HAS_PENDING_OPERATIONS" {
		t.Fatalf("expected error code MODULE_HAS_PENDING_OPERATIONS, got %v", errPendingResp["code"])
	}

	// Remove pending inspection so module no longer has pending operations
	if _, err := tx.Exec(ctx, "DELETE FROM inspections WHERE id = $1", pendingInspID); err != nil {
		t.Fatalf("failed to delete pending inspection: %v", err)
	}

	// B) Módulo elegível sem histórico operacional (modWithClient):
	// Client não pode excluir (403)
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+modWithClient.Module.ID, client1Auth.AccessToken, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when Client tries to delete module, got %d", rec.Code)
	}

	// Técnico com acesso compartilhado (Tech 2) não pode excluir (403)
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+modWithClient.Module.ID, tech2Auth.AccessToken, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when Shared Technician tries to delete module, got %d", rec.Code)
	}

	// Usuário de outra empresa não pode excluir (404 / isolamento de tenant)
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+modWithClient.Module.ID, mgrBAuth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 when user from Company B tries to delete Company A module, got %d", rec.Code)
	}

	// Técnico instalador com acesso efetivo (Tech 1) pode excluir com sucesso (204)
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+modWithClient.Module.ID, tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204 when installer technician deletes eligible module, got %d: %s", rec.Code, rec.Body.String())
	}

	// Confirmar que o módulo foi realmente removido
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modWithClient.Module.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 after module was deleted, got %d", rec.Code)
	}

	// C) Manager exclui módulo elegível criado por engano:
	rec = doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":        "Accidental Module",
		"mac_address": "11:22:33:44:55:66",
		"manager_ids": []string{compA.DefaultManager.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 creating accidental module, got %d: %s", rec.Code, rec.Body.String())
	}
	var accMod struct {
		Module struct {
			ID string `json:"id"`
		} `json:"module"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &accMod)

	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+accMod.Module.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204 when manager deletes eligible module, got %d: %s", rec.Code, rec.Body.String())
	}

	// D) Exclusão de usuários:
	// Technician que instalou módulo (Tech 1 é instalador de modCreated) não pode ser excluído (409)
	rec = doJSON(http.MethodDelete, "/api/v1/users/"+tech1Res.User.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 when deleting technician with installed modules, got %d: %s", rec.Code, rec.Body.String())
	}

	// Manager tenta excluir outro Manager (403)
	rec = doJSON(http.MethodDelete, "/api/v1/users/"+compA.DefaultManager.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when deleting a manager, got %d", rec.Code)
	}

	// Manager exclui Client elegível sem histórico operacional (204)
	rec = doJSON(http.MethodPost, "/api/v1/users", mgrAAuth.AccessToken, map[string]any{
		"name":  "Disposable Client",
		"email": "disposable.client@company-a.local",
		"role":  auth.RoleClient,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 creating disposable client, got %d: %s", rec.Code, rec.Body.String())
	}
	var dispClient struct {
		User struct {
			ID string `json:"id"`
		} `json:"user"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &dispClient)

	rec = doJSON(http.MethodDelete, "/api/v1/users/"+dispClient.User.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204 deleting eligible client, got %d: %s", rec.Code, rec.Body.String())
	}

	// Confirmar que o usuário foi deletado
	rec = doJSON(http.MethodGet, "/api/v1/users/"+dispClient.User.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 after client was deleted, got %d", rec.Code)
	}

	// Test telemetry read endpoints (SCR-11, SCR-12)
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/measurements", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 listing measurements, got %d: %s", rec.Code, rec.Body.String())
	}
	var measResp struct {
		Measurements []any `json:"measurements"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &measResp); err != nil {
		t.Fatalf("failed to decode measurements response: %v", err)
	}
	if len(measResp.Measurements) != 0 {
		t.Fatalf("expected 0 initial measurements, got %d", len(measResp.Measurements))
	}

	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/cleanings", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 listing cleanings, got %d: %s", rec.Code, rec.Body.String())
	}
	var cleanResp struct {
		Cleanings []any `json:"cleanings"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &cleanResp); err != nil {
		t.Fatalf("failed to decode cleanings response: %v", err)
	}
	if len(cleanResp.Cleanings) != 0 {
		t.Fatalf("expected 0 initial cleanings, got %d", len(cleanResp.Cleanings))
	}

	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/latest-inspection", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 getting latest inspection, got %d: %s", rec.Code, rec.Body.String())
	}

	// Test device status handshake
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/device-status", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 getting device status, got %d: %s", rec.Code, rec.Body.String())
	}
	var devStatus struct {
		DeviceStatus struct {
			ModuleID         string `json:"module_id"`
			MACAddress       string `json:"mac_address"`
			MonitoringStatus string `json:"monitoring_status"`
			IsConfigured     bool   `json:"is_configured"`
			IsOnline         bool   `json:"is_online"`
		} `json:"device_status"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &devStatus); err != nil {
		t.Fatalf("failed to decode device status: %v", err)
	}
	if devStatus.DeviceStatus.MACAddress != "aa:bb:cc:dd:ee:01" {
		t.Fatalf("expected MAC aa:bb:cc:dd:ee:01, got %q", devStatus.DeviceStatus.MACAddress)
	}

	// Test device ping handshake simulation
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/device-ping", tech1Auth.AccessToken, map[string]any{
		"water_available": true,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 recording device ping, got %d: %s", rec.Code, rec.Body.String())
	}
	var devPingResp struct {
		DeviceStatus struct {
			IsOnline       bool   `json:"is_online"`
			WaterStatus    string `json:"water_status"`
			WaterAvailable *bool  `json:"water_available"`
		} `json:"device_status"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &devPingResp); err != nil {
		t.Fatalf("failed to decode device ping response: %v", err)
	}
	if !devPingResp.DeviceStatus.IsOnline {
		t.Fatalf("expected device to be online after ping")
	}
	if devPingResp.DeviceStatus.WaterStatus != "available" {
		t.Fatalf("expected waterStatus 'available', got %q", devPingResp.DeviceStatus.WaterStatus)
	}

	testFrame768 := func(baseline, hotspot float64) []float64 {
		f := make([]float64, 32*24)
		for i := range f {
			f[i] = baseline
		}
		if hotspot > baseline {
			f[12*32+16] = hotspot
			f[12*32+17] = hotspot - 1.2
			f[13*32+16] = hotspot - 2.0
		}
		return f
	}

	// Test telemetry ingestion with authentic 768-float matrix
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/telemetry", tech1Auth.AccessToken, map[string]any{
		"x_position_cm":          25.5,
		"max_temperature_c":      52.0,
		"hotspot_detected":      true,
		"voltage_v":              18.4,
		"current_a":              4.2,
		"thermal_frame":          testFrame768(35.0, 52.0),
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 ingesting telemetry, got %d: %s", rec.Code, rec.Body.String())
	}

	// Test chunked batch upload (<= 10 frames) with inspection_source_event_id
	inspSourceID := "d4e28639-6548-436f-b4df-b62a6bca2350"
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/telemetry", tech1Auth.AccessToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"batch": []map[string]any{
			{"source_event_id": "00000000-0000-0000-0000-000000000001", "x_position_cm": 0.0, "max_temperature_c": 37.0, "hotspot_detected": false, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": testFrame768(35.0, 37.0)},
			{"source_event_id": "00000000-0000-0000-0000-000000000002", "x_position_cm": 2.0, "max_temperature_c": 38.0, "hotspot_detected": false, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": testFrame768(35.0, 38.0)},
			{"source_event_id": "00000000-0000-0000-0000-000000000003", "x_position_cm": 4.0, "max_temperature_c": 56.5, "hotspot_detected": true, "voltage_v": 18.2, "current_a": 4.0, "thermal_frame": testFrame768(35.0, 56.5)},
			{"source_event_id": "00000000-0000-0000-0000-000000000004", "x_position_cm": 6.0, "max_temperature_c": 55.0, "hotspot_detected": true, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": testFrame768(35.0, 55.0)},
		},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 ingesting batch telemetry, got %d: %s", rec.Code, rec.Body.String())
	}

	// Finalize inspection with baseline and confirmed hotspot
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/inspections/"+inspSourceID+"/finalize", tech1Auth.AccessToken, map[string]any{
		"baseline_temperature_c": 35.0,
		"confirmed_hotspots": []map[string]any{
			{
				"source_event_id":            "00000000-0000-0000-0000-000000000099",
				"global_x_position_cm":        4.5,
				"max_temperature_c":           56.5,
				"origin_measurement_event_id": "00000000-0000-0000-0000-000000000003",
				"confirming_event_ids":        []string{"00000000-0000-0000-0000-000000000003", "00000000-0000-0000-0000-000000000004"},
			},
		},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 finalizing inspection, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify latest inspection returns baseline and confirmed anomalies
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/latest-inspection", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 getting latest inspection, got %d: %s", rec.Code, rec.Body.String())
	}
	var latestResp struct {
		LatestInspection struct {
			Inspection struct {
				ID                   string   `json:"id"`
				BaselineTemperatureC *float64 `json:"baseline_temperature_c"`
				Status               string   `json:"status"`
			} `json:"inspection"`
			TotalMeasurements  int64 `json:"total_measurements"`
			ConfirmedAnomalies []any `json:"confirmed_anomalies"`
		} `json:"latest_inspection"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &latestResp); err != nil {
		t.Fatalf("failed to decode latest inspection: %v", err)
	}
	if latestResp.LatestInspection.Inspection.BaselineTemperatureC == nil || *latestResp.LatestInspection.Inspection.BaselineTemperatureC != 35.0 {
		t.Fatalf("expected baseline 35.0, got %v", latestResp.LatestInspection.Inspection.BaselineTemperatureC)
	}
	if len(latestResp.LatestInspection.ConfirmedAnomalies) != 1 {
		t.Fatalf("expected 1 confirmed anomaly, got %d", len(latestResp.LatestInspection.ConfirmedAnomalies))
	}

	// Query paginated measurements ordered by x_position_cm ASC
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/inspections/"+latestResp.LatestInspection.Inspection.ID+"/measurements?page=1&limit=2", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 getting paged measurements, got %d: %s", rec.Code, rec.Body.String())
	}
	var pagedResp struct {
		Pagination struct {
			Page        int   `json:"page"`
			Limit       int   `json:"limit"`
			TotalCount  int64 `json:"total_count"`
			TotalPages  int   `json:"total_pages"`
			HasNextPage bool  `json:"has_next_page"`
		} `json:"pagination"`
		Measurements []any `json:"measurements"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &pagedResp); err != nil {
		t.Fatalf("failed to decode paged measurements: %v", err)
	}
	if pagedResp.Pagination.TotalCount != 4 || len(pagedResp.Measurements) != 2 || !pagedResp.Pagination.HasNextPage {
		t.Fatalf("expected 4 total, 2 items, has_next_page=true, got %+v", pagedResp.Pagination)
	}

	// Test cleaning operation ingestion with pump actuated -> post_cleaning_result is pending and anomaly remains open!
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/cleanings", tech1Auth.AccessToken, map[string]any{
		"target_x_position_cm":      4.5,
		"pump_actuated":             true,
		"attempt_number":            1,
		"duration_seconds":          42.0,
		"estimated_water_volume_ml": 85.0,
		"status":                    "completed",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 ingesting cleaning, got %d: %s", rec.Code, rec.Body.String())
	}
	var cleanCreatedResp struct {
		Cleaning module.CleaningDTO `json:"cleaning"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &cleanCreatedResp); err != nil {
		t.Fatalf("unmarshal cleaning: %v", err)
	}
	if cleanCreatedResp.Cleaning.PostCleaningResult != "pending" {
		t.Fatalf("expected post_cleaning_result 'pending', got %q", cleanCreatedResp.Cleaning.PostCleaningResult)
	}

	// Test verification inspection referencing the cleaning operation
	verifInspSourceID := "e5f39740-7659-5470-c5ef-c73b7cda3461"
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/telemetry", tech1Auth.AccessToken, map[string]any{
		"inspection_source_event_id": verifInspSourceID,
		"inspection_type":           "verification",
		"cleaning_operation_id":     cleanCreatedResp.Cleaning.ID,
		"batch": []map[string]any{
			{"source_event_id": "00000000-0000-0000-0000-000000000011", "x_position_cm": 3.0, "max_temperature_c": 36.0, "hotspot_detected": false, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": testFrame768(35.0, 36.0)},
			{"source_event_id": "00000000-0000-0000-0000-000000000012", "x_position_cm": 5.0, "max_temperature_c": 36.5, "hotspot_detected": false, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": testFrame768(35.0, 36.5)},
		},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 ingesting verification telemetry, got %d: %s", rec.Code, rec.Body.String())
	}

	// Finalize verification inspection with empty confirmed_hotspots (hotspot resolved!)
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/inspections/"+verifInspSourceID+"/finalize", tech1Auth.AccessToken, map[string]any{
		"baseline_temperature_c": 35.0,
		"confirmed_hotspots":     []map[string]any{},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 finalizing verification inspection, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify verification inspection was completed with resolved result
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/latest-inspection", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 getting latest inspection, got %d: %s", rec.Code, rec.Body.String())
	}
	var verifLatestResp struct {
		LatestInspection struct {
			Inspection struct {
				ID                 string  `json:"id"`
				Type               string  `json:"type"`
				Status             string  `json:"status"`
				VerificationResult *string `json:"verification_result"`
			} `json:"inspection"`
		} `json:"latest_inspection"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &verifLatestResp); err != nil {
		t.Fatalf("decode verif latest inspection: %v", err)
	}
	if verifLatestResp.LatestInspection.Inspection.Type != "verification" || verifLatestResp.LatestInspection.Inspection.VerificationResult == nil || *verifLatestResp.LatestInspection.Inspection.VerificationResult != "resolved" {
		t.Fatalf("expected verification resolved, got %+v", verifLatestResp.LatestInspection.Inspection)
	}

	// Test Opção B: ESP32 Hardware Claim and direct device_token authentication
	rec = doJSON(http.MethodPost, "/api/v1/devices/claim", "", map[string]any{
		"mac_address":           devStatus.DeviceStatus.MACAddress,
		"firmware_version":      "v1.4.2",
		"water_available":       true,
		"limits_check_passed":   true,
		"thermal_sensor_active": true,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 claiming device, got %d: %s", rec.Code, rec.Body.String())
	}
	var claimResp struct {
		ModuleID            string `json:"module_id"`
		DeviceToken         string `json:"device_token"`
		Status              string `json:"status"`
		PingIntervalSeconds int    `json:"ping_interval_seconds"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &claimResp); err != nil {
		t.Fatalf("failed to decode claim response: %v", err)
	}
	if claimResp.DeviceToken == "" || !strings.HasPrefix(claimResp.DeviceToken, "dev_sec_") {
		t.Fatalf("expected valid device_token starting with dev_sec_, got %q", claimResp.DeviceToken)
	}
	if claimResp.PingIntervalSeconds != 300 {
		t.Fatalf("expected ping_interval_seconds 300, got %d", claimResp.PingIntervalSeconds)
	}

	// Test dedicated device route POST /api/v1/devices/{id}/ping
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/ping", claimResp.DeviceToken, map[string]any{
		"water_available":       true,
		"limits_check_passed":   true,
		"thermal_sensor_active": true,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 pinging device via /devices/{id}/ping, got %d: %s", rec.Code, rec.Body.String())
	}

	// Test GET /api/v1/devices/{id}/configuration with device_token
	rec = doJSON(http.MethodGet, "/api/v1/devices/"+claimResp.ModuleID+"/configuration", claimResp.DeviceToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 getting device configuration, got %d: %s", rec.Code, rec.Body.String())
	}
	var devCfgResp struct {
		ConfigVersion       int32   `json:"config_version"`
		MinSolarAngle       float64 `json:"min_solar_angle"`
		IntervalDays        int32   `json:"interval_days"`
		PingIntervalSeconds int     `json:"ping_interval_seconds"`
		Geometry            struct {
			PanelLengthCm  float64 `json:"panel_length_cm"`
			PanelWidthCm   float64 `json:"panel_width_cm"`
			PanelCount     int32   `json:"panel_count"`
			PanelSpacingCm float64 `json:"panel_spacing_cm"`
		} `json:"geometry"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &devCfgResp); err != nil {
		t.Fatalf("failed to decode device configuration response: %v", err)
	}
	initialVer := devCfgResp.ConfigVersion
	if initialVer < 1 {
		t.Fatalf("expected positive config_version, got %d", initialVer)
	}
	if devCfgResp.PingIntervalSeconds != 300 {
		t.Fatalf("expected ping_interval_seconds 300, got %d", devCfgResp.PingIntervalSeconds)
	}
	if devCfgResp.Geometry.PanelCount != 10 {
		t.Fatalf("expected panel_count 10, got %d", devCfgResp.Geometry.PanelCount)
	}

	// Test POST /api/v1/devices/{id}/configuration/ack with STALE config version -> 409 Conflict
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/configuration/ack", claimResp.DeviceToken, map[string]any{
		"config_version": initialVer + 99,
		"applied":        true,
		"checksum":       "abc123",
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict for stale config_version, got %d: %s", rec.Code, rec.Body.String())
	}

	// Test POST /api/v1/devices/{id}/configuration/ack reporting failure -> 200 OK with failed state
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/configuration/ack", claimResp.DeviceToken, map[string]any{
		"config_version": initialVer,
		"applied":        false,
		"checksum":       "abc123",
		"error":          "NVS write timeout",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 acking failed config, got %d: %s", rec.Code, rec.Body.String())
	}
	var failAckResp struct {
		ConfigurationSync struct {
			State            string  `json:"state"`
			ConfigVersion    int32   `json:"config_version"`
			ConfigApplyError *string `json:"config_apply_error"`
		} `json:"configuration_sync"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &failAckResp); err != nil {
		t.Fatalf("failed to decode fail ack response: %v", err)
	}
	if failAckResp.ConfigurationSync.State != "failed" {
		t.Fatalf("expected state failed, got %q", failAckResp.ConfigurationSync.State)
	}
	if failAckResp.ConfigurationSync.ConfigApplyError == nil || *failAckResp.ConfigurationSync.ConfigApplyError != "NVS write timeout" {
		t.Fatalf("expected apply error 'NVS write timeout', got %+v", failAckResp.ConfigurationSync.ConfigApplyError)
	}

	// Test POST /api/v1/devices/{id}/configuration/ack reporting success -> 200 OK with synced state
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/configuration/ack", claimResp.DeviceToken, map[string]any{
		"config_version": initialVer,
		"applied":        true,
		"checksum":       "sha256_mock_1",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 acking successful config, got %d: %s", rec.Code, rec.Body.String())
	}
	var successAckResp struct {
		ConfigurationSync struct {
			State                string  `json:"state"`
			ConfigVersion        int32   `json:"config_version"`
			ConfigAppliedVersion int32   `json:"config_applied_version"`
			ConfigAppliedAt      *string `json:"config_applied_at"`
			ConfigApplyError     *string `json:"config_apply_error"`
		} `json:"configuration_sync"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &successAckResp); err != nil {
		t.Fatalf("failed to decode success ack response: %v", err)
	}
	if successAckResp.ConfigurationSync.State != "synced" {
		t.Fatalf("expected state synced, got %q", successAckResp.ConfigurationSync.State)
	}
	if successAckResp.ConfigurationSync.ConfigAppliedVersion != initialVer || successAckResp.ConfigurationSync.ConfigAppliedAt == nil {
		t.Fatalf("expected applied_version %d and non-nil applied_at, got %+v", initialVer, successAckResp.ConfigurationSync)
	}

	// Verify device status endpoint reflects synced configuration
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+claimResp.ModuleID+"/device-status", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 getting device status, got %d: %s", rec.Code, rec.Body.String())
	}
	var devStatusCheck struct {
		DeviceStatus struct {
			IsOnline            bool `json:"is_online"`
			PingIntervalSeconds int  `json:"ping_interval_seconds"`
			OnlineWindowSeconds int  `json:"online_window_seconds"`
			ConfigurationSync   struct {
				State string `json:"state"`
			} `json:"configuration_sync"`
		} `json:"device_status"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &devStatusCheck); err != nil {
		t.Fatalf("failed to decode dev status check: %v", err)
	}
	if devStatusCheck.DeviceStatus.ConfigurationSync.State != "synced" {
		t.Fatalf("expected device status sync state synced, got %q", devStatusCheck.DeviceStatus.ConfigurationSync.State)
	}
	if devStatusCheck.DeviceStatus.PingIntervalSeconds != 300 || devStatusCheck.DeviceStatus.OnlineWindowSeconds != 900 {
		t.Fatalf("expected ping 300 and online window 900, got %d / %d", devStatusCheck.DeviceStatus.PingIntervalSeconds, devStatusCheck.DeviceStatus.OnlineWindowSeconds)
	}

	// Update module configuration via PATCH -> increments config_version to initialVer+1 and resets state to pending
	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+claimResp.ModuleID+"/configuration", tech1Auth.AccessToken, map[string]any{
		"panel_count": 14,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 updating configuration, got %d: %s", rec.Code, rec.Body.String())
	}
	var patchResp struct {
		ConfigurationSync struct {
			State         string `json:"state"`
			ConfigVersion int32  `json:"config_version"`
		} `json:"configuration_sync"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &patchResp); err != nil {
		t.Fatalf("failed to decode patch response: %v", err)
	}
	expectedNextVer := initialVer + 1
	if patchResp.ConfigurationSync.ConfigVersion != expectedNextVer {
		t.Fatalf("expected config_version %d after update, got %d", expectedNextVer, patchResp.ConfigurationSync.ConfigVersion)
	}
	if patchResp.ConfigurationSync.State != "pending" {
		t.Fatalf("expected sync state pending after update, got %q", patchResp.ConfigurationSync.State)
	}

	// Device fetches updated configuration
	rec = doJSON(http.MethodGet, "/api/v1/devices/"+claimResp.ModuleID+"/configuration", claimResp.DeviceToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 fetching updated config, got %d: %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &devCfgResp); err != nil {
		t.Fatalf("failed to decode dev cfg: %v", err)
	}
	if devCfgResp.ConfigVersion != expectedNextVer || devCfgResp.Geometry.PanelCount != 14 {
		t.Fatalf("expected config_version %d and panel_count 14, got v=%d count=%d", expectedNextVer, devCfgResp.ConfigVersion, devCfgResp.Geometry.PanelCount)
	}

	// Device acks next version
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/configuration/ack", claimResp.DeviceToken, map[string]any{
		"config_version": expectedNextVer,
		"applied":        true,
		"checksum":       "sha256_mock_2",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 acking v2 config, got %d: %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &successAckResp); err != nil {
		t.Fatalf("failed to decode success ack: %v", err)
	}
	if successAckResp.ConfigurationSync.State != "synced" || successAckResp.ConfigurationSync.ConfigAppliedVersion != expectedNextVer {
		t.Fatalf("expected synced v%d, got %+v", expectedNextVer, successAckResp.ConfigurationSync)
	}

	// Test telemetry and inspection finalizing an open anomaly using ONLY device_token via dedicated routes
	insp2SourceID := "a1b2c3d4-e5f6-47a8-b9c0-d1e2f3a4b5c6"
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/telemetry", claimResp.DeviceToken, map[string]any{
		"inspection_source_event_id": insp2SourceID,
		"batch": []map[string]any{
			{"source_event_id": "00000000-0000-0000-0000-000000000021", "x_position_cm": 10.0, "max_temperature_c": 50.0, "hotspot_detected": true, "voltage_v": 18.6, "current_a": 4.3, "thermal_frame": testFrame768(36.0, 50.0)},
			{"source_event_id": "00000000-0000-0000-0000-000000000022", "x_position_cm": 12.0, "max_temperature_c": 52.0, "hotspot_detected": true, "voltage_v": 18.6, "current_a": 4.3, "thermal_frame": testFrame768(36.0, 52.0)},
		},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 ingesting telemetry with device_token, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/inspections/"+insp2SourceID+"/finalize", claimResp.DeviceToken, map[string]any{
		"baseline_temperature_c": 36.0,
		"confirmed_hotspots": []map[string]any{
			{
				"source_event_id":            "00000000-0000-0000-0000-000000000098",
				"global_x_position_cm":        12.0,
				"max_temperature_c":           52.0,
				"origin_measurement_event_id": "00000000-0000-0000-0000-000000000021",
				"confirming_event_ids":        []string{"00000000-0000-0000-0000-000000000021", "00000000-0000-0000-0000-000000000022"},
			},
		},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 finalizing inspection via device_token, got %d: %s", rec.Code, rec.Body.String())
	}

	// Test cleaning ingestion using ONLY device_token via dedicated /devices/{id}/cleanings
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/cleanings", claimResp.DeviceToken, map[string]any{
		"target_x_position_cm": 12.0,
		"pump_actuated":        false,
		"status":               "refused",
		"post_cleaning_result": "unresolved",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 ingesting cleaning with device_token, got %d: %s", rec.Code, rec.Body.String())
	}

	// Test GET /api/v1/alerts returns real alerts from open anomalies
	rec = doJSON(http.MethodGet, "/api/v1/alerts", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 listing alerts, got %d: %s", rec.Code, rec.Body.String())
	}
	var alertsResp struct {
		Total    int `json:"total"`
		Critical int `json:"critical"`
		Warning  int `json:"warning"`
		Alerts   []struct {
			ID       string `json:"id"`
			Severity string `json:"severity"`
			Type     string `json:"type"`
		} `json:"alerts"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &alertsResp); err != nil {
		t.Fatalf("failed to decode alerts response: %v", err)
	}
	if alertsResp.Total == 0 {
		t.Fatalf("expected active alerts from open anomaly, got 0")
	}
}

func TestModuleDefinitiveDeletionRedesign(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, testDBURL())
	if err != nil {
		t.Skipf("PostgreSQL pool not reachable for integration test: %v", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		t.Skipf("PostgreSQL ping failed: %v", err)
	}

	t.Cleanup(func() {
		cleanCtx := context.Background()
		conn, err := pool.Acquire(cleanCtx)
		if err == nil {
			_, _ = conn.Exec(cleanCtx, "SET session_replication_role = 'replica'")
			_, _ = conn.Exec(cleanCtx, `DO $$
			DECLARE
				r RECORD;
			BEGIN
				FOR r IN (SELECT id FROM companies WHERE name LIKE 'Solar Del Redesign%') LOOP
					DELETE FROM notifications WHERE company_id = r.id;
					DELETE FROM reservoir_readings WHERE module_id IN (SELECT id FROM modules WHERE company_id = r.id);
					DELETE FROM cleaning_operations WHERE module_id IN (SELECT id FROM modules WHERE company_id = r.id);
					DELETE FROM anomaly_events WHERE module_id IN (SELECT id FROM modules WHERE company_id = r.id);
					DELETE FROM measurements WHERE module_id IN (SELECT id FROM modules WHERE company_id = r.id);
					DELETE FROM inspections WHERE module_id IN (SELECT id FROM modules WHERE company_id = r.id);
					DELETE FROM interval_change_logs WHERE company_id = r.id;
					DELETE FROM module_managers WHERE company_id = r.id;
					DELETE FROM module_technicians WHERE company_id = r.id;
					DELETE FROM module_clients WHERE company_id = r.id;
					DELETE FROM modules WHERE company_id = r.id;
					DELETE FROM technician_managers WHERE company_id = r.id;
					DELETE FROM auth_sessions WHERE user_id IN (SELECT id FROM users WHERE company_id = r.id);
					DELETE FROM users WHERE company_id = r.id;
					DELETE FROM companies WHERE id = r.id;
				END LOOP;
			END $$;`)
			_, _ = conn.Exec(cleanCtx, "DELETE FROM auth_sessions WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'sysadmin.delredesign%')")
			_, _ = conn.Exec(cleanCtx, "DELETE FROM users WHERE email LIKE 'sysadmin.delredesign%'")
			_, _ = conn.Exec(cleanCtx, "SET session_replication_role = 'origin'")
			conn.Release()
		}
		pool.Close()
	})

	tokens := auth.NewTokenManager("module-deletion-redesign-secret-2026")
	q := db.New(pool)

	adminPass := "AdminPass#2026"
	adminHash, err := auth.HashPassword(adminPass)
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	nano := time.Now().UnixNano()
	adminEmail := fmt.Sprintf("sysadmin.delredesign.%d@thermoscan.local", nano)
	if _, err := q.CreateUser(ctx, db.CreateUserParams{
		CompanyID:          pgtype.UUID{Valid: false},
		Name:               "System Admin DelRedesign",
		Email:              adminEmail,
		PasswordHash:       adminHash,
		Role:               auth.RoleSystemAdmin,
		IsActive:           true,
		IsDefaultManager:   false,
		MustChangePassword: false,
	}); err != nil {
		t.Fatalf("CreateUser (system_admin): %v", err)
	}

	router := httpapi.NewRouter(httpapi.Dependencies{
		AuthHandler:    auth.NewHandler(auth.NewService(pool, tokens), q, tokens),
		CompanyHandler: company.NewHandler(company.NewService(pool), q, tokens),
		UserHandler:    user.NewHandler(user.NewService(pool), q, tokens),
		ModuleHandler:  module.NewHandler(module.NewService(pool), q, tokens),
	})

	doJSON := func(method, path, bearer string, body any) *httptest.ResponseRecorder {
		var buf bytes.Buffer
		if body != nil {
			if err := json.NewEncoder(&buf).Encode(body); err != nil {
				t.Fatalf("encode body: %v", err)
			}
		}
		req := httptest.NewRequest(method, path, &buf)
		req.Header.Set("Content-Type", "application/json")
		if bearer != "" {
			req.Header.Set("Authorization", "Bearer "+bearer)
		}
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		return rec
	}

	loginAndActivate := func(email, tempPass, newPass string) auth.AuthResponse {
		rec := doJSON(http.MethodPost, "/api/v1/auth/login", "", map[string]string{
			"email":    email,
			"password": tempPass,
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("login(%s) failed (%d): %s", email, rec.Code, rec.Body.String())
		}
		var resp auth.AuthResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("decode login: %v", err)
		}
		if resp.User.MustChangePassword {
			rec = doJSON(http.MethodPost, "/api/v1/auth/change-password", resp.AccessToken, map[string]string{
				"current_password": tempPass,
				"new_password":     newPass,
			})
			if rec.Code != http.StatusOK {
				t.Fatalf("change-password(%s) failed (%d): %s", email, rec.Code, rec.Body.String())
			}
			rec = doJSON(http.MethodPost, "/api/v1/auth/login", "", map[string]string{
				"email":    email,
				"password": newPass,
			})
			if rec.Code != http.StatusOK {
				t.Fatalf("re-login(%s) failed (%d): %s", email, rec.Code, rec.Body.String())
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
				t.Fatalf("decode re-login: %v", err)
			}
		}
		return resp
	}

	adminAuth := loginAndActivate(adminEmail, adminPass, adminPass)

	// Create Company A
	compAName := fmt.Sprintf("Solar Del Redesign A %d", nano)
	compAEmail := fmt.Sprintf("manager.del.a.%d@thermoscan.local", nano)
	compAResp := doJSON(http.MethodPost, "/api/v1/companies", adminAuth.AccessToken, map[string]string{
		"name":          compAName,
		"manager_name":  "Manager Del A",
		"manager_email": compAEmail,
	})
	if compAResp.Code != http.StatusCreated {
		t.Fatalf("create company A: %d: %s", compAResp.Code, compAResp.Body.String())
	}
	var compA company.CreateCompanyResult
	_ = json.Unmarshal(compAResp.Body.Bytes(), &compA)

	// Create Company B for cross-tenant tests
	compBName := fmt.Sprintf("Solar Del Redesign B %d", nano)
	compBEmail := fmt.Sprintf("manager.del.b.%d@thermoscan.local", nano)
	compBResp := doJSON(http.MethodPost, "/api/v1/companies", adminAuth.AccessToken, map[string]string{
		"name":          compBName,
		"manager_name":  "Manager Del B",
		"manager_email": compBEmail,
	})
	if compBResp.Code != http.StatusCreated {
		t.Fatalf("create company B: %d: %s", compBResp.Code, compBResp.Body.String())
	}
	var compB company.CreateCompanyResult
	_ = json.Unmarshal(compBResp.Body.Bytes(), &compB)

	t.Cleanup(func() {
		cleanCtx, cleanCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cleanCancel()
		_, _ = pool.Exec(cleanCtx, "DELETE FROM companies WHERE id IN ($1, $2)", compA.Company.ID, compB.Company.ID)
		_, _ = pool.Exec(cleanCtx, "DELETE FROM users WHERE email = $1", adminEmail)
	})

	mgrAAuth := loginAndActivate(compA.DefaultManager.Email, compA.TemporaryPassword, "ManagerPass#2026")
	mgrBAuth := loginAndActivate(compB.DefaultManager.Email, compB.TemporaryPassword, "ManagerPass#2026")

	// Create Technician 1 (installer) and Technician 2 (shared) in Company A
	createTech := func(name, email string) auth.AuthResponse {
		rec := doJSON(http.MethodPost, "/api/v1/users", mgrAAuth.AccessToken, map[string]any{
			"name":        name,
			"email":       email,
			"role":        "technician",
			"manager_ids": []string{compA.DefaultManager.ID},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("create technician %s: %d: %s", email, rec.Code, rec.Body.String())
		}
		var userResp struct {
			User         struct{ ID, Email string } `json:"user"`
			TempPassword string                     `json:"temporary_password"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &userResp)
		return loginAndActivate(userResp.User.Email, userResp.TempPassword, "TechPass#2026")
	}

	tech1Email := fmt.Sprintf("tech1.del.%d@solardelredesigna.local", nano)
	tech2Email := fmt.Sprintf("tech2.del.%d@solardelredesigna.local", nano)
	tech1Auth := createTech("Tech 1 Del", tech1Email)
	tech2Auth := createTech("Tech 2 Del", tech2Email)

	_, err = pool.Exec(ctx, "INSERT INTO technician_managers (company_id, technician_id, manager_id) VALUES ($1, $2, $3), ($1, $4, $3) ON CONFLICT DO NOTHING",
		compA.Company.ID, tech1Auth.User.ID, compA.DefaultManager.ID, tech2Auth.User.ID)
	if err != nil {
		t.Fatalf("link tech managers: %v", err)
	}

	testFrame768 := func(baseline, hotspot float64) []float64 {
		f := make([]float64, 768)
		for i := range f {
			f[i] = baseline
		}
		f[384] = hotspot
		return f
	}

	mac1 := fmt.Sprintf("02:%02x:%02x:%02x:00:01", byte(nano>>24), byte(nano>>16), byte(nano>>8))
	mac2 := fmt.Sprintf("02:%02x:%02x:%02x:00:02", byte(nano>>24), byte(nano>>16), byte(nano>>8))
	mac3 := fmt.Sprintf("02:%02x:%02x:%02x:00:03", byte(nano>>24), byte(nano>>16), byte(nano>>8))
	mac4 := fmt.Sprintf("02:%02x:%02x:%02x:00:04", byte(nano>>24), byte(nano>>16), byte(nano>>8))
	mac5 := fmt.Sprintf("02:%02x:%02x:%02x:00:05", byte(nano>>24), byte(nano>>16), byte(nano>>8))

	// =========================================================================
	// 1. Technician installer deletes module without operational history
	//    even if it has interval_change_logs or periodic reservoir_readings
	// =========================================================================
	rec := doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":                          "Mod Without Operational History",
		"mac_address":                   mac1,
		"manager_ids":                   []string{compA.DefaultManager.ID},
		"inspection_interval_days":      7,
		"panel_length_cm":               100.0,
		"panel_width_cm":                50.0,
		"panel_count":                   10,
		"panel_spacing_cm":              2.0,
		"latitude":                      -23.5505,
		"longitude":                     -46.6333,
		"elevation_m":                   760.0,
		"azimuth_deg":                   0.0,
		"tilt_deg":                      15.0,
		"azimuth_source":                "manual",
		"tilt_source":                   "manual",
		"minimum_solar_angle_deg":       10.0,
		"reservoir_nominal_capacity_ml": 5000.0,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create mod 1: %d: %s", rec.Code, rec.Body.String())
	}
	var mod1 struct{ Module struct{ ID string `json:"id"` } `json:"module"` }
	_ = json.Unmarshal(rec.Body.Bytes(), &mod1)

	// Update configuration -> creates interval_change_logs
	rec = doJSON(http.MethodPatch, "/api/v1/modules/"+mod1.Module.ID+"/configuration", mgrAAuth.AccessToken, map[string]any{
		"inspection_interval_days": 14,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("patch mod 1 config: %d: %s", rec.Code, rec.Body.String())
	}

	// Claim device -> sets device_token & records handshake periodic reservoir_readings
	rec = doJSON(http.MethodPost, "/api/v1/devices/claim", "", map[string]any{
		"mac_address":     mac1,
		"water_available": true,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("claim mod 1: %d: %s", rec.Code, rec.Body.String())
	}
	var claimMod1 struct{ DeviceToken string `json:"device_token"` }
	_ = json.Unmarshal(rec.Body.Bytes(), &claimMod1)

	// Device pings -> records another reservoir reading
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+mod1.Module.ID+"/ping", claimMod1.DeviceToken, map[string]any{
		"water_available": true,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("ping mod 1: %d: %s", rec.Code, rec.Body.String())
	}

	// Verify that mod1 has interval_change_logs and reservoir_readings, but 0 measurements, 0 cleanings, 0 completed inspections, 0 anomalies
	var intvCount, resvCount, measCount, inspCount int
	_ = pool.QueryRow(ctx, "SELECT count(*) FROM interval_change_logs WHERE module_id = $1", mod1.Module.ID).Scan(&intvCount)
	_ = pool.QueryRow(ctx, "SELECT count(*) FROM reservoir_readings WHERE module_id = $1", mod1.Module.ID).Scan(&resvCount)
	_ = pool.QueryRow(ctx, "SELECT count(*) FROM measurements WHERE module_id = $1", mod1.Module.ID).Scan(&measCount)
	_ = pool.QueryRow(ctx, "SELECT count(*) FROM inspections WHERE module_id = $1", mod1.Module.ID).Scan(&inspCount)
	if intvCount == 0 || resvCount == 0 || measCount != 0 || inspCount != 0 {
		t.Fatalf("expected intv>0 and resv>0, but meas=0 and insp=0; got intv=%d resv=%d meas=%d insp=%d", intvCount, resvCount, measCount, inspCount)
	}

	// Technician Installer (Tech 1) can delete this module!
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+mod1.Module.ID, tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204 when installer deletes module with only interval logs and reservoir readings, got %d: %s", rec.Code, rec.Body.String())
	}

	// Confirm module and related rows are gone
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+mod1.Module.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 after module deletion, got %d", rec.Code)
	}
	_ = pool.QueryRow(ctx, "SELECT count(*) FROM interval_change_logs WHERE module_id = $1", mod1.Module.ID).Scan(&intvCount)
	_ = pool.QueryRow(ctx, "SELECT count(*) FROM reservoir_readings WHERE module_id = $1", mod1.Module.ID).Scan(&resvCount)
	if intvCount != 0 || resvCount != 0 {
		t.Fatalf("expected interval logs and reservoir readings deleted, got intv=%d, resv=%d", intvCount, resvCount)
	}

	// =========================================================================
	// 2. Technician installer CANNOT delete module with operational history (409 MODULE_HAS_HISTORY)
	// =========================================================================
	rec = doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":        "Mod With Operational History",
		"mac_address": mac2,
		"manager_ids": []string{compA.DefaultManager.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create mod 2: %d: %s", rec.Code, rec.Body.String())
	}
	var mod2 struct{ Module struct{ ID string `json:"id"` } `json:"module"` }
	_ = json.Unmarshal(rec.Body.Bytes(), &mod2)

	// Claim device
	rec = doJSON(http.MethodPost, "/api/v1/devices/claim", "", map[string]any{
		"mac_address": mac2,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("claim mod 2: %d: %s", rec.Code, rec.Body.String())
	}
	var claimMod2 struct{ DeviceToken string `json:"device_token"` }
	_ = json.Unmarshal(rec.Body.Bytes(), &claimMod2)

	// Ingest telemetry with batch and finalize inspection -> creates completed inspection, measurements, and confirmed anomaly
	delModInspSourceID := "b1c2d3e4-f5a6-47b8-89c0-d1e2f3a4b5c7"
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+mod2.Module.ID+"/telemetry", claimMod2.DeviceToken, map[string]any{
		"inspection_source_event_id": delModInspSourceID,
		"batch": []map[string]any{
			{"source_event_id": "00000000-0000-0000-0000-000000000051", "x_position_cm": 8.0, "max_temperature_c": 54.0, "hotspot_detected": true, "voltage_v": 18.0, "current_a": 4.0, "thermal_frame": testFrame768(35.0, 54.0)},
			{"source_event_id": "00000000-0000-0000-0000-000000000052", "x_position_cm": 10.0, "max_temperature_c": 55.0, "hotspot_detected": true, "voltage_v": 18.0, "current_a": 4.0, "thermal_frame": testFrame768(35.0, 55.0)},
		},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("ingest telemetry mod 2: %d: %s", rec.Code, rec.Body.String())
	}

	rec = doJSON(http.MethodPost, "/api/v1/devices/"+mod2.Module.ID+"/inspections/"+delModInspSourceID+"/finalize", claimMod2.DeviceToken, map[string]any{
		"baseline_temperature_c": 35.0,
		"confirmed_hotspots": []map[string]any{
			{
				"source_event_id":            "00000000-0000-0000-0000-000000000097",
				"global_x_position_cm":        10.0,
				"max_temperature_c":           55.0,
				"origin_measurement_event_id": "00000000-0000-0000-0000-000000000051",
				"confirming_event_ids":        []string{"00000000-0000-0000-0000-000000000051", "00000000-0000-0000-0000-000000000052"},
			},
		},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("finalize inspection mod 2: %d: %s", rec.Code, rec.Body.String())
	}

	// Tech 1 (installer) attempts to delete -> must fail with 409 MODULE_HAS_HISTORY
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+mod2.Module.ID, tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 when technician deletes module with operational history, got %d: %s", rec.Code, rec.Body.String())
	}
	var errHistResp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &errHistResp)
	if errHistResp["code"] != "MODULE_HAS_HISTORY" {
		t.Fatalf("expected code MODULE_HAS_HISTORY, got %v", errHistResp["code"])
	}

	// =========================================================================
	// 3. Pending operations block deletion (BOTH Manager and Technician with 409 MODULE_HAS_PENDING_OPERATIONS)
	// =========================================================================
	var pendingInspID string
	err = pool.QueryRow(ctx, "INSERT INTO inspections (module_id, type, scheduled_for, status) VALUES ($1, 'scheduled', NOW(), 'scheduled') RETURNING id", mod2.Module.ID).Scan(&pendingInspID)
	if err != nil {
		t.Fatalf("insert pending insp: %v", err)
	}

	// Manager cannot delete while pending inspection exists
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+mod2.Module.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 when manager deletes module with pending inspection, got %d: %s", rec.Code, rec.Body.String())
	}
	var pendingErrResp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &pendingErrResp)
	if pendingErrResp["code"] != "MODULE_HAS_PENDING_OPERATIONS" {
		t.Fatalf("expected MODULE_HAS_PENDING_OPERATIONS, got %v", pendingErrResp["code"])
	}

	// Technician cannot delete either
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+mod2.Module.ID, tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 when technician deletes module with pending inspection, got %d: %s", rec.Code, rec.Body.String())
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &pendingErrResp)
	if pendingErrResp["code"] != "MODULE_HAS_PENDING_OPERATIONS" {
		t.Fatalf("expected MODULE_HAS_PENDING_OPERATIONS, got %v", pendingErrResp["code"])
	}

	// Delete pending inspection
	_, _ = pool.Exec(ctx, "DELETE FROM inspections WHERE id = $1", pendingInspID)

	// Now insert in_progress cleaning on mod2
	var anomID string
	err = pool.QueryRow(ctx, "SELECT id FROM anomaly_events WHERE module_id = $1 LIMIT 1", mod2.Module.ID).Scan(&anomID)
	if err != nil {
		t.Fatalf("get anomaly: %v", err)
	}
	var pendingCleanID string
	err = pool.QueryRow(ctx, "INSERT INTO cleaning_operations (module_id, anomaly_event_id, source_event_id, target_x_position_cm, status, pump_actuated, attempt_number, started_at) VALUES ($1, $2, gen_random_uuid(), 10.0, 'in_progress', true, 1, NOW()) RETURNING id", mod2.Module.ID, anomID).Scan(&pendingCleanID)
	if err != nil {
		t.Fatalf("insert pending clean: %v", err)
	}

	// Manager cannot delete while cleaning in_progress
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+mod2.Module.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 when manager deletes module with in_progress cleaning, got %d: %s", rec.Code, rec.Body.String())
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &pendingErrResp)
	if pendingErrResp["code"] != "MODULE_HAS_PENDING_OPERATIONS" {
		t.Fatalf("expected MODULE_HAS_PENDING_OPERATIONS, got %v", pendingErrResp["code"])
	}

	// Complete cleaning operation
	_, err = pool.Exec(ctx, "UPDATE cleaning_operations SET status = 'completed', pump_actuated = true, attempt_number = 1, started_at = NOW() - interval '10s', ended_at = NOW(), duration_seconds = 10, estimated_water_volume_ml = 200 WHERE id = $1", pendingCleanID)
	if err != nil {
		t.Fatalf("complete cleaning: %v", err)
	}

	// =========================================================================
	// 4. Permissions checks: Revoked technician (403), Other company (404)
	// =========================================================================
	rec = doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":        "Mod For Access Revocation Test",
		"mac_address": mac3,
		"manager_ids": []string{compA.DefaultManager.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create mod 3: %d: %s", rec.Code, rec.Body.String())
	}
	var mod3 struct{ Module struct{ ID string `json:"id"` } `json:"module"` }
	_ = json.Unmarshal(rec.Body.Bytes(), &mod3)

	// Revoke Tech 1's view access on Mod 3
	rec = doJSON(http.MethodPut, "/api/v1/modules/"+mod3.Module.ID+"/technicians/"+tech1Auth.User.ID, mgrAAuth.AccessToken, map[string]any{
		"can_view": false,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("revoke tech access: %d: %s", rec.Code, rec.Body.String())
	}

	// Tech 1 cannot delete when can_view is false (403)
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+mod3.Module.ID, tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when revoked technician attempts to delete module, got %d: %s", rec.Code, rec.Body.String())
	}

	// Shared technician (Tech 2) cannot delete either (403)
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+mod3.Module.ID, tech2Auth.AccessToken, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when shared technician attempts to delete module, got %d: %s", rec.Code, rec.Body.String())
	}

	// User of Company B cannot delete (404) or query (404)
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+mod3.Module.ID, mgrBAuth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 when company B tries to delete module, got %d: %s", rec.Code, rec.Body.String())
	}
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+mod3.Module.ID, mgrBAuth.AccessToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 when company B tries to get module, got %d: %s", rec.Code, rec.Body.String())
	}

	// =========================================================================
	// 5. Manager deletes module with full operational history
	//    (including verification inspection linked to cleaning operation, thermal maps, anomalies, measurements, reservoir readings, notifications)
	// =========================================================================
	var verifInspID string
	err = pool.QueryRow(ctx, `INSERT INTO inspections (
		module_id, type, cleaning_operation_id, scheduled_for, started_at, finished_at, status, verification_result
	) VALUES (
		$1, 'verification', $2, NOW() - interval '5m', NOW() - interval '4m', NOW() - interval '3m', 'completed', 'resolved'
	) RETURNING id`, mod2.Module.ID, pendingCleanID).Scan(&verifInspID)
	if err != nil {
		t.Fatalf("insert verification inspection: %v", err)
	}

	_, err = pool.Exec(ctx, "INSERT INTO reservoir_readings (module_id, cleaning_operation_id, source_event_id, measured_at, reading_status, water_available, context) VALUES ($1, $2, gen_random_uuid(), NOW(), 'valid', true, 'after_cleaning')", mod2.Module.ID, pendingCleanID)
	if err != nil {
		t.Fatalf("insert reservoir reading: %v", err)
	}

	_, err = pool.Exec(ctx, `INSERT INTO notifications (
		company_id, user_id, module_id, anomaly_event_id, inspection_id, type, title, message, deduplication_key
	) VALUES (
		$1, $2, $3, $4, $5, 'hotspot_detected', 'Hotspot Alert', 'Hotspot detected on panel', 'test-dedup-del-2'
	)`, compA.Company.ID, compA.DefaultManager.ID, mod2.Module.ID, anomID, verifInspID)
	if err != nil {
		t.Fatalf("insert notification: %v", err)
	}

	// Manager A deletes Mod 2 with full history
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+mod2.Module.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204 when manager deletes module with full operational history, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify all dependent tables have 0 rows for mod2.ID
	assertCount := func(table string) {
		col := "module_id"
		if table == "modules" {
			col = "id"
		}
		var cnt int
		err := pool.QueryRow(ctx, "SELECT count(*) FROM "+table+" WHERE "+col+" = $1", mod2.Module.ID).Scan(&cnt)
		if err != nil {
			t.Fatalf("query count %s: %v", table, err)
		}
		if cnt != 0 {
			t.Fatalf("expected 0 rows in %s for deleted module, got %d", table, cnt)
		}
	}
	assertCount("modules")
	assertCount("inspections")
	assertCount("measurements")
	assertCount("anomaly_events")
	assertCount("cleaning_operations")
	assertCount("reservoir_readings")
	assertCount("interval_change_logs")
	assertCount("notifications")
	assertCount("module_managers")
	assertCount("module_technicians")
	assertCount("module_clients")

	// =========================================================================
	// 6. Rejection of data sent to deleted modules & Device reconnection rejection
	// =========================================================================
	// ESP32 with old deviceToken tries to ping -> 401 UNAUTHORIZED
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+mod2.Module.ID+"/ping", claimMod2.DeviceToken, map[string]any{
		"water_available": true,
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for ping on deleted module with old token, got %d: %s", rec.Code, rec.Body.String())
	}

	// ESP32 with old deviceToken tries to send telemetry -> 401 UNAUTHORIZED
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+mod2.Module.ID+"/telemetry", claimMod2.DeviceToken, map[string]any{
		"x_position_cm":     10.0,
		"max_temperature_c": 36.0,
		"hotspot_detected":  false,
		"voltage_v":         18.0,
		"current_a":         4.0,
		"thermal_frame":     testFrame768(35.0, 36.0),
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for telemetry on deleted module, got %d: %s", rec.Code, rec.Body.String())
	}

	// ESP32 with old deviceToken tries to send cleanings -> 401 UNAUTHORIZED
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+mod2.Module.ID+"/cleanings", claimMod2.DeviceToken, map[string]any{
		"target_x_position_cm": 10.0,
		"status":               "completed",
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for cleanings on deleted module, got %d: %s", rec.Code, rec.Body.String())
	}

	// ESP32 with old deviceToken tries to send config ack -> 401 UNAUTHORIZED
	rec = doJSON(http.MethodPost, "/api/v1/devices/"+mod2.Module.ID+"/configuration/ack", claimMod2.DeviceToken, map[string]any{
		"config_version": 1,
		"applied":        true,
	})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for config ack on deleted module, got %d: %s", rec.Code, rec.Body.String())
	}

	// ESP32 tries to claim with deleted module MAC -> 404 NOT_FOUND
	rec = doJSON(http.MethodPost, "/api/v1/devices/claim", "", map[string]any{
		"mac_address": mac2,
	})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 claiming deleted module MAC, got %d: %s", rec.Code, rec.Body.String())
	}

	// Manager with JWT tries to send telemetry -> 404 NOT_FOUND
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+mod2.Module.ID+"/telemetry", mgrAAuth.AccessToken, map[string]any{
		"x_position_cm":     10.0,
		"max_temperature_c": 36.0,
		"hotspot_detected":  false,
		"voltage_v":         18.0,
		"current_a":         4.0,
		"thermal_frame":     testFrame768(35.0, 36.0),
	})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for JWT telemetry on deleted module, got %d: %s", rec.Code, rec.Body.String())
	}

	// Manager with JWT tries to send device-ping -> 404 NOT_FOUND
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+mod2.Module.ID+"/device-ping", mgrAAuth.AccessToken, map[string]any{
		"water_available": true,
	})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for JWT ping on deleted module, got %d: %s", rec.Code, rec.Body.String())
	}

	// Manager with JWT tries to send cleaning -> 404 NOT_FOUND
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+mod2.Module.ID+"/cleanings", mgrAAuth.AccessToken, map[string]any{
		"target_x_position_cm": 10.0,
		"status":               "completed",
	})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for JWT cleanings on deleted module, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify no records were recreated anywhere
	assertCount("modules")
	assertCount("measurements")
	assertCount("inspections")
	assertCount("reservoir_readings")

	// =========================================================================
	// 7. Transactional coordination / Concurrent telemetry during DeleteModule
	// =========================================================================
	rec = doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":        "Mod Concurrency Test",
		"mac_address": mac4,
		"manager_ids": []string{compA.DefaultManager.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create mod 4: %d: %s", rec.Code, rec.Body.String())
	}
	var mod4 struct{ Module struct{ ID string `json:"id"` } `json:"module"` }
	_ = json.Unmarshal(rec.Body.Bytes(), &mod4)

	rec = doJSON(http.MethodPost, "/api/v1/devices/claim", "", map[string]any{
		"mac_address": mac4,
	})
	var claimMod4 struct{ DeviceToken string `json:"device_token"` }
	_ = json.Unmarshal(rec.Body.Bytes(), &claimMod4)

	var wg sync.WaitGroup
	var concurrentTelemetryCode int

	wg.Add(2)
	// Goroutine 1: Initiates DeleteModule holding the row lock
	go func() {
		defer wg.Done()
		delTx, err := pool.Begin(ctx)
		if err != nil {
			t.Errorf("begin delTx: %v", err)
			return
		}
		defer delTx.Rollback(ctx)

		var id string
		err = delTx.QueryRow(ctx, "SELECT id FROM modules WHERE id = $1 FOR UPDATE", mod4.Module.ID).Scan(&id)
		if err != nil {
			t.Errorf("lock module: %v", err)
			return
		}
		time.Sleep(100 * time.Millisecond)

		cUUID, _ := auth.ParseUUID(compA.Company.ID)
		mUUID, _ := auth.ParseUUID(mod4.Module.ID)
		delQtx := db.New(delTx)
		_ = delQtx.DeleteAllManagersForModule(ctx, db.DeleteAllManagersForModuleParams{CompanyID: cUUID, ModuleID: mUUID})
		_ = delQtx.DeleteAllTechniciansForModule(ctx, db.DeleteAllTechniciansForModuleParams{CompanyID: cUUID, ModuleID: mUUID})
		_ = delQtx.DeleteModule(ctx, db.DeleteModuleParams{CompanyID: cUUID, ID: mUUID})
		_ = delTx.Commit(ctx)
	}()

	// Goroutine 2: Ingest telemetry concurrently (starts slightly after Goroutine 1 locks)
	go func() {
		defer wg.Done()
		time.Sleep(20 * time.Millisecond)
		telemetryRec := doJSON(http.MethodPost, "/api/v1/modules/"+mod4.Module.ID+"/telemetry", mgrAAuth.AccessToken, map[string]any{
			"x_position_cm":     10.0,
			"max_temperature_c": 36.0,
			"hotspot_detected":  false,
			"voltage_v":         18.0,
			"current_a":         4.0,
			"thermal_frame":     testFrame768(35.0, 36.0),
		})
		concurrentTelemetryCode = telemetryRec.Code
	}()

	wg.Wait()

	if concurrentTelemetryCode != http.StatusNotFound {
		t.Fatalf("expected concurrent telemetry to return 404 after module deleted, got %d", concurrentTelemetryCode)
	}

	var mod4MeasCount int
	_ = pool.QueryRow(ctx, "SELECT count(*) FROM measurements WHERE module_id = $1", mod4.Module.ID).Scan(&mod4MeasCount)
	if mod4MeasCount != 0 {
		t.Fatalf("expected 0 measurements for Mod 4, got %d", mod4MeasCount)
	}

	// =========================================================================
	// 8. Rollback after intermediate failure leaves all rows intact
	// =========================================================================
	rec = doJSON(http.MethodPost, "/api/v1/modules", tech1Auth.AccessToken, map[string]any{
		"name":        "Mod Rollback Test",
		"mac_address": mac5,
		"manager_ids": []string{compA.DefaultManager.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create mod 5: %d: %s", rec.Code, rec.Body.String())
	}
	var mod5 struct{ Module struct{ ID string `json:"id"` } `json:"module"` }
	_ = json.Unmarshal(rec.Body.Bytes(), &mod5)

	rbTx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin rbTx: %v", err)
	}
	rbCUUID, _ := auth.ParseUUID(compA.Company.ID)
	rbMUUID, _ := auth.ParseUUID(mod5.Module.ID)
	rbQtx := db.New(rbTx)
	_ = rbQtx.DeleteAllManagersForModule(ctx, db.DeleteAllManagersForModuleParams{CompanyID: rbCUUID, ModuleID: rbMUUID})
	_ = rbTx.Rollback(ctx)

	// Verify manager assignment and module still exist
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+mod5.Module.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 after rollback, got %d", rec.Code)
	}
}
