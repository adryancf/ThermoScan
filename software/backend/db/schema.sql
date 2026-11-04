BEGIN;

CREATE TABLE companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (btrim(name) <> ''),
    address text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid REFERENCES companies(id) ON DELETE RESTRICT,
    name text NOT NULL CHECK (btrim(name) <> ''),
    email text NOT NULL UNIQUE CHECK (email = lower(btrim(email)) AND email <> ''),
    password_hash text NOT NULL CHECK (password_hash <> ''),
    role text NOT NULL CHECK (role IN ('system_admin', 'manager', 'technician', 'client')),
    is_active boolean NOT NULL DEFAULT true,
    is_default_manager boolean NOT NULL DEFAULT false,
    must_change_password boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, id),
    CHECK ((role = 'system_admin' AND company_id IS NULL)
        OR (role <> 'system_admin' AND company_id IS NOT NULL)),
    CHECK (NOT is_default_manager OR (role = 'manager' AND is_active))
);

CREATE UNIQUE INDEX users_one_default_manager_per_company
    ON users(company_id) WHERE is_default_manager;
CREATE INDEX users_company_role_idx ON users(company_id, role);

CREATE TABLE auth_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    refresh_token_hash text NOT NULL UNIQUE CHECK (refresh_token_hash <> ''),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (expires_at > created_at),
    CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX auth_sessions_user_idx ON auth_sessions(user_id);

CREATE TABLE technician_managers (
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    technician_id uuid NOT NULL,
    manager_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (technician_id, manager_id),
    FOREIGN KEY (company_id, technician_id) REFERENCES users(company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (company_id, manager_id) REFERENCES users(company_id, id) ON DELETE RESTRICT,
    CHECK (technician_id <> manager_id)
);
CREATE INDEX technician_managers_manager_idx ON technician_managers(manager_id);

CREATE TABLE modules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    installer_technician_id uuid NOT NULL,
    name text NOT NULL CHECK (btrim(name) <> ''),
    mac_address macaddr NOT NULL UNIQUE,
    device_token text UNIQUE,
    limits_check_passed boolean NOT NULL DEFAULT false,
    thermal_sensor_active boolean NOT NULL DEFAULT false,
    last_ping_at timestamptz,
    config_version int NOT NULL DEFAULT 0,
    config_applied_version int NOT NULL DEFAULT 0,
    config_applied_at timestamptz,
    config_apply_error text,
    is_active boolean NOT NULL DEFAULT true,
    monitoring_status text NOT NULL DEFAULT 'pending_configuration'
        CHECK (monitoring_status IN ('pending_configuration', 'active', 'maintenance', 'inactive')),
    panel_length_cm numeric(12,3) CHECK (panel_length_cm > 0),
    panel_width_cm numeric(12,3) CHECK (panel_width_cm > 0),
    panel_count integer CHECK (panel_count > 0),
    panel_spacing_cm numeric(12,3) CHECK (panel_spacing_cm >= 0),
    latitude double precision CHECK (latitude BETWEEN -90 AND 90),
    longitude double precision CHECK (longitude BETWEEN -180 AND 180),
    elevation_m double precision CHECK (elevation_m > '-Infinity'::double precision
        AND elevation_m < 'Infinity'::double precision),
    azimuth_deg numeric(7,3) CHECK (azimuth_deg >= 0 AND azimuth_deg < 360),
    tilt_deg numeric(6,3) CHECK (tilt_deg BETWEEN 0 AND 90),
    azimuth_source text CHECK (azimuth_source IN ('sensor', 'manual')),
    tilt_source text CHECK (tilt_source IN ('sensor', 'manual')),
    minimum_solar_angle_deg numeric(6,3) CHECK (minimum_solar_angle_deg BETWEEN 0 AND 90),
    inspection_interval_days integer NOT NULL DEFAULT 1 CHECK (inspection_interval_days >= 1),
    reservoir_nominal_capacity_ml numeric(12,3) CHECK (reservoir_nominal_capacity_ml > 0),
    configured_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, id),
    FOREIGN KEY (company_id, installer_technician_id)
        REFERENCES users(company_id, id) ON DELETE RESTRICT,
    CHECK (monitoring_status <> 'active' OR (
        is_active AND panel_length_cm IS NOT NULL AND panel_width_cm IS NOT NULL
        AND panel_count IS NOT NULL AND panel_spacing_cm IS NOT NULL
        AND latitude IS NOT NULL AND longitude IS NOT NULL AND elevation_m IS NOT NULL
        AND azimuth_deg IS NOT NULL AND tilt_deg IS NOT NULL
        AND azimuth_source IS NOT NULL AND tilt_source IS NOT NULL
        AND minimum_solar_angle_deg IS NOT NULL AND configured_at IS NOT NULL
    ))
);
CREATE INDEX modules_company_idx ON modules(company_id);
CREATE INDEX modules_installer_idx ON modules(installer_technician_id);

