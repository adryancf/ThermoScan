-- ThermoScan Clean/Reset Database (Preserves System Admin only)
BEGIN;

-- Temporarily disable default manager deletion guard trigger
ALTER TABLE users DISABLE TRIGGER users_protect_default_manager;

-- 1. Wipe non-admin auth sessions and push devices
DELETE FROM auth_sessions WHERE user_id NOT IN (SELECT id FROM users WHERE role = 'system_admin');
DELETE FROM user_devices WHERE user_id NOT IN (SELECT id FROM users WHERE role = 'system_admin');

-- 2. Wipe operational notifications
DELETE FROM notifications;

-- 3. Wipe inspections, thermal maps, measurements, operations and anomalies
DELETE FROM reservoir_readings;
DELETE FROM inspection_thermal_maps;
DELETE FROM measurements;
DELETE FROM inspections;
DELETE FROM cleaning_operations;
DELETE FROM anomaly_events;
DELETE FROM interval_change_logs;

-- 4. Wipe module relations and modules
DELETE FROM module_technicians;
DELETE FROM module_managers;
DELETE FROM module_clients;
DELETE FROM modules;

-- 5. Wipe technician-manager relationships
DELETE FROM technician_managers;

-- 6. Wipe all company users (managers, technicians, clients)
DELETE FROM users WHERE role <> 'system_admin';

-- 7. Wipe all companies
DELETE FROM companies;

-- Re-enable default manager deletion guard trigger
ALTER TABLE users ENABLE TRIGGER users_protect_default_manager;

COMMIT;
