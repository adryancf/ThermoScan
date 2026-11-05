-- name: ListActiveCompanyManagers :many
SELECT
    id,
    company_id,
    name,
    email,
    is_active,
    is_default_manager,
    created_at
FROM users
WHERE company_id = $1
  AND role = 'manager'
  AND is_active = true
ORDER BY is_default_manager DESC, name ASC;

-- name: ListActiveCompanyClients :many
SELECT
    id,
    company_id,
    name,
    email,
    is_active,
    created_at
FROM users
WHERE company_id = $1
  AND role = 'client'
  AND is_active = true
ORDER BY name ASC;

-- name: CreateModule :one
INSERT INTO modules (
    company_id,
    installer_technician_id,
    name,
    mac_address,
    is_active,
    monitoring_status,
    panel_length_cm,
    panel_width_cm,
    panel_count,
    panel_spacing_cm,
    latitude,
    longitude,
    elevation_m,
    azimuth_deg,
    tilt_deg,
    azimuth_source,
    tilt_source,
    minimum_solar_angle_deg,
    inspection_interval_days,
    reservoir_nominal_capacity_ml,
    power_sensors,
    configured_at,
    config_version
) VALUES (
    sqlc.arg('company_id'),
    sqlc.arg('installer_technician_id'),
    btrim(sqlc.arg('name')::text),
    sqlc.arg('mac_address')::text::macaddr,
    sqlc.arg('is_active'),
    sqlc.arg('monitoring_status'),
    sqlc.narg('panel_length_cm'),
    sqlc.narg('panel_width_cm'),
    sqlc.narg('panel_count'),
    sqlc.narg('panel_spacing_cm'),
    sqlc.narg('latitude'),
    sqlc.narg('longitude'),
    sqlc.narg('elevation_m'),
    sqlc.narg('azimuth_deg'),
    sqlc.narg('tilt_deg'),
    sqlc.narg('azimuth_source'),
    sqlc.narg('tilt_source'),
    sqlc.narg('minimum_solar_angle_deg'),
    sqlc.arg('inspection_interval_days'),
    sqlc.narg('reservoir_nominal_capacity_ml'),
    sqlc.narg('power_sensors'),
    sqlc.narg('configured_at'),
    sqlc.arg('config_version')
)
RETURNING
    id,
    company_id,
    installer_technician_id,
    name,
    mac_address::text AS mac_address,
    is_active,
    monitoring_status,
    panel_length_cm,
    panel_width_cm,
    panel_count,
    panel_spacing_cm,
    latitude,
    longitude,
    elevation_m,
    azimuth_deg,
    tilt_deg,
    azimuth_source,
    tilt_source,
    minimum_solar_angle_deg,
    inspection_interval_days,
    reservoir_nominal_capacity_ml,
    power_sensors,
    configured_at,
    created_at,
    updated_at,
    config_version,
    config_applied_version,
    config_applied_at,
    config_apply_error;

-- name: GetModuleByID :one
SELECT
    m.id,
    m.company_id,
    m.installer_technician_id,
    u.name AS installer_name,
    u.email AS installer_email,
    m.name,
    m.mac_address::text AS mac_address,
    m.is_active,
    m.monitoring_status,
    m.panel_length_cm,
    m.panel_width_cm,
    m.panel_count,
    m.panel_spacing_cm,
    m.latitude,
    m.longitude,
    m.elevation_m,
    m.azimuth_deg,
    m.tilt_deg,
    m.azimuth_source,
    m.tilt_source,
    m.minimum_solar_angle_deg,
    m.inspection_interval_days,
    m.reservoir_nominal_capacity_ml,
    m.power_sensors,
    m.limits_check_passed,
    m.thermal_sensor_active,
    m.last_ping_at,
    m.configured_at,
    m.created_at,
    m.updated_at,
    m.config_version,
    m.config_applied_version,
    m.config_applied_at,
    m.config_apply_error
