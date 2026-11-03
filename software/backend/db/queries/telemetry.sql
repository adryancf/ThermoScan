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
ORDER BY i.started_at DESC, tm.generated_at DESC
LIMIT 1;

-- name: GetLatestReservoirReadingByModule :one
SELECT
    r.id,
    r.module_id,
    r.measured_at,
    r.reading_status,
    r.water_available,
    r.context,
    r.error_reason,
    r.received_at
FROM reservoir_readings r
WHERE r.module_id = $1
ORDER BY r.measured_at DESC
LIMIT 1;

-- name: RecordDeviceHandshakePing :one
INSERT INTO reservoir_readings (
    module_id,
    source_event_id,
    measured_at,
    reading_status,
    water_available,
    context
) VALUES (
    sqlc.arg('module_id'),
    sqlc.arg('source_event_id'),
    now(),
    'valid',
    sqlc.arg('water_available'),
    'periodic'
)
RETURNING id, module_id, measured_at, reading_status, water_available, context, received_at;

-- name: CreateInspection :one
INSERT INTO inspections (
    module_id,
    source_event_id,
    type,
    scheduled_for,
    started_at,
    finished_at,
    status
) VALUES (
    sqlc.arg('module_id'),
    sqlc.arg('source_event_id'),
    sqlc.arg('type'),
    sqlc.arg('scheduled_for'),
    sqlc.arg('started_at'),
    sqlc.arg('finished_at'),
    sqlc.arg('status')
)
RETURNING id, module_id, source_event_id, type, cleaning_operation_id, scheduled_for, started_at, finished_at, status, verification_result, created_at, updated_at;

-- name: CreateMeasurement :one
INSERT INTO measurements (
    module_id,
    inspection_id,
    source_event_id,
    measured_at,
    x_position_cm,
    baseline_temperature_c,
    max_temperature_c,
    hotspot_detected,
    hotspot_confirmed,
    voltage_v,
    current_a,
    power_w,
    thermal_frame
) VALUES (
    sqlc.arg('module_id'),
    sqlc.arg('inspection_id'),
    sqlc.arg('source_event_id'),
    sqlc.arg('measured_at'),
    sqlc.arg('x_position_cm'),
    sqlc.arg('baseline_temperature_c'),
    sqlc.arg('max_temperature_c'),
    sqlc.arg('hotspot_detected'),
    sqlc.arg('hotspot_confirmed'),
    sqlc.arg('voltage_v'),
    sqlc.arg('current_a'),
    sqlc.arg('power_w'),
    sqlc.arg('thermal_frame')
)
RETURNING id, module_id, inspection_id, source_event_id, measured_at, x_position_cm::text AS x_position_cm, baseline_temperature_c::text AS baseline_temperature_c, max_temperature_c::text AS max_temperature_c, hotspot_detected, hotspot_confirmed, voltage_v::text AS voltage_v, current_a::text AS current_a, power_w::text AS power_w, thermal_frame, received_at;

-- name: CreateInspectionThermalMap :one
INSERT INTO inspection_thermal_maps (
    inspection_id,
    width_pixels,
    height_pixels,
    temperatures_c,
    algorithm_version
) VALUES (
    sqlc.arg('inspection_id'),
    sqlc.arg('width_pixels'),
    sqlc.arg('height_pixels'),
    sqlc.arg('temperatures_c'),
    sqlc.arg('algorithm_version')
)
RETURNING id, inspection_id, width_pixels, height_pixels, temperatures_c, algorithm_version, generated_at;

-- name: CreateAnomalyEvent :one
INSERT INTO anomaly_events (
    module_id,
    origin_measurement_id,
    source_event_id,
    x_position_cm,
    detected_at,
    status,
    actuated_attempts_count,
    retry_pending
) VALUES (
    sqlc.arg('module_id'),
    sqlc.arg('origin_measurement_id'),
    sqlc.arg('source_event_id'),
    sqlc.arg('x_position_cm'),
    sqlc.arg('detected_at'),
    sqlc.arg('status'),
    sqlc.arg('actuated_attempts_count'),
    sqlc.arg('retry_pending')
)
RETURNING id, module_id, origin_measurement_id, source_event_id, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at;

-- name: CreateCleaningOperation :one
INSERT INTO cleaning_operations (
    module_id,
    anomaly_event_id,
    source_event_id,
    target_x_position_cm,
    pump_actuated,
    attempt_number,
    started_at,
    ended_at,
    duration_seconds,
    estimated_water_volume_ml,
    status,
    failure_reason,
    post_cleaning_result
) VALUES (
    sqlc.arg('module_id'),
    sqlc.arg('anomaly_event_id'),
    sqlc.arg('source_event_id'),
    sqlc.arg('target_x_position_cm'),
    sqlc.arg('pump_actuated'),
    sqlc.arg('attempt_number'),
    sqlc.arg('started_at'),
    sqlc.arg('ended_at'),
    sqlc.arg('duration_seconds'),
    sqlc.arg('estimated_water_volume_ml'),
    sqlc.arg('status'),
    sqlc.arg('failure_reason'),
    sqlc.arg('post_cleaning_result')
)
RETURNING id, module_id, anomaly_event_id, source_event_id, target_x_position_cm::text AS target_x_position_cm, pump_actuated, attempt_number, started_at, ended_at, duration_seconds::text AS duration_seconds, estimated_water_volume_ml::text AS estimated_water_volume_ml, status, failure_reason, post_cleaning_result, created_at, updated_at;

-- name: GetAnomalyEventByID :one
SELECT id, module_id, origin_measurement_id, source_event_id, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at
FROM anomaly_events
WHERE id = $1 AND module_id = $2;

-- name: GetLatestOpenAnomalyEventByModule :one
SELECT id, module_id, origin_measurement_id, source_event_id, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at
FROM anomaly_events
WHERE module_id = $1 AND status = 'open'
ORDER BY detected_at DESC
LIMIT 1;

-- name: UpdateAnomalyEventStatus :one
UPDATE anomaly_events
SET status = $1,
    actuated_attempts_count = actuated_attempts_count + $2,
    closed_at = $3,
    updated_at = now()
WHERE id = $4 AND module_id = $5
RETURNING id, module_id, origin_measurement_id, source_event_id, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at;

-- name: ListActiveAnomaliesForCompany :many
SELECT a.id, a.module_id, m.name AS module_name, m.installer_technician_id, a.x_position_cm::text AS x_position_cm,
       a.detected_at, a.status, a.actuated_attempts_count,
       meas.max_temperature_c::text AS max_temperature_c,
       meas.baseline_temperature_c::text AS baseline_temperature_c
FROM anomaly_events a
JOIN modules m ON m.id = a.module_id
JOIN measurements meas ON meas.id = a.origin_measurement_id
WHERE m.company_id = $1 AND a.status IN ('open', 'unresolved')
ORDER BY a.detected_at DESC;

-- name: ListActiveWaterWarningsForCompany :many
SELECT r.id, r.module_id, m.name AS module_name, m.installer_technician_id, r.measured_at, r.water_available
FROM (
    SELECT DISTINCT ON (module_id) id, module_id, measured_at, water_available
    FROM reservoir_readings
    ORDER BY module_id, measured_at DESC
) r
JOIN modules m ON m.id = r.module_id
WHERE m.company_id = $1 AND m.is_active = true AND r.water_available = false
ORDER BY r.measured_at DESC;



