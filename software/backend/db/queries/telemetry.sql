-- name: ListMeasurementsByModule :many
SELECT
    m.id,
    m.module_id,
    m.inspection_id,
    m.source_event_id,
    m.panel_index,
    m.measured_at,
    m.x_position_cm::text AS x_position_cm,
    m.max_temperature_c::text AS max_temperature_c,
    m.voltage_v,
    m.current_a,
    m.power_w,
    m.thermal_frame,
    m.received_at
FROM measurements m
WHERE m.module_id = $1
ORDER BY m.measured_at DESC
LIMIT $2 OFFSET $3;

-- name: ListMeasurementsByInspectionPaged :many
SELECT
    m.id,
    m.module_id,
    m.inspection_id,
    m.source_event_id,
    m.panel_index,
    m.measured_at,
    m.x_position_cm::text AS x_position_cm,
    m.max_temperature_c::text AS max_temperature_c,
    m.voltage_v,
    m.current_a,
    m.power_w,
    m.thermal_frame,
    m.received_at
FROM measurements m
WHERE m.inspection_id = $1 AND m.module_id = $2
ORDER BY m.x_position_cm ASC, m.measured_at ASC
LIMIT $3 OFFSET $4;

-- name: CountMeasurementsByInspection :one
SELECT count(*)
FROM measurements
WHERE inspection_id = $1 AND module_id = $2;

-- name: ListCleaningOperationsByModule :many
SELECT
    c.id,
    c.module_id,
    c.anomaly_event_id,
    c.source_event_id,
    c.panel_index,
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

-- name: GetLatestInspectionByModule :one
SELECT
    i.id,
    i.module_id,
    i.source_event_id,
    i.type,
    i.cleaning_operation_id,
    COALESCE(i.baseline_temperature_c::text, '')::text AS baseline_temperature_c,
    i.scheduled_for,
    i.started_at,
    i.finished_at,
    i.status,
    i.verification_result,
    i.created_at,
    i.updated_at
FROM inspections i
WHERE i.module_id = $1
ORDER BY i.scheduled_for DESC, i.created_at DESC
LIMIT 1;

-- name: GetInspectionBySourceEventID :one
SELECT
    i.id,
    i.module_id,
    i.source_event_id,
    i.type,
    i.cleaning_operation_id,
    COALESCE(i.baseline_temperature_c::text, '')::text AS baseline_temperature_c,
    i.scheduled_for,
    i.started_at,
    i.finished_at,
    i.status,
    i.verification_result,
    i.created_at,
    i.updated_at
FROM inspections i
WHERE i.module_id = $1 AND i.source_event_id = $2;

-- name: GetInspectionByID :one
SELECT
    i.id,
    i.module_id,
    i.source_event_id,
    i.type,
    i.cleaning_operation_id,
    COALESCE(i.baseline_temperature_c::text, '')::text AS baseline_temperature_c,
    i.scheduled_for,
    i.started_at,
    i.finished_at,
    i.status,
    i.verification_result,
    i.created_at,
    i.updated_at
FROM inspections i
WHERE i.id = $1 AND i.module_id = $2;

-- name: FinalizeInspection :one
UPDATE inspections
SET
    status = $1,
    finished_at = $2,
    baseline_temperature_c = $3,
    verification_result = $4,
    updated_at = now()
WHERE id = $5 AND module_id = $6
RETURNING id, module_id, source_event_id, type, cleaning_operation_id, COALESCE(baseline_temperature_c::text, '')::text AS baseline_temperature_c, scheduled_for, started_at, finished_at, status, verification_result, created_at, updated_at;

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
    cleaning_operation_id,
    scheduled_for,
    started_at,
    finished_at,
    status
) VALUES (
    sqlc.arg('module_id'),
    sqlc.arg('source_event_id'),
    sqlc.arg('type'),
    sqlc.narg('cleaning_operation_id'),
    sqlc.arg('scheduled_for'),
    sqlc.arg('started_at'),
    sqlc.arg('finished_at'),
    sqlc.arg('status')
)
RETURNING id, module_id, source_event_id, type, cleaning_operation_id, COALESCE(baseline_temperature_c::text, '')::text AS baseline_temperature_c, scheduled_for, started_at, finished_at, status, verification_result, created_at, updated_at;