CREATE TABLE module_managers (
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    module_id uuid NOT NULL,
    manager_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (module_id, manager_id),
    FOREIGN KEY (company_id, module_id) REFERENCES modules(company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (company_id, manager_id) REFERENCES users(company_id, id) ON DELETE RESTRICT
);
CREATE INDEX module_managers_manager_idx ON module_managers(manager_id);

CREATE TABLE module_technicians (
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    module_id uuid NOT NULL,
    technician_id uuid NOT NULL,
    can_view boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (module_id, technician_id),
    FOREIGN KEY (company_id, module_id) REFERENCES modules(company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (company_id, technician_id) REFERENCES users(company_id, id) ON DELETE RESTRICT
);
CREATE INDEX module_technicians_technician_idx ON module_technicians(technician_id);

CREATE TABLE module_clients (
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    module_id uuid NOT NULL,
    client_id uuid NOT NULL,
    operational_email_enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (module_id, client_id),
    FOREIGN KEY (company_id, module_id) REFERENCES modules(company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (company_id, client_id) REFERENCES users(company_id, id) ON DELETE RESTRICT
);
CREATE INDEX module_clients_client_idx ON module_clients(client_id);

CREATE TABLE interval_change_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    module_id uuid NOT NULL,
    author_user_id uuid NOT NULL,
    previous_interval_days integer NOT NULL CHECK (previous_interval_days >= 1),
    new_interval_days integer NOT NULL CHECK (new_interval_days >= 1),
    changed_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (company_id, module_id) REFERENCES modules(company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (company_id, author_user_id) REFERENCES users(company_id, id) ON DELETE RESTRICT,
    CHECK (previous_interval_days <> new_interval_days)
);
CREATE INDEX interval_change_logs_module_idx ON interval_change_logs(module_id, changed_at DESC);

CREATE TABLE inspections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id uuid NOT NULL REFERENCES modules(id) ON DELETE RESTRICT,
    source_event_id uuid,
    type text NOT NULL CHECK (type IN ('scheduled', 'verification')),
    cleaning_operation_id uuid,
    baseline_temperature_c numeric(8,3) NULL,
    scheduled_for timestamptz NOT NULL,
    started_at timestamptz,
    finished_at timestamptz,
    status text NOT NULL DEFAULT 'scheduled'
        CHECK (status IN ('scheduled', 'in_progress', 'completed', 'failed', 'cancelled')),
    failure_reason text,
    verification_result text CHECK (verification_result IN ('resolved', 'unresolved')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (module_id, id),
    UNIQUE (module_id, source_event_id),
    CHECK ((type = 'verification' AND cleaning_operation_id IS NOT NULL)
        OR (type = 'scheduled' AND cleaning_operation_id IS NULL)),
    CHECK (verification_result IS NULL OR (type = 'verification' AND status = 'completed')),
    CHECK (finished_at IS NULL OR (started_at IS NOT NULL AND finished_at >= started_at))
);
CREATE INDEX inspections_module_time_idx ON inspections(module_id, scheduled_for DESC);
CREATE INDEX inspections_pending_idx ON inspections(scheduled_for) WHERE status = 'scheduled';

CREATE TABLE measurements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id uuid NOT NULL,
    inspection_id uuid NOT NULL,
    source_event_id uuid NOT NULL,
    measured_at timestamptz NOT NULL,
    x_position_cm numeric(12,3) NOT NULL CHECK (x_position_cm >= 0),
    max_temperature_c numeric(8,3) NOT NULL,
    voltage_v numeric(12,4) NULL,
    current_a numeric(12,4) NULL,
    power_w numeric(14,4) NULL,
    thermal_frame jsonb NOT NULL CHECK (jsonb_typeof(thermal_frame) = 'array'),
    received_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (module_id, id),
    UNIQUE (module_id, source_event_id),
    FOREIGN KEY (module_id, inspection_id) REFERENCES inspections(module_id, id) ON DELETE RESTRICT
);
CREATE INDEX measurements_inspection_idx ON measurements(inspection_id, x_position_cm);
CREATE INDEX measurements_module_time_idx ON measurements(module_id, measured_at DESC);

CREATE TABLE anomaly_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id uuid NOT NULL REFERENCES modules(id) ON DELETE RESTRICT,
    origin_measurement_id uuid NOT NULL,
    confirming_measurement_ids uuid[] NOT NULL CHECK (array_length(confirming_measurement_ids, 1) >= 2),
    source_event_id uuid NOT NULL,
    x_position_cm numeric(12,3) NOT NULL CHECK (x_position_cm >= 0),
    detected_at timestamptz NOT NULL,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved', 'unresolved')),
    actuated_attempts_count integer NOT NULL DEFAULT 0 CHECK (actuated_attempts_count BETWEEN 0 AND 3),
    retry_pending boolean NOT NULL DEFAULT false,
    retry_reason text CHECK (retry_reason IS NULL OR btrim(retry_reason) <> ''),
    closed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (module_id, id),
    UNIQUE (module_id, source_event_id),
    FOREIGN KEY (module_id, origin_measurement_id) REFERENCES measurements(module_id, id) ON DELETE RESTRICT,
    CHECK ((status = 'open' AND closed_at IS NULL)
        OR (status IN ('resolved', 'unresolved') AND closed_at IS NOT NULL)),
    CHECK (closed_at IS NULL OR closed_at >= detected_at),
    CHECK (NOT retry_pending OR (status = 'open' AND actuated_attempts_count < 3)),
    CHECK (retry_pending OR retry_reason IS NULL)
);
CREATE INDEX anomaly_events_module_time_idx ON anomaly_events(module_id, detected_at DESC);

CREATE TABLE cleaning_operations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id uuid NOT NULL,
    anomaly_event_id uuid NOT NULL,
    source_event_id uuid NOT NULL,
    target_x_position_cm numeric(12,3) NOT NULL CHECK (target_x_position_cm >= 0),
    pump_actuated boolean NOT NULL DEFAULT false,
    attempt_number integer CHECK (attempt_number BETWEEN 1 AND 3),
    started_at timestamptz,
    ended_at timestamptz,
    duration_seconds numeric(10,3) CHECK (duration_seconds >= 0),
    estimated_water_volume_ml numeric(12,3) CHECK (estimated_water_volume_ml >= 0),
    status text NOT NULL DEFAULT 'scheduled'
        CHECK (status IN ('scheduled', 'in_progress', 'completed', 'refused', 'failed')),
    failure_reason text CHECK (failure_reason IS NULL OR btrim(failure_reason) <> ''),
    post_cleaning_result text NOT NULL DEFAULT 'pending'
        CHECK (post_cleaning_result IN ('pending', 'resolved', 'unresolved')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (module_id, id),
    UNIQUE (module_id, source_event_id),
    FOREIGN KEY (module_id, anomaly_event_id) REFERENCES anomaly_events(module_id, id) ON DELETE RESTRICT,
    CHECK (ended_at IS NULL OR (started_at IS NOT NULL AND ended_at >= started_at)),
    CHECK ((pump_actuated AND attempt_number IS NOT NULL AND started_at IS NOT NULL AND status IN ('in_progress', 'completed', 'failed'))
        OR (NOT pump_actuated AND attempt_number IS NULL AND status IN ('scheduled', 'refused', 'failed'))),
    CHECK (status <> 'refused' OR (NOT pump_actuated AND started_at IS NULL AND ended_at IS NULL AND failure_reason IS NOT NULL)),
    CHECK (status <> 'completed' OR (pump_actuated AND ended_at IS NOT NULL)),
    CHECK (status NOT IN ('refused', 'failed') OR failure_reason IS NOT NULL)
);
CREATE INDEX cleaning_operations_module_time_idx ON cleaning_operations(module_id, created_at DESC);
CREATE INDEX cleaning_operations_anomaly_time_idx ON cleaning_operations(anomaly_event_id, created_at ASC);
CREATE UNIQUE INDEX cleaning_operations_anomaly_attempt_idx
    ON cleaning_operations(anomaly_event_id, attempt_number)
    WHERE attempt_number IS NOT NULL;
CREATE UNIQUE INDEX cleaning_operations_one_active_per_anomaly_idx
    ON cleaning_operations(anomaly_event_id)
    WHERE status IN ('scheduled', 'in_progress');

ALTER TABLE inspections ADD CONSTRAINT inspections_cleaning_same_module_fk
    FOREIGN KEY (module_id, cleaning_operation_id)
    REFERENCES cleaning_operations(module_id, id) ON DELETE RESTRICT;
CREATE INDEX inspections_cleaning_idx ON inspections(cleaning_operation_id)
    WHERE cleaning_operation_id IS NOT NULL;

CREATE TABLE reservoir_readings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id uuid NOT NULL REFERENCES modules(id) ON DELETE RESTRICT,
    cleaning_operation_id uuid,
    source_event_id uuid NOT NULL,
    measured_at timestamptz NOT NULL,
    reading_status text NOT NULL CHECK (reading_status IN ('valid', 'error')),
    water_available boolean,
    context text NOT NULL CHECK (context IN ('periodic', 'before_cleaning', 'during_cleaning', 'after_cleaning')),
    error_reason text,
    received_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (module_id, source_event_id),
    FOREIGN KEY (module_id, cleaning_operation_id)
        REFERENCES cleaning_operations(module_id, id) ON DELETE RESTRICT,
    CHECK ((reading_status = 'valid' AND water_available IS NOT NULL AND error_reason IS NULL)
        OR (reading_status = 'error' AND water_available IS NULL AND error_reason IS NOT NULL)),
    CHECK (context = 'periodic' OR cleaning_operation_id IS NOT NULL)
);
CREATE INDEX reservoir_readings_module_time_idx ON reservoir_readings(module_id, measured_at DESC);
CREATE INDEX reservoir_readings_cleaning_idx ON reservoir_readings(cleaning_operation_id)
    WHERE cleaning_operation_id IS NOT NULL;

