package httpapi_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestFinalizeInspectionStatusOptions(t *testing.T) {
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

	t.Run("FinalizeWithFailedStatusAndFailureReason", func(t *testing.T) {
		inspSourceID := "61000000-0000-0000-0000-000000000001"
		m1 := "61000000-0000-0000-0000-000000000011"
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"source_event_id":           m1,
			"x_position_cm":             15.0,
			"max_temperature_c":         35.0,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("expected 201 telemetry, got %d: %s", rec.Code, rec.Body.String())
		}

		failStatus := "failed"
		failReason := "camera_overheated"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"status":         failStatus,
			"failure_reason": failReason,
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 finalizing failed inspection, got %d: %s", rec.Code, rec.Body.String())
		}

		var finResp struct {
			LatestInspection struct {
				Inspection struct {
					Status        string  `json:"status"`
					FailureReason *string `json:"failure_reason"`
					FinishedAt    *string `json:"finished_at"`
				} `json:"inspection"`
			} `json:"latest_inspection"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &finResp); err != nil {
			t.Fatalf("decode finalize response: %v", err)
		}
		if finResp.LatestInspection.Inspection.Status != "failed" {
			t.Fatalf("expected status 'failed', got %q", finResp.LatestInspection.Inspection.Status)
		}
		if finResp.LatestInspection.Inspection.FailureReason == nil || *finResp.LatestInspection.Inspection.FailureReason != "camera_overheated" {
			t.Fatalf("expected failure_reason 'camera_overheated', got %+v", finResp.LatestInspection.Inspection.FailureReason)
		}
		if finResp.LatestInspection.Inspection.FinishedAt == nil {
			t.Fatalf("expected non-nil finished_at")
		}

		// Idempotency: resending finalize on already failed inspection
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"status": failStatus,
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 idempotent finalize resend, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("FinalizeWithCancelledStatus", func(t *testing.T) {
		inspSourceID := "62000000-0000-0000-0000-000000000001"
		m1 := "62000000-0000-0000-0000-000000000011"
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"source_event_id":           m1,
			"x_position_cm":             25.0,
			"max_temperature_c":         36.0,
			"thermal_frame":             makeTestFrame768(36.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("expected 201 telemetry, got %d: %s", rec.Code, rec.Body.String())
		}

		cancelStatus := "cancelled"
		cancelReason := "user_aborted_via_app"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"status":         cancelStatus,
			"failure_reason": cancelReason,
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 finalizing cancelled inspection, got %d: %s", rec.Code, rec.Body.String())
		}

		var finResp struct {
			LatestInspection struct {
				Inspection struct {
					Status        string  `json:"status"`
					FailureReason *string `json:"failure_reason"`
				} `json:"inspection"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &finResp)
		if finResp.LatestInspection.Inspection.Status != "cancelled" {
			t.Fatalf("expected status 'cancelled', got %q", finResp.LatestInspection.Inspection.Status)
		}
		if finResp.LatestInspection.Inspection.FailureReason == nil || *finResp.LatestInspection.Inspection.FailureReason != "user_aborted_via_app" {
			t.Fatalf("expected failure_reason 'user_aborted_via_app', got %+v", finResp.LatestInspection.Inspection.FailureReason)
		}
	})

	t.Run("FinalizeWithInvalidStatusRejected", func(t *testing.T) {
		inspSourceID := "63000000-0000-0000-0000-000000000001"
		m1 := "63000000-0000-0000-0000-000000000011"
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"source_event_id":           m1,
			"x_position_cm":             10.0,
			"max_temperature_c":         35.0,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("expected 201 telemetry, got %d", rec.Code)
		}

		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"status": "in_progress", // Invalid status for finalization!
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for invalid status, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestAbortInspectionEndpoints(t *testing.T) {
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

	// 1. Get module MAC address to claim device
	var mac string
	err := tx.QueryRow(ctx, "SELECT mac_address FROM modules WHERE id = $1", modID).Scan(&mac)
	if err != nil {
		t.Fatalf("failed to query mac: %v", err)
	}

	// Claim device to get deviceToken
	rec := doJSON(http.MethodPost, "/api/v1/devices/claim", "", map[string]any{
		"mac_address":      mac,
		"firmware_version": "v1.0.0",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("claim failed: %d: %s", rec.Code, rec.Body.String())
	}
	var claimResp struct {
		ModuleID    string `json:"module_id"`
		DeviceToken string `json:"device_token"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &claimResp)

	t.Run("AbortViaDeviceEndpointWithExplicitReason", func(t *testing.T) {
		inspSourceID := "71000000-0000-0000-0000-000000000001"
		m1 := "71000000-0000-0000-0000-000000000011"
		// Start inspection via telemetry
		rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/telemetry", claimResp.DeviceToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"source_event_id":           m1,
			"x_position_cm":             10.0,
			"max_temperature_c":         35.0,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry failed: %d: %s", rec.Code, rec.Body.String())
		}

		// Abort via /api/v1/devices/{id}/inspections/{sourceEventId}/abort
		rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/inspections/"+inspSourceID+"/abort", claimResp.DeviceToken, map[string]any{
			"failure_reason": "rail_motor_jammed",
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("abort failed: %d: %s", rec.Code, rec.Body.String())
		}

		var abortResp struct {
			Status  string `json:"status"`
			Message string `json:"message"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &abortResp); err != nil {
			t.Fatalf("decode abort response: %v", err)
		}
		if abortResp.Status != "failed" || abortResp.Message != "inspection aborted" {
			t.Fatalf("unexpected abort response: %+v", abortResp)
		}

		// Verify DB inspection status
		var dbStatus, dbFailReason string
		err := tx.QueryRow(ctx, "SELECT status, failure_reason FROM inspections WHERE source_event_id = $1", inspSourceID).Scan(&dbStatus, &dbFailReason)
		if err != nil {
			t.Fatalf("query inspection: %v", err)
		}
		if dbStatus != "failed" || dbFailReason != "rail_motor_jammed" {
			t.Fatalf("expected status 'failed' and reason 'rail_motor_jammed', got %q, %q", dbStatus, dbFailReason)
		}

		// Idempotent resend
		rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/inspections/"+inspSourceID+"/abort", claimResp.DeviceToken, map[string]any{
			"failure_reason": "rail_motor_jammed",
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 on idempotent abort resend, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("AbortViaDeviceEndpointWithoutIDInPath", func(t *testing.T) {
		inspSourceID := "72000000-0000-0000-0000-000000000001"
		m1 := "72000000-0000-0000-0000-000000000011"
		rec = doJSON(http.MethodPost, "/api/v1/devices/"+claimResp.ModuleID+"/telemetry", claimResp.DeviceToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"source_event_id":           m1,
			"x_position_cm":             10.0,
			"max_temperature_c":         35.0,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry failed: %d: %s", rec.Code, rec.Body.String())
		}

		// Abort via /api/v1/devices/inspections/{sourceEventId}/abort (direct device route)
		rec = doJSON(http.MethodPost, "/api/v1/devices/inspections/"+inspSourceID+"/abort", claimResp.DeviceToken, map[string]any{
			"failure_reason": "battery_depleted",
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("abort without ID in path failed: %d: %s", rec.Code, rec.Body.String())
		}

		var dbStatus, dbFailReason string
		err := tx.QueryRow(ctx, "SELECT status, failure_reason FROM inspections WHERE source_event_id = $1", inspSourceID).Scan(&dbStatus, &dbFailReason)
		if err != nil {
			t.Fatalf("query inspection: %v", err)
		}
		if dbStatus != "failed" || dbFailReason != "battery_depleted" {
			t.Fatalf("expected failed / battery_depleted, got %q, %q", dbStatus, dbFailReason)
		}
	})

	t.Run("AbortViaModuleEndpointDefaultReason", func(t *testing.T) {
		inspSourceID := "73000000-0000-0000-0000-000000000001"
		m1 := "73000000-0000-0000-0000-000000000011"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"source_event_id":           m1,
			"x_position_cm":             10.0,
			"max_temperature_c":         35.0,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry failed: %d: %s", rec.Code, rec.Body.String())
		}

		// Abort via module route with empty body -> defaults to "aborted_by_device"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+inspSourceID+"/abort", techAuth.AccessToken, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("abort failed: %d: %s", rec.Code, rec.Body.String())
		}

		var dbStatus, dbFailReason string
		err := tx.QueryRow(ctx, "SELECT status, failure_reason FROM inspections WHERE source_event_id = $1", inspSourceID).Scan(&dbStatus, &dbFailReason)
		if err != nil {
			t.Fatalf("query inspection: %v", err)
		}
		if dbStatus != "failed" || dbFailReason != "aborted_by_device" {
			t.Fatalf("expected failed / aborted_by_device, got %q, %q", dbStatus, dbFailReason)
		}
	})

	t.Run("AbortNonExistentInspectionReturns404", func(t *testing.T) {
		nonExistentSourceID := "99999999-9999-9999-9999-999999999999"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+nonExistentSourceID+"/abort", techAuth.AccessToken, nil)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("expected 404 for non-existent inspection abort, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestTriggerManualInspectionStaleHandling(t *testing.T) {
	ctx, conn, tx, _, router, techAuth, _ := setupTelemetryTestEnv(t)
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

	createModule := func(name string) string {
		mac := fmt.Sprintf("02:%02x:%02x:%02x:%02x:%02x", time.Now().UnixNano()&0xff, (time.Now().UnixNano()>>8)&0xff, (time.Now().UnixNano()>>16)&0xff, (time.Now().UnixNano()>>24)&0xff, (time.Now().UnixNano()>>32)&0xff)
		rec := doJSON(http.MethodPost, "/api/v1/modules", techAuth.AccessToken, map[string]any{
			"name":                     name,
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
			t.Fatalf("create module %s failed: %d: %s", name, rec.Code, rec.Body.String())
		}
		var modCreated struct {
			Module struct {
				ID string `json:"id"`
			} `json:"module"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &modCreated)
		return modCreated.Module.ID
	}

	t.Run("NonStaleInspectionBlocksTrigger", func(t *testing.T) {
		modID := createModule("NonStale Test Module")
		inspSourceID := "81000000-0000-0000-0000-000000000001"
		m1 := "81000000-0000-0000-0000-000000000011"
		// Start inspection via telemetry (in_progress, started right now)
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"source_event_id":           m1,
			"x_position_cm":             10.0,
			"max_temperature_c":         35.0,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry: %d: %s", rec.Code, rec.Body.String())
		}

		// Trigger manual inspection
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/trigger-inspection", techAuth.AccessToken, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}
		var trigResp struct {
			Success bool   `json:"success"`
			Status  string `json:"status"`
			Message string `json:"message"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &trigResp)
		if trigResp.Status != "in_progress" || trigResp.Message != "Inspection is already in progress on this module" {
			t.Fatalf("expected in_progress status and already in progress message, got %+v", trigResp)
		}
	})

	t.Run("StaleInspectionAutoFailsAndAllowsNewSchedule", func(t *testing.T) {
		modID := createModule("Stale Test Module")
		inspSourceID := "82000000-0000-0000-0000-000000000001"
		m1 := "82000000-0000-0000-0000-000000000011"
		// Start inspection via telemetry
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": inspSourceID,
			"source_event_id":           m1,
			"x_position_cm":             10.0,
			"max_temperature_c":         35.0,
			"thermal_frame":             makeTestFrame768(35.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry: %d: %s", rec.Code, rec.Body.String())
		}

		// Make the inspection stale: 20 minutes ago
		staleTime := time.Now().Add(-20 * time.Minute)
		_, err := tx.Exec(ctx, `
			UPDATE inspections
			SET updated_at = $1, started_at = $1, created_at = $1, scheduled_for = $1
			WHERE module_id = $2 AND source_event_id = $3
		`, staleTime, modID, inspSourceID)
		if err != nil {
			t.Fatalf("failed to make inspection stale: %v", err)
		}

		// Trigger manual inspection
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/trigger-inspection", techAuth.AccessToken, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 on trigger-inspection with stale inspection, got %d: %s", rec.Code, rec.Body.String())
		}
		var trigResp struct {
			Success bool   `json:"success"`
			Status  string `json:"status"`
			Message string `json:"message"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &trigResp)
		if !trigResp.Success || trigResp.Status != "scheduled" {
			t.Fatalf("expected success true and scheduled status, got %+v", trigResp)
		}

		// Verify the stale inspection was marked as 'failed' with failure_reason = 'device_timeout_inactivity'
		var staleStatus, staleReason string
		err = tx.QueryRow(ctx, "SELECT status, failure_reason FROM inspections WHERE source_event_id = $1", inspSourceID).Scan(&staleStatus, &staleReason)
		if err != nil {
			t.Fatalf("query stale inspection: %v", err)
		}
		if staleStatus != "failed" {
			t.Fatalf("expected stale inspection to be 'failed', got %q", staleStatus)
		}
		if staleReason != "device_timeout_inactivity" {
			t.Fatalf("expected failure_reason 'device_timeout_inactivity', got %q", staleReason)
		}

		// Verify a new scheduled inspection exists
		var scheduledCount int
		err = tx.QueryRow(ctx, "SELECT count(*) FROM inspections WHERE module_id = $1 AND status = 'scheduled'", modID).Scan(&scheduledCount)
		if err != nil {
			t.Fatalf("query scheduled count: %v", err)
		}
		if scheduledCount != 1 {
			t.Fatalf("expected 1 scheduled inspection, got %d", scheduledCount)
		}
	})

	t.Run("CompletedInspectionPreservedDuringScheduledInspection", func(t *testing.T) {
		modID := createModule("Preserve Completed Test Module")
		insp1SourceID := "82000000-0000-0000-0000-000000000001"
		m1 := "82000000-0000-0000-0000-000000000011"

		// 1. Ingest telemetry for initial inspection
		rec := doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": insp1SourceID,
			"source_event_id":           m1,
			"x_position_cm":             15.0,
			"max_temperature_c":         42.0,
			"thermal_frame":             makeTestFrame768(42.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry: %d: %s", rec.Code, rec.Body.String())
		}

		// 2. Finalize initial inspection with baseline and an anomaly
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+insp1SourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"status":                 "completed",
			"baseline_temperature_c": 25.5,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":             "82000000-0000-0000-0000-000000000099",
					"global_x_position_cm":        15.0,
					"max_temperature_c":           42.0,
					"origin_measurement_event_id": m1,
					"confirming_event_ids":        []string{m1},
				},
			},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize insp1: %d: %s", rec.Code, rec.Body.String())
		}

		// 3. Verify latest-inspection returns completed inspection
		rec = doJSON(http.MethodGet, "/api/v1/modules/"+modID+"/latest-inspection", techAuth.AccessToken, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
		var latest1 struct {
			LatestInspection struct {
				Inspection struct {
					SourceEventID        string   `json:"source_event_id"`
					BaselineTemperatureC *float64 `json:"baseline_temperature_c"`
					Status               string   `json:"status"`
				} `json:"inspection"`
				ConfirmedAnomalies []any `json:"confirmed_anomalies"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &latest1)
		if latest1.LatestInspection.Inspection.SourceEventID != insp1SourceID {
			t.Fatalf("expected %s, got %s", insp1SourceID, latest1.LatestInspection.Inspection.SourceEventID)
		}
		if latest1.LatestInspection.Inspection.BaselineTemperatureC == nil || *latest1.LatestInspection.Inspection.BaselineTemperatureC != 25.5 {
			t.Fatalf("expected baseline 25.5, got %v", latest1.LatestInspection.Inspection.BaselineTemperatureC)
		}
		if len(latest1.LatestInspection.ConfirmedAnomalies) != 1 {
			t.Fatalf("expected 1 anomaly, got %d", len(latest1.LatestInspection.ConfirmedAnomalies))
		}

		// 4. Trigger manual inspection (schedules new inspection)
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/trigger-inspection", techAuth.AccessToken, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 triggering manual inspection, got %d: %s", rec.Code, rec.Body.String())
		}

		// 5. Verify latest-inspection STILL serves the completed inspection (preserving colormap and anomalies!)
		rec = doJSON(http.MethodGet, "/api/v1/modules/"+modID+"/latest-inspection", techAuth.AccessToken, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
		var latestDuringScheduled struct {
			LatestInspection struct {
				Inspection struct {
					SourceEventID        string   `json:"source_event_id"`
					BaselineTemperatureC *float64 `json:"baseline_temperature_c"`
					Status               string   `json:"status"`
				} `json:"inspection"`
				ConfirmedAnomalies []any `json:"confirmed_anomalies"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &latestDuringScheduled)
		if latestDuringScheduled.LatestInspection.Inspection.SourceEventID != insp1SourceID {
			t.Fatalf("expected latest-inspection to preserve completed %s during scheduled state, got %s", insp1SourceID, latestDuringScheduled.LatestInspection.Inspection.SourceEventID)
		}
		if latestDuringScheduled.LatestInspection.Inspection.BaselineTemperatureC == nil || *latestDuringScheduled.LatestInspection.Inspection.BaselineTemperatureC != 25.5 {
			t.Fatalf("expected preserved baseline 25.5, got %v", latestDuringScheduled.LatestInspection.Inspection.BaselineTemperatureC)
		}
		if len(latestDuringScheduled.LatestInspection.ConfirmedAnomalies) != 1 {
			t.Fatalf("expected preserved 1 anomaly, got %d", len(latestDuringScheduled.LatestInspection.ConfirmedAnomalies))
		}

		// 6. Ingest telemetry for the 2nd inspection and finalize it
		insp2SourceID := "82000000-0000-0000-0000-000000000002"
		m2 := "82000000-0000-0000-0000-000000000022"
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/telemetry", techAuth.AccessToken, map[string]any{
			"inspection_source_event_id": insp2SourceID,
			"source_event_id":           m2,
			"x_position_cm":             15.0,
			"max_temperature_c":         28.0,
			"thermal_frame":             makeTestFrame768(28.0, nil, false),
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("telemetry insp2: %d: %s", rec.Code, rec.Body.String())
		}
		rec = doJSON(http.MethodPost, "/api/v1/modules/"+modID+"/inspections/"+insp2SourceID+"/finalize", techAuth.AccessToken, map[string]any{
			"status":                 "completed",
			"baseline_temperature_c": 26.0,
			"confirmed_hotspots":     []map[string]any{},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("finalize insp2: %d: %s", rec.Code, rec.Body.String())
		}

		// 7. Verify latest-inspection immediately updates to the newly completed scan
		rec = doJSON(http.MethodGet, "/api/v1/modules/"+modID+"/latest-inspection", techAuth.AccessToken, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
		var latest2 struct {
			LatestInspection struct {
				Inspection struct {
					SourceEventID        string   `json:"source_event_id"`
					BaselineTemperatureC *float64 `json:"baseline_temperature_c"`
					Status               string   `json:"status"`
				} `json:"inspection"`
				ConfirmedAnomalies []any `json:"confirmed_anomalies"`
			} `json:"latest_inspection"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &latest2)
		if latest2.LatestInspection.Inspection.SourceEventID != insp2SourceID {
			t.Fatalf("expected updated %s, got %s", insp2SourceID, latest2.LatestInspection.Inspection.SourceEventID)
		}
		if latest2.LatestInspection.Inspection.BaselineTemperatureC == nil || *latest2.LatestInspection.Inspection.BaselineTemperatureC != 26.0 {
			t.Fatalf("expected new baseline 26.0, got %v", latest2.LatestInspection.Inspection.BaselineTemperatureC)
		}
		if len(latest2.LatestInspection.ConfirmedAnomalies) != 0 {
			t.Fatalf("expected 0 anomalies after new clean scan, got %d", len(latest2.LatestInspection.ConfirmedAnomalies))
		}
	})
}
