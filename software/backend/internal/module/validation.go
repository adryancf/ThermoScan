package module

import (
	"net"
	"strconv"
	"strings"
)

func validatePowerSensorsConfig(sensors []PowerSensorConfigDTO, panelCount int32) error {
	if len(sensors) == 0 {
		return nil
	}
	if panelCount <= 0 {
		return ErrInvalidInput
	}
	seenPanels := make(map[int32]struct{}, len(sensors))
	seenAddrs := make(map[string]struct{}, len(sensors))
	for _, s := range sensors {
		if s.PanelIndex < 1 || s.PanelIndex > panelCount {
			return ErrInvalidInput
		}
		if _, exists := seenPanels[s.PanelIndex]; exists {
			return ErrInvalidInput
		}
		seenPanels[s.PanelIndex] = struct{}{}

		addr := strings.ToLower(strings.TrimSpace(s.I2CAddress))
		if len(addr) != 4 || !strings.HasPrefix(addr, "0x") {
			return ErrInvalidInput
		}
		val, err := strconv.ParseUint(addr[2:], 16, 8)
		if err != nil || val < 0x08 || val > 0x77 {
			return ErrInvalidInput
		}
		if _, exists := seenAddrs[addr]; exists {
			return ErrInvalidInput
		}
		seenAddrs[addr] = struct{}{}
	}
	return nil
}

func normalizeAndValidateMAC(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", ErrInvalidInput
	}
	hw, err := net.ParseMAC(trimmed)
	if err != nil || len(hw) != 6 {
		return "", ErrInvalidInput
	}
	return strings.ToLower(hw.String()), nil
}

func validateOptionalConfigFields(
	panelLengthCm *float64,
	panelWidthCm *float64,
	panelCount *int32,
	panelSpacingCm *float64,
	latitude *float64,
	longitude *float64,
	elevationM *float64,
	azimuthDeg *float64,
	tiltDeg *float64,
	azimuthSource *string,
	tiltSource *string,
	minSolarAngleDeg *float64,
	reservoirCapMl *float64,
) error {
	if panelLengthCm != nil && (!isFinite(*panelLengthCm) || *panelLengthCm <= 0) {
		return ErrInvalidInput
	}
	if panelWidthCm != nil && (!isFinite(*panelWidthCm) || *panelWidthCm <= 0) {
		return ErrInvalidInput
	}
	if panelCount != nil && *panelCount <= 0 {
		return ErrInvalidInput
	}
	if panelSpacingCm != nil && (!isFinite(*panelSpacingCm) || *panelSpacingCm < 0) {
		return ErrInvalidInput
	}
	if latitude != nil && (!isFinite(*latitude) || *latitude < -90 || *latitude > 90) {
		return ErrInvalidInput
	}
	if longitude != nil && (!isFinite(*longitude) || *longitude < -180 || *longitude > 180) {
		return ErrInvalidInput
	}
	if elevationM != nil && !isFinite(*elevationM) {
		return ErrInvalidInput
	}
	if azimuthDeg != nil && (!isFinite(*azimuthDeg) || *azimuthDeg < 0 || *azimuthDeg >= 360) {
		return ErrInvalidInput
	}
	if tiltDeg != nil && (!isFinite(*tiltDeg) || *tiltDeg < 0 || *tiltDeg > 90) {
		return ErrInvalidInput
	}
	if azimuthSource != nil {
		s := strings.TrimSpace(*azimuthSource)
		if s != SourceSensor && s != SourceManual {
			return ErrInvalidInput
		}
	}
	if tiltSource != nil {
		s := strings.TrimSpace(*tiltSource)
		if s != SourceSensor && s != SourceManual {
			return ErrInvalidInput
		}
	}
	if minSolarAngleDeg != nil && (!isFinite(*minSolarAngleDeg) || *minSolarAngleDeg < 0 || *minSolarAngleDeg > 90) {
		return ErrInvalidInput
	}
	if reservoirCapMl != nil && (!isFinite(*reservoirCapMl) || *reservoirCapMl <= 0) {
		return ErrInvalidInput
	}
	return nil
}

func isConfigurationComplete(
	panelLengthCm *float64,
	panelWidthCm *float64,
	panelCount *int32,
	panelSpacingCm *float64,
	latitude *float64,
	longitude *float64,
	elevationM *float64,
	azimuthDeg *float64,
	tiltDeg *float64,
	azimuthSource *string,
	tiltSource *string,
	minSolarAngleDeg *float64,
) bool {
	return panelLengthCm != nil &&
		panelWidthCm != nil &&
		panelCount != nil &&
		panelSpacingCm != nil &&
		latitude != nil &&
		longitude != nil &&
		elevationM != nil &&
		azimuthDeg != nil &&
		tiltDeg != nil &&
		azimuthSource != nil &&
		tiltSource != nil &&
		minSolarAngleDeg != nil
}
