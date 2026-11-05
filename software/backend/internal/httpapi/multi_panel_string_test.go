package httpapi_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func testUUID(suffix int) string {
	return fmt.Sprintf("58000000-0000-0000-0000-%012d", suffix)
}

func TestMultiPanelStringWorkflow(t *testing.T) {
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

	// 1. Create a multi-panel string module (3 panels, 100cm each, 5cm spacing)
	// Total rail length = 3 * 100 + 2 * 5 = 310 cm
	panelLen := 100.0
	panelWidth := 50.0
	panelCount := int32(3)
	panelSpacing := 5.0
	modMac := "02:ab:cd:11:22:33"

	createModRec := doJSON(http.MethodPost, "/api/v1/modules", techToken, map[string]any{
		"name":                          "String Array Bloco A",
		"mac_address":                   modMac,
		"panel_length_cm":               panelLen,
		"panel_width_cm":                panelWidth,
		"panel_count":                   panelCount,
		"panel_spacing_cm":              panelSpacing,
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
			ID            string   `json:"id"`
			TotalLengthCm *float64 `json:"total_length_cm"`
		} `json:"module"`
	}
	require.NoError(t, json.Unmarshal(createModRec.Body.Bytes(), &modResp))
	moduleID := modResp.Module.ID
	require.NotEmpty(t, moduleID)
	require.NotNil(t, modResp.Module.TotalLengthCm)
	assert.InDelta(t, 310.0, *modResp.Module.TotalLengthCm, 1e-3)

	// 2. Claim device to obtain device token
	claimRec := doJSON(http.MethodPost, "/api/v1/devices/claim", "", map[string]any{
		"mac_address":           modMac,
		"firmware_version":      "2.0.0-multi-panel",
		"water_available":       true,
		"limits_check_passed":   true,
		"thermal_sensor_active": true,
	})
	require.Equal(t, http.StatusOK, claimRec.Code, claimRec.Body.String())
	var claimResp struct {
		DeviceToken string `json:"device_token"`
	}
	require.NoError(t, json.Unmarshal(claimRec.Body.Bytes(), &claimResp))
	deviceToken := claimResp.DeviceToken
	require.NotEmpty(t, deviceToken)

	// 3. Get Device Configuration and check geometry
	cfgRec := doJSON(http.MethodGet, "/api/v1/devices/"+moduleID+"/configuration", deviceToken, nil)
	require.Equal(t, http.StatusOK, cfgRec.Code, cfgRec.Body.String())
	var cfgResp struct {
		Geometry struct {
			PanelLengthCm  float64  `json:"panel_length_cm"`
			PanelCount     int32    `json:"panel_count"`
			PanelSpacingCm float64  `json:"panel_spacing_cm"`
			TotalLengthCm  *float64 `json:"total_length_cm"`
		} `json:"geometry"`
	}
	require.NoError(t, json.Unmarshal(cfgRec.Body.Bytes(), &cfgResp))
	assert.Equal(t, 100.0, cfgResp.Geometry.PanelLengthCm)
	assert.Equal(t, int32(3), cfgResp.Geometry.PanelCount)
	assert.Equal(t, 5.0, cfgResp.Geometry.PanelSpacingCm)
	require.NotNil(t, cfgResp.Geometry.TotalLengthCm)
	assert.InDelta(t, 310.0, *cfgResp.Geometry.TotalLengthCm, 1e-3)

	// 4. Telemetry Validation: In inter-panel gap (Panel 1 is [0, 100], Gap 1-2 is (100, 105))
	// X = 102 cm should be REJECTED with 400 COORDINATE_IN_GAP
	inspSourceID := testUUID(1)
	gapMeasID := testUUID(2)
	frameData := makeTestFrame768(25.0, nil, false)

	gapRec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/telemetry", deviceToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"source_event_id":            gapMeasID,
		"x_position_cm":              102.0,
		"max_temperature_c":          25.0,
		"thermal_frame":              frameData,
	})
	assert.Equal(t, http.StatusBadRequest, gapRec.Code)
	assert.Contains(t, gapRec.Body.String(), "COORDINATE_IN_GAP")

	// 5. Telemetry Validation: Out of bounds (X = 350 cm exceeds total string length 310 cm)
	oobMeasID := testUUID(3)
	oobRec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/telemetry", deviceToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"source_event_id":            oobMeasID,
		"x_position_cm":              350.0,
		"max_temperature_c":          25.0,
		"thermal_frame":              frameData,
	})
	assert.Equal(t, http.StatusBadRequest, oobRec.Code)

	// 6. Ingest valid telemetry in Panel 1 (X = 20 cm) and confirm local position
	hotspotTemp := 42.0
	meas1ID := testUUID(11)
	frameHotspot := makeTestFrame768(25.0, &hotspotTemp, false)
	meas1Rec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/telemetry", deviceToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"source_event_id":            meas1ID,
		"x_position_cm":              20.0,
		"max_temperature_c":          hotspotTemp,
		"thermal_frame":              frameHotspot,
	})
	require.Equal(t, http.StatusCreated, meas1Rec.Code, meas1Rec.Body.String())
	var meas1Resp struct {
		Measurement struct {
			PanelIndex       *int32  `json:"panel_index"`
			LocalXPositionCM *string `json:"local_x_position_cm"`
		} `json:"measurement"`
	}
	require.NoError(t, json.Unmarshal(meas1Rec.Body.Bytes(), &meas1Resp))
	require.NotNil(t, meas1Resp.Measurement.PanelIndex)
	assert.Equal(t, int32(1), *meas1Resp.Measurement.PanelIndex)
	require.NotNil(t, meas1Resp.Measurement.LocalXPositionCM)
	assert.Equal(t, "20.00", *meas1Resp.Measurement.LocalXPositionCM)

	// Ingest a second measurement in Panel 1 for hotspot confirmation (X = 20.0 cm)
	meas2ID := testUUID(12)
	meas2Rec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/telemetry", deviceToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"source_event_id":            meas2ID,
		"x_position_cm":              20.0,
		"max_temperature_c":          hotspotTemp,
		"thermal_frame":              frameHotspot,
	})
	require.Equal(t, http.StatusCreated, meas2Rec.Code, meas2Rec.Body.String())

	// 7. Ingest valid telemetry in Panel 2 (Gap is 100-105, Panel 2 is [105, 205]; X = 115 cm => local X = 10 cm)
	meas3ID := testUUID(13)
	meas3Rec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/telemetry", deviceToken, map[string]any{
		"inspection_source_event_id": inspSourceID,
		"source_event_id":            meas3ID,
		"x_position_cm":              115.0,
		"max_temperature_c":          25.5,
		"thermal_frame":              frameData,
	})
	require.Equal(t, http.StatusCreated, meas3Rec.Code, meas3Rec.Body.String())
	var meas3Resp struct {
		Measurement struct {
			PanelIndex       *int32  `json:"panel_index"`
			LocalXPositionCM *string `json:"local_x_position_cm"`
		} `json:"measurement"`
	}
	require.NoError(t, json.Unmarshal(meas3Rec.Body.Bytes(), &meas3Resp))
	require.NotNil(t, meas3Resp.Measurement.PanelIndex)
	assert.Equal(t, int32(2), *meas3Resp.Measurement.PanelIndex)
	require.NotNil(t, meas3Resp.Measurement.LocalXPositionCM)
	assert.Equal(t, "10.00", *meas3Resp.Measurement.LocalXPositionCM)

	// 8. Submit Panel 1 Thermal Result via dedicated endpoint
	panel1ResultRec := doJSON(
		http.MethodPost,
		fmt.Sprintf("/api/v1/devices/%s/inspections/%s/panels/1/result", moduleID, inspSourceID),
		deviceToken,
		map[string]any{
			"baseline_temperature_c": 25.0,
			"truncated_by_memory":    false,
			"confirmed_hotspots": []map[string]any{
				{
					"source_event_id":              testUUID(21),
					"global_x_position_cm":         20.0,
					"max_temperature_c":            hotspotTemp,
					"origin_measurement_event_id":  meas1ID,
					"confirming_event_ids":         []string{meas1ID, meas2ID},
				},
			},
		},
	)
	require.Equal(t, http.StatusOK, panel1ResultRec.Code, panel1ResultRec.Body.String())
	var p1Resp struct {
		PanelResult struct {
			PanelIndex            int32   `json:"panel_index"`
			BaselineTemperatureC float64 `json:"baseline_temperature_c"`
			TruncatedByMemory     bool    `json:"truncated_by_memory"`
		} `json:"panel_result"`
		ConfirmedAnomalies []struct {
			ID               string   `json:"id"`
			PanelIndex       *int32   `json:"panel_index"`
			XPositionCM      float64  `json:"x_position_cm"`
			LocalXPositionCM *float64 `json:"local_x_position_cm"`
		} `json:"confirmed_anomalies"`
	}
	require.NoError(t, json.Unmarshal(panel1ResultRec.Body.Bytes(), &p1Resp))
	assert.Equal(t, int32(1), p1Resp.PanelResult.PanelIndex)
	assert.Equal(t, 25.0, p1Resp.PanelResult.BaselineTemperatureC)
	assert.False(t, p1Resp.PanelResult.TruncatedByMemory)
	require.Len(t, p1Resp.ConfirmedAnomalies, 1)
	assert.NotEmpty(t, p1Resp.ConfirmedAnomalies[0].ID)
	assert.Equal(t, int32(1), *p1Resp.ConfirmedAnomalies[0].PanelIndex)
	assert.Equal(t, 20.0, p1Resp.ConfirmedAnomalies[0].XPositionCM)
	assert.Equal(t, 20.0, *p1Resp.ConfirmedAnomalies[0].LocalXPositionCM)

	// 9. Cleaning operation targeting a gap coordinate: must refuse spray with target_in_gap
	gapCleanRec := doJSON(http.MethodPost, "/api/v1/devices/"+moduleID+"/cleanings", deviceToken, map[string]any{
		"target_x_position_cm":      102.0, // in gap 1-2
		"pump_actuated":             false,
		"duration_seconds":          0.0,
		"estimated_water_volume_ml": 0.0,
		"status":                    "refused",
		"failure_reason":            "target_in_gap",
		"post_cleaning_result":      "pending",
	})
	require.Equal(t, http.StatusCreated, gapCleanRec.Code, gapCleanRec.Body.String())
	var gapCleanResp struct {
		Cleaning struct {
			PumpActuated  bool    `json:"pump_actuated"`
			Status        string  `json:"status"`
			FailureReason *string `json:"failure_reason"`
		} `json:"cleaning"`
	}
	require.NoError(t, json.Unmarshal(gapCleanRec.Body.Bytes(), &gapCleanResp))
	assert.False(t, gapCleanResp.Cleaning.PumpActuated)
	assert.Equal(t, "refused", gapCleanResp.Cleaning.Status)
	require.NotNil(t, gapCleanResp.Cleaning.FailureReason)
	assert.Equal(t, "target_in_gap", *gapCleanResp.Cleaning.FailureReason)

	// 10. Finalize String Inspection (providing baseline 0 to verify backend consolidates from panel results)
	finRec := doJSON(
		http.MethodPost,
		fmt.Sprintf("/api/v1/devices/%s/inspections/%s/finalize", moduleID, inspSourceID),
		deviceToken,
		map[string]any{
			"baseline_temperature_c": 0.0, // test baseline consolidation from panel results
			"confirmed_hotspots":     []map[string]any{},
		},
	)
	require.Equal(t, http.StatusOK, finRec.Code, finRec.Body.String())
	var finResp struct {
		LatestInspection struct {
			Inspection struct {
				Status               string   `json:"status"`
				BaselineTemperatureC *float64 `json:"baseline_temperature_c"`
			} `json:"inspection"`
			PanelResults []struct {
				PanelIndex            int32   `json:"panel_index"`
				BaselineTemperatureC float64 `json:"baseline_temperature_c"`
			} `json:"panel_results"`
			ConfirmedAnomalies []struct {
				PanelIndex       *int32   `json:"panel_index"`
				XPositionCM      float64  `json:"x_position_cm"`
				LocalXPositionCM *float64 `json:"local_x_position_cm"`
			} `json:"confirmed_anomalies"`
		} `json:"latest_inspection"`
	}
	require.NoError(t, json.Unmarshal(finRec.Body.Bytes(), &finResp))
	assert.Equal(t, "completed", finResp.LatestInspection.Inspection.Status)
	require.NotNil(t, finResp.LatestInspection.Inspection.BaselineTemperatureC)
	assert.InDelta(t, 25.0, *finResp.LatestInspection.Inspection.BaselineTemperatureC, 1e-2)

	require.Len(t, finResp.LatestInspection.PanelResults, 1)
	assert.Equal(t, int32(1), finResp.LatestInspection.PanelResults[0].PanelIndex)

	require.Len(t, finResp.LatestInspection.ConfirmedAnomalies, 1)
	anom := finResp.LatestInspection.ConfirmedAnomalies[0]
	require.NotNil(t, anom.PanelIndex)
	assert.Equal(t, int32(1), *anom.PanelIndex)
	assert.InDelta(t, 20.0, anom.XPositionCM, 1e-2)
	require.NotNil(t, anom.LocalXPositionCM)
	assert.InDelta(t, 20.0, *anom.LocalXPositionCM, 1e-2)

	// 11. Check Active Alerts: Alert description should identify the panel
	alertsRec := doJSON(http.MethodGet, "/api/v1/alerts", techToken, nil)
	require.Equal(t, http.StatusOK, alertsRec.Code, alertsRec.Body.String())
	var alertsResp struct {
		Alerts []struct {
			PanelIndex  *int32  `json:"panel_index"`
			Description string  `json:"description"`
			MetaText    string  `json:"meta_text"`
		} `json:"alerts"`
	}
	require.NoError(t, json.Unmarshal(alertsRec.Body.Bytes(), &alertsResp))
	require.NotEmpty(t, alertsResp.Alerts)
	foundAlert := false
	for _, al := range alertsResp.Alerts {
		if al.PanelIndex != nil && *al.PanelIndex == 1 {
			foundAlert = true
			assert.Contains(t, al.Description, "panel 1")
			assert.Contains(t, al.MetaText, "Delta: +17.0°C vs Baseline")
		}
	}
	assert.True(t, foundAlert, "expected to find alert referencing panel 1")

	// 12. List Inspections by module endpoint
	listInspRec := doJSON(http.MethodGet, "/api/v1/modules/"+moduleID+"/inspections", techToken, nil)
	require.Equal(t, http.StatusOK, listInspRec.Code, listInspRec.Body.String())
	var listInspResp struct {
		Inspections []struct {
			ID     string `json:"id"`
			Status string `json:"status"`
		} `json:"inspections"`
	}
	require.NoError(t, json.Unmarshal(listInspRec.Body.Bytes(), &listInspResp))
	assert.Len(t, listInspResp.Inspections, 1)
}
