package bootstrap_test

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"backend/internal/bootstrap"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestRunMigrationsIdempotent(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, testDBURL())
	if err != nil {
		t.Skipf("cannot connect to db: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		t.Skipf("db ping failed: %v", err)
	}

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	// First run
	if err := bootstrap.RunMigrations(ctx, pool, logger); err != nil {
		t.Fatalf("first RunMigrations failed: %v", err)
	}

	// Second run (idempotent)
	if err := bootstrap.RunMigrations(ctx, pool, logger); err != nil {
		t.Fatalf("second RunMigrations failed: %v", err)
	}

	var exists bool
	err = pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = '0001_add_modules_next_inspection_at')").Scan(&exists)
	if err != nil {
		t.Fatalf("failed to query schema_migrations: %v", err)
	}
	if !exists {
		t.Fatalf("expected version 0001_add_modules_next_inspection_at to be recorded in schema_migrations")
	}
}