-- name: CreateMeasurement :one
INSERT INTO measurements (
    module_id,
    inspection_id,
    source_event_id,
    panel_index,
    measured_at,
    x_position_cm,
    max_temperature_c,
    voltage_v,
    current_a,
    power_w,
    thermal_frame
) VALUES (
    sqlc.arg('module_id'),
    sqlc.arg('inspection_id'),
    sqlc.arg('source_event_id'),
    sqlc.arg('panel_index'),
    sqlc.arg('measured_at'),
    sqlc.arg('x_position_cm'),
    sqlc.arg('max_temperature_c'),
    sqlc.narg('voltage_v'),
    sqlc.narg('current_a'),
    sqlc.narg('power_w'),
    sqlc.arg('thermal_frame')
)
ON CONFLICT (module_id, source_event_id) DO NOTHING
RETURNING id, module_id, inspection_id, source_event_id, panel_index, measured_at, x_position_cm::text AS x_position_cm, max_temperature_c::text AS max_temperature_c, voltage_v, current_a, power_w, thermal_frame, received_at;

-- name: GetMeasurementBySourceEventID :one
SELECT id, module_id, inspection_id, source_event_id, panel_index, measured_at, x_position_cm::text AS x_position_cm, max_temperature_c::text AS max_temperature_c, voltage_v, current_a, power_w, thermal_frame, received_at
FROM measurements
WHERE module_id = $1 AND source_event_id = $2;

-- name: CreateAnomalyEvent :one
INSERT INTO anomaly_events (
    module_id,
    origin_measurement_id,
    confirming_measurement_ids,
    source_event_id,
    panel_index,
    x_position_cm,
    detected_at,
    status,
    actuated_attempts_count,
    retry_pending
) VALUES (
    sqlc.arg('module_id'),
    sqlc.arg('origin_measurement_id'),
    sqlc.arg('confirming_measurement_ids'),
    sqlc.arg('source_event_id'),
    sqlc.arg('panel_index'),
    sqlc.arg('x_position_cm'),
    sqlc.arg('detected_at'),
    sqlc.arg('status'),
    sqlc.arg('actuated_attempts_count'),
    sqlc.arg('retry_pending')
)
ON CONFLICT (module_id, source_event_id) DO UPDATE
SET updated_at = anomaly_events.updated_at
RETURNING id, module_id, origin_measurement_id, confirming_measurement_ids, source_event_id, panel_index, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at;

-- name: ListAnomaliesByInspection :many
SELECT a.id, a.module_id, a.origin_measurement_id, a.confirming_measurement_ids, a.source_event_id, a.panel_index, a.x_position_cm::text AS x_position_cm, a.detected_at, a.status, a.actuated_attempts_count, a.retry_pending, a.closed_at, a.created_at, a.updated_at
FROM anomaly_events a
JOIN measurements m ON m.id = a.origin_measurement_id
WHERE m.inspection_id = $1 AND a.module_id = $2
ORDER BY a.detected_at ASC;

