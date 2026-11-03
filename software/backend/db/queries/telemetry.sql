-- name: ListMeasurementsByModule :many
SELECT
    m.id,
    m.module_id,
    m.inspection_id,
    m.source_event_id,
    m.measured_at,
    m.x_position_cm::text AS x_position_cm,
    m.baseline_temperature_c::text AS baseline_temperature_c,
    m.max_temperature_c::text AS max_temperature_c,
    m.hotspot_detected,
    m.hotspot_confirmed,
    m.voltage_v::text AS voltage_v,
    m.current_a::text AS current_a,
    m.power_w::text AS power_w,
    m.thermal_frame,
    m.received_at
FROM measurements m
WHERE m.module_id = $1
ORDER BY m.measured_at DESC
LIMIT $2 OFFSET $3;

-- name: ListCleaningOperationsByModule :many
SELECT
    c.id,
    c.module_id,
    c.anomaly_event_id,
    c.source_event_id,
    c.target_x_position_cm::text AS target_x_position_cm,
    c.pump_actuated,
    c.attempt_number,
    c.started_at,
    c.ended_at,
    c.duration_seconds::text AS duration_seconds,
    c.estimated_water_volume_ml::text AS estimated_water_volume_ml,
    c.status,
    c.failure_reason,
    c.post_cleaning_result,
    c.created_at,
    c.updated_at
FROM cleaning_operations c
WHERE c.module_id = $1
ORDER BY c.created_at DESC
LIMIT $2 OFFSET $3;

-- name: GetLatestThermalMapByModule :one
SELECT
    tm.id,
    tm.inspection_id,
    tm.width_pixels,
    tm.height_pixels,
    tm.temperatures_c,
    tm.algorithm_version,
    tm.generated_at
FROM inspection_thermal_maps tm
JOIN inspections i ON i.id = tm.inspection_id
WHERE i.module_id = $1
ORDER BY tm.generated_at DESC
LIMIT 1;
