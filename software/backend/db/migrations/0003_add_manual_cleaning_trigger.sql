-- 0003_add_manual_cleaning_trigger.sql
-- Adds manual cleaning trigger pending state and target coordinate
ALTER TABLE modules
ADD COLUMN IF NOT EXISTS manual_cleaning_pending boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS manual_cleaning_target_x_cm numeric(12,3) NULL;
