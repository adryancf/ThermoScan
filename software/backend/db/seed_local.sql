-- ThermoScan Local/Dev Seed (Test company + manager, technician, client)
-- Password for all seeded users: teste123
BEGIN;

INSERT INTO companies (id, name, address, is_active)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'ThermoScan Test',
    'Local Network Lab',
    true
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (
    company_id,
    name,
    email,
    password_hash,
    role,
    is_active,
    is_default_manager,
    must_change_password
)
VALUES
    (
        '00000000-0000-0000-0000-000000000001',
        'Test Manager',
        'manager@test.local',
        '$2a$10$soXxrciTVTzHSD1o2cr9Zui3B69vp.gdwrvcyiEcp6B19JkiowoFi',
        'manager',
        true,
        true,
        false
    ),
    (
        '00000000-0000-0000-0000-000000000001',
        'Test Technician',
        'tech@test.local',
        '$2a$10$soXxrciTVTzHSD1o2cr9Zui3B69vp.gdwrvcyiEcp6B19JkiowoFi',
        'technician',
        true,
        false,
        false
    ),
    (
        '00000000-0000-0000-0000-000000000001',
        'Test Client',
        'client@test.local',
        '$2a$10$soXxrciTVTzHSD1o2cr9Zui3B69vp.gdwrvcyiEcp6B19JkiowoFi',
        'client',
        true,
        false,
        false
    )
ON CONFLICT (email) DO NOTHING;

INSERT INTO technician_managers (company_id, technician_id, manager_id)
SELECT
    t.company_id,
    t.id,
    m.id
FROM users t
JOIN users m ON m.company_id = t.company_id
WHERE t.email = 'tech@test.local'
  AND m.email = 'manager@test.local'
ON CONFLICT (technician_id, manager_id) DO NOTHING;

COMMIT;
