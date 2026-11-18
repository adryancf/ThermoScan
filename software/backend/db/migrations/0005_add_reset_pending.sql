-- 0005_add_reset_pending.sql
-- Adds reset_pending flag to modules for the Reset Routine ("Red Button") feature
ALTER TABLE modules
ADD COLUMN IF NOT EXISTS reset_pending boolean NOT NULL DEFAULT false;
