-- name: CreateAuthSession :one
INSERT INTO auth_sessions (
    user_id,
    refresh_token_hash,
    expires_at
) VALUES (
    $1,
    $2,
    $3
)
RETURNING id, user_id, refresh_token_hash, expires_at, revoked_at, created_at;

-- name: GetActiveAuthSessionByTokenHash :one
SELECT
    s.id,
    s.user_id,
    s.refresh_token_hash,
    s.expires_at,
    s.revoked_at,
    s.created_at,
    u.company_id,
    u.role,
    u.is_active AS user_is_active,
    u.must_change_password,
    COALESCE(c.is_active, true) AS company_is_active
FROM auth_sessions s
JOIN users u ON u.id = s.user_id
LEFT JOIN companies c ON c.id = u.company_id
WHERE s.refresh_token_hash = $1
  AND s.revoked_at IS NULL
  AND s.expires_at > now()
FOR UPDATE OF s;

-- name: RevokeAuthSessionByID :exec
UPDATE auth_sessions
SET revoked_at = now()
WHERE id = $1
  AND revoked_at IS NULL;

-- name: RevokeAuthSessionByTokenHash :exec
UPDATE auth_sessions
SET revoked_at = now()
WHERE refresh_token_hash = $1
  AND revoked_at IS NULL;

-- name: RevokeAllUserAuthSessions :exec
UPDATE auth_sessions
SET revoked_at = now()
WHERE user_id = $1
  AND revoked_at IS NULL;

-- name: GetActiveAuthSessionWithUserByID :one
SELECT
    s.id AS session_id,
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
FROM auth_sessions s
JOIN users u ON u.id = s.user_id
LEFT JOIN companies c ON c.id = u.company_id
WHERE s.id = $1
  AND s.user_id = $2
  AND s.revoked_at IS NULL
  AND s.expires_at > now();
