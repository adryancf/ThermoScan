-- 0006_add_verification_ready_at.sql
-- Adds verification_ready_at timestamp to modules for post-cleaning cooldown tracking
ALTER TABLE modules
ADD COLUMN IF NOT EXISTS verification_ready_at timestamptz NULL;
