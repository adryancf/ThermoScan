-- 0007_add_localized_reading.sql
-- Adds manual localized thermal reading trigger state and stored result
ALTER TABLE modules
ADD COLUMN IF NOT EXISTS manual_reading_pending boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS manual_reading_target_x_cm numeric(8,2) NULL,
ADD COLUMN IF NOT EXISTS localized_reading_at timestamptz NULL,
ADD COLUMN IF NOT EXISTS localized_reading_result jsonb NULL;
