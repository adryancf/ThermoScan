CREATE TABLE IF NOT EXISTS power_readings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id uuid NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
    panel_index integer NOT NULL CHECK (panel_index >= 1),
    voltage_v double precision,
    current_a double precision,
    power_w double precision,
    measured_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_power_readings_module_measured_at
    ON power_readings (module_id, measured_at DESC);

CREATE INDEX IF NOT EXISTS idx_power_readings_module_panel_measured_at
    ON power_readings (module_id, panel_index, measured_at DESC);

ALTER TABLE modules
    ADD COLUMN IF NOT EXISTS latest_power_readings jsonb NULL,
    ADD COLUMN IF NOT EXISTS latest_power_at timestamptz NULL;