FROM modules m
JOIN users u ON u.company_id = m.company_id AND u.id = m.installer_technician_id
WHERE m.company_id = $1
  AND m.id = $2;

-- name: GetModuleByIDForUpdate :one
SELECT
    m.id,
    m.company_id,
    m.installer_technician_id,
    m.name,
    m.mac_address::text AS mac_address,
    m.is_active,
    m.monitoring_status,
    m.panel_length_cm,
    m.panel_width_cm,
    m.panel_count,
    m.panel_spacing_cm,
    m.latitude,
    m.longitude,
    m.elevation_m,
    m.azimuth_deg,
    m.tilt_deg,
    m.azimuth_source,
    m.tilt_source,
    m.minimum_solar_angle_deg,
    m.inspection_interval_days,
    m.reservoir_nominal_capacity_ml,
    m.power_sensors,
    m.limits_check_passed,
    m.thermal_sensor_active,
    m.last_ping_at,
    m.configured_at,
    m.created_at,
    m.updated_at,
    m.config_version,
    m.config_applied_version,
    m.config_applied_at,
    m.config_apply_error
FROM modules m
WHERE m.company_id = $1
  AND m.id = $2
FOR UPDATE;

-- name: ListModulesForManager :many
SELECT
    m.id,
    m.company_id,
    m.installer_technician_id,
    u.name AS installer_name,
    u.email AS installer_email,
    m.name,
    m.mac_address::text AS mac_address,
    m.is_active,
    m.monitoring_status,
    m.panel_length_cm,
    m.panel_width_cm,
    m.panel_count,
    m.panel_spacing_cm,
    m.latitude,
    m.longitude,
    m.elevation_m,
    m.azimuth_deg,
    m.tilt_deg,
    m.azimuth_source,
    m.tilt_source,
    m.minimum_solar_angle_deg,
    m.inspection_interval_days,
    m.reservoir_nominal_capacity_ml,
    m.power_sensors,
    m.limits_check_passed,
    m.thermal_sensor_active,
    m.last_ping_at,
    m.configured_at,
    m.created_at,
    m.updated_at,
    m.config_version,
    m.config_applied_version,
    m.config_applied_at,
    m.config_apply_error
FROM modules m
JOIN users u ON u.company_id = m.company_id AND u.id = m.installer_technician_id
WHERE m.company_id = $1
ORDER BY m.created_at DESC
LIMIT $2 OFFSET $3;

-- name: ListModulesForTechnician :many
SELECT
    m.id,
    m.company_id,
    m.installer_technician_id,
    u.name AS installer_name,
    u.email AS installer_email,
    m.name,
    m.mac_address::text AS mac_address,
    m.is_active,
    m.monitoring_status,
    m.panel_length_cm,
    m.panel_width_cm,
    m.panel_count,
    m.panel_spacing_cm,
    m.latitude,
    m.longitude,
    m.elevation_m,
    m.azimuth_deg,
    m.tilt_deg,
    m.azimuth_source,
    m.tilt_source,
    m.minimum_solar_angle_deg,
    m.inspection_interval_days,
    m.reservoir_nominal_capacity_ml,
    m.power_sensors,
    m.limits_check_passed,
    m.thermal_sensor_active,
    m.last_ping_at,
    m.configured_at,
    m.created_at,
    m.updated_at,
    m.config_version,
    m.config_applied_version,
    m.config_applied_at,
    m.config_apply_error
FROM modules m
JOIN users u ON u.company_id = m.company_id AND u.id = m.installer_technician_id
JOIN module_technicians mt ON mt.company_id = m.company_id AND mt.module_id = m.id
WHERE m.company_id = $1
  AND mt.technician_id = $2
  AND mt.can_view = true
ORDER BY m.created_at DESC
LIMIT $3 OFFSET $4;

