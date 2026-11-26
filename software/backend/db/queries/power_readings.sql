-- name: InsertPowerReading :one
INSERT INTO power_readings (
    module_id,
    panel_index,
    voltage_v,
    current_a,
    power_w,
    measured_at
) VALUES (
    sqlc.arg('module_id'),
    sqlc.arg('panel_index'),
    sqlc.narg('voltage_v'),
    sqlc.narg('current_a'),
    sqlc.narg('power_w'),
    sqlc.arg('measured_at')
)
RETURNING id, module_id, panel_index, voltage_v, current_a, power_w, measured_at, received_at;

-- name: UpdateModuleLatestPower :exec
UPDATE modules
SET latest_power_readings = sqlc.arg('latest_power_readings'),
    latest_power_at = sqlc.arg('latest_power_at'),
    updated_at = now()
WHERE id = sqlc.arg('id');

-- name: ListPowerReadingsByModule :many
SELECT
    id,
    module_id,
    panel_index,
    voltage_v,
    current_a,
    power_w,
    measured_at,
    received_at
FROM power_readings
WHERE module_id = sqlc.arg('module_id')
  AND (sqlc.narg('panel_index')::integer IS NULL OR panel_index = sqlc.narg('panel_index')::integer)
  AND (sqlc.narg('since')::timestamptz IS NULL OR measured_at >= sqlc.narg('since')::timestamptz)
ORDER BY measured_at DESC, panel_index ASC
LIMIT sqlc.arg('limit_rows')
OFFSET sqlc.arg('offset_rows');

-- name: CountPowerReadingsByModule :one
SELECT COUNT(*)::bigint AS total_count
FROM power_readings
WHERE module_id = sqlc.arg('module_id')
  AND (sqlc.narg('panel_index')::integer IS NULL OR panel_index = sqlc.narg('panel_index')::integer)
  AND (sqlc.narg('since')::timestamptz IS NULL OR measured_at >= sqlc.narg('since')::timestamptz);

-- name: GetPowerReadingStatsByModule :one
SELECT
    COUNT(*)::bigint AS total_readings,
    COUNT(power_w)::bigint AS valid_power_readings,
    COALESCE(MAX(power_w), 0)::double precision AS peak_power_w,
    COALESCE(AVG(power_w), 0)::double precision AS avg_power_w,
    COUNT(voltage_v)::bigint AS valid_voltage_readings,
    COALESCE(AVG(voltage_v), 0)::double precision AS avg_voltage_v,
    COUNT(current_a)::bigint AS valid_current_readings,
    COALESCE(AVG(current_a), 0)::double precision AS avg_current_a,
    COALESCE(MIN(measured_at), to_timestamp(0))::timestamptz AS first_reading_at,
    COALESCE(MAX(measured_at), to_timestamp(0))::timestamptz AS last_reading_at
FROM power_readings
WHERE module_id = sqlc.arg('module_id')
  AND (sqlc.narg('panel_index')::integer IS NULL OR panel_index = sqlc.narg('panel_index')::integer)
  AND (sqlc.narg('since')::timestamptz IS NULL OR measured_at >= sqlc.narg('since')::timestamptz);

-- name: GetPowerReadingSeriesByModule :many
WITH per_panel_bucket AS (
    SELECT
        to_timestamp(
            floor(extract(epoch FROM measured_at) / GREATEST(sqlc.arg('bucket_seconds')::bigint, 1))
            * GREATEST(sqlc.arg('bucket_seconds')::bigint, 1)
        )::timestamptz AS bucket_at,
        panel_index,
        AVG(voltage_v) AS avg_v,
        AVG(current_a) AS avg_a,
        AVG(power_w) AS avg_w,
        MAX(power_w) AS max_w,
        COUNT(*)::bigint AS panel_samples
    FROM power_readings
    WHERE module_id = sqlc.arg('module_id')
      AND (sqlc.narg('panel_index')::integer IS NULL OR panel_index = sqlc.narg('panel_index')::integer)
      AND (sqlc.narg('since')::timestamptz IS NULL OR measured_at >= sqlc.narg('since')::timestamptz)
    GROUP BY 1, panel_index
)
SELECT
    bucket_at::timestamptz AS bucket_at,
    COUNT(avg_v)::bigint AS valid_v_count,
    COALESCE(AVG(avg_v), 0)::double precision AS voltage_v,
    COUNT(avg_a)::bigint AS valid_a_count,
    COALESCE(SUM(avg_a), 0)::double precision AS current_a,
    COUNT(avg_w)::bigint AS valid_w_count,
    COALESCE(SUM(avg_w), 0)::double precision AS power_w,
    COALESCE(SUM(max_w), 0)::double precision AS peak_power_w,
    SUM(panel_samples)::bigint AS sample_count
FROM per_panel_bucket
GROUP BY bucket_at
ORDER BY bucket_at ASC;
