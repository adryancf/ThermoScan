-- 0004_add_firmware_state_logs.sql
-- Adds firmware state tracking columns to modules and module_state_logs table
ALTER TABLE modules
ADD COLUMN IF NOT EXISTS firmware_state text NOT NULL DEFAULT 'UNKNOWN',
ADD COLUMN IF NOT EXISTS firmware_state_detail text NULL,
ADD COLUMN IF NOT EXISTS firmware_state_updated_at timestamptz NULL;

CREATE TABLE IF NOT EXISTS module_state_logs (
    seq bigserial NOT NULL,
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id uuid NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
    state text NOT NULL,
    detail text NULL,
    occurred_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_module_state_logs_module_occurred_seq
    ON module_state_logs (module_id, occurred_at DESC, seq DESC);