-- name: ListModulesForClient :many
SELECT
    m.id,
    m.company_id,
    m.installer_technician_id,
    u.name AS installer_name,
    u.email AS installer_email,
    m.name,
    m.mac_address::text AS mac_address,
    m.is_active,
    m.monitoring_status,
    m.panel_length_cm,
    m.panel_width_cm,
    m.panel_count,
    m.panel_spacing_cm,
    m.latitude,
    m.longitude,
    m.elevation_m,
    m.azimuth_deg,
    m.tilt_deg,
    m.azimuth_source,
    m.tilt_source,
    m.minimum_solar_angle_deg,
    m.inspection_interval_days,
    m.reservoir_nominal_capacity_ml,
    m.power_sensors,
    m.configured_at,
    m.created_at,
    m.updated_at,
    mc.operational_email_enabled,
    m.config_version,
    m.config_applied_version,
    m.config_applied_at,
    m.config_apply_error
FROM modules m
JOIN users u ON u.company_id = m.company_id AND u.id = m.installer_technician_id
JOIN module_clients mc ON mc.company_id = m.company_id AND mc.module_id = m.id
WHERE m.company_id = $1
  AND mc.client_id = $2
ORDER BY m.created_at DESC
LIMIT $3 OFFSET $4;

-- name: UpdateModuleConfiguration :one
UPDATE modules
SET
    name = btrim(sqlc.arg('name')::text),
    monitoring_status = sqlc.arg('monitoring_status'),
    panel_length_cm = sqlc.narg('panel_length_cm'),
    panel_width_cm = sqlc.narg('panel_width_cm'),
    panel_count = sqlc.narg('panel_count'),
    panel_spacing_cm = sqlc.narg('panel_spacing_cm'),
    latitude = sqlc.narg('latitude'),
    longitude = sqlc.narg('longitude'),
    elevation_m = sqlc.narg('elevation_m'),
    azimuth_deg = sqlc.narg('azimuth_deg'),
    tilt_deg = sqlc.narg('tilt_deg'),
    azimuth_source = sqlc.narg('azimuth_source'),
    tilt_source = sqlc.narg('tilt_source'),
    minimum_solar_angle_deg = sqlc.narg('minimum_solar_angle_deg'),
    inspection_interval_days = sqlc.arg('inspection_interval_days'),
    reservoir_nominal_capacity_ml = sqlc.narg('reservoir_nominal_capacity_ml'),
    power_sensors = sqlc.narg('power_sensors'),
    configured_at = sqlc.narg('configured_at'),
    config_version = modules.config_version + 1,
    config_apply_error = NULL,
    updated_at = NOW()
WHERE company_id = sqlc.arg('company_id')
  AND id = sqlc.arg('id')
RETURNING
    id,
    company_id,
    installer_technician_id,
    name,
    mac_address::text AS mac_address,
    is_active,
    monitoring_status,
    panel_length_cm,
    panel_width_cm,
    panel_count,
    panel_spacing_cm,
    latitude,
    longitude,
    elevation_m,
    azimuth_deg,
    tilt_deg,
    azimuth_source,
    tilt_source,
    minimum_solar_angle_deg,
    inspection_interval_days,
    reservoir_nominal_capacity_ml,
    power_sensors,
    configured_at,
    created_at,
    updated_at,
    config_version,
    config_applied_version,
    config_applied_at,
    config_apply_error;

-- name: AddModuleManager :one
INSERT INTO module_managers (
    company_id,
    module_id,
    manager_id
) VALUES (
    $1,
    $2,
    $3
)
RETURNING company_id, module_id, manager_id, created_at;

-- name: DeleteAllManagersForModule :exec
DELETE FROM module_managers
WHERE company_id = $1
  AND module_id = $2;

-- name: ListManagersByModule :many
SELECT
    u.id,
    u.company_id,
    u.name,
    u.email,
    u.is_active,
    u.is_default_manager,
    mm.created_at AS assigned_at
FROM module_managers mm
JOIN users u ON u.company_id = mm.company_id AND u.id = mm.manager_id
WHERE mm.company_id = $1
  AND mm.module_id = $2
