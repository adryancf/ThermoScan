package db_test

import (
	"context"
	"os"
	"testing"
	"time"

	"backend/internal/db"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func testDBURL() string {
	if url := os.Getenv("DATABASE_URL"); url != "" {
		return url
	}
	return "postgres://thermoscan:thermoscan@localhost:5432/thermoscan?sslmode=disable"
}

func TestSchemaTablesAndQueries(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	conn, err := pgx.Connect(ctx, testDBURL())
	if err != nil {
		t.Skipf("PostgreSQL not reachable for integration test: %v", err)
	}
	defer conn.Close(ctx)

	// 1. Verify expected tables exist in public schema (17 base tables + schema_migrations)
	var tableCount int
	err = conn.QueryRow(ctx, `
		SELECT count(*)
		FROM information_schema.tables
		WHERE table_schema = 'public'
		  AND table_type = 'BASE TABLE'
	`).Scan(&tableCount)
	if err != nil {
		t.Fatalf("failed to count tables: %v", err)
	}
	if tableCount != 17 && tableCount != 18 {
		t.Fatalf("expected 17 or 18 tables in public schema, got %d", tableCount)
	}

	// 2. Run transactional tests using sqlc Queries and roll back at the end
	tx, err := conn.Begin(ctx)
	if err != nil {
		t.Fatalf("failed to begin tx: %v", err)
	}
	defer tx.Rollback(ctx)

	q := db.New(tx)

	// Create company
	company, err := q.CreateCompany(ctx, db.CreateCompanyParams{
		Name:    "SolarCorp Test",
		Address: pgtype.Text{String: "Av. Sete de Setembro, 3165", Valid: true},
	})
	if err != nil {
		t.Fatalf("CreateCompany failed: %v", err)
	}

	// Create default manager
	defaultMgr, err := q.CreateUser(ctx, db.CreateUserParams{
		CompanyID:          company.ID,
		Name:               "Default Manager",
		Email:              "  MANAGER@SOLARCORP.COM  ",
		PasswordHash:       "$2a$10$dummyhashvalue1234567890123456789012345678901234",
		Role:               "manager",
		IsActive:           true,
		IsDefaultManager:   true,
		MustChangePassword: true,
	})
	if err != nil {
		t.Fatalf("CreateUser (default manager) failed: %v", err)
	}
	if defaultMgr.Email != "manager@solarcorp.com" {
		t.Fatalf("expected normalized email 'manager@solarcorp.com', got %q", defaultMgr.Email)
	}

	// Verify GetUserByEmail returns company_is_active = true
	fetchedMgr, err := q.GetUserByEmail(ctx, "MANAGER@solarcorp.com")
	if err != nil {
		t.Fatalf("GetUserByEmail failed: %v", err)
	}
	if !fetchedMgr.CompanyIsActive || fetchedMgr.ID != defaultMgr.ID {
		t.Fatalf("unexpected GetUserByEmail result: %+v", fetchedMgr)
	}

	// Verify trigger protect_default_manager prevents deactivating default manager
	_, err = tx.Exec(ctx, "SAVEPOINT before_protect_test")
	if err != nil {
		t.Fatalf("failed to create savepoint: %v", err)
	}
	_, err = tx.Exec(ctx, "UPDATE users SET is_active = false WHERE id = $1", defaultMgr.ID)
	if err == nil {
		t.Fatalf("expected error when deactivating default manager, got nil")
	}
	_, _ = tx.Exec(ctx, "ROLLBACK TO SAVEPOINT before_protect_test")

	// Create technician and link to manager
	tech, err := q.CreateUser(ctx, db.CreateUserParams{
		CompanyID:          company.ID,
		Name:               "Tech One",
		Email:              "tech1@solarcorp.com",
		PasswordHash:       "$2a$10$dummyhashvalue1234567890123456789012345678901234",
		Role:               "technician",
		IsActive:           true,
		IsDefaultManager:   false,
		MustChangePassword: true,
	})
	if err != nil {
		t.Fatalf("CreateUser (technician) failed: %v", err)
	}

	_, err = q.AddTechnicianManager(ctx, db.AddTechnicianManagerParams{
		CompanyID:    company.ID,
		TechnicianID: tech.ID,
		ManagerID:    defaultMgr.ID,
	})
	if err != nil {
		t.Fatalf("AddTechnicianManager failed: %v", err)
	}

	mgrCount, err := q.CountManagersForTechnician(ctx, db.CountManagersForTechnicianParams{
		CompanyID:    company.ID,
		TechnicianID: tech.ID,
	})
	if err != nil || mgrCount != 1 {
		t.Fatalf("expected 1 manager for technician, got %d (err=%v)", mgrCount, err)
	}

	// Create and revoke auth session
	sess, err := q.CreateAuthSession(ctx, db.CreateAuthSessionParams{
		UserID:           defaultMgr.ID,
		RefreshTokenHash: "sha256_refresh_token_hash_test",
		ExpiresAt:        time.Now().Add(24 * time.Hour),
	})
	if err != nil {
		t.Fatalf("CreateAuthSession failed: %v", err)
	}

	activeSess, err := q.GetActiveAuthSessionByTokenHash(ctx, sess.RefreshTokenHash)
	if err != nil {
		t.Fatalf("GetActiveAuthSessionByTokenHash failed: %v", err)
	}
	if activeSess.UserID != defaultMgr.ID {
		t.Fatalf("expected session user_id %v, got %v", defaultMgr.ID, activeSess.UserID)
	}

	if err := q.RevokeAllUserAuthSessions(ctx, defaultMgr.ID); err != nil {
		t.Fatalf("RevokeAllUserAuthSessions failed: %v", err)
	}

	_, err = q.GetActiveAuthSessionByTokenHash(ctx, sess.RefreshTokenHash)
	if err == nil {
		t.Fatalf("expected error fetching revoked session, got nil")
	}

	// 3. Verify anomaly_events & cleaning_operations retry constraints (up to 3 actuated attempts, refusals do not consume attempts)
	var moduleID, inspectionID, measurementID, anomalyID pgtype.UUID
	err = tx.QueryRow(ctx, `
		INSERT INTO modules (company_id, installer_technician_id, name, mac_address)
		VALUES ($1, $2, 'Mod-01', 'AA:BB:CC:DD:EE:01')
		RETURNING id
	`, company.ID, tech.ID).Scan(&moduleID)
	if err != nil {
		t.Fatalf("insert module failed: %v", err)
	}

	err = tx.QueryRow(ctx, `
		INSERT INTO inspections (module_id, type, scheduled_for, started_at, status)
		VALUES ($1, 'scheduled', now(), now(), 'in_progress')
		RETURNING id
	`, moduleID).Scan(&inspectionID)
	if err != nil {
		t.Fatalf("insert inspection failed: %v", err)
	}

	err = tx.QueryRow(ctx, `
		INSERT INTO measurements (
			module_id, inspection_id, source_event_id, measured_at,
			x_position_cm, max_temperature_c,
			voltage_v, current_a, power_w, thermal_frame
		) VALUES (
			$1, $2, gen_random_uuid(), now(),
			10.0, 50.0,
			20.0, 4.0, 80.0, '[[35.0]]'::jsonb
		) RETURNING id
	`, moduleID, inspectionID).Scan(&measurementID)
	if err != nil {
		t.Fatalf("insert measurement failed: %v", err)
	}

	err = tx.QueryRow(ctx, `
		INSERT INTO anomaly_events (
			module_id, origin_measurement_id, confirming_measurement_ids, source_event_id, x_position_cm,
			detected_at, status, actuated_attempts_count, retry_pending, retry_reason
		) VALUES (
			$1, $2, ARRAY[$2, $2]::uuid[], gen_random_uuid(), 10.0,
			now(), 'open', 0, true, 'insufficient_water'
		) RETURNING id
	`, moduleID, measurementID).Scan(&anomalyID)
	if err != nil {
		t.Fatalf("insert anomaly_event failed: %v", err)
	}

	// Refusal before pump actuation (does not consume attempt_number 1..3)
	_, err = tx.Exec(ctx, `
		INSERT INTO cleaning_operations (
			module_id, anomaly_event_id, source_event_id, target_x_position_cm,
			pump_actuated, attempt_number, status, failure_reason
		) VALUES (
			$1, $2, gen_random_uuid(), 10.0,
			false, NULL, 'refused', 'insufficient_water'
		)
	`, moduleID, anomalyID)
	if err != nil {
		t.Fatalf("insert refused cleaning_operation failed: %v", err)
	}

	// Actuated attempts 1, 2 (interrupted/failed), and 3 (completed) on the same anomaly_event_id succeed
	for attempt := 1; attempt <= 2; attempt++ {
		_, err = tx.Exec(ctx, `
			INSERT INTO cleaning_operations (
				module_id, anomaly_event_id, source_event_id, target_x_position_cm,
				pump_actuated, attempt_number, started_at, ended_at, status, failure_reason
			) VALUES (
				$1, $2, gen_random_uuid(), 10.0,
				true, $3, now(), now(), 'failed', 'insufficient_water'
			)
		`, moduleID, anomalyID, attempt)
		if err != nil {
			t.Fatalf("insert actuated attempt %d failed: %v", attempt, err)
		}
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO cleaning_operations (
			module_id, anomaly_event_id, source_event_id, target_x_position_cm,
			pump_actuated, attempt_number, started_at, ended_at, status
		) VALUES (
			$1, $2, gen_random_uuid(), 10.0,
			true, 3, now(), now(), 'completed'
		)
	`, moduleID, anomalyID)
	if err != nil {
		t.Fatalf("insert actuated attempt 3 failed: %v", err)
	}

	// 4th attempt must be rejected by CHECK (attempt_number BETWEEN 1 AND 3)
	_, _ = tx.Exec(ctx, "SAVEPOINT before_4th_attempt")
	_, err = tx.Exec(ctx, `
		INSERT INTO cleaning_operations (
			module_id, anomaly_event_id, source_event_id, target_x_position_cm,
			pump_actuated, attempt_number, started_at, ended_at, status
		) VALUES (
			$1, $2, gen_random_uuid(), 10.0,
			true, 4, now(), now(), 'completed'
		)
	`, moduleID, anomalyID)
	if err == nil {
		t.Fatalf("expected error on 4th actuated attempt, got nil")
	}
	_, _ = tx.Exec(ctx, "ROLLBACK TO SAVEPOINT before_4th_attempt")
}
