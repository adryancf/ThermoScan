package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
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
	// A) Módulo com histórico operacional (modCreated possui logs de intervalo do passo 10) não pode ser excluído
	rec = doJSON(http.MethodDelete, "/api/v1/modules/"+modCreated.Module.ID, mgrAAuth.AccessToken, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 when deleting module with operational history, got %d: %s", rec.Code, rec.Body.String())
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

	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/thermal-map", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 getting thermal map, got %d: %s", rec.Code, rec.Body.String())
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

	// Test telemetry ingestion
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/telemetry", tech1Auth.AccessToken, map[string]any{
		"x_position_cm":          25.5,
		"baseline_temperature_c": 35.0,
		"max_temperature_c":      52.0,
		"hotspot_detected":      true,
		"hotspot_confirmed":     true,
		"voltage_v":              18.4,
		"current_a":              4.2,
		"width_pixels":           32,
		"height_pixels":          24,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 ingesting telemetry, got %d: %s", rec.Code, rec.Body.String())
	}

	// Test cleaning operation ingestion
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/cleanings", tech1Auth.AccessToken, map[string]any{
		"target_x_position_cm":      25.5,
		"pump_actuated":             true,
		"attempt_number":            1,
		"duration_seconds":          42.0,
		"estimated_water_volume_ml": 85.0,
		"status":                    "completed",
		"post_cleaning_result":      "resolved",
	})
	// Test batch multi-frame telemetry with 2cm steps & 60% overlap
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modCreated.Module.ID+"/telemetry", tech1Auth.AccessToken, map[string]any{
		"batch": []map[string]any{
			{"x_position_cm": 0.0, "baseline_temperature_c": 35.0, "max_temperature_c": 37.0, "hotspot_detected": false, "voltage_v": 18.5, "current_a": 4.2},
			{"x_position_cm": 2.0, "baseline_temperature_c": 35.0, "max_temperature_c": 38.0, "hotspot_detected": false, "voltage_v": 18.5, "current_a": 4.2},
			{"x_position_cm": 4.0, "baseline_temperature_c": 35.0, "max_temperature_c": 56.5, "hotspot_detected": true, "voltage_v": 18.2, "current_a": 4.0},
			{"x_position_cm": 6.0, "baseline_temperature_c": 35.0, "max_temperature_c": 37.5, "hotspot_detected": false, "voltage_v": 18.5, "current_a": 4.2},
		},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 ingesting batch telemetry, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify thermal map has 60% overlap stitching and 5cm bands
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modCreated.Module.ID+"/thermal-map", tech1Auth.AccessToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 getting thermal map, got %d: %s", rec.Code, rec.Body.String())
	}
	var tmResp struct {
		ThermalMap struct {
			WidthPixels      int32  `json:"width_pixels"`
			HeightPixels     int32  `json:"height_pixels"`
			AlgorithmVersion string `json:"algorithm_version"`
			Bands            []struct {
				BandIndex       int     `json:"band_index"`
				StartXCm        float64 `json:"start_x_cm"`
				EndXCm          float64 `json:"end_x_cm"`
				MaxTemperatureC float64 `json:"max_temperature_c"`
				HasHotspot      bool    `json:"has_hotspot"`
			} `json:"bands"`
		} `json:"thermal_map"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &tmResp); err != nil {
		t.Fatalf("failed to decode thermal map response: %v", err)
	}
	if tmResp.ThermalMap.WidthPixels <= 32 {
		t.Fatalf("expected stitched width > 32 cols, got %d", tmResp.ThermalMap.WidthPixels)
	}
	if len(tmResp.ThermalMap.Bands) == 0 {
		t.Fatalf("expected 5cm bands in thermal map, got 0")
	}
	if tmResp.ThermalMap.AlgorithmVersion != "overlap-60-blend-v1.0" {
		t.Fatalf("expected algorithm overlap-60-blend-v1.0, got %q", tmResp.ThermalMap.AlgorithmVersion)
	}
}
