package module

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"sort"
	"strconv"
	"time"

	"backend/internal/auth"
	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func (s *Service) ListMeasurements(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, limit, offset int32) ([]MeasurementDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	row, err := s.queries.GetModuleByID(ctx, db.GetModuleByIDParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	_, _, err = s.resolveUserModuleRelationship(ctx, s.queries, principal, row.ID, row.InstallerTechnicianID)
	if err != nil {
		return nil, err
	}

	rows, err := s.queries.ListMeasurementsByModule(ctx, db.ListMeasurementsByModuleParams{
		ModuleID: moduleID,
		Limit:    limit,
		Offset:   offset,
	})
	if err != nil {
		return nil, err
	}

	out := make([]MeasurementDTO, 0, len(rows))
	for _, m := range rows {
		out = append(out, MeasurementDTO{
			ID:               auth.FormatUUID(m.ID),
			ModuleID:         auth.FormatUUID(m.ModuleID),
			InspectionID:     auth.FormatUUID(m.InspectionID),
			SourceEventID:    auth.FormatUUID(m.SourceEventID),
			MeasuredAt:       m.MeasuredAt.UTC().Format(time.RFC3339),
			XPositionCM:      m.XPositionCm,
			BaselineTempC:    m.BaselineTemperatureC,
			MaxTempC:         m.MaxTemperatureC,
			HotspotDetected:  m.HotspotDetected,
			HotspotConfirmed: m.HotspotConfirmed,
			VoltageV:         m.VoltageV,
			CurrentA:         m.CurrentA,
			PowerW:           m.PowerW,
			ReceivedAt:       m.ReceivedAt.UTC().Format(time.RFC3339),
		})
	}
	return out, nil
}

func (s *Service) GetLatestThermalMap(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID) (*ThermalMapDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	row, err := s.queries.GetModuleByID(ctx, db.GetModuleByIDParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	_, _, err = s.resolveUserModuleRelationship(ctx, s.queries, principal, row.ID, row.InstallerTechnicianID)
	if err != nil {
		return nil, err
	}

	tm, err := s.queries.GetLatestThermalMapByModule(ctx, moduleID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}

	measurements, _ := s.queries.ListMeasurementsByModule(ctx, db.ListMeasurementsByModuleParams{
		ModuleID: moduleID,
		Limit:    100,
		Offset:   0,
	})
	bands := computeBandsFromMeasurements(tm.WidthPixels, measurements)

	return &ThermalMapDTO{
		ID:               auth.FormatUUID(tm.ID),
		InspectionID:     auth.FormatUUID(tm.InspectionID),
		WidthPixels:      tm.WidthPixels,
		HeightPixels:     tm.HeightPixels,
		TemperaturesC:    tm.TemperaturesC,
		AlgorithmVersion: tm.AlgorithmVersion,
		Bands:            bands,
		GeneratedAt:      tm.GeneratedAt.UTC().Format(time.RFC3339),
	}, nil
}

func computeBandsFromMeasurements(widthPixels int32, measurements []db.ListMeasurementsByModuleRow) []ThermalBandDTO {
	totalCols := int(widthPixels)
	if totalCols <= 0 {
		totalCols = 32
	}

	var totalLengthCm float64
	if totalCols <= 32 {
		totalLengthCm = 5.0
	} else {
		steps := float64(totalCols-32) / 13.0
		totalLengthCm = 5.0 + steps*2.0
	}

	numBands := int(math.Ceil(totalLengthCm / 5.0))
	if numBands < 1 {
		numBands = 1
	}

	bands := make([]ThermalBandDTO, 0, numBands)
	for b := 0; b < numBands; b++ {
		startX := float64(b) * 5.0
		endX := startX + 5.0
		if endX > totalLengthCm {
			endX = totalLengthCm
		}

		hasHotspot := false
		maxTemp := 0.0
		avgTemp := 0.0
		count := 0

		for _, m := range measurements {
			x, _ := strconv.ParseFloat(m.XPositionCm, 64)
			mT, _ := strconv.ParseFloat(m.MaxTemperatureC, 64)
			bT, _ := strconv.ParseFloat(m.BaselineTemperatureC, 64)
			if x >= startX && x < endX {
				if m.HotspotDetected {
					hasHotspot = true
				}
				if mT > maxTemp {
					maxTemp = mT
				}
				avgTemp += bT
				count++
			}
		}

		var maxTempPtr *float64
		var avgTempPtr *float64
		hasData := false

		if count > 0 {
			hasData = true
			a := math.Round((avgTemp/float64(count))*10) / 10
			m := math.Round(maxTemp*10) / 10
			avgTempPtr = &a
			maxTempPtr = &m
		}

		bands = append(bands, ThermalBandDTO{
			BandIndex:       b + 1,
			StartXCm:        math.Round(startX*10) / 10,
			EndXCm:          math.Round(endX*10) / 10,
			MaxTemperatureC: maxTempPtr,
			AvgTemperatureC: avgTempPtr,
			HasHotspot:      hasHotspot,
			HasData:         hasData,
		})
	}
	return bands
}

func stitchThermalFrames(frames []IngestTelemetryInput) (int32, int32, []float64, []ThermalBandDTO) {
	if len(frames) == 0 {
		return 32, 24, make([]float64, 32*24), nil
	}

	sort.Slice(frames, func(i, j int) bool {
		return frames[i].XPositionCm < frames[j].XPositionCm
	})

	if len(frames) == 1 {
		f := frames[0]
		data := f.ThermalFrame
		maxT := f.MaxTemperatureC
		baseT := f.BaselineTemperatureC
		bands := []ThermalBandDTO{
			{
				BandIndex:       1,
				StartXCm:        0.0,
				EndXCm:          5.0,
				MaxTemperatureC: &maxT,
				AvgTemperatureC: &baseT,
				HasHotspot:      f.HotspotDetected,
				HasData:         true,
			},
		}
		return 32, 24, data, bands
	}

	colsPerStep := 13
	totalCols := 32 + (len(frames)-1)*colsPerStep
	totalRows := 24

	composite := make([]float64, totalCols*totalRows)
	weights := make([]float64, totalCols*totalRows)

	for frameIdx, f := range frames {
		frameData := f.ThermalFrame
		colOffset := frameIdx * colsPerStep

		for r := 0; r < totalRows; r++ {
			for c := 0; c < 32; c++ {
				targetCol := colOffset + c
				if targetCol >= totalCols {
					continue
				}
				targetIdx := r*totalCols + targetCol
				srcIdx := r*32 + c

				w := 1.0
				if c < 13 && frameIdx > 0 {
					w = float64(c+1) / 13.0
				} else if c >= (32-13) && frameIdx < len(frames)-1 {
					w = float64(32-c) / 13.0
				}
				if w < 0.05 {
					w = 0.05
				}

				composite[targetIdx] += frameData[srcIdx] * w
				weights[targetIdx] += w
			}
		}
	}

	for i := range composite {
		if weights[i] > 0 {
			composite[i] = math.Round((composite[i]/weights[i])*10.0) / 10.0
		}
	}

	minX := frames[0].XPositionCm
	maxX := frames[len(frames)-1].XPositionCm + 5.0
	totalLengthCm := maxX - minX
	if totalLengthCm <= 0 {
		totalLengthCm = 5.0
	}

	numBands := int(math.Ceil(totalLengthCm / 5.0))
	if numBands < 1 {
		numBands = 1
	}

	bands := make([]ThermalBandDTO, 0, numBands)
	for b := 0; b < numBands; b++ {
		startX := minX + float64(b)*5.0
		endX := startX + 5.0
		if endX > maxX {
			endX = maxX
		}

		maxTemp := 0.0
		sumTemp := 0.0
		count := 0
		hasHotspot := false

		for _, f := range frames {
			centerFrameX := f.XPositionCm + 2.5
			if centerFrameX >= startX && centerFrameX <= endX {
				if f.HotspotDetected {
					hasHotspot = true
				}
				if f.MaxTemperatureC > maxTemp {
					maxTemp = f.MaxTemperatureC
				}
			}
		}

		colStart := int(float64(b) * 5.0 / totalLengthCm * float64(totalCols))
		colEnd := int(float64(b+1) * 5.0 / totalLengthCm * float64(totalCols))
		if colEnd > totalCols {
			colEnd = totalCols
		}
		for r := 0; r < totalRows; r++ {
			for c := colStart; c < colEnd; c++ {
				t := composite[r*totalCols+c]
				if t > maxTemp {
					maxTemp = t
				}
				sumTemp += t
				count++
			}
		}

		var avgTempPtr *float64
		var maxTempPtr *float64
		hasData := false

		if count > 0 {
			hasData = true
			a := math.Round((sumTemp/float64(count))*10.0) / 10.0
			m := math.Round(maxTemp*10.0) / 10.0
			avgTempPtr = &a
			maxTempPtr = &m
		}

		bands = append(bands, ThermalBandDTO{
			BandIndex:       b + 1,
			StartXCm:        math.Round(startX*10.0) / 10.0,
			EndXCm:          math.Round(endX*10.0) / 10.0,
			MaxTemperatureC: maxTempPtr,
			AvgTemperatureC: avgTempPtr,
			HasHotspot:      hasHotspot,
			HasData:         hasData,
		})
	}

	return int32(totalCols), int32(totalRows), composite, bands
}

func (s *Service) IngestTelemetry(ctx context.Context, principal auth.Principal, moduleID pgtype.UUID, input IngestTelemetryInput) (*MeasurementDTO, error) {
	if !principal.CompanyID.Valid || !moduleID.Valid {
		return nil, ErrForbidden
	}

	tx, err := s.database.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	qtx := db.New(tx)

	row, err := qtx.GetModuleByIDForUpdate(ctx, db.GetModuleByIDForUpdateParams{
		CompanyID: principal.CompanyID,
		ID:        moduleID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	_, _, err = s.resolveUserModuleRelationship(ctx, qtx, principal, row.ID, row.InstallerTechnicianID)
	if err != nil {
		return nil, err
	}

	framesToProcess := input.Batch
	if len(framesToProcess) == 0 {
		framesToProcess = []IngestTelemetryInput{input}
	}

	for _, f := range framesToProcess {
		if len(f.ThermalFrame) != 32*24 {
			return nil, ErrInvalidInput
		}
	}

	now := time.Now().UTC()
	measuredAt := now
	if framesToProcess[0].MeasuredAt != nil && !framesToProcess[0].MeasuredAt.IsZero() {
		measuredAt = framesToProcess[0].MeasuredAt.UTC()
	}

	inspType := "scheduled"
	if input.InspectionType != nil && *input.InspectionType != "" {
		inspType = *input.InspectionType
	}
	schedFor := measuredAt
	if input.InspectionScheduledFor != nil {
		schedFor = *input.InspectionScheduledFor
	}
	startedAt := measuredAt
	if input.InspectionStartedAt != nil {
		startedAt = *input.InspectionStartedAt
	}

	// 1. Create inspection session with real timestamps
	inspEventID := newRandomUUID()
	insp, err := qtx.CreateInspection(ctx, db.CreateInspectionParams{
		ModuleID:      moduleID,
		SourceEventID: inspEventID,
		Type:          inspType,
		ScheduledFor:  schedFor,
		StartedAt:     &startedAt,
		FinishedAt:    &now,
		Status:        "completed",
	})
	if err != nil {
		return nil, err
	}

	var primaryMeasRow *db.CreateMeasurementRow

	// 2. Ingest each measurement frame with authentic sensor data
	for _, f := range framesToProcess {
		fMeasuredAt := now
		if f.MeasuredAt != nil && !f.MeasuredAt.IsZero() {
			fMeasuredAt = f.MeasuredAt.UTC()
		}

		powerW := f.VoltageV * f.CurrentA
		if f.PowerW != nil && *f.PowerW > 0 {
			powerW = *f.PowerW
		}

		frameBytes, err := json.Marshal(f.ThermalFrame)
		if err != nil {
			return nil, err
		}

		measEventID := newRandomUUID()
		meas, err := qtx.CreateMeasurement(ctx, db.CreateMeasurementParams{
			ModuleID:             moduleID,
			InspectionID:         insp.ID,
			SourceEventID:        measEventID,
			MeasuredAt:           fMeasuredAt,
			XPositionCm:          floatPtrToNumeric(&f.XPositionCm),
			BaselineTemperatureC: floatPtrToNumeric(&f.BaselineTemperatureC),
			MaxTemperatureC:      floatPtrToNumeric(&f.MaxTemperatureC),
			HotspotDetected:      f.HotspotDetected,
			HotspotConfirmed:     f.HotspotConfirmed,
			VoltageV:             floatPtrToNumeric(&f.VoltageV),
			CurrentA:             floatPtrToNumeric(&f.CurrentA),
			PowerW:               floatPtrToNumeric(&powerW),
			ThermalFrame:         frameBytes,
		})
		if err != nil {
			return nil, err
		}

		if primaryMeasRow == nil || f.HotspotDetected {
			primaryMeasRow = &meas
		}

		// If hotspot detected, register real anomaly event
		if f.HotspotDetected {
			anomEventID := newRandomUUID()
			_, _ = qtx.CreateAnomalyEvent(ctx, db.CreateAnomalyEventParams{
				ModuleID:              moduleID,
				OriginMeasurementID:   meas.ID,
				SourceEventID:         anomEventID,
				XPositionCm:           floatPtrToNumeric(&f.XPositionCm),
				DetectedAt:            fMeasuredAt,
				Status:                "open",
				ActuatedAttemptsCount: 0,
				RetryPending:          false,
			})
		}
	}

	// 3. Run multi-frame stitching with authentic overlap-60 blending
	totalCols, totalRows, compositeData, _ := stitchThermalFrames(framesToProcess)
	compositeBytes, _ := json.Marshal(compositeData)
	_, _ = qtx.CreateInspectionThermalMap(ctx, db.CreateInspectionThermalMapParams{
		InspectionID:     insp.ID,
		WidthPixels:      totalCols,
		HeightPixels:     totalRows,
		TemperaturesC:    compositeBytes,
		AlgorithmVersion: "overlap-60-blend-v1.0",
	})

	// 4. Update device online timestamp (without overwriting water_available!)
	_, _ = qtx.UpdateModuleDeviceHealth(ctx, db.UpdateModuleDeviceHealthParams{
		ID: moduleID,
	})
	if input.WaterAvailable != nil {
		pingEventID := newRandomUUID()
		_, _ = qtx.RecordDeviceHandshakePing(ctx, db.RecordDeviceHandshakePingParams{
			ModuleID:       moduleID,
			SourceEventID:  pingEventID,
			WaterAvailable: pgtype.Bool{Bool: *input.WaterAvailable, Valid: true},
		})
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	meas := primaryMeasRow
	return &MeasurementDTO{
		ID:               auth.FormatUUID(meas.ID),
		ModuleID:         auth.FormatUUID(meas.ModuleID),
		InspectionID:     auth.FormatUUID(meas.InspectionID),
		SourceEventID:    auth.FormatUUID(meas.SourceEventID),
		MeasuredAt:       meas.MeasuredAt.UTC().Format(time.RFC3339),
		XPositionCM:      meas.XPositionCm,
		BaselineTempC:    meas.BaselineTemperatureC,
		MaxTempC:         meas.MaxTemperatureC,
		HotspotDetected:  meas.HotspotDetected,
		HotspotConfirmed: meas.HotspotConfirmed,
		VoltageV:         meas.VoltageV,
		CurrentA:         meas.CurrentA,
		PowerW:           meas.PowerW,
		ReceivedAt:       meas.ReceivedAt.UTC().Format(time.RFC3339),
	}, nil
}
