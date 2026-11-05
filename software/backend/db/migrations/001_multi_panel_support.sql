-- Migration 001: Multi-panel array support (idempotent)
-- Adds power_sensors to modules, creates inspection_panel_results,
-- and adds panel_index to measurements, anomaly_events, and cleaning_operations.

BEGIN;

-- 1. Modules: optional power_sensors config
ALTER TABLE modules
    ADD COLUMN IF NOT EXISTS power_sensors jsonb NULL
    CHECK (power_sensors IS NULL OR jsonb_typeof(power_sensors) = 'array');

-- 2. Inspection Panel Results (per-panel thermal baseline and metadata)
CREATE TABLE IF NOT EXISTS inspection_panel_results (
    inspection_id uuid NOT NULL,
    module_id uuid NOT NULL,
    panel_index integer NOT NULL CHECK (panel_index >= 1),
    baseline_temperature_c numeric(8,3) NOT NULL,
    truncated_by_memory boolean NOT NULL DEFAULT false,
    finished_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (inspection_id, panel_index),
    FOREIGN KEY (module_id, inspection_id) REFERENCES inspections(module_id, id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS inspection_panel_results_module_idx
    ON inspection_panel_results(module_id, inspection_id);

DROP TRIGGER IF EXISTS inspection_panel_results_updated_at ON inspection_panel_results;
CREATE TRIGGER inspection_panel_results_updated_at BEFORE UPDATE ON inspection_panel_results
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 3. Measurements: panel_index column and index
ALTER TABLE measurements
    ADD COLUMN IF NOT EXISTS panel_index integer NOT NULL DEFAULT 1
    CHECK (panel_index >= 1);

CREATE INDEX IF NOT EXISTS measurements_inspection_panel_idx
    ON measurements(inspection_id, panel_index, x_position_cm);

-- 4. Anomaly Events: panel_index column and index
ALTER TABLE anomaly_events
    ADD COLUMN IF NOT EXISTS panel_index integer NOT NULL DEFAULT 1
    CHECK (panel_index >= 1);

CREATE INDEX IF NOT EXISTS anomaly_events_module_panel_idx
    ON anomaly_events(module_id, panel_index, detected_at DESC);

-- 5. Cleaning Operations: panel_index column and index (nullable for refusals in inter-panel gaps)
ALTER TABLE cleaning_operations
    ADD COLUMN IF NOT EXISTS panel_index integer NULL
    CHECK (panel_index IS NULL OR panel_index >= 1);

CREATE INDEX IF NOT EXISTS cleaning_operations_module_panel_idx
    ON cleaning_operations(module_id, panel_index, created_at DESC);

-- 6. Backfill existing completed inspections into inspection_panel_results for panel_index = 1
INSERT INTO inspection_panel_results (inspection_id, module_id, panel_index, baseline_temperature_c, finished_at)
SELECT id, module_id, 1, baseline_temperature_c, COALESCE(finished_at, now())
FROM inspections
WHERE baseline_temperature_c IS NOT NULL
ON CONFLICT (inspection_id, panel_index) DO NOTHING;

COMMIT;
