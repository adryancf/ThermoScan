package module

import (
	"math"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func f64(v float64) *float64 { return &v }

func TestDeciCelsiusFrameToCelsius(t *testing.T) {
	in := []*float64{f64(275), nil, f64(-400), f64(3000), f64(555), f64(math.Inf(1))}
	out := deciCelsiusFrameToCelsius(in)

	require.Len(t, out, len(in))
	assert.Equal(t, 27.5, *out[0])
	assert.Nil(t, out[1], "invalid pixel must stay null")
	assert.Equal(t, -40.0, *out[2])
	assert.Equal(t, 300.0, *out[3])
	assert.Equal(t, 55.5, *out[4])
	assert.True(t, math.IsInf(*out[5], 1), "non-finite values are left for validation to reject")

	// input is not modified
	assert.Equal(t, 275.0, *in[0])
	assert.Nil(t, deciCelsiusFrameToCelsius(nil))
}
