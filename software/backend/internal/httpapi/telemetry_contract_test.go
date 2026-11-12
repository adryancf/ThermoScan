package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
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

func makeTestFrame768(baseline float64, hotspot *float64, withNull bool) []*float64 {
	f := make([]*float64, 768)
	for i := range f {
		val := baseline
		f[i] = &val
	}
	if withNull {
		f[0] = nil
		f[10] = nil
	}
	if hotspot != nil {
		f[12*32+16] = hotspot
	}
	return f
}

func setupTelemetryTestEnv(t *testing.T) (context.Context, *pgx.Conn, pgx.Tx, *db.Queries, http.Handler, auth.AuthResponse, string) {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	t.Cleanup(cancel)

	conn, err := pgx.Connect(ctx, testDBURL())
	if err != nil {
		t.Skipf("PostgreSQL not reachable: %v", err)
	}

	tx, err := conn.Begin(ctx)
	if err != nil {
		t.Fatalf("failed to begin tx: %v", err)
	}

	q := db.New(tx)
	tokens := auth.NewTokenManager("telemetry-contract-secret-2026")

	adminPass := "Admin#Pass2026"
	adminHash, _ := auth.HashPassword(adminPass)
	adminEmail := fmt.Sprintf("sysadmin.%d@thermoscan.local", time.Now().UnixNano())
	_, _ = q.CreateUser(ctx, db.CreateUserParams{
		CompanyID:          pgtype.UUID{Valid: false},
		Name:               "System Admin",
		Email:              adminEmail,
		PasswordHash:       adminHash,
		Role:               auth.RoleSystemAdmin,
		IsActive:           true,
		IsDefaultManager:   false,
		MustChangePassword: false,
	})

	router := httpapi.NewRouter(httpapi.Dependencies{
		AuthHandler:    auth.NewHandler(auth.NewService(tx, tokens), q, tokens),
		CompanyHandler: company.NewHandler(company.NewService(tx), q, tokens),
		UserHandler:    user.NewHandler(user.NewService(tx), q, tokens),
		ModuleHandler:  module.NewHandler(module.NewService(tx), q, tokens),
	})

	doJSON := func(method, path, bearer string, body any) *httptest.ResponseRecorder {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
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

	// Login admin
	adminAuth := loginAndActivate(adminEmail, adminPass, adminPass)

	// Create Company
	compName := fmt.Sprintf("Test Company %d", time.Now().UnixNano())
	mgrEmail := fmt.Sprintf("mgr.%d@thermoscan.local", time.Now().UnixNano())
	rec := doJSON(http.MethodPost, "/api/v1/companies", adminAuth.AccessToken, map[string]string{
		"name":          compName,
		"manager_name":  "Default Manager",
		"manager_email": mgrEmail,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create company failed: %d: %s", rec.Code, rec.Body.String())
	}
	var compCreated company.CreateCompanyResult
	_ = json.Unmarshal(rec.Body.Bytes(), &compCreated)

	// Activate Manager
	mgrAuth := loginAndActivate(mgrEmail, compCreated.TemporaryPassword, "ManagerPass#2026")

	// Create Technician
	techEmail := fmt.Sprintf("tech.%d@thermoscan.local", time.Now().UnixNano())
	rec = doJSON(http.MethodPost, "/api/v1/users", mgrAuth.AccessToken, map[string]any{
		"name":        "Field Tech",
		"email":       techEmail,
		"role":        "technician",
		"manager_ids": []string{compCreated.DefaultManager.ID},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create technician failed: %d: %s", rec.Code, rec.Body.String())
	}
	var techCreated user.CreateUserResult
	_ = json.Unmarshal(rec.Body.Bytes(), &techCreated)

	// Activate Technician
	techAuth := loginAndActivate(techEmail, techCreated.TemporaryPassword, "TechPass#2026")

	// Create Module with panel_length_cm = 100.0
	mac := fmt.Sprintf("02:%02x:%02x:%02x:%02x:%02x", time.Now().UnixNano()&0xff, (time.Now().UnixNano()>>8)&0xff, (time.Now().UnixNano()>>16)&0xff, (time.Now().UnixNano()>>24)&0xff, (time.Now().UnixNano()>>32)&0xff)
	rec = doJSON(http.MethodPost, "/api/v1/modules", techAuth.AccessToken, map[string]any{
		"name":                     "Test PV Panel",
		"mac_address":              mac,
		"panel_length_cm":          100.0,
		"panel_width_cm":           50.0,
		"panel_count":              1,
		"panel_spacing_cm":         0.0,
		"latitude":                 -23.55,
		"longitude":                -46.63,
		"elevation_m":              760.0,
		"azimuth_deg":              180.0,
		"tilt_deg":                 20.0,
		"azimuth_source":           "manual",
		"tilt_source":              "manual",
		"minimum_solar_angle_deg":  15.0,
		"inspection_interval_days": 1,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create module failed: %d: %s", rec.Code, rec.Body.String())
	}
	var modCreated struct {
		Module struct {
			ID string `json:"id"`
		} `json:"module"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &modCreated)

	return ctx, conn, tx, q, router, techAuth, modCreated.Module.ID
}

func TestTelemetryContractValidations(t *testing.T) {
	ctx, conn, tx, q, router, techAuth, modID := setupTelemetryTestEnv(t)
	defer conn.Close(ctx)
	defer tx.Rollback(ctx)

	doJSON := func(method, path, bearer string, body any) *httptest.ResponseRecorder {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
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

	// 1. Frame térmico com null aceito
	t.Run("FrameWithNullAccepted", func(t *testing.T) {
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "10000000-0000-0000-0000-000000000001",
			"source_event_id":           "10000000-0000-0000-0000-000000000002",
			"x_position_cm":             10.0,
			"max_temperature_c":         38.0,
			"voltage_v":                 18.5,
			"current_a":                 4.2,
			"thermal_frame":             makeTestFrame768(35.0, nil, true), // contains nulls!
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("expected 201 for frame with null, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 2. Frame com menos ou mais de 768 posições é rejeitado
	t.Run("FrameInvalidSizeRejected", func(t *testing.T) {
		shortFrame := make([]float64, 767)
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "11000000-0000-0000-0000-000000000001",
			"source_event_id":           "11000000-0000-0000-0000-000000000002",
			"x_position_cm":             10.0,
			"max_temperature_c":         38.0,
			"thermal_frame":             shortFrame,
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for frame size 767, got %d: %s", rec.Code, rec.Body.String())
		}

		longFrame := make([]float64, 769)
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "11000000-0000-0000-0000-000000000001",
			"source_event_id":           "11000000-0000-0000-0000-000000000003",
			"x_position_cm":             10.0,
			"max_temperature_c":         38.0,
			"thermal_frame":             longFrame,
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for frame size 769, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 3. Lote com mais de 5 medições rejeitado (testar com 6 medições)
	t.Run("BatchExceeding5Rejected", func(t *testing.T) {
		batch := make([]map[string]any, 6)
		for i := 0; i < 6; i++ {
			batch[i] = map[string]any{
				"source_event_id":   fmt.Sprintf("20000000-0000-0000-0000-%012d", i+1),
				"x_position_cm":     float64(i * 2),
				"max_temperature_c": 35.0,
				"voltage_v":         18.5,
				"current_a":         4.2,
				"thermal_frame":     makeTestFrame768(35.0, nil, false),
			}
		}
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "20000000-0000-0000-0000-000000000099",
			"batch":                      batch,
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for batch > 5, got %d: %s", rec.Code, rec.Body.String())
		}
		var errResp struct {
			Error string `json:"error"`
			Code  string `json:"code"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &errResp)
		if errResp.Error != "telemetry batch exceeds maximum limit of 5 items" {
			t.Fatalf("expected error message 'telemetry batch exceeds maximum limit of 5 items', got %q", errResp.Error)
		}
	})

	// 4. source_event_id duplicado no mesmo lote rejeitado
	t.Run("DuplicateSourceEventIDInBatchRejected", func(t *testing.T) {
		dupID := "30000000-0000-0000-0000-000000000099"
		batch := []map[string]any{
			{
				"source_event_id":   dupID,
				"x_position_cm":     2.0,
				"max_temperature_c": 35.0,
				"voltage_v":         18.5,
				"current_a":         4.2,
				"thermal_frame":     makeTestFrame768(35.0, nil, false),
			},
			{
				"source_event_id":   dupID, // Duplicate!
				"x_position_cm":     4.0,
				"max_temperature_c": 36.0,
				"voltage_v":         18.5,
				"current_a":         4.2,
				"thermal_frame":     makeTestFrame768(35.0, nil, false),
			},
		}
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "30000000-0000-0000-0000-000000000001",
			"batch":                      batch,
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for duplicate source_event_id in batch, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 5. x_position_cm fora do painel rejeitado (panel length is 100.0)
	t.Run("XPositionBeyondPanelLengthRejected", func(t *testing.T) {
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "40000000-0000-0000-0000-000000000001",
			"source_event_id":           "40000000-0000-0000-0000-000000000002",
			"x_position_cm":             150.0, // > 100.0!
			"max_temperature_c":         35.0,
			"voltage_v":                 18.5,
			"current_a":                 4.2,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for x_position_cm > panel_length_cm, got %d: %s", rec.Code, rec.Body.String())
		}

		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "40000000-0000-0000-0000-000000000001",
			"source_event_id":           "40000000-0000-0000-0000-000000000003",
			"x_position_cm":             -1.0, // < 0
			"max_temperature_c":         35.0,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for negative x_position_cm, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 6. NaN ou Inf rejeitado
	t.Run("NaNOrInfRejected", func(t *testing.T) {
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "45000000-0000-0000-0000-000000000001",
			"source_event_id":           "45000000-0000-0000-0000-000000000002",
			"x_position_cm":             10.0,
			"max_temperature_c":         "NaN",
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for NaN, got %d", rec.Code)
		}
	})

	// 7. voltage_v / current_a / power_w null são aceitos
	t.Run("VoltageCurrentPowerNullAccepted", func(t *testing.T) {
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "46000000-0000-0000-0000-000000000001",
			"source_event_id":           "46000000-0000-0000-0000-000000000002",
			"x_position_cm":             10.0,
			"max_temperature_c":         35.0,
			"voltage_v":                 nil,
			"current_a":                 nil,
			"power_w":                   nil,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("expected 201 for null electrical values, got %d: %s", rec.Code, rec.Body.String())
		}
		var mResp struct {
			Measurement module.MeasurementDTO `json:"measurement"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &mResp)
		if mResp.Measurement.VoltageV != nil || mResp.Measurement.CurrentA != nil || mResp.Measurement.PowerW != nil {
			t.Fatalf("expected nil electrical fields in response, got v=%v, c=%v, p=%v", mResp.Measurement.VoltageV, mResp.Measurement.CurrentA, mResp.Measurement.PowerW)
		}
	})

	// 8 & 9. Uma varredura gera uma única inspeção e múltiplas medições são persistidas na mesma inspeção
	t.Run("SingleInspectionMultipleMeasurements", func(t *testing.T) {
		inspSourceID := "47000000-0000-0000-0000-000000000001"
		m1 := "47000000-0000-0000-0000-000000000011"
		m2 := "47000000-0000-0000-0000-000000000012"
		m3 := "47000000-0000-0000-0000-000000000013"

		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"batch": []map[string]any{
				{"source_event_id": m1, "x_position_cm": 10.0, "max_temperature_c": 36.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m2, "x_position_cm": 12.0, "max_temperature_c": 37.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m3, "x_position_cm": 14.0, "max_temperature_c": 38.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("expected 201 for batch, got %d: %s", rec.Code, rec.Body.String())
		}

		rec = doJSON(http.MethodGet, "/api/v1/modules/"+modID+"/latest-inspection", techAuth.AccessToken, nil)
		var latestResp struct {
			LatestInspection struct {
				Inspection struct {
					ID            string `json:"id"`
					SourceEventID string `json:"source_event_id"`
				} `json:"inspection"`
				TotalMeasurements int64 `json:"total_measurements"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &latestResp)
		if latestResp.LatestInspection.Inspection.SourceEventID != inspSourceID {
			t.Fatalf("expected inspection source_event_id %s, got %s", inspSourceID, latestResp.LatestInspection.Inspection.SourceEventID)
		}
		if latestResp.LatestInspection.TotalMeasurements != 3 {
			t.Fatalf("expected 3 measurements in single inspection, got %d", latestResp.LatestInspection.TotalMeasurements)
		}
	})

	// 10. Finalização de inspeção: validações de confirming_event_ids, origin, row_index e baseline
	t.Run("FinalizeInspectionValidations", func(t *testing.T) {
		inspSourceID := "50000000-0000-0000-0000-000000000001"
		m1 := "50000000-0000-0000-0000-000000000011"
		m2 := "50000000-0000-0000-0000-000000000012"
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"batch": []map[string]any{
				{"source_event_id": m1, "x_position_cm": 20.0, "max_temperature_c": 55.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m2, "x_position_cm": 22.0, "max_temperature_c": 56.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("create measurements: %d: %s", rec.Code, rec.Body.String())
		}

		// a) confirming_event_ids repetidos rejeitado ([m1, m1])
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            "50000000-0000-0000-0000-000000000099",
					"global_x_position_cm":        21.0,
					"max_temperature_c":           56.0,
					"origin_measurement_event_id": m1,
					"confirming_event_ids":        []string{m1, m1}, // Repeated!
				},
			},
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for repeated confirming_event_ids, got %d: %s", rec.Code, rec.Body.String())
		}

		// b) origin_measurement_event_id fora de confirming_event_ids rejeitado
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            "50000000-0000-0000-0000-000000000099",
					"global_x_position_cm":        21.0,
					"max_temperature_c":           56.0,
					"origin_measurement_event_id": "00000000-0000-0000-0000-000000000000", // Not in confirming!
					"confirming_event_ids":        []string{m1, m2},
				},
			},
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for origin not in confirming_event_ids, got %d: %s", rec.Code, rec.Body.String())
		}

		// c) row_index < 0 rejeitado
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            "50000000-0000-0000-0000-000000000099",
					"global_x_position_cm":        21.0,
					"row_index":                  -1, // Out of range!
					"max_temperature_c":           56.0,
					"origin_measurement_event_id": m1,
					"confirming_event_ids":        []string{m1, m2},
				},
			},
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for row_index < 0, got %d: %s", rec.Code, rec.Body.String())
		}

		// d) row_index > 23 rejeitado
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            "50000000-0000-0000-0000-000000000099",
					"global_x_position_cm":        21.0,
					"row_index":                  24, // Out of range!
					"max_temperature_c":           56.0,
					"origin_measurement_event_id": m1,
					"confirming_event_ids":        []string{m1, m2},
				},
			},
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for row_index > 23, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 11. Finalização com baseline e nenhum hotspot conclui inspeção sem anomalia
	t.Run("FinalizeWithNoHotspotsConcludesWithoutAnomaly", func(t *testing.T) {
		inspSourceID := "51000000-0000-0000-0000-000000000001"
		m1 := "51000000-0000-0000-0000-000000000011"
		m2 := "51000000-0000-0000-0000-000000000012"
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"batch": []map[string]any{
				{"source_event_id": m1, "x_position_cm": 10.0, "max_temperature_c": 35.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m2, "x_position_cm": 12.0, "max_temperature_c": 35.5, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry: %d", rec.Code)
		}

		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots":     []map[string]any{},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize without hotspots: %d: %s", rec.Code, rec.Body.String())
		}
		var finResp struct {
			LatestInspection struct {
				Inspection struct {
					Status               string   `json:"status"`
					BaselineTemperatureC *float64 `json:"baseline_temperature_c"`
				} `json:"inspection"`
				ConfirmedAnomalies []any `json:"confirmed_anomalies"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &finResp)
		if finResp.LatestInspection.Inspection.Status != "completed" {
			t.Fatalf("expected completed status, got %s", finResp.LatestInspection.Inspection.Status)
		}
		if finResp.LatestInspection.Inspection.BaselineTemperatureC == nil || *finResp.LatestInspection.Inspection.BaselineTemperatureC != 35.0 {
			t.Fatalf("expected baseline 35.0, got %v", finResp.LatestInspection.Inspection.BaselineTemperatureC)
		}
		if len(finResp.LatestInspection.ConfirmedAnomalies) != 0 {
			t.Fatalf("expected 0 anomalies, got %d", len(finResp.LatestInspection.ConfirmedAnomalies))
		}
	})

	// 12. Finalização com múltiplos hotspots cria múltiplas anomalias
	t.Run("FinalizeWithMultipleHotspotsCreatesMultipleAnomalies", func(t *testing.T) {
		inspSourceID := "52000000-0000-0000-0000-000000000001"
		m1 := "52000000-0000-0000-0000-000000000011"
		m2 := "52000000-0000-0000-0000-000000000012"
		m3 := "52000000-0000-0000-0000-000000000013"
		m4 := "52000000-0000-0000-0000-000000000014"

		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"batch": []map[string]any{
				{"source_event_id": m1, "x_position_cm": 10.0, "max_temperature_c": 50.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m2, "x_position_cm": 12.0, "max_temperature_c": 51.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m3, "x_position_cm": 30.0, "max_temperature_c": 55.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m4, "x_position_cm": 32.0, "max_temperature_c": 56.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry: %d", rec.Code)
		}

		h1 := "52000000-0000-0000-0000-000000000091"
		h2 := "52000000-0000-0000-0000-000000000092"
		row1 := 5
		row2 := 12
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            h1,
					"global_x_position_cm":        11.0,
					"row_index":                  row1,
					"max_temperature_c":           51.0,
					"origin_measurement_event_id": m1,
					"confirming_event_ids":        []string{m1, m2},
				},
				{
					"source_event_id":            h2,
					"global_x_position_cm":        31.0,
					"row_index":                  row2,
					"max_temperature_c":           56.0,
					"origin_measurement_event_id": m3,
					"confirming_event_ids":        []string{m3, m4},
				},
			},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize with 2 hotspots: %d: %s", rec.Code, rec.Body.String())
		}

		var finResp struct {
			LatestInspection struct {
				ConfirmedAnomalies []any `json:"confirmed_anomalies"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &finResp)
		if len(finResp.LatestInspection.ConfirmedAnomalies) != 2 {
			t.Fatalf("expected 2 anomalies created, got %d", len(finResp.LatestInspection.ConfirmedAnomalies))
		}
	})

	// 13. detected_at derivado da maior medição confirmadora se não enviado
	t.Run("DetectedAtDerivedFromMaxConfirmingMeasuredAt", func(t *testing.T) {
		inspSourceID := "53000000-0000-0000-0000-000000000001"
		m1 := "53000000-0000-0000-0000-000000000011"
		m2 := "53000000-0000-0000-0000-000000000012"
		now := time.Now().UTC().Truncate(time.Second)
		tEarly := now.Add(-10 * time.Minute)
		tLate := now.Add(-5 * time.Minute)

		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"batch": []map[string]any{
				{"source_event_id": m1, "measured_at": tEarly, "x_position_cm": 20.0, "max_temperature_c": 52.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m2, "measured_at": tLate, "x_position_cm": 22.0, "max_temperature_c": 53.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry: %d", rec.Code)
		}

		anomSourceID := "53000000-0000-0000-0000-000000000099"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            anomSourceID,
					"global_x_position_cm":        21.0,
					"max_temperature_c":           53.0,
					"origin_measurement_event_id": m1,
					"confirming_event_ids":        []string{m1, m2},
					// detected_at omitted!
				},
			},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize: %d: %s", rec.Code, rec.Body.String())
		}

		var finResp struct {
			LatestInspection struct {
				ConfirmedAnomalies []struct {
					DetectedAt string `json:"detected_at"`
				} `json:"confirmed_anomalies"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &finResp)
		if len(finResp.LatestInspection.ConfirmedAnomalies) != 1 {
			t.Fatalf("expected 1 anomaly, got %d", len(finResp.LatestInspection.ConfirmedAnomalies))
		}
		expectedTimeStr := tLate.Format(time.RFC3339)
		if finResp.LatestInspection.ConfirmedAnomalies[0].DetectedAt != expectedTimeStr {
			t.Fatalf("expected detected_at %q (from max confirming measurement), got %q", expectedTimeStr, finResp.LatestInspection.ConfirmedAnomalies[0].DetectedAt)
		}
	})

	// 13b. Listar inspeções retorna confirmed_anomalies preenchidos para inspeções históricas
	t.Run("ListInspectionsReturnsConfirmedAnomaliesForHistoricalInspections", func(t *testing.T) {
		rec := doJSON(http.MethodGet, "/api/v1/modules/"+modID+"/inspections", techAuth.AccessToken, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 listing inspections, got %d: %s", rec.Code, rec.Body.String())
		}

		// Ensure raw JSON contains empty array "confirmed_anomalies":[] and not null
		if strings.Contains(rec.Body.String(), `"confirmed_anomalies":null`) {
			t.Fatalf("expected confirmed_anomalies never to be null in JSON response: %s", rec.Body.String())
		}

		var listResp struct {
			Inspections []struct {
				ID                 string `json:"id"`
				SourceEventID      string `json:"source_event_id"`
				Status             string `json:"status"`
				ConfirmedAnomalies []struct {
					ID               string   `json:"id"`
					SourceEventID    string   `json:"source_event_id"`
					XPositionCM      float64  `json:"x_position_cm"`
					LocalXPositionCM *float64 `json:"local_x_position_cm"`
					Status           string   `json:"status"`
				} `json:"confirmed_anomalies"`
			} `json:"inspections"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &listResp); err != nil {
			t.Fatalf("failed to decode list inspections response: %v", err)
		}

		if len(listResp.Inspections) == 0 {
			t.Fatalf("expected inspections to be returned")
		}

		var foundHistoricalWith2Anomalies bool
		var foundHistoricalWithNoAnomalies bool
		for _, insp := range listResp.Inspections {
			if insp.ConfirmedAnomalies == nil {
				t.Fatalf("expected confirmed_anomalies slice not to be nil for inspection %s", insp.ID)
			}
			if insp.SourceEventID == "52000000-0000-0000-0000-000000000001" {
				foundHistoricalWith2Anomalies = true
				if len(insp.ConfirmedAnomalies) != 2 {
					t.Fatalf("expected 2 confirmed anomalies for historical inspection, got %d", len(insp.ConfirmedAnomalies))
				}
				for _, anom := range insp.ConfirmedAnomalies {
					if anom.ID == "" || anom.SourceEventID == "" {
						t.Fatalf("expected anomaly to have ID and SourceEventID, got %+v", anom)
					}
					if anom.LocalXPositionCM == nil {
						t.Fatalf("expected local_x_position_cm to be calculated, got nil")
					}
					if anom.Status != "open" {
						t.Fatalf("expected anomaly status 'open', got %s", anom.Status)
					}
				}
			}
			if insp.SourceEventID == "51000000-0000-0000-0000-000000000001" {
				foundHistoricalWithNoAnomalies = true
				if len(insp.ConfirmedAnomalies) != 0 {
					t.Fatalf("expected 0 confirmed anomalies for inspection without hotspots, got %d", len(insp.ConfirmedAnomalies))
				}
			}
		}

		if !foundHistoricalWith2Anomalies {
			t.Fatalf("expected to find historical inspection 52000000-0000-0000-0000-000000000001 with confirmed anomalies")
		}
		if !foundHistoricalWithNoAnomalies {
			t.Fatalf("expected to find historical inspection 51000000-0000-0000-0000-000000000001 without hotspots")
		}
	})

	// 14. Limpeza não fecha anomalia, e fluxo de inspeção de verificação
	t.Run("CleaningLifecycleAndVerification", func(t *testing.T) {
		inspSourceID := "60000000-0000-0000-0000-000000000001"
		m1 := "60000000-0000-0000-0000-000000000011"
		m2 := "60000000-0000-0000-0000-000000000012"
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"batch": []map[string]any{
				{"source_event_id": m1, "x_position_cm": 30.0, "max_temperature_c": 58.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m2, "x_position_cm": 32.0, "max_temperature_c": 59.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry: %d", rec.Code)
		}

		anomSourceID := "60000000-0000-0000-0000-000000000099"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            anomSourceID,
					"global_x_position_cm":        31.0,
					"max_temperature_c":           59.0,
					"origin_measurement_event_id": m1,
					"confirming_event_ids":        []string{m1, m2},
				},
			},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize: %d: %s", rec.Code, rec.Body.String())
		}
		var finResp struct {
			LatestInspection struct {
				ConfirmedAnomalies []struct {
					ID string `json:"id"`
				} `json:"confirmed_anomalies"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &finResp)
		if len(finResp.LatestInspection.ConfirmedAnomalies) == 0 {
			t.Fatalf("expected anomaly created")
		}
		anomID := finResp.LatestInspection.ConfirmedAnomalies[0].ID

		// a) IngestCleaning: pump actuated -> post_cleaning_result is pending and anomaly remains open!
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/cleanings", techAuth.AccessToken, map[string]any{
			"anomaly_event_id":          anomID,
			"target_x_position_cm":      31.0,
			"pump_actuated":             true,
			"attempt_number":            1,
			"duration_seconds":          40.0,
			"estimated_water_volume_ml": 80.0,
			"status":                    "completed",
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("cleaning: %d: %s", rec.Code, rec.Body.String())
		}
		var cleanResp struct {
			Cleaning struct {
				ID                 string `json:"id"`
				AnomalyEventID     string `json:"anomaly_event_id"`
				PostCleaningResult string `json:"post_cleaning_result"`
			} `json:"cleaning"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &cleanResp)
		if cleanResp.Cleaning.PostCleaningResult != "pending" {
			t.Fatalf("expected post_cleaning_result 'pending', got %q", cleanResp.Cleaning.PostCleaningResult)
		}

		// Verify anomaly is STILL open!
		anomUUID, _ := auth.ParseUUID(cleanResp.Cleaning.AnomalyEventID)
		modUUID, _ := auth.ParseUUID(modID)
		anomRow, err := q.GetAnomalyEventByID(ctx, db.GetAnomalyEventByIDParams{
			ID:       anomUUID,
			ModuleID: modUUID,
		})
		if err != nil {
			t.Fatalf("get anomaly: %v", err)
		}
		if anomRow.Status != "open" || anomRow.ClosedAt != nil {
			t.Fatalf("expected anomaly to remain open after cleaning ingestion, got status=%q closed_at=%v", anomRow.Status, anomRow.ClosedAt)
		}

		// b) Verification inspection: resolved
		verifInspSourceID := "60000000-0000-0000-0000-000000000002"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": verifInspSourceID,
			"inspection_type":           "verification",
			"cleaning_operation_id":     cleanResp.Cleaning.ID,
			"batch": []map[string]any{
				{"source_event_id": "60000000-0000-0000-0000-000000000031", "x_position_cm": 30.0, "max_temperature_c": 36.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": "60000000-0000-0000-0000-000000000032", "x_position_cm": 32.0, "max_temperature_c": 36.5, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("verification telemetry: %d: %s", rec.Code, rec.Body.String())
		}

		// Finalize with NO hotspots confirmed -> resolved!
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+verifInspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots":     []map[string]any{},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize verification: %d: %s", rec.Code, rec.Body.String())
		}

		// Check latest inspection verification_result
		rec = doJSON(http.MethodGet, "/api/v1/modules/"+modID+"/latest-inspection", techAuth.AccessToken, nil)
		var verifLatest struct {
			LatestInspection struct {
				Inspection struct {
					VerificationResult *string `json:"verification_result"`
				} `json:"inspection"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &verifLatest)
		if verifLatest.LatestInspection.Inspection.VerificationResult == nil || *verifLatest.LatestInspection.Inspection.VerificationResult != "resolved" {
			t.Fatalf("expected verification_result 'resolved', got %v", verifLatest.LatestInspection.Inspection.VerificationResult)
		}

		// Check anomaly status updated to resolved
		anomRow, _ = q.GetAnomalyEventByID(ctx, db.GetAnomalyEventByIDParams{
			ID:       anomUUID,
			ModuleID: modUUID,
		})
		if anomRow.Status != "resolved" || anomRow.ClosedAt == nil {
			t.Fatalf("expected anomaly status 'resolved', got %q", anomRow.Status)
		}
	})

	// 15. Verificação não resolvida após limpeza completa fecha como unresolved
	t.Run("VerificationUnresolvedAfterCompletedCleaning", func(t *testing.T) {
		inspSourceID := "70000000-0000-0000-0000-000000000001"
		m1 := "70000000-0000-0000-0000-000000000011"
		m2 := "70000000-0000-0000-0000-000000000012"
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"batch": []map[string]any{
				{"source_event_id": m1, "x_position_cm": 50.0, "max_temperature_c": 60.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m2, "x_position_cm": 52.0, "max_temperature_c": 61.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry: %d", rec.Code)
		}

		anomSourceID := "70000000-0000-0000-0000-000000000099"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            anomSourceID,
					"global_x_position_cm":        51.0,
					"max_temperature_c":           61.0,
					"origin_measurement_event_id": m1,
					"confirming_event_ids":        []string{m1, m2},
				},
			},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize: %d", rec.Code)
		}
		var finResp struct {
			LatestInspection struct {
				ConfirmedAnomalies []struct {
					ID string `json:"id"`
				} `json:"confirmed_anomalies"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &finResp)
		if len(finResp.LatestInspection.ConfirmedAnomalies) == 0 {
			t.Fatalf("expected anomaly created")
		}
		anomID := finResp.LatestInspection.ConfirmedAnomalies[0].ID

		// Completed cleaning attempt 1
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/cleanings", techAuth.AccessToken, map[string]any{
			"anomaly_event_id":          anomID,
			"target_x_position_cm":      51.0,
			"pump_actuated":             true,
			"attempt_number":            1,
			"duration_seconds":          40.0,
			"estimated_water_volume_ml": 80.0,
			"status":                    "completed",
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("cleaning completed: %d", rec.Code)
		}
		var cleanResp struct {
			Cleaning struct {
				ID string `json:"id"`
			} `json:"cleaning"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &cleanResp)

		// Verification telemetry
		verifInspSourceID := "70000000-0000-0000-0000-000000000002"
		vm1 := "70000000-0000-0000-0000-000000000021"
		vm2 := "70000000-0000-0000-0000-000000000022"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": verifInspSourceID,
			"inspection_type":           "verification",
			"cleaning_operation_id":     cleanResp.Cleaning.ID,
			"batch": []map[string]any{
				{"source_event_id": vm1, "x_position_cm": 50.0, "max_temperature_c": 60.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": vm2, "x_position_cm": 52.0, "max_temperature_c": 60.5, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("verif telemetry: %d: %s", rec.Code, rec.Body.String())
		}

		// Finalize with hotspot STILL PERSISTING at x=51.0!
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+verifInspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            "70000000-0000-0000-0000-000000000088",
					"global_x_position_cm":        51.0, // Hotspot persists!
					"max_temperature_c":           60.5,
					"origin_measurement_event_id": vm1,
					"confirming_event_ids":        []string{vm1, vm2},
				},
			},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize verification: %d: %s", rec.Code, rec.Body.String())
		}

		// Verification result must be 'unresolved' and anomaly closed as 'unresolved'
		rec = doJSON(http.MethodGet, "/api/v1/modules/"+modID+"/latest-inspection", techAuth.AccessToken, nil)
		var verifUnresLatest struct {
			LatestInspection struct {
				Inspection struct {
					VerificationResult *string `json:"verification_result"`
				} `json:"inspection"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &verifUnresLatest)
		if verifUnresLatest.LatestInspection.Inspection.VerificationResult == nil || *verifUnresLatest.LatestInspection.Inspection.VerificationResult != "unresolved" {
			t.Fatalf("expected verification_result 'unresolved', got %v", verifUnresLatest.LatestInspection.Inspection.VerificationResult)
		}

		anomUUID, _ := auth.ParseUUID(anomID)
		modUUID, _ := auth.ParseUUID(modID)
		anomRow, _ := q.GetAnomalyEventByID(ctx, db.GetAnomalyEventByIDParams{
			ID:       anomUUID,
			ModuleID: modUUID,
		})
		if anomRow.Status != "unresolved" || anomRow.ClosedAt == nil {
			t.Fatalf("expected anomaly closed as unresolved, got status=%q closed_at=%v", anomRow.Status, anomRow.ClosedAt)
		}
	})

	// 16. Verificação após limpeza interrompida mantém anomalia open com retry_pending
	t.Run("VerificationAfterInterruptedCleaningKeepsOpenRetryPending", func(t *testing.T) {
		inspSourceID := "80000000-0000-0000-0000-000000000001"
		m1 := "80000000-0000-0000-0000-000000000011"
		m2 := "80000000-0000-0000-0000-000000000012"
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"batch": []map[string]any{
				{"source_event_id": m1, "x_position_cm": 70.0, "max_temperature_c": 54.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": m2, "x_position_cm": 72.0, "max_temperature_c": 55.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry: %d", rec.Code)
		}

		anomSourceID := "80000000-0000-0000-0000-000000000099"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            anomSourceID,
					"global_x_position_cm":        71.0,
					"max_temperature_c":           55.0,
					"origin_measurement_event_id": m1,
					"confirming_event_ids":        []string{m1, m2},
				},
			},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize: %d", rec.Code)
		}
		var finResp struct {
			LatestInspection struct {
				ConfirmedAnomalies []struct {
					ID string `json:"id"`
				} `json:"confirmed_anomalies"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &finResp)
		if len(finResp.LatestInspection.ConfirmedAnomalies) == 0 {
			t.Fatalf("expected anomaly created")
		}
		anomID := finResp.LatestInspection.ConfirmedAnomalies[0].ID

		// Interrupted cleaning (status = failed, pump_actuated = true, attempt = 1)
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/cleanings", techAuth.AccessToken, map[string]any{
			"anomaly_event_id":          anomID,
			"target_x_position_cm":      71.0,
			"pump_actuated":             true,
			"attempt_number":            1,
			"duration_seconds":          12.0,
			"estimated_water_volume_ml": 25.0,
			"status":                    "failed",
			"failure_reason":            "Water reservoir low level tripped during wash",
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("interrupted cleaning: %d: %s", rec.Code, rec.Body.String())
		}
		var cleanFailResp struct {
			Cleaning struct {
				ID             string `json:"id"`
				AnomalyEventID string `json:"anomaly_event_id"`
			} `json:"cleaning"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &cleanFailResp)

		// Verification telemetry
		verifInspSourceID := "80000000-0000-0000-0000-000000000002"
		vm1 := "80000000-0000-0000-0000-000000000021"
		vm2 := "80000000-0000-0000-0000-000000000022"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": verifInspSourceID,
			"inspection_type":           "verification",
			"cleaning_operation_id":     cleanFailResp.Cleaning.ID,
			"batch": []map[string]any{
				{"source_event_id": vm1, "x_position_cm": 70.0, "max_temperature_c": 54.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
				{"source_event_id": vm2, "x_position_cm": 72.0, "max_temperature_c": 55.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("verif telemetry: %d: %s", rec.Code, rec.Body.String())
		}

		// Finalize with hotspot STILL PERSISTING at x=71.0
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+verifInspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"baseline_temperature_c": 35.0,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":            "80000000-0000-0000-0000-000000000088",
					"global_x_position_cm":        71.0,
					"max_temperature_c":           55.0,
					"origin_measurement_event_id": vm1,
					"confirming_event_ids":        []string{vm1, vm2},
				},
			},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize verification: %d: %s", rec.Code, rec.Body.String())
		}

		// Verify anomaly remains OPEN with retry_pending = true!
		anomUUID, _ := auth.ParseUUID(cleanFailResp.Cleaning.AnomalyEventID)
		modUUID, _ := auth.ParseUUID(modID)
		anomRow, err := q.GetAnomalyEventByID(ctx, db.GetAnomalyEventByIDParams{
			ID:       anomUUID,
			ModuleID: modUUID,
		})
		if err != nil {
			t.Fatalf("get anomaly: %v", err)
		}
		if anomRow.Status != "open" || !anomRow.RetryPending {
			t.Fatalf("expected anomaly status 'open' with retry_pending=true, got status=%q, retry_pending=%v", anomRow.Status, anomRow.RetryPending)
		}
	})

	// 17. Verificação inválida mantém avaliação pendente
	t.Run("VerificationInvalidKeepsEvaluationPending", func(t *testing.T) {
		// Non-existent cleaning_operation_id
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": "85000000-0000-0000-0000-000000000001",
			"inspection_type":           "verification",
			"cleaning_operation_id":     "85000000-0000-0000-0000-999999999999", // non-existent
			"batch": []map[string]any{
				{"source_event_id": "85000000-0000-0000-0000-000000000011", "x_position_cm": 10.0, "max_temperature_c": 35.0, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			},
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for non-existent cleaning operation, got %d", rec.Code)
		}
	})
}

