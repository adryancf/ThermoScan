package module_test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"backend/internal/module"
)

func TestCalculateTotalStringLength(t *testing.T) {
	tests := []struct {
		name           string
		panelCount     int32
		panelLengthCm  float64
		panelSpacingCm float64
		expected       float64
	}{
		{
			name:           "single panel",
			panelCount:     1,
			panelLengthCm:  100.0,
			panelSpacingCm: 5.0,
			expected:       100.0,
		},
		{
			name:           "three panels with 5cm gap",
			panelCount:     3,
			panelLengthCm:  100.0,
			panelSpacingCm: 5.0,
			expected:       310.0, // 300 + 2*5
		},
		{
			name:           "invalid panel count",
			panelCount:     0,
			panelLengthCm:  100.0,
			panelSpacingCm: 5.0,
			expected:       0.0,
		},
		{
			name:           "negative spacing treated as 0",
			panelCount:     2,
			panelLengthCm:  50.0,
			panelSpacingCm: -10.0,
			expected:       100.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			res := module.CalculateTotalStringLength(tt.panelCount, tt.panelLengthCm, tt.panelSpacingCm)
			assert.InDelta(t, tt.expected, res, 1e-4)
		})
	}
}

func TestGetPanelBounds(t *testing.T) {
	// 3 panels, 100cm each, 10cm spacing
	// Panel 1: [0, 100]
	// Gap 1-2: (100, 110)
	// Panel 2: [110, 210]
	// Gap 2-3: (210, 220)
	// Panel 3: [220, 320]

	s1, e1 := module.GetPanelBounds(1, 100.0, 10.0)
	assert.Equal(t, 0.0, s1)
	assert.Equal(t, 100.0, e1)

	s2, e2 := module.GetPanelBounds(2, 100.0, 10.0)
	assert.Equal(t, 110.0, s2)
	assert.Equal(t, 210.0, e2)

	s3, e3 := module.GetPanelBounds(3, 100.0, 10.0)
	assert.Equal(t, 220.0, s3)
	assert.Equal(t, 320.0, e3)

	s0, e0 := module.GetPanelBounds(0, 100.0, 10.0)
	assert.Equal(t, 0.0, s0)
	assert.Equal(t, 0.0, e0)
}

func TestResolvePanelPosition(t *testing.T) {
	panelCount := int32(3)
	panelLengthCm := 100.0
	panelSpacingCm := 10.0

	// 1. Point inside Panel 1
	res := module.ResolvePanelPosition(panelCount, panelLengthCm, panelSpacingCm, 25.0)
	require.True(t, res.WithinBounds)
	require.False(t, res.InGap)
	assert.Equal(t, int32(1), res.PanelIndex)
	assert.InDelta(t, 25.0, res.LocalXCm, 1e-4)

	// 2. Exact boundary start of Panel 1
	res = module.ResolvePanelPosition(panelCount, panelLengthCm, panelSpacingCm, 0.0)
	require.True(t, res.WithinBounds)
	require.False(t, res.InGap)
	assert.Equal(t, int32(1), res.PanelIndex)
	assert.InDelta(t, 0.0, res.LocalXCm, 1e-4)

	// 3. Exact boundary end of Panel 1
	res = module.ResolvePanelPosition(panelCount, panelLengthCm, panelSpacingCm, 100.0)
	require.True(t, res.WithinBounds)
	require.False(t, res.InGap)
	assert.Equal(t, int32(1), res.PanelIndex)
	assert.InDelta(t, 100.0, res.LocalXCm, 1e-4)

	// 4. In gap between Panel 1 and Panel 2 (e.g. 105cm)
	res = module.ResolvePanelPosition(panelCount, panelLengthCm, panelSpacingCm, 105.0)
	require.True(t, res.WithinBounds)
	require.True(t, res.InGap)
	assert.Equal(t, int32(0), res.PanelIndex)
	assert.Equal(t, int32(2), res.NearestPanel) // 105 is closer to or at midpoint

	// 5. Point inside Panel 2 (e.g. 150cm)
	res = module.ResolvePanelPosition(panelCount, panelLengthCm, panelSpacingCm, 150.0)
	require.True(t, res.WithinBounds)
	require.False(t, res.InGap)
	assert.Equal(t, int32(2), res.PanelIndex)
	assert.InDelta(t, 40.0, res.LocalXCm, 1e-4) // 150 - 110 = 40

	// 6. Point inside Panel 3 (e.g. 310cm)
	res = module.ResolvePanelPosition(panelCount, panelLengthCm, panelSpacingCm, 310.0)
	require.True(t, res.WithinBounds)
	require.False(t, res.InGap)
	assert.Equal(t, int32(3), res.PanelIndex)
	assert.InDelta(t, 90.0, res.LocalXCm, 1e-4) // 310 - 220 = 90

	// 7. Negative coordinate out of bounds
	res = module.ResolvePanelPosition(panelCount, panelLengthCm, panelSpacingCm, -5.0)
	require.False(t, res.WithinBounds)
	assert.Equal(t, int32(0), res.PanelIndex)
	assert.Equal(t, int32(1), res.NearestPanel)

	// 8. Beyond total length out of bounds
	res = module.ResolvePanelPosition(panelCount, panelLengthCm, panelSpacingCm, 350.0)
	require.False(t, res.WithinBounds)
	assert.Equal(t, int32(0), res.PanelIndex)
	assert.Equal(t, int32(3), res.NearestPanel)
}