ORDER BY u.is_default_manager DESC, u.name ASC;

-- name: UpsertModuleTechnician :one
INSERT INTO module_technicians (
    company_id,
    module_id,
    technician_id,
    can_view
) VALUES (
    $1,
    $2,
    $3,
    $4
)
ON CONFLICT (module_id, technician_id)
DO UPDATE SET can_view = EXCLUDED.can_view
RETURNING company_id, module_id, technician_id, can_view, created_at, updated_at;

-- name: GetModuleTechnicianAccess :one
SELECT
    company_id,
    module_id,
    technician_id,
    can_view,
    created_at,
    updated_at
FROM module_technicians
WHERE company_id = $1
  AND module_id = $2
  AND technician_id = $3;

-- name: ListTechniciansByModule :many
SELECT
    u.id,
    u.company_id,
    u.name,
    u.email,
    u.is_active,
    mt.can_view,
    mt.created_at AS assigned_at,
    mt.updated_at
FROM module_technicians mt
JOIN users u ON u.company_id = mt.company_id AND u.id = mt.technician_id
WHERE mt.company_id = $1
  AND mt.module_id = $2
ORDER BY u.name ASC;

-- name: AddModuleClient :one
INSERT INTO module_clients (
    company_id,
    module_id,
    client_id,
    operational_email_enabled
) VALUES (
    $1,
    $2,
    $3,
    $4
)
ON CONFLICT (module_id, client_id)
DO NOTHING
RETURNING company_id, module_id, client_id, operational_email_enabled, created_at, updated_at;

-- name: DeleteAllClientsForModule :exec
DELETE FROM module_clients
WHERE company_id = $1
  AND module_id = $2;

-- name: RemoveModuleClient :exec
DELETE FROM module_clients
WHERE company_id = $1
  AND module_id = $2
  AND client_id = $3;

-- name: GetModuleClientAssignment :one
SELECT
    company_id,
    module_id,
    client_id,
    operational_email_enabled,
    created_at,
    updated_at
FROM module_clients
WHERE company_id = $1
  AND module_id = $2
  AND client_id = $3;

-- name: ListClientsByModule :many
SELECT
    u.id,
    u.company_id,
    u.name,
    u.email,
    u.is_active,
    mc.operational_email_enabled,
    mc.created_at AS assigned_at,
    mc.updated_at
FROM module_clients mc
JOIN users u ON u.company_id = mc.company_id AND u.id = mc.client_id
WHERE mc.company_id = $1
  AND mc.module_id = $2
ORDER BY u.name ASC;

-- name: UpdateModuleClientEmailPreference :one
UPDATE module_clients
SET operational_email_enabled = $4
WHERE company_id = $1
  AND module_id = $2
  AND client_id = $3
RETURNING company_id, module_id, client_id, operational_email_enabled, created_at, updated_at;

-- name: CreateIntervalChangeLog :one
INSERT INTO interval_change_logs (
    company_id,
    module_id,
    author_user_id,
    previous_interval_days,
    new_interval_days
) VALUES (
    $1,
    $2,
    $3,
    $4,
    $5
)
RETURNING id, company_id, module_id, author_user_id, previous_interval_days, new_interval_days, changed_at;

-- name: ListIntervalChangeLogsByModule :many
SELECT
    l.id,
    l.company_id,
    l.module_id,
    l.author_user_id,
    u.name AS author_name,
    u.email AS author_email,
    u.role AS author_role,
    l.previous_interval_days,
    l.new_interval_days,
    l.changed_at
FROM interval_change_logs l
JOIN users u ON u.company_id = l.company_id AND u.id = l.author_user_id
WHERE l.company_id = $1
  AND l.module_id = $2
ORDER BY l.changed_at DESC
LIMIT $3 OFFSET $4;

