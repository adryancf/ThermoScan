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

func TestFirmwareStateTrackingAndLogs(t *testing.T) {
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

	modMac := "02:ab:cd:77:88:99"
	createModRec := doJSON(http.MethodPost, "/api/v1/modules", techToken, map[string]any{
		"name":                          "Firmware State Array",
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

	// 1. State transitions with same occurred_at -> seq tie-break + NTP fallback (< 1000000000)
	sameTs := int64(1700000100)
	ping1Rec := doJSON(http.MethodPost, "/api/v1/modules/"+moduleID+"/device-ping", deviceToken, map[string]any{
		"firmware_state":        "INSPECTING",
		"firmware_state_detail": "panel 1",
		"state_transitions": []map[string]any{
			{"state": "IDLE", "detail": "boot", "occurred_at": int64(123)}, // NTP fallback -> now()
			{"state": "HOMING", "detail": "start", "occurred_at": sameTs},
			{"state": "INSPECTING", "detail": "panel 1", "occurred_at": sameTs},
		},
	})
	require.Equal(t, http.StatusOK, ping1Rec.Code, ping1Rec.Body.String())

	var pingResp struct {
		DeviceStatus struct {
			FirmwareState          string  `json:"firmware_state"`
			FirmwareStateDetail    *string `json:"firmware_state_detail"`
			FirmwareStateUpdatedAt *string `json:"firmware_state_updated_at"`
		} `json:"device_status"`
	}
	require.NoError(t, json.Unmarshal(ping1Rec.Body.Bytes(), &pingResp))
	assert.Equal(t, "INSPECTING", pingResp.DeviceStatus.FirmwareState)
	require.NotNil(t, pingResp.DeviceStatus.FirmwareStateDetail)
	assert.Equal(t, "panel 1", *pingResp.DeviceStatus.FirmwareStateDetail)
	require.NotNil(t, pingResp.DeviceStatus.FirmwareStateUpdatedAt)

	// 2. Deduplication: empty state_transitions and same firmware_state -> no new log
	ping2Rec := doJSON(http.MethodPost, "/api/v1/modules/"+moduleID+"/device-ping", deviceToken, map[string]any{
		"firmware_state":        "INSPECTING",
		"firmware_state_detail": "panel 1",
	})
	require.Equal(t, http.StatusOK, ping2Rec.Code, ping2Rec.Body.String())

	// 3. Verify GET /state-logs ordering (occurred_at DESC, seq DESC) & NTP fallback
	logsRec := doJSON(http.MethodGet, "/api/v1/modules/"+moduleID+"/state-logs", techToken, nil)
	require.Equal(t, http.StatusOK, logsRec.Code, logsRec.Body.String())

	var logsResp struct {
		Items []struct {
			Seq        int64   `json:"seq"`
			State      string  `json:"state"`
			Detail     *string `json:"detail"`
			OccurredAt string  `json:"occurred_at"`
		} `json:"items"`
	}
	require.NoError(t, json.Unmarshal(logsRec.Body.Bytes(), &logsResp))
	require.Len(t, logsResp.Items, 3)

	// First item should be IDLE (NTP fallback to ~now, which is > 1700000100)
	assert.Equal(t, "IDLE", logsResp.Items[0].State)
	occ0, err := time.Parse(time.RFC3339, logsResp.Items[0].OccurredAt)
	require.NoError(t, err)
	assert.True(t, occ0.Year() >= 2024, "expected NTP fallback to current year, got %v", occ0)

	// Next two items have same occurred_at=1700000100; seq DESC puts INSPECTING before HOMING
	assert.Equal(t, "INSPECTING", logsResp.Items[1].State)
	assert.Equal(t, "HOMING", logsResp.Items[2].State)
	assert.Greater(t, logsResp.Items[1].Seq, logsResp.Items[2].Seq)

	// 4. Verify ListModules exposes firmware_state fields
	listRec := doJSON(http.MethodGet, "/api/v1/modules", techToken, nil)
	require.Equal(t, http.StatusOK, listRec.Code, listRec.Body.String())

	var listResp struct {
		Modules []struct {
			ID                     string  `json:"id"`
			FirmwareState          string  `json:"firmware_state"`
			FirmwareStateDetail    *string `json:"firmware_state_detail"`
			FirmwareStateUpdatedAt *string `json:"firmware_state_updated_at"`
		} `json:"modules"`
	}
	require.NoError(t, json.Unmarshal(listRec.Body.Bytes(), &listResp))
	var found bool
	for _, m := range listResp.Modules {
		if m.ID == moduleID {
			found = true
			assert.Equal(t, "INSPECTING", m.FirmwareState)
			require.NotNil(t, m.FirmwareStateDetail)
			assert.Equal(t, "panel 1", *m.FirmwareStateDetail)
			require.NotNil(t, m.FirmwareStateUpdatedAt)
		}
	}
	assert.True(t, found, "created module not found in ListModules")
}
