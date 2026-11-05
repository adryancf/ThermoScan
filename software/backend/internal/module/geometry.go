package module

import (
	"errors"
	"math"
)

var (
	ErrMeasurementInGap  = errors.New("measurement x_position_cm falls inside inter-panel gap")
	ErrHotspotInGap      = errors.New("hotspot x_position_cm falls inside inter-panel gap")
	ErrPositionOutOfBounds = errors.New("x_position_cm is outside photovoltaic string bounds")
	ErrPanelIndexMismatch  = errors.New("specified panel_index does not match position x_position_cm")
	ErrInvalidPanelIndex   = errors.New("panel_index must be between 1 and panel_count")
)

const floatTolerance = 1e-3

// CalculateTotalStringLength returns the physical rail length from the start of panel 1
// to the end of panel N, including all (N-1) inter-panel gaps.
func CalculateTotalStringLength(panelCount int32, panelLengthCm float64, panelSpacingCm float64) float64 {
	if panelCount <= 0 || panelLengthCm <= 0 {
		return 0
	}
	if panelSpacingCm < 0 {
		panelSpacingCm = 0
	}
	return (float64(panelCount) * panelLengthCm) + (float64(panelCount-1) * panelSpacingCm)
}

// TotalStringLengthCm is an alias for CalculateTotalStringLength.
func TotalStringLengthCm(panelCount int32, panelLengthCm float64, panelSpacingCm float64) float64 {
	return CalculateTotalStringLength(panelCount, panelLengthCm, panelSpacingCm)
}

// ValidatePanelAndPosition validates that xCm and an optional providedPanelIndex are within the module string geometry and not in an inter-panel gap.
func ValidatePanelAndPosition(xCm, panelLengthCm, panelSpacingCm float64, panelCount int32, providedPanelIndex *int32) (PanelPositionResult, error) {
	if panelCount <= 0 {
		panelCount = 1
	}
	if providedPanelIndex != nil && (*providedPanelIndex < 1 || *providedPanelIndex > panelCount) {
		return PanelPositionResult{}, ErrInvalidPanelIndex
	}
	if xCm < -floatTolerance {
		return PanelPositionResult{}, ErrPositionOutOfBounds
	}
	if panelLengthCm <= 0 {
		pIdx := int32(1)
		if providedPanelIndex != nil {
			pIdx = *providedPanelIndex
		}
		return PanelPositionResult{
			PanelIndex:   pIdx,
			LocalXCm:     xCm,
			InGap:        false,
			WithinBounds: true,
			NearestPanel: pIdx,
		}, nil
	}
	posRes := ResolvePanelPosition(panelCount, panelLengthCm, panelSpacingCm, xCm)
	if !posRes.WithinBounds {
		return posRes, ErrPositionOutOfBounds
	}
	if posRes.InGap {
		return posRes, ErrMeasurementInGap
	}
	if providedPanelIndex != nil && *providedPanelIndex != posRes.PanelIndex {
		return posRes, ErrPanelIndexMismatch
	}
	return posRes, nil
}

// GetPanelBounds returns the physical coordinates [startCm, endCm] along the rail for a given panel (1-indexed).
func GetPanelBounds(panelIndex int32, panelLengthCm float64, panelSpacingCm float64) (startCm float64, endCm float64) {
	if panelIndex <= 0 || panelLengthCm <= 0 {
		return 0, 0
	}
	if panelSpacingCm < 0 {
		panelSpacingCm = 0
	}
	startCm = float64(panelIndex-1) * (panelLengthCm + panelSpacingCm)
	endCm = startCm + panelLengthCm
	return startCm, endCm
}

// PanelPositionResult carries the resolved position details.
type PanelPositionResult struct {
	PanelIndex     int32
	LocalXCm       float64
	InGap          bool
	WithinBounds   bool
	PanelStartCm   float64
	PanelEndCm     float64
	NearestPanel   int32
}

// ResolvePanelPosition takes a global position X on the rail and determines
// which panel it belongs to, its local coordinate, and whether it falls in an inter-panel gap.
func ResolvePanelPosition(panelCount int32, panelLengthCm float64, panelSpacingCm float64, xPositionCm float64) PanelPositionResult {
	if panelCount <= 0 {
		panelCount = 1
	}
	if panelLengthCm <= 0 {
		return PanelPositionResult{
			PanelIndex:   1,
			LocalXCm:     xPositionCm,
			InGap:        false,
			WithinBounds: true,
			NearestPanel: 1,
		}
	}
	if panelSpacingCm < 0 {
		panelSpacingCm = 0
	}

	totalLength := CalculateTotalStringLength(panelCount, panelLengthCm, panelSpacingCm)
	if xPositionCm < -floatTolerance || xPositionCm > totalLength+floatTolerance {
		nearest := int32(1)
		if xPositionCm > totalLength {
			nearest = panelCount
		}
		return PanelPositionResult{
			PanelIndex:   0,
			LocalXCm:     0,
			InGap:        false,
			WithinBounds: false,
			NearestPanel: nearest,
		}
	}

	// Clamp near 0 or totalLength to absorb minute numerical noise
	if math.Abs(xPositionCm) < floatTolerance {
		xPositionCm = 0
	}
	if math.Abs(xPositionCm-totalLength) < floatTolerance {
		xPositionCm = totalLength
	}

	for p := int32(1); p <= panelCount; p++ {
		startCm, endCm := GetPanelBounds(p, panelLengthCm, panelSpacingCm)
		if xPositionCm >= startCm-floatTolerance && xPositionCm <= endCm+floatTolerance {
			localX := xPositionCm - startCm
			if localX < 0 {
				localX = 0
			}
			if localX > panelLengthCm {
				localX = panelLengthCm
			}
			return PanelPositionResult{
				PanelIndex:   p,
				LocalXCm:     localX,
				InGap:        false,
				WithinBounds: true,
				PanelStartCm: startCm,
				PanelEndCm:   endCm,
				NearestPanel: p,
			}
		}

		if p < panelCount && panelSpacingCm > 0 {
			nextStartCm, _ := GetPanelBounds(p+1, panelLengthCm, panelSpacingCm)
			if xPositionCm > endCm+floatTolerance && xPositionCm < nextStartCm-floatTolerance {
				nearest := p
				if xPositionCm >= (endCm+nextStartCm)/2.0 {
					nearest = p + 1
				}
				return PanelPositionResult{
					PanelIndex:   0, // not in any panel
					LocalXCm:     xPositionCm - startCm,
					InGap:        true,
					WithinBounds: true,
					PanelStartCm: endCm,
					PanelEndCm:   nextStartCm,
					NearestPanel: nearest,
				}
			}
		}
	}

	return PanelPositionResult{
		PanelIndex:   0,
		LocalXCm:     0,
		InGap:        true,
		WithinBounds: false,
		NearestPanel: 1,
	}
}