CREATE TABLE user_devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    push_token text NOT NULL UNIQUE CHECK (push_token <> ''),
    platform text NOT NULL CHECK (platform IN ('android', 'ios')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX user_devices_user_idx ON user_devices(user_id);

CREATE TABLE notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    user_id uuid NOT NULL,
    module_id uuid,
    anomaly_event_id uuid,
    inspection_id uuid,
    type text NOT NULL CHECK (btrim(type) <> ''),
    title text NOT NULL CHECK (btrim(title) <> ''),
    message text NOT NULL,
    deduplication_key text,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (company_id, user_id) REFERENCES users(company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (company_id, module_id) REFERENCES modules(company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (module_id, anomaly_event_id) REFERENCES anomaly_events(module_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (module_id, inspection_id) REFERENCES inspections(module_id, id) ON DELETE RESTRICT,
    UNIQUE (user_id, deduplication_key),
    CHECK ((anomaly_event_id IS NULL AND inspection_id IS NULL) OR module_id IS NOT NULL)
);
CREATE INDEX notifications_user_time_idx ON notifications(user_id, created_at DESC);
CREATE INDEX notifications_module_idx ON notifications(module_id) WHERE module_id IS NOT NULL;

-- Automatic timestamp update for mutable records.
CREATE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER companies_updated_at BEFORE UPDATE ON companies
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER modules_updated_at BEFORE UPDATE ON modules
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER module_technicians_updated_at BEFORE UPDATE ON module_technicians
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER module_clients_updated_at BEFORE UPDATE ON module_clients
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER inspections_updated_at BEFORE UPDATE ON inspections
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER anomaly_events_updated_at BEFORE UPDATE ON anomaly_events
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER cleaning_operations_updated_at BEFORE UPDATE ON cleaning_operations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER user_devices_updated_at BEFORE UPDATE ON user_devices
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Prevent default manager protection from being removed via UPDATE or DELETE.
CREATE FUNCTION protect_default_manager() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.is_default_manager THEN
        IF TG_OP = 'DELETE' THEN
            RAISE EXCEPTION 'The default manager cannot be deleted';
        END IF;
        IF NOT NEW.is_default_manager OR NOT NEW.is_active
           OR NEW.role <> 'manager' OR NEW.company_id IS DISTINCT FROM OLD.company_id THEN
            RAISE EXCEPTION 'The default manager cannot be deactivated, reassigned or demoted';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER users_protect_default_manager BEFORE UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION protect_default_manager();

COMMENT ON COLUMN modules.reservoir_nominal_capacity_ml IS
    'Optional descriptive metadata. The binary sensor does not measure remaining volume.';
COMMENT ON COLUMN measurements.thermal_frame IS
    'Acquisition matrix: 24 rows of 32 temperatures in Celsius; null for invalid pixel. Validate shape and values in the backend.';
COMMENT ON COLUMN module_technicians.can_view IS
    'Revocable effective access including for the installer. No bypass via installer_technician_id.';
COMMENT ON COLUMN modules.minimum_solar_angle_deg IS
    'Angle in degrees; do not store the cosine score in this field. Confirm semantics during solar integration.';
COMMENT ON COLUMN auth_sessions.refresh_token_hash IS
    'Hash of a high-entropy random token, never the raw refresh token.';

COMMIT;