-- name: CreateCleaningOperation :one
INSERT INTO cleaning_operations (
    module_id,
    anomaly_event_id,
    source_event_id,
    panel_index,
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
    sqlc.narg('panel_index'),
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
RETURNING id, module_id, anomaly_event_id, source_event_id, panel_index, target_x_position_cm::text AS target_x_position_cm, pump_actuated, attempt_number, started_at, ended_at, duration_seconds::text AS duration_seconds, estimated_water_volume_ml::text AS estimated_water_volume_ml, status, failure_reason, post_cleaning_result, created_at, updated_at;

-- name: GetCleaningOperationByID :one
SELECT
    c.id,
    c.module_id,
    c.anomaly_event_id,
    c.source_event_id,
    c.panel_index,
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
WHERE c.id = $1 AND c.module_id = $2;

-- name: UpdateCleaningOperationPostResult :one
UPDATE cleaning_operations
SET post_cleaning_result = $1,
    updated_at = now()
WHERE id = $2 AND module_id = $3
RETURNING id, module_id, anomaly_event_id, source_event_id, panel_index, target_x_position_cm::text AS target_x_position_cm, pump_actuated, attempt_number, started_at, ended_at, duration_seconds::text AS duration_seconds, estimated_water_volume_ml::text AS estimated_water_volume_ml, status, failure_reason, post_cleaning_result, created_at, updated_at;

-- name: GetAnomalyEventByID :one
SELECT id, module_id, origin_measurement_id, confirming_measurement_ids, source_event_id, panel_index, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at
FROM anomaly_events
WHERE id = $1 AND module_id = $2;

-- name: GetAnomalyEventBySourceEventID :one
SELECT id, module_id, origin_measurement_id, confirming_measurement_ids, source_event_id, panel_index, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at
FROM anomaly_events
WHERE source_event_id = $1 AND module_id = $2;

-- name: GetLatestOpenAnomalyEventByModule :one
SELECT id, module_id, origin_measurement_id, confirming_measurement_ids, source_event_id, panel_index, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at
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
RETURNING id, module_id, origin_measurement_id, confirming_measurement_ids, source_event_id, panel_index, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at;

-- name: UpdateAnomalyEventVerification :one
UPDATE anomaly_events
SET status = $1,
    retry_pending = $2,
    retry_reason = $3,
    closed_at = $4,
    updated_at = now()
WHERE id = $5 AND module_id = $6
RETURNING id, module_id, origin_measurement_id, confirming_measurement_ids, source_event_id, panel_index, x_position_cm::text AS x_position_cm, detected_at, status, actuated_attempts_count, retry_pending, closed_at, created_at, updated_at;

-- name: ListActiveAnomaliesForCompany :many
SELECT a.id, a.module_id, m.name AS module_name, m.installer_technician_id, a.panel_index, a.x_position_cm::text AS x_position_cm,
       a.detected_at, a.status, a.actuated_attempts_count,
       meas.max_temperature_c::text AS max_temperature_c,
       COALESCE(ipr.baseline_temperature_c::text, insp.baseline_temperature_c::text, '0.0')::text AS baseline_temperature_c
FROM anomaly_events a
JOIN modules m ON m.id = a.module_id
JOIN measurements meas ON meas.id = a.origin_measurement_id
JOIN inspections insp ON insp.id = meas.inspection_id
LEFT JOIN inspection_panel_results ipr ON ipr.inspection_id = insp.id AND ipr.panel_index = a.panel_index
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

-- name: UpsertInspectionPanelResult :one
INSERT INTO inspection_panel_results (
    inspection_id,
    module_id,
    panel_index,
    baseline_temperature_c,
    truncated_by_memory,
    finished_at
) VALUES (
    sqlc.arg('inspection_id'),
    sqlc.arg('module_id'),
    sqlc.arg('panel_index'),
    sqlc.arg('baseline_temperature_c'),
    sqlc.arg('truncated_by_memory'),
    sqlc.arg('finished_at')
)
ON CONFLICT (inspection_id, panel_index) DO UPDATE
SET baseline_temperature_c = EXCLUDED.baseline_temperature_c,
    truncated_by_memory = EXCLUDED.truncated_by_memory,
    finished_at = EXCLUDED.finished_at,
    updated_at = now()
RETURNING inspection_id, module_id, panel_index, baseline_temperature_c::text AS baseline_temperature_c, truncated_by_memory, finished_at, created_at, updated_at;

-- name: ListInspectionPanelResults :many
SELECT inspection_id, module_id, panel_index, baseline_temperature_c::text AS baseline_temperature_c, truncated_by_memory, finished_at, created_at, updated_at
FROM inspection_panel_results
WHERE inspection_id = $1 AND module_id = $2
ORDER BY panel_index ASC;

-- name: GetInspectionPanelResult :one
SELECT inspection_id, module_id, panel_index, baseline_temperature_c::text AS baseline_temperature_c, truncated_by_memory, finished_at, created_at, updated_at
FROM inspection_panel_results
WHERE inspection_id = $1 AND module_id = $2 AND panel_index = $3;

-- name: ListInspectionsByModule :many
SELECT
    i.id,
    i.module_id,
    i.source_event_id,
    i.type,
    i.cleaning_operation_id,
    COALESCE(i.baseline_temperature_c::text, '')::text AS baseline_temperature_c,
    i.scheduled_for,
    i.started_at,
    i.finished_at,
    i.status,
    i.verification_result,
    i.created_at,
    i.updated_at
FROM inspections i
WHERE i.module_id = $1
ORDER BY i.scheduled_for DESC, i.created_at DESC
LIMIT $2 OFFSET $3;
