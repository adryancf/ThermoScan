-- ThermoScan Clean/Reset Database (Preserves System Admin only)
BEGIN;

-- Temporarily disable default manager deletion guard trigger
ALTER TABLE users DISABLE TRIGGER users_protect_default_manager;

-- 1. Wipe non-admin auth sessions and push devices
DELETE FROM auth_sessions WHERE user_id NOT IN (SELECT id FROM users WHERE role = 'system_admin');
DELETE FROM user_devices WHERE user_id NOT IN (SELECT id FROM users WHERE role = 'system_admin');

-- 2. Wipe operational notifications
DELETE FROM notifications;

-- 3. Wipe operational tables, inspections, operations, anomalies and modules with CASCADE
TRUNCATE TABLE cleaning_operations, anomaly_events, measurements, inspection_panel_results, inspections, reservoir_readings, interval_change_logs, module_technicians, module_managers, module_clients, modules CASCADE;

-- 4. Wipe technician-manager relationships
DELETE FROM technician_managers;

-- 5. Wipe all company users (managers, technicians, clients)
DELETE FROM users WHERE role <> 'system_admin';

-- 6. Wipe all companies
DELETE FROM companies;

-- Re-enable default manager deletion guard trigger
ALTER TABLE users ENABLE TRIGGER users_protect_default_manager;

COMMIT;
