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

func TestManualCleaningWorkflow(t *testing.T) {
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

	// Create a 3-panel module: 100cm each, 5cm spacing -> panels at [0,100], [105,205], [210,310]
	modMac := "02:ab:cd:44:55:66"
	createModRec := doJSON(http.MethodPost, "/api/v1/modules", techToken, map[string]any{
		"name":                          "Manual Cleaning Array",
		"mac_address":                   modMac,
		"panel_length_cm":               100.0,
		"panel_width_cm":                50.0,
		"panel_count":                   3,
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
	require.NotEmpty(t, moduleID)

	// Claim device to obtain device token
	claimRec := doJSON(http.MethodPost, "/api/v1/devices/claim", "", map[string]any{
		"mac_address": modMac,
	})
	require.Equal(t, http.StatusOK, claimRec.Code, claimRec.Body.String())

	var claimResp struct {
		DeviceToken string `json:"device_token"`
	}
	require.NoError(t, json.Unmarshal(claimRec.Body.Bytes(), &claimResp))
	deviceToken := claimResp.DeviceToken
	require.NotEmpty(t, deviceToken)

	// 1. Authorization: unauthenticated request -> 401
	unauthRec := doJSON(http.MethodPost, "/api/v1/modules/"+moduleID+"/trigger-cleaning", "", map[string]any{
		"target_x_position_cm": 150.0,
	})
	assert.Equal(t, http.StatusUnauthorized, unauthRec.Code)

	// 2. Out-of-bounds coordinate -> 400
	oobRec := doJSON(http.MethodPost, "/api/v1/modules/"+moduleID+"/trigger-cleaning", techToken, map[string]any{
		"target_x_position_cm": 350.0,
	})
	assert.Equal(t, http.StatusBadRequest, oobRec.Code, oobRec.Body.String())

	negRec := doJSON(http.MethodPost, "/api/v1/modules/"+moduleID+"/trigger-cleaning", techToken, map[string]any{
		"target_x_position_cm": -5.0,
	})
	assert.Equal(t, http.StatusBadRequest, negRec.Code, negRec.Body.String())

	// 3. Gap coordinate (between panel 1 [0..100] and panel 2 [105..205]) -> 400
	gapRec := doJSON(http.MethodPost, "/api/v1/modules/"+moduleID+"/trigger-cleaning", techToken, map[string]any{
		"target_x_position_cm": 102.5,
	})
	assert.Equal(t, http.StatusBadRequest, gapRec.Code, gapRec.Body.String())

	// 4. Valid coordinate (panel 2: 150.0 cm) -> 200 OK
	validRec := doJSON(http.MethodPost, "/api/v1/modules/"+moduleID+"/trigger-cleaning", techToken, map[string]any{
		"target_x_position_cm": 150.0,
	})
	require.Equal(t, http.StatusOK, validRec.Code, validRec.Body.String())

	var triggerResp struct {
		Success           bool    `json:"success"`
		Message           string  `json:"message"`
		Status            string  `json:"status"`
		TargetXPositionCm float64 `json:"target_x_position_cm"`
	}
	require.NoError(t, json.Unmarshal(validRec.Body.Bytes(), &triggerResp))
	assert.True(t, triggerResp.Success)
	assert.Equal(t, "scheduled", triggerResp.Status)
	assert.InDelta(t, 150.0, triggerResp.TargetXPositionCm, 1e-6)
	assert.Contains(t, triggerResp.Message, "Panel 2")

	// 5. Device ping without ack -> manual_cleaning_pending is true, target_x_position_cm is 150.0
	pingNoAckRec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/ping", deviceToken, map[string]any{
		"limits_check_passed":   true,
		"thermal_sensor_active": true,
	})
	require.Equal(t, http.StatusOK, pingNoAckRec.Code, pingNoAckRec.Body.String())

	var pingNoAckResp struct {
		DeviceStatus struct {
			ManualCleaningPending   bool     `json:"manual_cleaning_pending"`
			ManualCleaningTargetXCm *float64 `json:"manual_cleaning_target_x_cm"`
		} `json:"device_status"`
	}
	require.NoError(t, json.Unmarshal(pingNoAckRec.Body.Bytes(), &pingNoAckResp))
	assert.True(t, pingNoAckResp.DeviceStatus.ManualCleaningPending, pingNoAckRec.Body.String())
	require.NotNil(t, pingNoAckResp.DeviceStatus.ManualCleaningTargetXCm, pingNoAckRec.Body.String())
	assert.InDelta(t, 150.0, *pingNoAckResp.DeviceStatus.ManualCleaningTargetXCm, 1e-6)

	// 6. Device ping with manual_cleaning_ack: true -> clears pending and target
	pingAckRec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/ping", deviceToken, map[string]any{
		"limits_check_passed":   true,
		"thermal_sensor_active": true,
		"manual_cleaning_ack":   true,
	})
	require.Equal(t, http.StatusOK, pingAckRec.Code, pingAckRec.Body.String())

	var pingAckResp struct {
		DeviceStatus struct {
			ManualCleaningPending   bool     `json:"manual_cleaning_pending"`
			ManualCleaningTargetXCm *float64 `json:"manual_cleaning_target_x_cm"`
		} `json:"device_status"`
	}
	require.NoError(t, json.Unmarshal(pingAckRec.Body.Bytes(), &pingAckResp))
	assert.False(t, pingAckResp.DeviceStatus.ManualCleaningPending)
	assert.Nil(t, pingAckResp.DeviceStatus.ManualCleaningTargetXCm)
}