func TestTelemetryIdempotency(t *testing.T) {
	ctx, conn, tx, _, router, techAuth, modID := setupTelemetryTestEnv(t)
	defer conn.Close(ctx)
	defer tx.Rollback(ctx)

	doJSON := func(method, path, bearer string, body any) *httptest.ResponseRecorder {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
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

	inspSourceID := "90000000-0000-0000-0000-000000000001"
	measSourceID := "90000000-0000-0000-0000-000000000011"
	meas2SourceID := "90000000-0000-0000-0000-000000000012"

	// 1. Enviar lote inicial
	rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"batch": []map[string]any{
			{"source_event_id": measSourceID, "x_position_cm": 15.0, "max_temperature_c": 42.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			{"source_event_id": meas2SourceID, "x_position_cm": 17.0, "max_temperature_c": 43.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
		},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("first telemetry failed: %d: %s", rec.Code, rec.Body.String())
	}

	// 2. Reenviar mesmo lote IDÊNTICO: sucesso idempotente (201), não duplica e não altera medição original
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"batch": []map[string]any{
			{"source_event_id": measSourceID, "x_position_cm": 15.0, "max_temperature_c": 42.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			{"source_event_id": meas2SourceID, "x_position_cm": 17.0, "max_temperature_c": 43.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
		},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("identical resend failed: %d: %s", rec.Code, rec.Body.String())
	}

	// Verificar se continua com exatamente 2 medições e valores originais preservados
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modID+"/measurements", techAuth.AccessToken, nil)
	var measListResp struct {
		Measurements []module.MeasurementDTO `json:"measurements"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &measListResp)
	if len(measListResp.Measurements) != 2 {
		t.Fatalf("expected exactly 2 measurements (no duplicates), got %d", len(measListResp.Measurements))
	}
	for _, m := range measListResp.Measurements {
		if m.SourceEventID == measSourceID {
			if m.XPositionCM != "15.000" || m.MaxTempC != "42.000" {
				t.Fatalf("expected original values (15.000, 42.000) preserved on resend, got x=%q max=%q", m.XPositionCM, m.MaxTempC)
			}
		}
	}

	// 3. Reenviar com conteúdo DIVERGENTE -> retorna 409 Conflict
	// a) Divergente no x_position_cm
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"batch": []map[string]any{
			{"source_event_id": measSourceID, "x_position_cm": 99.0, "max_temperature_c": 42.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
		},
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict on divergent x_position_cm resend, got %d: %s", rec.Code, rec.Body.String())
	}

	// b) Divergente no max_temperature_c
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"batch": []map[string]any{
			{"source_event_id": measSourceID, "x_position_cm": 15.0, "max_temperature_c": 99.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
		},
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict on divergent max_temperature_c resend, got %d: %s", rec.Code, rec.Body.String())
	}

	// c) Divergente no voltage_v
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"batch": []map[string]any{
			{"source_event_id": measSourceID, "x_position_cm": 15.0, "max_temperature_c": 42.0, "voltage_v": 99.0, "current_a": 4.2, "thermal_frame": makeTestFrame768(35.0, nil, false)},
		},
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict on divergent voltage_v resend, got %d: %s", rec.Code, rec.Body.String())
	}

	// d) Divergente no thermal_frame
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"batch": []map[string]any{
			{"source_event_id": measSourceID, "x_position_cm": 15.0, "max_temperature_c": 42.0, "voltage_v": 18.5, "current_a": 4.2, "thermal_frame": makeTestFrame768(99.0, nil, false)},
		},
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict on divergent thermal_frame resend, got %d: %s", rec.Code, rec.Body.String())
	}

	// 4. Finalizar inspeção
	anomSourceID := "90000000-0000-0000-0000-000000000099"
	finalizePayload := map[string]any{
		"baseline_temperature_c": 35.0,
		"confirmed_hotspots": []map[string]any{
			{
				"source_event_id":            anomSourceID,
				"global_x_position_cm":        16.0,
				"max_temperature_c":           43.0,
				"origin_measurement_event_id": measSourceID,
				"confirming_event_ids":        []string{measSourceID, meas2SourceID},
			},
		},
	}
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, finalizePayload)
	if rec.Code != http.StatusOK {
		t.Fatalf("first finalize: %d: %s", rec.Code, rec.Body.String())
	}

	// 5. Reenviar mesma finalização: não duplica anomalia
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, finalizePayload)
	if rec.Code != http.StatusOK {
		t.Fatalf("resend finalize: %d: %s", rec.Code, rec.Body.String())
	}

	// Verificar se continua com exatamente 1 anomalia
	rec = doJSON(http.MethodGet, "/api/v1/modules/"+modID+"/latest-inspection", techAuth.AccessToken, nil)
	var latestResp struct {
		LatestInspection struct {
			ConfirmedAnomalies []any `json:"confirmed_anomalies"`
		} `json:"latest_inspection"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &latestResp)
	if len(latestResp.LatestInspection.ConfirmedAnomalies) != 1 {
		t.Fatalf("expected 1 anomaly after idempotent finalize resend, got %d", len(latestResp.LatestInspection.ConfirmedAnomalies))
	}
}

func TestCleaningIngestIdempotencyAndVerificationSpatialProximity(t *testing.T) {
	ctx, conn, tx, q, router, techAuth, modID := setupTelemetryTestEnv(t)
	defer conn.Close(ctx)
	defer tx.Rollback(ctx)

	doJSON := func(method, path, bearer string, body any) *httptest.ResponseRecorder {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
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

	// 1. Ingest telemetry measurements (meas1 at X=16.0cm, meas2 at X=50.0cm)
	inspSourceID := "77000000-0000-0000-0000-000000000001"
	meas1 := "77000000-0000-0000-0000-000000000011"
	meas2 := "77000000-0000-0000-0000-000000000012"
	v, a := 18.5, 4.2
	rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"inspection_type":           "scheduled",
		"batch": []map[string]any{
			{"source_event_id": meas1, "x_position_cm": 16.0, "max_temperature_c": 55.0, "voltage_v": v, "current_a": a, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			{"source_event_id": meas2, "x_position_cm": 50.0, "max_temperature_c": 56.0, "voltage_v": v, "current_a": a, "thermal_frame": makeTestFrame768(35.0, nil, false)},
		},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("telemetry ingest: %d: %s", rec.Code, rec.Body.String())
	}

	// 2. Finalize with SINGLE confirming event ID (origin measurement alone)
	anomSourceID := "77000000-0000-0000-0000-000000000099"
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
		"baseline_temperature_c": 35.0,
		"confirmed_hotspots": []map[string]any{
			{
				"source_event_id":            anomSourceID,
				"global_x_position_cm":        16.0,
				"max_temperature_c":           55.0,
				"origin_measurement_event_id": meas1,
				"confirming_event_ids":        []string{meas1}, // Single confirming event ID!
			},
		},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("single confirming event finalize should succeed, got %d: %s", rec.Code, rec.Body.String())
	}

	var finResp struct {
		LatestInspection struct {
			ConfirmedAnomalies []struct {
				ID string `json:"id"`
			} `json:"confirmed_anomalies"`
		} `json:"latest_inspection"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &finResp)
	if len(finResp.LatestInspection.ConfirmedAnomalies) != 1 {
		t.Fatalf("expected 1 anomaly, got %d (body: %s)", len(finResp.LatestInspection.ConfirmedAnomalies), rec.Body.String())
	}
	anomalyID := finResp.LatestInspection.ConfirmedAnomalies[0].ID

	// 3. Ingest Cleaning with source_event_id
	cleanSrcID1 := "77000000-0000-0000-0000-000000000081"
	cleanPayload := map[string]any{
		"source_event_id":      cleanSrcID1,
		"anomaly_event_id":     anomalyID,
		"target_x_position_cm": 16.0,
		"pump_actuated":        true,
		"attempt_number":       1,
		"duration_seconds":     3.5,
		"status":               "completed",
	}
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/cleanings", techAuth.AccessToken, cleanPayload)
	if rec.Code != http.StatusCreated {
		t.Fatalf("cleaning 1 failed: %d: %s", rec.Code, rec.Body.String())
	}
	var cResp1 struct {
		Cleaning struct {
			ID            string `json:"id"`
			SourceEventID string `json:"source_event_id"`
		} `json:"cleaning"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &cResp1)
	firstCleaningID := cResp1.Cleaning.ID
	if cResp1.Cleaning.SourceEventID != cleanSrcID1 {
		t.Fatalf("expected source_event_id %s, got %s", cleanSrcID1, cResp1.Cleaning.SourceEventID)
	}

	// 4. Idempotency test: Re-send with same source_event_id
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/cleanings", techAuth.AccessToken, cleanPayload)
	if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		t.Fatalf("re-send with same source_event_id failed: %d: %s", rec.Code, rec.Body.String())
	}
	var cResp2 struct {
		Cleaning struct {
			ID string `json:"id"`
		} `json:"cleaning"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &cResp2)
	if cResp2.Cleaning.ID != firstCleaningID {
		t.Fatalf("expected same cleaning ID on idempotent resend, got %s vs %s", cResp2.Cleaning.ID, firstCleaningID)
	}

	// 5. Idempotency test: Re-send with different source_event_id but same anomaly_event_id & attempt_number
	cleanSrcID2 := "77000000-0000-0000-0000-000000000082"
	cleanPayloadDiffSource := map[string]any{
		"source_event_id":      cleanSrcID2,
		"anomaly_event_id":     anomalyID,
		"target_x_position_cm": 16.0,
		"pump_actuated":        true,
		"attempt_number":       1,
		"duration_seconds":     3.5,
		"status":               "completed",
	}
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/cleanings", techAuth.AccessToken, cleanPayloadDiffSource)
	if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		t.Fatalf("re-send with same attempt_number should succeed idempotently, got %d: %s", rec.Code, rec.Body.String())
	}
	var cResp3 struct {
		Cleaning struct {
			ID string `json:"id"`
		} `json:"cleaning"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &cResp3)
	if cResp3.Cleaning.ID != firstCleaningID {
		t.Fatalf("expected original cleaning ID for duplicate attempt_number, got %s vs %s", cResp3.Cleaning.ID, firstCleaningID)
	}

	// 6. Verification inspection with a DISTANT hotspot (at X=50.0cm, far from origX=16.0cm)
	verifInspSourceID := "77000000-0000-0000-0000-000000000002"
	vMeas1 := "77000000-0000-0000-0000-000000000021"
	vMeas2 := "77000000-0000-0000-0000-000000000022"
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
		"inspection_source_event_id": verifInspSourceID,
		"inspection_type":           "verification",
		"cleaning_operation_id":     firstCleaningID,
		"batch": []map[string]any{
			{"source_event_id": vMeas1, "x_position_cm": 16.0, "max_temperature_c": 35.0, "voltage_v": v, "current_a": a, "thermal_frame": makeTestFrame768(35.0, nil, false)},
			{"source_event_id": vMeas2, "x_position_cm": 50.0, "max_temperature_c": 58.0, "voltage_v": v, "current_a": a, "thermal_frame": makeTestFrame768(35.0, nil, false)},
		},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("verification telemetry ingest: %d: %s", rec.Code, rec.Body.String())
	}

	// Finalize verification: reports hotspot only at X=50.0cm (NOT at 16.0cm)
	distantHotspotSourceID := "77000000-0000-0000-0000-000000000098"
	rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+verifInspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
		"baseline_temperature_c": 35.0,
		"confirmed_hotspots": []map[string]any{
			{
				"source_event_id":            distantHotspotSourceID,
				"global_x_position_cm":        50.0,
				"max_temperature_c":           58.0,
				"origin_measurement_event_id": vMeas2,
				"confirming_event_ids":        []string{vMeas2},
			},
		},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("verification finalize: %d: %s", rec.Code, rec.Body.String())
	}

	// 7. Spatial proximity check verification:
	// The original anomaly at X=16.0cm MUST be marked 'resolved' because the hotspot at X=50.0cm is distant!
	anomUUID, _ := auth.ParseUUID(anomalyID)
	modUUID, _ := auth.ParseUUID(modID)
	anomRow, err := q.GetAnomalyEventByID(ctx, db.GetAnomalyEventByIDParams{
		ID:       anomUUID,
		ModuleID: modUUID,
	})
	if err != nil {
		t.Fatalf("get anomaly: %v", err)
	}
	if anomRow.Status != "resolved" || anomRow.ClosedAt == nil {
		t.Fatalf("expected anomaly at 16cm to be 'resolved' with closed_at set, got status=%s closed_at=%v", anomRow.Status, anomRow.ClosedAt)
	}
}
