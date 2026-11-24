-- 0008_add_resolved_later_anomaly_status.sql
-- Adds 'resolved_later' to anomaly_events.status so prior 'unresolved' anomalies
-- whose position is clean in a subsequent scan can be cleared without altering
-- historical cleaning_operations.post_cleaning_result.

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'anomaly_events'::regclass
          AND contype = 'c'
          AND (
              (pg_get_constraintdef(oid) LIKE '%status%' AND pg_get_constraintdef(oid) LIKE '%resolved%')
              OR (pg_get_constraintdef(oid) LIKE '%status%' AND pg_get_constraintdef(oid) LIKE '%closed_at%')
          )
    LOOP
        EXECUTE format('ALTER TABLE anomaly_events DROP CONSTRAINT IF EXISTS %I', r.conname);
    END LOOP;
END $$;

ALTER TABLE anomaly_events
    ADD CONSTRAINT anomaly_events_status_check
    CHECK (status IN ('open', 'resolved', 'resolved_later', 'unresolved'));

ALTER TABLE anomaly_events
    ADD CONSTRAINT anomaly_events_closed_at_check
    CHECK ((status = 'open' AND closed_at IS NULL)
        OR (status IN ('resolved', 'resolved_later', 'unresolved') AND closed_at IS NOT NULL));