-- name: CheckModuleOperationalHistory :one
SELECT
    (SELECT COUNT(*) FROM inspections insp WHERE insp.module_id = sqlc.arg('module_id')) AS inspections_count,
    (SELECT COUNT(*) FROM measurements meas WHERE meas.module_id = sqlc.arg('module_id')) AS measurements_count,
    (SELECT COUNT(*) FROM anomaly_events anom WHERE anom.module_id = sqlc.arg('module_id')) AS anomalies_count,
    (SELECT COUNT(*) FROM cleaning_operations cln WHERE cln.module_id = sqlc.arg('module_id')) AS cleanings_count,
    (SELECT COUNT(*) FROM reservoir_readings resv WHERE resv.module_id = sqlc.arg('module_id')) AS reservoir_readings_count,
    (SELECT COUNT(*) FROM interval_change_logs intv WHERE intv.module_id = sqlc.arg('module_id')) AS interval_change_logs_count,
    (SELECT COUNT(*) FROM inspections insp2 WHERE insp2.module_id = sqlc.arg('module_id') AND insp2.status IN ('scheduled', 'in_progress')) AS pending_inspections_count,
    (SELECT COUNT(*) FROM cleaning_operations cln2 WHERE cln2.module_id = sqlc.arg('module_id') AND cln2.status IN ('scheduled', 'in_progress')) AS pending_cleanings_count;

-- name: DeleteAllTechniciansForModule :exec
DELETE FROM module_technicians
WHERE company_id = $1
  AND module_id = $2;

-- name: DeleteAllNotificationsForModule :exec
DELETE FROM notifications
WHERE company_id = $1
  AND module_id = $2;

-- name: NeutralizeVerificationInspectionsForModule :exec
UPDATE inspections
SET
    type = 'scheduled',
    cleaning_operation_id = NULL,
    verification_result = NULL
WHERE module_id = $1
  AND type = 'verification';

-- name: DeleteAllReservoirReadingsForModule :exec
DELETE FROM reservoir_readings
WHERE module_id = $1;

-- name: DeleteAllCleaningsForModule :exec
DELETE FROM cleaning_operations
WHERE module_id = $1;

-- name: DeleteAllAnomaliesForModule :exec
DELETE FROM anomaly_events
WHERE module_id = $1;

-- name: DeleteAllMeasurementsForModule :exec
DELETE FROM measurements
WHERE module_id = $1;

-- name: DeleteAllInspectionPanelResultsForModule :exec
DELETE FROM inspection_panel_results
WHERE module_id = $1;

-- name: DeleteAllInspectionsForModule :exec
DELETE FROM inspections
WHERE module_id = $1;

-- name: DeleteAllIntervalChangeLogsForModule :exec
DELETE FROM interval_change_logs
WHERE module_id = $1;

-- name: DeleteModule :exec
DELETE FROM modules
WHERE company_id = $1
  AND id = $2;

-- name: GetModuleByMACAddress :one
SELECT * FROM modules
WHERE mac_address = $1::macaddr;

-- name: GetModuleByDeviceToken :one
SELECT * FROM modules
WHERE device_token = $1;

-- name: SetModuleDeviceToken :one
UPDATE modules
SET device_token = $1,
    updated_at = now()
WHERE id = $2
RETURNING id, mac_address, device_token, monitoring_status, inspection_interval_days;

-- name: UpdateModuleDeviceHealth :one
UPDATE modules
SET limits_check_passed = coalesce(sqlc.narg('limits_check_passed'), limits_check_passed),
    thermal_sensor_active = coalesce(sqlc.narg('thermal_sensor_active'), thermal_sensor_active),
    last_ping_at = now(),
    updated_at = now()
WHERE id = sqlc.arg('id')
RETURNING id, mac_address, limits_check_passed, thermal_sensor_active, last_ping_at;

-- name: UpdateModuleConfigAck :exec
UPDATE modules
SET config_applied_version = $2,
    config_applied_at = $3,
    config_apply_error = $4,
    updated_at = NOW()
WHERE id = $1;

-- name: GetModuleByIDForDevice :one
SELECT * FROM modules
WHERE id = $1;



