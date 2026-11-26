package httpapi_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestContinuousPowerReadingsLiveAndHistory(t *testing.T) {
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

	modMac := "02:ab:cd:44:55:66"
	createModRec := doJSON(http.MethodPost, "/api/v1/modules", techToken, map[string]any{
		"name":                          "Continuous Power Array",
		"mac_address":                   modMac,
		"panel_length_cm":               100.0,
		"panel_width_cm":                50.0,
		"panel_count":                   2,
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

	now := time.Now().UTC()
	t1 := now.Add(-10 * time.Minute).Unix()
	t2 := now.Add(-5 * time.Minute).Unix()

	// Ping 1: both panels valid
	ping1Rec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/ping", deviceToken, map[string]any{
		"firmware_state": "IDLE",
		"power_readings": []map[string]any{
			{"panel_index": 1, "voltage_v": 18.0, "current_a": 0.5, "power_w": 9.0, "measured_at": t1},
			{"panel_index": 2, "voltage_v": 18.2, "current_a": 0.6, "power_w": 10.92, "measured_at": t1},
		},
	})
	require.Equal(t, http.StatusOK, ping1Rec.Code, ping1Rec.Body.String())

	// Ping 2: panel 1 valid, panel 2 disconnected (null readings)
	ping2Rec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/ping", deviceToken, map[string]any{
		"firmware_state": "IDLE",
		"power_readings": []map[string]any{
			{"panel_index": 1, "voltage_v": 19.0, "current_a": 1.2, "power_w": 22.8, "measured_at": t2},
			{"panel_index": 2, "voltage_v": nil, "current_a": nil, "power_w": nil, "measured_at": t2},
		},
	})
	require.Equal(t, http.StatusOK, ping2Rec.Code, ping2Rec.Body.String())

	// 1. Verify live readings on GET /device-status
	statusRec := doJSON(http.MethodGet, "/api/v1/modules/"+moduleID+"/device-status", techToken, nil)
	require.Equal(t, http.StatusOK, statusRec.Code, statusRec.Body.String())

	var statusResp struct {
		DeviceStatus struct {
			LatestPowerAt       *string `json:"latest_power_at"`
			LatestPowerReadings []struct {
				PanelIndex int32    `json:"panel_index"`
				VoltageV   *float64 `json:"voltage_v"`
				CurrentA   *float64 `json:"current_a"`
				PowerW     *float64 `json:"power_w"`
			} `json:"latest_power_readings"`
		} `json:"device_status"`
	}
	require.NoError(t, json.Unmarshal(statusRec.Body.Bytes(), &statusResp))
	require.NotNil(t, statusResp.DeviceStatus.LatestPowerAt)
	require.Len(t, statusResp.DeviceStatus.LatestPowerReadings, 2)
	require.NotNil(t, statusResp.DeviceStatus.LatestPowerReadings[0].PowerW)
	assert.InDelta(t, 22.8, *statusResp.DeviceStatus.LatestPowerReadings[0].PowerW, 0.01)
	assert.Nil(t, statusResp.DeviceStatus.LatestPowerReadings[1].PowerW)

	// 2. Verify series endpoint (1h, all panels)
	seriesRec := doJSON(http.MethodGet, "/api/v1/modules/"+moduleID+"/power-readings/series?range=1h", techToken, nil)
	require.Equal(t, http.StatusOK, seriesRec.Code, seriesRec.Body.String())

	var seriesResp struct {
		Range   string `json:"range"`
		Summary struct {
			TotalReadings int64    `json:"total_readings"`
			PeakPowerW    *float64 `json:"peak_power_w"`
		} `json:"summary"`
		Points []struct {
			BucketAt string   `json:"bucket_at"`
			PowerW   *float64 `json:"power_w"`
		} `json:"points"`
	}
	require.NoError(t, json.Unmarshal(seriesRec.Body.Bytes(), &seriesResp))
	assert.Equal(t, "1h", seriesResp.Range)
	assert.Equal(t, int64(4), seriesResp.Summary.TotalReadings)
	require.NotNil(t, seriesResp.Summary.PeakPowerW)
	assert.InDelta(t, 22.8, *seriesResp.Summary.PeakPowerW, 0.05)
	assert.Len(t, seriesResp.Points, 2)

	// 3. Verify panel_index filter + paginated list
	listRec := doJSON(http.MethodGet, "/api/v1/modules/"+moduleID+"/power-readings?range=all&panel_index=1&page=1&limit=1", techToken, nil)
	require.Equal(t, http.StatusOK, listRec.Code, listRec.Body.String())

	var listResp struct {
		Items []struct {
			PanelIndex int32    `json:"panel_index"`
			PowerW     *float64 `json:"power_w"`
		} `json:"items"`
		Pagination struct {
			TotalCount  int64 `json:"total_count"`
			TotalPages  int   `json:"total_pages"`
			HasNextPage bool  `json:"has_next_page"`
		} `json:"pagination"`
	}
	require.NoError(t, json.Unmarshal(listRec.Body.Bytes(), &listResp))
	assert.Len(t, listResp.Items, 1)
	assert.Equal(t, int32(1), listResp.Items[0].PanelIndex)
	assert.Equal(t, int64(2), listResp.Pagination.TotalCount)
	assert.Equal(t, 2, listResp.Pagination.TotalPages)
	assert.True(t, listResp.Pagination.HasNextPage)
}
