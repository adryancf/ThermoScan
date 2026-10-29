-- name: CreateUser :one
INSERT INTO users (
    company_id,
    name,
    email,
    password_hash,
    role,
    is_active,
    is_default_manager,
    must_change_password
) VALUES (
    $1,
    $2,
    lower(btrim(sqlc.arg(email)::text)),
    $3,
    $4,
    $5,
    $6,
    $7
)
RETURNING id, company_id, name, email, password_hash, role, is_active, is_default_manager, must_change_password, created_at, updated_at;

-- name: GetUserByEmail :one
SELECT
    u.id,
    u.company_id,
    u.name,
    u.email,
    u.password_hash,
    u.role,
    u.is_active,
    u.is_default_manager,
    u.must_change_password,
    u.created_at,
    u.updated_at,
    COALESCE(c.is_active, true) AS company_is_active
FROM users u
LEFT JOIN companies c ON c.id = u.company_id
WHERE u.email = lower(btrim(sqlc.arg(email)::text));

-- name: GetUserByID :one
SELECT
    u.id,
    u.company_id,
    u.name,
    u.email,
    u.password_hash,
    u.role,
    u.is_active,
    u.is_default_manager,
    u.must_change_password,
    u.created_at,
    u.updated_at,
    COALESCE(c.is_active, true) AS company_is_active
FROM users u
LEFT JOIN companies c ON c.id = u.company_id
WHERE u.id = $1;

-- name: GetCompanyUserByID :one
SELECT
    id,
    company_id,
    name,
    email,
    password_hash,
    role,
    is_active,
    is_default_manager,
    must_change_password,
    created_at,
    updated_at
FROM users
WHERE company_id = $1 AND id = $2;

-- name: GetCompanyUserByIDForUpdate :one
SELECT
    id,
    company_id,
    name,
    email,
    password_hash,
    role,
    is_active,
    is_default_manager,
    must_change_password,
    created_at,
    updated_at
FROM users
WHERE company_id = $1 AND id = $2
FOR UPDATE;

-- name: ListUsersByCompany :many
SELECT
    id,
    company_id,
    name,
    email,
    role,
    is_active,
    is_default_manager,
    must_change_password,
    created_at,
    updated_at
FROM users
WHERE company_id = $1
  AND (sqlc.narg('role')::text IS NULL OR role = sqlc.narg('role')::text)
ORDER BY created_at DESC
LIMIT $2 OFFSET $3;

-- name: UpdateOwnProfile :one
UPDATE users
SET
    name = $2,
    email = lower(btrim(sqlc.arg(email)::text))
WHERE id = $1
RETURNING id, company_id, name, email, role, is_active, is_default_manager, must_change_password, created_at, updated_at;

-- name: UpdateUserPassword :one
UPDATE users
SET
    password_hash = $2,
    must_change_password = $3
WHERE id = $1
RETURNING id, company_id, name, email, role, is_active, is_default_manager, must_change_password, created_at, updated_at;

-- name: SetCompanyUserActiveStatus :one
UPDATE users
SET is_active = $3
WHERE company_id = $1
  AND id = $2
  AND role IN ('technician', 'client')
RETURNING id, company_id, name, email, role, is_active, is_default_manager, must_change_password, created_at, updated_at;

-- name: CountSystemAdmins :one
SELECT count(*)
FROM users
WHERE role = 'system_admin';

-- name: CheckUserOperationalHistory :one
SELECT
    (SELECT COUNT(*) FROM modules m WHERE m.company_id = sqlc.arg('company_id') AND m.installer_technician_id = sqlc.arg('user_id')) AS installed_modules_count,
    (SELECT COUNT(*) FROM interval_change_logs l WHERE l.company_id = sqlc.arg('company_id') AND l.author_user_id = sqlc.arg('user_id')) AS authored_interval_logs_count;

-- name: DeleteAllUserAuthSessions :exec
DELETE FROM auth_sessions
WHERE user_id = $1;

-- name: DeleteAllUserDevices :exec
DELETE FROM user_devices
WHERE user_id = $1;

-- name: DeleteAllModuleAssignmentsForTechnician :exec
DELETE FROM module_technicians
WHERE company_id = $1 AND technician_id = $2;

-- name: DeleteAllModuleAssignmentsForClient :exec
DELETE FROM module_clients
WHERE company_id = $1 AND client_id = $2;

-- name: DeleteAllNotificationsForUser :exec
DELETE FROM notifications
WHERE company_id = $1 AND user_id = $2;

-- name: DeleteCompanyUser :exec
DELETE FROM users
WHERE company_id = $1
  AND id = $2
  AND role IN ('technician', 'client');

