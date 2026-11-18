package httpapi_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestResetRoutineWorkflow(t *testing.T) {
	ctx, conn, tx, _, router, techAuth, _ := setupTelemetryTestEnv(t)
	defer conn.Close(ctx)
	defer tx.Rollback(ctx)
	techToken := techAuth.AccessToken

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

	// Create and claim a module
	modMac := "02:ab:cd:77:88:99"
	createModRec := doJSON(http.MethodPost, "/api/v1/modules", techToken, map[string]any{
		"name":                          "Reset Routine Array",
		"mac_address":                   modMac,
		"panel_length_cm":               100.0,
		"panel_width_cm":                50.0,
		"panel_count":                   1,
		"panel_spacing_cm":              5.0,
		"latitude":                      -25.4284,
		"longitude":                     -49.2733,
		"elevation_m":                   934.0,
		"azimuth_deg":                   15.0,
		"tilt_deg":                      20.0,
		"azimuth_source":                "manual",
		"tilt_source":                   "manual",
		"minimum_solar_angle_deg":       10.0,
		"inspection_interval_days":      1,
		"reservoir_nominal_capacity_ml": 5000.0,
	})
	require.Equal(t, http.StatusCreated, createModRec.Code, createModRec.Body.String())

	var modResp struct {
		Module struct {
			ID string `json:"id"`
		} `json:"module"`
	}
	require.NoError(t, json.Unmarshal(createModRec.Body.Bytes(), &modResp))
	moduleID := modResp.Module.ID

	claimRec := doJSON(http.MethodPost, "/api/v1/devices/claim", "", map[string]any{
		"mac_address":      modMac,
		"firmware_version": "1.0.0",
	})
	require.Equal(t, http.StatusOK, claimRec.Code, claimRec.Body.String())
	var claimResp struct {
		DeviceToken string `json:"device_token"`
	}
	require.NoError(t, json.Unmarshal(claimRec.Body.Bytes(), &claimResp))
	deviceToken := claimResp.DeviceToken

	// Set manual flags and insert in_progress inspection & cleaning directly in tx
	_, err := tx.Exec(ctx, `
		UPDATE modules
		SET manual_cleaning_pending = true,
		    manual_cleaning_target_x_cm = 42.5
		WHERE id = $1
	`, moduleID)
	require.NoError(t, err)

	var inspID string
	err = tx.QueryRow(ctx, `
		INSERT INTO inspections (module_id, type, scheduled_for, status, started_at)
		VALUES ($1, 'scheduled', now(), 'in_progress', now())
		RETURNING id
	`, moduleID).Scan(&inspID)
	require.NoError(t, err)

	var measID string
	err = tx.QueryRow(ctx, `
		INSERT INTO measurements (module_id, inspection_id, source_event_id, measured_at, x_position_cm, max_temperature_c, thermal_frame)
		VALUES ($1, $2, gen_random_uuid(), now(), 42.5, 65.0, '[65.0]')
		RETURNING id
	`, moduleID, inspID).Scan(&measID)
	require.NoError(t, err)

	var anomalyID string
	err = tx.QueryRow(ctx, `
		INSERT INTO anomaly_events (module_id, origin_measurement_id, confirming_measurement_ids, source_event_id, x_position_cm, detected_at)
		VALUES ($1, $2, ARRAY[$2::uuid, $2::uuid], gen_random_uuid(), 42.5, now())
		RETURNING id
	`, moduleID, measID).Scan(&anomalyID)
	require.NoError(t, err)

	var cleanID string
	err = tx.QueryRow(ctx, `
		INSERT INTO cleaning_operations (module_id, anomaly_event_id, source_event_id, target_x_position_cm, pump_actuated, attempt_number, status, started_at)
		VALUES ($1, $2, gen_random_uuid(), 42.5, true, 1, 'in_progress', now())
		RETURNING id
	`, moduleID, anomalyID).Scan(&cleanID)
	require.NoError(t, err)

	// 1. Trigger reset routine
	resetRec := doJSON(http.MethodPost, "/api/v1/modules/"+moduleID+"/reset-routine", techToken, nil)
	require.Equal(t, http.StatusOK, resetRec.Code, resetRec.Body.String())

	var resetResp struct {
		Success bool   `json:"success"`
		Status  string `json:"status"`
		Message string `json:"message"`
	}
	require.NoError(t, json.Unmarshal(resetRec.Body.Bytes(), &resetResp))
	assert.True(t, resetResp.Success)
	assert.Equal(t, "reset_requested", resetResp.Status)

	// Verify DB state: reset_pending = true, manual flags cleared, inspection & cleaning aborted
	var resetPending, manualClean bool
	var manualTarget *float64
	err = tx.QueryRow(ctx, `
		SELECT reset_pending, manual_cleaning_pending, manual_cleaning_target_x_cm
		FROM modules WHERE id = $1
	`, moduleID).Scan(&resetPending, &manualClean, &manualTarget)
	require.NoError(t, err)
	assert.True(t, resetPending)
	assert.False(t, manualClean)
	assert.Nil(t, manualTarget)

	var inspStatus string
	var failureReason *string
	err = tx.QueryRow(ctx, `SELECT status, failure_reason FROM inspections WHERE id = $1`, inspID).Scan(&inspStatus, &failureReason)
	require.NoError(t, err)
	assert.Equal(t, "cancelled", inspStatus)
	require.NotNil(t, failureReason)
	assert.Equal(t, "user_reset", *failureReason)

	var cleanStatus string
	err = tx.QueryRow(ctx, `SELECT status FROM cleaning_operations WHERE id = $1`, cleanID).Scan(&cleanStatus)
	require.NoError(t, err)
	assert.Equal(t, "failed", cleanStatus)

	// 2. Device ping with reset_ack: true clears reset_pending
	pingRec := doJSON(http.MethodPost, "/api/v1/modules/"+moduleID+"/device-ping", deviceToken, map[string]any{
		"reset_ack": true,
	})
	require.Equal(t, http.StatusOK, pingRec.Code, pingRec.Body.String())

	var pingResp struct {
		ResetPending bool `json:"reset_pending"`
	}
	require.NoError(t, json.Unmarshal(pingRec.Body.Bytes(), &pingResp))
	assert.False(t, pingResp.ResetPending)

	err = tx.QueryRow(ctx, `SELECT reset_pending FROM modules WHERE id = $1`, moduleID).Scan(&resetPending)
	require.NoError(t, err)
	assert.False(t, resetPending)
}
